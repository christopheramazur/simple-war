class_name MatchLog
extends RefCounted
## A record of one played game (sw-ip8.7), for reviewing a match afterwards:
## user://matches/<started>-<map>-s<seed>/ (user://matches_headless/ for
## runs without a display: tests and scripts) holds
##   match.json  what was played (map, seed, the human's side, AI profile)
##   log.md      per turn, in order: the player's clicks and what they did
##               (UI notes, including orders the game refused), every
##               player's accepted inputs, and everything that happened (all
##               events, not just what the player saw)
##   match.sav   the replayable OverworldSession save, rewritten each turn
## Presentation-side and write-only: nothing in the game reads it. Keeps
## the newest KEEP matches.

const ROOT := "user://matches"
## Headless runs (tests, harness scripts) log here, apart from played games.
const HEADLESS_ROOT := "user://matches_headless"
const KEEP: int = 30

var dir: String = ""
var _session: OverworldSession
var _inputs_seen: int = 0
var _notes: PackedStringArray = PackedStringArray()


## Starts a log for a session at turn 1. Returns null if the folder can't be
## written.
static func start(session: OverworldSession, meta: Dictionary) -> MatchLog:
	var stamp := Time.get_datetime_string_from_system(false, false).replace(":", "").replace("-", "").replace("T", "-")
	var name := "%s-%s-s%d" % [stamp, session.map_id, session.seed_value]
	var root := root_dir()
	if DirAccess.make_dir_recursive_absolute(root + "/" + name) != OK:
		return null
	_prune(root)
	var m := MatchLog.new()
	m.dir = root + "/" + name
	m._session = session
	var info := meta.duplicate()
	info.merge({"map": session.map_id, "seed": session.seed_value, "started": Time.get_datetime_string_from_system(),
		"players": Array(session.players())})
	m._write("match.json", JSON.stringify(info, "\t"))
	m._write("log.md", "# Match %s\n\n%s\n" % [name, _meta_line(info)])
	m._inputs_seen = session.input_log.size()
	return m


## The folder as an OS path (for showing the player where it is).
func os_path() -> String:
	return ProjectSettings.globalize_path(dir)


## A UI action and its result, logged under the turn it happened in.
func note(text: String) -> void:
	_notes.append("- %s · %s: %s" % [_session.phase_name().capitalize(), _clock(), text])


## Appends the turn that just resolved: notes, inputs, events. Then saves
## the session (at a phase boundary).
func turn_resolved() -> void:
	var s := _session
	var lines := PackedStringArray(["", "## Turn %d" % s.turns_resolved(), ""])
	if not _notes.is_empty():
		lines.append("**Your actions**")
		lines.append_array(_notes)
		lines.append("")
		_notes = PackedStringArray()
	var inputs := s.input_log.slice(_inputs_seen)
	_inputs_seen = s.input_log.size()
	var orders := PackedStringArray()
	for i: Dictionary in inputs:
		var text := _input_text(i)
		if not text.is_empty():
			orders.append("- P%d %s" % [int(i["player"]), text])
	if not orders.is_empty():
		lines.append("**Orders accepted** (all players)")
		lines.append_array(orders)
		lines.append("")
	lines.append("**What happened**")
	var moves := {}  # commander -> [line index, first from, last to, hexes]
	var happened := PackedStringArray()
	for e in s.last_events:
		var d := e.to_dict()
		var data: Dictionary = d["data"]
		if d["type"] == &"commander_moved":  # one line per commander
			var cid := int(data.get("commander", -1))
			if moves.has(cid):
				moves[cid][2] = int(data.get("to", -1))
				moves[cid][3] += 1
			else:
				moves[cid] = [happened.size(), int(data.get("from", -1)), int(data.get("to", -1)), 1]
				happened.append("")
			continue
		_enrich(d)
		var text := EventText.describe(d, s.rules, 0)
		if text.is_empty():
			text = "%s %s" % [String(d["type"]), _brief(data)]
		happened.append("- %s" % text)
	for cid: int in moves:
		var m: Array = moves[cid]
		happened[m[0]] = "- %s moved %s → %s (%d hex%s)." % [EventText.commander(cid), EventText.hex(m[1], s.rules),
			EventText.hex(m[2], s.rules), m[3], "" if m[3] == 1 else "es"]
	lines.append_array(happened if not happened.is_empty() else PackedStringArray(["- (nothing)"]))
	if not s.state.outcome.is_empty():
		lines.append("")
		lines.append("**Result:** %s" % JSON.stringify(s.state.outcome))
	_append("log.md", "\n".join(lines) + "\n")
	if s.clock.phase != PulseClock.Phase.EXECUTE:
		var f := FileAccess.open(dir + "/match.sav", FileAccess.WRITE)
		if f != null:
			f.store_buffer(s.save())


## Adds a feature's template to events that name a feature (for its name).
func _enrich(d: Dictionary) -> void:
	var data: Dictionary = d["data"]
	if data.has("feature"):
		var row := _session.state.features.row_of(int(data["feature"]))
		if row >= 0:
			data["feature_tmpl"] = _session.state.features.tmpl[row]


## An accepted input in words ("" for ready, which every turn has).
func _input_text(i: Dictionary) -> String:
	var r := _session.rules
	var p: Variant = i.get("payload")
	var d: Dictionary = p if p is Dictionary else {}
	var who := EventText.commander(int(d.get("commander", -1)))
	match String(i["kind"]):
		"ready":
			return ""
		"route":
			var plots: Array = Array(d.get("plots", []))
			return "%s: route to %s (%d hex%s)" % [who, EventText.hex(int(plots[-1]) if not plots.is_empty() else -1, r),
				plots.size(), "" if plots.size() == 1 else "es"] if not plots.is_empty() else "%s: stop" % who
		"activity":
			return "%s: %s %s" % [who, String(d.get("activity", "")), String(d.get("option", ""))]
		"battle_orders":
			var parts := PackedStringArray()
			for o: Dictionary in d.get("orders", []):
				var t := String(o.get("type", "?"))
				if o.has("x"):
					t += " to (%.0f, %.0f)" % [float(o["x"]) / ContextView.ONE, float(o["y"]) / ContextView.ONE]
				if o.has("target"):
					t += " squad %d" % (int(o["target"]) & 0xffff)
				parts.append("squad %d %s" % [int(o["squad"]) & 0xffff, t])
			return "battle orders: %s" % (", ".join(parts) if not parts.is_empty() else "none")
		"reinforce":
			return "%s: reinforce with squad %d" % [who, int(d.get("squad", -1)) & 0xffff]
		"transfer":
			return "squad %d to %s" % [int(d.get("squad", -1)) & 0xffff, EventText.commander(int(d.get("to", -1)))]
		"battleforce":
			return "%s: battleforce %s" % [who, String(d.get("preset", "")) if not String(d.get("preset", "")).is_empty() else "strongest first"]
	return "%s: %s" % [String(i["kind"]), _brief(p)]


func _clock() -> String:
	return "turn %d" % (_session.turns_resolved() + 1)


static func _brief(v: Variant) -> String:
	var s := JSON.stringify(v)
	return s if s.length() <= 160 else s.substr(0, 157) + "..."


static func _meta_line(info: Dictionary) -> String:
	var parts := PackedStringArray()
	for k: String in ["map", "seed", "human", "opponent", "started"]:
		if info.has(k):
			parts.append("%s: %s" % [k, str(info[k])])
	return " · ".join(parts)


func _write(file: String, text: String) -> void:
	var f := FileAccess.open(dir + "/" + file, FileAccess.WRITE)
	if f != null:
		f.store_string(text)


func _append(file: String, text: String) -> void:
	var path := dir + "/" + file
	var f := FileAccess.open(path, FileAccess.READ_WRITE) if FileAccess.file_exists(path) else FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.seek_end()
		f.store_string(text)


## Where logs go: ROOT for played games, HEADLESS_ROOT without a display.
static func root_dir() -> String:
	return HEADLESS_ROOT if DisplayServer.get_name() == "headless" else ROOT


## Drops the oldest match folders beyond KEEP.
static func _prune(root: String) -> void:
	var d := DirAccess.open(root)
	if d == null:
		return
	var names := Array(d.get_directories())
	names.sort()
	while names.size() > KEEP:
		var old: String = names.pop_front()
		var sub := DirAccess.open(root + "/" + old)
		if sub != null:
			for f in sub.get_files():
				sub.remove(f)
		d.remove(old)
