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
## What a fresh session is built from (rewind).
var _templates: Variant
var _data_hash: Variant
var _map: Variant
var _seed: Variant
var _clock_config: Variant
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
	s.keep_playback = true  # the relations at a frame need the turn's record (sw-bafi.5)
	var r := MatchReplay.new()
	r.session = s
	r.dir = folder
	r._templates = l.templates
	r._data_hash = l.data_hash
	r._map = data["map"]
	r._seed = data["seed"]
	r._clock_config = data["clock_config"]
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


## Goes to the start of the given turn (turns already played: 0 = the
## beginning; clamped to the recording). Going back starts a fresh session
## (`session` is then a new object: hosts re-read it) and plays it forward
## again, so every turn on the way is checked against its recorded hash.
## Returns whether `session` was replaced.
func seek(played: int) -> bool:
	played = clampi(played, 0, turns())
	var replaced := false
	if played < session.turns_resolved():
		var s := OverworldSession.create(_templates, _data_hash, _map, _seed, OverworldSession._config_from(_clock_config))
		if s == null:
			return false
		session = s
		s.locked = true
		s.keep_playback = true
		_next = 0
		diverged_turn = -1
		replaced = true
	while session.turns_resolved() < played and step():
		pass
	return replaced


## SquadRelation.facts(a, b) at playback frame `frame` of battle `eid` in the
## last turn played, as `player` sees it (0: all-seeing). See
## OverworldSession.playback_relation; [] when there is nothing to show.
func playback_relation(player: int, eid: int, frame: int, a: int, b: int) -> Array:
	return session.playback_relation(player, eid, frame, a, b)


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
