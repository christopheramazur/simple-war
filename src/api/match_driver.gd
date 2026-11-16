class_name MatchDriver
extends RefCounted
## Runs one match for a human seat (GDD 04 §4.1, O1Q3, sw-ll4.8): makes the
## session, seats the AI opponents, ends turns and keeps the match log. The
## war room draws and takes input; this drives. It uses only the Game API
## (OverworldSession), so anything else that hosts a match (a test, a
## dedicated server, another UI) can use it the same way.

var session: OverworldSession
## The human's player number.
var human: int = 1
## AI opponents: player -> controller (HeadlessOverworld.plan_for/react_for).
var ai: Dictionary = {}
## Written each resolved turn if set.
var match_log: MatchLog
## "turn:phase" the AI last acted in, so it acts once per phase.
var _ai_step: String = ""
## What is being played: {"map", "seed", "profile", "human"}. Saved with the
## game so it can be loaded, or played again.
var meta: Dictionary = {}
## Tallies for the results screen, from every resolved turn's events:
## {"turns", "battles", "players": {player: {"squads_lost",
## "commanders_lost", "features_taken"}}}.
var stats: Dictionary = {"turns": 0, "battles": 0, "players": {}}
## Save to the "autosave" slot after every resolved turn.
var autosave: bool = false

## Where saved games are kept (tests point this elsewhere).
static var save_dir: String = "user://saves"
const SAVE_VERSION: int = 1
const AUTOSAVE := "autosave"
## Every save file starts with this, so other files are never decoded.
const MAGIC := "SIMPLEWAR-SAVE
"
## Why the last save_game / load_game failed ("" on success).
static var last_error: String = ""


func _init(of_session: OverworldSession, human_player: int = 1) -> void:
	session = of_session
	human = human_player


## A session on a map from the core package, at turn 1.
static func play_session(map: String, seed_value: int) -> OverworldSession:
	var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	return OverworldSession.create(l.templates, l.data_hash, map, seed_value)


## Every player but `human_player` played by a controller profile (unknown
## profiles fall back to the default utility profile).
static func opponents(s: OverworldSession, human_player: int, profile: String, seed_value: int) -> Dictionary:
	var values: Dictionary = {}
	if s.templates.has(profile) and s.templates.kind_of(profile) == "controller_profile":
		values = s.templates.values_of(profile)
	var out := {}
	for p in s.players():
		if p != human_player:
			out[p] = ProfileController.new(p, values, seed_value)
	return out


## A UI action for the match log.
func note(text: String) -> void:
	if match_log != null:
		match_log.note(text)


## Ends the human's turn: the AI acts, then every player is readied until
## Planning comes round again, stopping early at a reaction window that
## offers the human something. Returns whether an overworld turn resolved
## (the match log is written then).
func end_turn() -> bool:
	var before := session.turns_resolved()
	for i in 4:
		ai_act()
		for p in session.players():
			session.ready(p)
		var ph := session.clock.phase
		if ph == PulseClock.Phase.PLANNING:
			break
		if ph == PulseClock.Phase.REACTION and not session.reaction_opportunities(human).is_empty():
			break
	var resolved := session.turns_resolved() != before
	if resolved:
		tally(session.last_events)
		if match_log != null:
			match_log.turn_resolved()
		if autosave:
			save_game(AUTOSAVE)
	return resolved


## Adds a resolved turn's events to the tallies.
func tally(events: Array) -> void:
	stats["turns"] = session.turns_resolved()
	var players: Dictionary = stats["players"]
	for p in session.players():
		if not players.has(p):
			players[p] = {"squads_lost": 0, "commanders_lost": 0, "features_taken": 0}
	for e: SimEvent in events:
		var who := int(e.data.get("player", 0))
		match e.type:
			&"engagement_started":
				stats["battles"] = int(stats["battles"]) + 1
			&"squads_lost":
				if players.has(who):
					players[who]["squads_lost"] += int(e.data.get("count", 0))
			&"commander_defeated":
				if players.has(who):
					players[who]["commanders_lost"] += 1
			&"feature_captured":
				if players.has(who):
					players[who]["features_taken"] += 1


# --- save and load ---------------------------------------------------------------

## Saves the game to a slot in user://saves (a file name without
## extension; "" makes one from the map and the time). Any phase but
## Execute. Returns the file's path, or "" (see last_error).
func save_game(slot: String = "") -> String:
	last_error = ""
	if session.clock.phase == PulseClock.Phase.EXECUTE:
		last_error = "the turn is resolving"
		return ""
	if slot.is_empty():
		slot = "%s-turn%d-%s" % [session.map_id, session.turns_resolved() + 1,
			Time.get_datetime_string_from_system(false, false).replace(":", "").replace("-", "").replace("T", "-")]
	DirAccess.make_dir_recursive_absolute(save_dir)
	var info := meta.duplicate(true)
	info.merge({"map": session.map_id, "seed": session.seed_value, "human": human, "turn": session.turns_resolved() + 1,
		"saved": Time.get_datetime_string_from_system(false, true), "stats": stats.duplicate(true)}, true)
	var path := "%s/%s.sav" % [save_dir, slot.validate_filename()]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		last_error = "could not write " + path
		return ""
	f.store_buffer(MAGIC.to_utf8_buffer())
	f.store_buffer(var_to_bytes({"version": SAVE_VERSION, "meta": info, "session": session.save()}))
	f.close()
	return path


## The saved games, newest first: [{"path", "slot", "map", "turn",
## "profile", "saved"}]. Files that can't be read are left out.
static func saves() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var d := DirAccess.open(save_dir)
	if d == null:
		return out
	for file in d.get_files():
		if not file.ends_with(".sav"):
			continue
		var path := save_dir + "/" + file
		var data: Variant = _read(path)
		if data == null:
			continue
		var info: Dictionary = data["meta"]
		out.append({"path": path, "slot": file.get_basename(), "map": String(info.get("map", "")), "turn": int(info.get("turn", 1)),
			"profile": String(info.get("profile", "")), "saved": String(info.get("saved", "")),
			"time": FileAccess.get_modified_time(path)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["time"] > b["time"] if a["time"] != b["time"] else String(a["slot"]) < String(b["slot"]))
	return out


static func _read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	var head := MAGIC.to_utf8_buffer()
	if bytes.size() <= head.size() or bytes.slice(0, head.size()) != head:
		return null
	var data: Variant = bytes_to_var(bytes.slice(head.size()))
	if typeof(data) != TYPE_DICTIONARY or data.get("version") != SAVE_VERSION or not data.get("meta") is Dictionary or not data.get("session") is PackedByteArray:
		return null
	return data


## Loads a saved game with the core package: the session where it was
## left, the same AI profile in the other seats, the tallies so far. Null
## if the file is unreadable or the content has changed (see last_error).
## The AI's own memory is not saved: it plans afresh from the loaded state.
static func load_game(path: String) -> MatchDriver:
	last_error = ""
	var data: Variant = _read(path)
	if data == null:
		last_error = "unreadable save"
		return null
	var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	var s := OverworldSession.load_save(data["session"], l.templates, l.data_hash)
	if s == null:
		last_error = OverworldSession.last_error
		return null
	var info: Dictionary = data["meta"]
	var m := MatchDriver.new(s, int(info.get("human", 1)))
	m.meta = {"map": s.map_id, "seed": s.seed_value, "profile": String(info.get("profile", "")), "human": m.human}
	if info.get("stats") is Dictionary:
		m.stats = (info["stats"] as Dictionary).duplicate(true)
	if not String(m.meta["profile"]).is_empty():
		m.ai = opponents(s, m.human, m.meta["profile"], s.seed_value)
	return m


## The AI opponents plan or react, once per phase, from the same state the
## human saw (simultaneous turns).
func ai_act() -> void:
	if ai.is_empty() or not session.state.outcome.is_empty():
		return
	var step := "%d:%d" % [session.turns_resolved(), session.clock.phase]
	if step == _ai_step:
		return
	_ai_step = step
	for p: int in ai:
		match session.clock.phase:
			PulseClock.Phase.PLANNING:
				HeadlessOverworld.plan_for(session, p, ai[p])
			PulseClock.Phase.REACTION:
				HeadlessOverworld.react_for(session, p, ai[p])
