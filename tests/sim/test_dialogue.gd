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
