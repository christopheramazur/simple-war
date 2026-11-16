class_name MapPlaytest
extends RefCounted
## "Play this map" (GDD 04 §4.9, O1Q6): a match that opens in a battle on a
## battle map as it is painted right now, saved or not. Nothing is written.
##
## The battle map alone is not a match, so this adds two templates in memory:
## a scenario on the map (the core field scenario's rules, with a deployment
## strip down the left and right edges and one zone in the middle) and a
## four-hex overworld whose two commanders meet at once. Player 1 attacks
## player 2, so the war room opens with the battle already begun.

const SCENARIO := "playtest_scenario"
const OVERWORLD := "playtest_overworld"
## Core templates the playtest borrows.
const BASE_SCENARIO := "ow_field"
const COMMANDER := "field_commander"
const HEX := "hex_plains"


## {"session": OverworldSession or null, "errors": PackedStringArray}.
static func start(model: PackageEditor, canvas: MapCanvas, seed_value: int = 1) -> Dictionary:
	var errors := PackedStringArray()
	var t := model.templates
	for need: String in [BASE_SCENARIO, COMMANDER, HEX]:
		if not t.has(need):
			errors.append("the package has no '%s', which the playtest borrows" % need)
	var map_def: Variant = JSON.parse_string(canvas.definition_text())
	if not map_def is Dictionary:
		errors.append("the map could not be written as data")
	if not errors.is_empty():
		return {"session": null, "errors": errors}
	var table := model.table_with({canvas.id: map_def, SCENARIO: scenario(t, canvas), OVERWORLD: overworld()})
	errors = table.errors.duplicate() if not table.is_valid() else DataSchema.validate(table)
	if errors.is_empty():
		errors = BattleRules.compile(table, SCENARIO).errors.duplicate()
	if not errors.is_empty():
		return {"session": null, "errors": errors}
	var s := OverworldSession.create(table, "playtest", OVERWORLD, seed_value)
	if s == null:
		return {"session": null, "errors": PackedStringArray([OverworldSession.last_error])}
	var mine := -1
	var theirs := -1
	for id in s.state.commanders.ids():
		if s.state.commanders.get_value(id, &"player") == 1:
			mine = id
		else:
			theirs = s.state.commanders.get_value(id, &"plot")
	var err := s.set_route(1, mine, PackedInt64Array([theirs]))
	if not err.is_empty():
		return {"session": null, "errors": PackedStringArray([err])}
	for i in 2:  # planning -> intermission -> planning: the battle begins
		for p in s.players():
			s.ready(p)
	if s.battles.is_empty():
		return {"session": null, "errors": PackedStringArray(["the playtest battle did not begin"])}
	return {"session": s, "errors": errors}


## A scenario on the canvas's map: the base scenario's rules, with a
## deployment strip inside each short edge and one zone in the middle.
static func scenario(t: TemplateTable, canvas: MapCanvas) -> Dictionary:
	var v: Dictionary = t.values_of(BASE_SCENARIO).duplicate(true)
	var w := canvas.width
	var h := canvas.height
	var inset := clampi(w / 24, 1, 5)
	var deep := clampi(w / 6, 2, 25)
	var top := h * 15 / 100
	var tall := maxi(h - 2 * top, 1)
	v["name"] = "Playtest: " + canvas.name
	v["map"] = canvas.id
	for k: String in ["width", "height", "terrain_default", "terrain", "triggers"]:
		v.erase(k)
	v["sides"] = [
		{"player": 1, "facing": 0, "deploy": {"x": inset, "y": top, "w": deep, "h": tall}, "squads": []},
		{"player": 2, "facing": 32768, "deploy": {"x": w - inset - deep, "y": top, "w": deep, "h": tall}, "squads": []},
	]
	v["zones"] = [{"id": "centre", "x": w / 2, "y": h / 2, "radius": clampi(mini(w, h) / 6, 2, 12),
		"decay": 10, "threshold": 10, "buffer": 10, "vp": 1}]
	return {"id": SCENARIO, "kind": "scenario", "values": v}


## Four hexes in a row, a commander each for players 1 and 2 side by side.
static func overworld() -> Dictionary:
	return {"id": OVERWORLD, "kind": "overworld_map", "values": {
		"name": "Playtest", "width": 4, "height": 1, "base_move_cost": 10,
		"battleforce": {"squads": 3, "value": 250}, "battle_scenario": SCENARIO, "elimination": true,
		"passes": [{"op": "fill", "feature": HEX}],
		"starts": [{"player": 1, "commander": COMMANDER, "col": 1, "row": 0},
			{"player": 2, "commander": COMMANDER, "col": 2, "row": 0}]}}
