extends GutTest
## The inspection call: effective stats with traces, active effects,
## accumulator progress, deception disguises, visibility (GDD 02 §2.13,
## E2Q3, E2Q12, E3Q8). Task sw-ps1.6.

const ONE := Fixed.ONE
const ACC := "weapon.modes.*.accuracy"

static var _loader: PackageLoader
static var _rules_cache: BattleRules


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	return _loader


func _rules() -> BattleRules:
	if _rules_cache == null:
		_rules_cache = BattleRules.compile(_l().templates, "duel_crossroads", _l().data_hash)
	return _rules_cache


func _place(s: BattleState, player: int, squad: String, x: int, y: int = 50) -> int:
	var sid := BattleSetup.spawn_squad(s, player, s.rules.squad_index(squad), x * ONE, y * ONE, 0)
	Centroids.update(s)
	return sid


func _b(id: String) -> int:
	return _rules().fx.index_of(id)


## The first stat entry with this ID (and label, if given).
func _stat(list: Array, stat: String, label: String = "") -> Dictionary:
	for e: Dictionary in list:
		if e["stat"] == stat and (label.is_empty() or e["label"] == label):
			return e
	return {}


func _effect(view: Dictionary, bundle: String) -> Dictionary:
	for e: Dictionary in view["effects"]:
		if e["bundle"] == bundle:
			return e
	return {}


func test_plain_squad() -> void:
	var s := BattleState.new(1, _rules(), 1)
	var sid := _place(s, 1, "rifle_squad", 40)
	var v := Inspection.squad(s, sid, 1)
	assert_eq(v["name"], "Rifle squad")
	var sight := _stat(v["stats"], "squad.sight")
	assert_eq(sight["value"], 45 * ONE)
	assert_eq(sight["name"], "Sight")
	assert_eq(sight["trace"].map(func(t: Dictionary) -> String: return t["step"]), ["base", "result"])
	assert_false(_stat(v["stats"], "squad.pools.morale.capacity").is_empty(), "owner sees pool capacities")
	assert_eq(v["units"].size(), 8)
	var leader: Dictionary = v["units"][0]
	assert_eq(leader["name"], "Sergeant")
	assert_eq(_stat(leader["stats"], "unit.hp")["value"], 12 * ONE)
	assert_eq(_stat(leader["stats"], ACC, "aimed")["value"], _rules().md_accuracy[_rules().wp_mode_start[_rules().ut_weapon[_rules().unit_ids.find("sergeant")]]])
	assert_false(_stat(leader["stats"], "weapon.modes.*.damage", "burst").is_empty(), "every fire mode")
	assert_eq(v["effects"], [])
	var halt: Dictionary = v["abilities"].filter(func(a: Dictionary) -> bool: return a["id"] == "halt")[0]
	assert_eq(halt["costs"], {"instinct": 8 * ONE})
	assert_eq(halt["lines"][0], "Reaction.")


func test_trace_names_its_sources() -> void:
	var s := BattleState.new(1, _rules(), 1)
	var sid := _place(s, 1, "rifle_squad", 40)
	Effects.apply(s, _b("inspired"), sid)
	s.tick = 20
	EffectSystem.new().run(s)
	var v := Inspection.squad(s, sid, 1)
	var acc := _stat(v["units"][1]["stats"], ACC, "aimed")
	assert_eq(acc["value"], Fixed.mul_ratio(acc["base"], 120, 100))
	var more: Dictionary = acc["trace"].filter(func(t: Dictionary) -> bool: return t["step"] == "more")[0]
	assert_eq(more["terms"], [{"source": "inspired", "name": "Inspired", "amount": 20 * ONE}])
	var e := _effect(v, "inspired")
	assert_eq(e["remaining_ticks"], 100 - 20, "10 s at 10 ticks/s, 2 s gone")
	assert_eq(e["lines"][0], "20% more Accuracy")
	assert_eq(e["accumulator"], {})


func test_accumulator_progress() -> void:
	var s := BattleState.new(1, _rules(), 1)
	var sid := _place(s, 1, "rifle_squad", 40)
	Effects.apply(s, _b("steady_aim"), sid)
	EffectSystem.new().run(s)
	Effects.on_event(s, "hit", sid, -1, -1, -1, ONE)
	var acc: Dictionary = _effect(Inspection.squad(s, sid, 1), "steady_aim")["accumulator"]
	assert_eq(acc["next_in"], 2 * ONE)
	assert_eq(acc["text"], "Next in 2 hits")
	Effects.on_event(s, "hit", sid, -1, -1, -1, ONE)
	assert_eq(_effect(Inspection.squad(s, sid, 1), "steady_aim")["accumulator"]["text"], "Next in 1 hit")


func test_deception_shows_the_disguise_to_others() -> void:
	var s := BattleState.new(1, _rules(), 1)
	var sid := _place(s, 1, "rifle_squad", 40)
	Effects.apply(s, _b("feigned_rout"), sid)
	EffectSystem.new().run(s)
	var mine := Inspection.squad(s, sid, 1)
	assert_false(_effect(mine, "feigned_rout").is_empty(), "the owner sees the truth")
	var unit: Dictionary = mine["units"][1]
	var acc := _stat(unit["stats"], ACC, "aimed")
	assert_eq(acc["value"], Fixed.mul_ratio(acc["base"], 130, 100))
	var theirs := Inspection.squad(s, sid, 2)
	assert_true(_effect(theirs, "feigned_rout").is_empty())
	assert_eq(_effect(theirs, "shaken")["name"], "Shaken")
	var tunit: Dictionary = theirs["units"][1]
	assert_eq(_stat(tunit["stats"], ACC, "aimed")["value"], acc["base"], "real accuracy bonus hidden")
	var ev := _stat(tunit["stats"], "defense.evasion_pct")
	assert_eq(ev["value"], maxi(ev["base"] - 10 * ONE, 0), "disguise's -10 evasion shown (clamped at 0)")
	var flat: Dictionary = ev["trace"].filter(func(t: Dictionary) -> bool: return t["step"] == "flat")[0]
	assert_eq(flat["value"], ev["base"] - 10 * ONE)
	assert_eq(flat["terms"][0]["name"], "Shaken")
	assert_false(theirs.has("abilities"), "enemy abilities stay hidden")
	assert_true(_stat(theirs["stats"], "squad.pools.morale.capacity").is_empty(), "enemy pools stay hidden")


func test_session_inspect_respects_visibility() -> void:
	var s := BattleSession.create(_l().templates, _l().data_hash, "duel_crossroads", 11)
	var mine: int = s.observe(1)["squads"][0]["id"]
	var theirs: int = s.observe(2)["squads"][0]["id"]
	assert_true(s.inspect(1, mine).has("abilities"))
	assert_eq(s.inspect(1, theirs), {}, "enemy out of sight: nothing")
	assert_eq(s.inspect(1, 999), {})
	var row := s.state.squads.row_of(theirs)
	s.state.squads.set_value(theirs, &"seen_by", s.state.squads.seen_by[row] | BattleSquads.bit(1))
	var v := s.inspect(1, theirs)
	assert_eq(v["id"], theirs, "seen: inspectable")
	assert_false(v.has("abilities"))


func test_inspection_leaves_state_untouched() -> void:
	var s := BattleState.new(1, _rules(), 1)
	var sid := _place(s, 1, "scout_team", 40)
	_place(s, 2, "rifle_squad", 60)
	Effects.apply(s, _b("feigned_rout"), sid)
	EffectSystem.new().run(s)
	var before := s.state_hash_hex()
	Inspection.squad(s, sid, 1)
	Inspection.squad(s, sid, 2)
	assert_eq(s.state_hash_hex(), before)
