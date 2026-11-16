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
	if resolved and match_log != null:
		match_log.turn_resolved()
	return resolved


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
