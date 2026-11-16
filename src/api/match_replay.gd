class_name MatchReplay
extends RefCounted
## A recorded match played back turn by turn (sw-ll4.22, R8Q5). A match log
## folder (MatchLog) holds `match.sav`: the session's inputs and the state
## hash after every turn. This starts a fresh session on the same map and
## seed and feeds it those inputs one turn at a time, checking each turn's
## hash, so whatever hosts it (the war room) can show every turn as it
## happened, from any player's side.
##
## The session takes no other orders while it is a replay (`locked`).

## Why the last `open` returned null ("" on success).
static var last_error: String = ""

var session: OverworldSession
## match.json: {"map", "seed", "human", "opponent", "started", ...}.
var info: Dictionary = {}
## The folder it was opened from.
var dir: String = ""
## The first turn whose hash did not match the recording, or -1.
var diverged_turn: int = -1

var _inputs: Array = []
var _next: int = 0
var _hashes: PackedStringArray = PackedStringArray()


## Recorded matches, newest first: [{"dir", "name", "map", "seed",
## "opponent", "started"}]. Folders without a save are left out.
static func list(root: String = "") -> Array[Dictionary]:
	if root.is_empty():
		root = MatchLog.root_dir()
	var out: Array[Dictionary] = []
	var d := DirAccess.open(root)
	if d == null:
		return out
	var names := Array(d.get_directories())
	names.sort()
	names.reverse()
	for n: String in names:
		var path := root + "/" + n
		if not FileAccess.file_exists(path + "/match.sav"):
			continue
		var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(path + "/match.json"))
		var m: Dictionary = meta if meta is Dictionary else {}
		out.append({"dir": path, "name": n, "map": str(m.get("map", "")), "seed": int(m.get("seed", 0)),
			"opponent": str(m.get("opponent", "")), "started": str(m.get("started", ""))})
	return out


## Opens the match recorded in a folder, at turn 1, with the core package.
## Null if there is no save or the content has changed since (last_error).
static func open(folder: String) -> MatchReplay:
	last_error = ""
	if not FileAccess.file_exists(folder + "/match.sav"):
		last_error = "no recording in " + folder
		return null
	var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	var data: Variant = OverworldSession._decode(FileAccess.get_file_as_bytes(folder + "/match.sav"))
	if typeof(data) != TYPE_DICTIONARY or not data.has("inputs"):
		last_error = "unreadable recording"
		return null
	if data.get("data_hash") != l.data_hash:
		last_error = "the game's content has changed since this match was recorded"
		return null
	var s := OverworldSession.create(l.templates, l.data_hash, data["map"], data["seed"], OverworldSession._config_from(data["clock_config"]))
	if s == null:
		last_error = OverworldSession.last_error
		return null
	var r := MatchReplay.new()
	r.session = s
	r.dir = folder
	r._inputs = data["inputs"]
	r._hashes = data["hashes"]
	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder + "/match.json"))
	if meta is Dictionary:
		r.info = meta
	s.locked = true
	return r


## Turns in the recording.
func turns() -> int:
	return _hashes.size()


## Whether every recorded turn has been played.
func at_end() -> bool:
	return session.turns_resolved() >= _hashes.size()


## Plays the next recorded turn: feeds the session its inputs until the
## turn resolves. Returns whether a turn resolved (false at the end).
func step() -> bool:
	if at_end():
		return false
	var before := session.turns_resolved()
	while _next < _inputs.size() and session.turns_resolved() == before:
		session.replay_inputs([_inputs[_next]])
		_next += 1
	var resolved := session.turns_resolved() != before
	if resolved and diverged_turn < 0 and session.turn_hashes[before] != _hashes[before]:
		diverged_turn = before + 1
	return resolved
