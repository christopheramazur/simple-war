extends GutTest
## The dialogue data model (GDD 03 §3.5, R3Q18). Task sw-cgl.4: graph
## validation, choices moving sim-side disposition variables, and the
## start_dialogue trigger action.

const NODES := {
	"hi": {"speaker": "jeff", "text": "Hello", "choices": [
		{"text": "Warm", "next": "bye", "do": [{"do": "add_var", "name": "disp.jeff", "value": 2}]},
		{"text": "Close", "next": "bye", "if": [{"check": "var", "name": "disp.jeff", "op": ">=", "value": 2}]}]},
	"bye": {"speaker": "jeff", "text": "Bye", "do": [{"do": "set_var", "name": "met", "value": 1}]},
}

static var _loader: PackageLoader


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://tests/fixtures/rules"]))
	return _loader


func _state() -> OverworldState:
	var r := OverworldRules.compile(_l().templates, "trigger_vale", _l().data_hash)
	return OverworldState.create(1, r, 7)


func test_problems() -> void:
	assert_eq(Dialogue.problems({"start": "hi", "nodes": NODES}), PackedStringArray())
	var bad := {"start": "zz", "nodes": {"a": {"next": "q", "choices": [], "oops": 1,
		"do": [{"do": "add_feature"}]}, "b": {"choices": [{"next": "nope", "if": [{"check": "owns"}]}]}}}
	assert_eq(Dialogue.problems(bad).size(), 7, "; ".join(Dialogue.problems(bad)))
	var t := TemplateTable.build([{"id": "d", "kind": "dialogue", "values": {"start": "hi", "nodes": NODES}},
		{"id": "e", "kind": "dialogue", "values": {"start": "x", "nodes": NODES}}])
	var errs := DataSchema.validate(t)
	assert_eq(errs.size(), 1)
	assert_string_contains(errs[0], "e: start 'x'")


func test_choices_move_dispositions() -> void:
	var s := _state()
	var v := {"start": "hi", "nodes": NODES}
	assert_eq(Dialogue.available(s, v, "hi"), PackedInt32Array([0]), "the second choice needs warmth")
	assert_eq(Dialogue.choose(s, v, "hi", 1), "", "an unavailable choice does nothing")
	assert_eq(Dialogue.choose(s, v, "hi", 0), "bye")
	assert_eq(s.vars["disp.jeff"], 2)
	assert_eq(Dialogue.available(s, v, "hi"), PackedInt32Array([0, 1]))
	Dialogue.enter(s, v, "bye")
	assert_eq(s.vars["met"], 1)


func test_start_dialogue_action() -> void:
	var t := TemplateTable.build([
		{"id": "d", "kind": "dialogue", "values": {"start": "hi", "nodes": NODES}},
		{"id": "ok", "kind": "trigger", "values": {"on": "turn_resolved", "do": [{"do": "start_dialogue", "dialogue": "d", "player": 1}]}},
		{"id": "bad", "kind": "trigger", "values": {"on": "turn_resolved", "do": [{"do": "start_dialogue", "dialogue": "ok"}]}}])
	assert_eq(TriggerRules.compile(t, PackedStringArray(["ok"]), "battle").errors, PackedStringArray())
	assert_eq(TriggerRules.compile(t, PackedStringArray(["bad"]), "battle").errors.size(), 1)
	var s := _state()
	var rules := TriggerRules.compile(t, PackedStringArray(["ok"]), "overworld")
	rules.run(s, [])
	var found := s.events.drain().filter(func(e: SimEvent) -> bool: return e.type == &"dialogue_started")
	assert_eq(found.size(), 1)
	assert_eq(found[0].data["dialogue"], "d")


func test_session_plays_dialogue_and_saves_progress() -> void:
	var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	var s := OverworldSession.create(l.templates, l.data_hash, "angelfall_frontier", 7)
	var id := "af_jeff_briefing"
	var v := s.dialogue_view(id)
	assert_eq(v["node"], "greet")
	assert_eq(v["choices"].size(), 2, "the trust choice needs warmth")
	assert_eq(s.dialogue_pick(1, id, 0), "the dialogue has not begun")
	assert_eq(s.dialogue_begin(1, id), "")
	assert_eq(s.dialogue_pick(1, id, 2), "that choice is not available")
	assert_eq(s.dialogue_pick(1, id, 0), "")
	assert_eq(s.state.vars["disp.jeff"], 1)
	assert_eq(s.dialogue_view(id)["node"], "fast")
	assert_eq(s.dialogue_pick(1, id, -1), "")
	assert_eq(s.dialogue_pick(1, id, -1), "")
	assert_true(s.dialogue_view(id)["ended"])
	var back := OverworldSession.load_save(s.save(), l.templates, l.data_hash)
	assert_true(back.dialogue_view(id)["ended"], "progress survives a save")
	assert_eq(back.state_hash_hex(), s.state_hash_hex())
