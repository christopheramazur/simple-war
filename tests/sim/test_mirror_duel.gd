extends GutTest
## Mirror-swap regression (sw-0nl): duel_crossroads is 180-degree rotation
## symmetric and both seats play the same profile, so swapping the players
## between the two sides must swap the result — not keep handing seat 1 the
## win. GDD 01 determinism pillar, 02 §2.2/§2.5 (R5Q17).

const ONE := Fixed.ONE

static var _loader: PackageLoader


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://tests/fixtures/rules"]))
	return _loader


## The fixture duel, optionally with the two sides' players exchanged (the
## seat swap). Facings stay with their seats: the east seat always faces west.
func _templates(swapped: bool) -> TemplateTable:
	var defs := _l().defs.duplicate(true)
	if swapped:
		for d: Dictionary in defs:
			if d.get("id") == "duel_crossroads" and d.get("kind") == "scenario":
				var sides: Array = d["values"]["sides"]
				var p: int = sides[0]["player"]
				sides[0]["player"] = sides[1]["player"]
				sides[1]["player"] = p
	var t := TemplateTable.build(defs)
	assert_true(t.is_valid(), "\n".join(t.errors))
	return t


## Plays the duel headless with the baseline (zone) profile on both seats,
## exactly as hx sim run does, and returns the result.
func _play(swapped: bool, seed_value: int) -> Dictionary:
	var t := _templates(swapped)
	var s := BattleSession.create(t, PackageLoader._hash(t), "duel_crossroads", seed_value)
	assert_not_null(s)
	var controllers := {
		1: ProfileController.new(1, SimVariant.builtin("zone"), seed_value),
		2: ProfileController.new(2, SimVariant.builtin("zone"), seed_value),
	}
	HeadlessDuel.play(s, controllers, 50)
	assert_true(s.is_over(), "the duel ran to its end")
	return s.state.result


func test_swapping_seats_swaps_the_result() -> void:
	for seed_value in [1, 2]:
		var a := _play(false, seed_value)
		var b := _play(true, seed_value)
		var wa: int = a["winner"]
		if wa == 0:
			assert_eq(b["winner"], 0, "a drawn mirror duel stays drawn (seed %d)" % seed_value)
		else:
			assert_true(wa in [1, 2], "a winner, not a forfeit: %s" % str(a))
			assert_eq(b["winner"], 3 - wa, "the other seat wins the seat-swapped duel (seed %d)" % seed_value)
		assert_eq(b["reason"], a["reason"], "same ending (seed %d)" % seed_value)
		assert_eq(b["turn"], a["turn"], "same length (seed %d)" % seed_value)
		for p: int in [1, 2]:
			var q: int = 3 - p
			assert_eq(b["scores"][p]["influence"], a["scores"][q]["influence"], "influence mirrors (seed %d)" % seed_value)
			assert_eq(b["scores"][p]["value"], a["scores"][q]["value"], "value mirrors (seed %d)" % seed_value)


func test_zone_ties_follow_the_side_facing() -> void:
	# Two unheld zones exactly equidistant from the squad: west-south and
	# east-north. The tie goes to the lowest x then y in the side's frame.
	var obs := {
		"zones": [
			{"owner": 0, "amount": 0, "threshold": 10, "x": 145 * ONE, "y": 30 * ONE},
			{"owner": 0, "amount": 0, "threshold": 10, "x": 55 * ONE, "y": 70 * ONE},
		],
		"squads": [{"id": 1, "player": 1, "destroyed": false, "withdrawn": false,
			"hp_lost": 0, "hp_max": 100, "order": "hold", "x": 100 * ONE, "y": 50 * ONE}],
	}
	var west := ZoneController.new(1)
	var east := ZoneController.new(1)
	east.facing = Fixed.ANGLE_HALF
	assert_eq([west.orders(obs)[0]["x"], west.orders(obs)[0]["y"]], [55 * ONE, 70 * ONE], "facing 0 takes the west zone")
	assert_eq([east.orders(obs)[0]["x"], east.orders(obs)[0]["y"]], [145 * ONE, 30 * ONE], "facing 180 takes the east zone")
	obs["zones"].reverse()
	assert_eq(west.orders(obs)[0]["x"], 55 * ONE, "list order never decides")
	assert_eq(east.orders(obs)[0]["x"], 145 * ONE, "list order never decides, flipped either")


func test_zone_controller_reads_its_side_facing() -> void:
	var r := BattleRules.compile(_templates(false), "duel_crossroads")
	var z1 := ZoneController.new(1)
	var z2 := ZoneController.new(2)
	z1.set_battle_rules(r)
	z2.set_battle_rules(r)
	assert_eq(z1.facing, 0)
	assert_eq(z2.facing, Fixed.ANGLE_HALF)
