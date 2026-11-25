extends GutTest
## The squad card's activity line and weapon status (sw-ll4.27.3): what the
## squad is doing and why its guns are silent, in the glossary's words, from
## the BattleActivity codes the API reports; per weapon the range band, ammo,
## timers and shots / hits; during playback the card follows the shown
## moment (SquadCard.moment), never the end-of-turn state. Every number is
## the simulation's; the playback fixture is a hand-built playback record.

const ONE := Fixed.ONE

var _session: BattleSession
var _templates: TemplateTable
var _sid: int = -1
var _row: int = -1


func before_each() -> void:
	var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	_templates = l.templates
	_session = BattleSession.create(l.templates, l.data_hash, "duel_crossroads", 11)
	for q: Dictionary in _session.observe(1)["squads"]:
		if q["player"] == 1 and q["template"] == "rifle_squad":
			_sid = q["id"]
			break
	_row = _session.state.squads.row_of(_sid)


func _squad() -> Dictionary:
	for q: Dictionary in _session.observe(1)["squads"]:
		if q["id"] == _sid:
			return q
	return {}


func _ctx() -> Dictionary:
	var r := _session.state.rules
	var names := {}
	for wid: String in r.weapon_index:
		names[wid] = String(_templates.values_of(wid).get("name", wid))
	return {"rules": r, "weapon_names": names}


func _card(squad: Dictionary, insp: Dictionary, verbose: bool = false) -> VBoxContainer:
	var card := SquadCard.build(squad, insp, 1, 10, verbose, _ctx())
	autofree(card)
	return card


func _texts(node: Node, out: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	if node is Label:
		out.append((node as Label).text)
	for c in node.get_children():
		_texts(c, out)
	return out


func test_the_activity_line_is_the_sims_code_in_words() -> void:
	var code := BattleActivity.squad(_session.state, _row)
	var text := "\n".join(_texts(_card(_squad(), _session.inspect(1, _sid))))
	assert_string_contains(text, Glossary.activity_text(code), "the activity line is the glossary's text")
	# The hold-position order still fires: HOLDING is not "holding fire".
	assert_eq(code, BattleActivity.Squad.HOLDING, "a fresh squad holds position")
	assert_false(text.to_lower().contains("holding fire"), "HOLDING never reads as holding fire")


func test_engaged_names_its_target_through_the_panel() -> void:
	var st := _session.state
	var sq := st.squads
	var enemy := -1
	var ename := ""
	for row in sq.count():
		if sq.player[row] == 2 and sq.is_active(row):
			enemy = sq.id_at(row)
			ename = st.rules.sq_names[sq.tmpl[row]]
			sq.seen_by[row] |= BattleSquads.bit(1)
			break
	assert_gt(enemy, -1, "the scenario has an enemy squad")
	st.tick = 5
	sq.engaged[_row] = enemy
	sq.fired_tick[_row] = 4
	assert_eq(BattleActivity.squad(st, _row), BattleActivity.Squad.ENGAGED)
	var panel := BattlePanel.new()
	autofree(panel)
	panel.show_battle("Test", _session.observe(1), _squad(), _session.inspect(1, _sid), 1, 10, false, _ctx())
	assert_string_contains("\n".join(_texts(panel)), "Firing at %s" % ename,
		"the panel resolves the engaged squad's name from the observation")


func test_hold_reasons_read_in_words_and_seconds() -> void:
	var st := _session.state
	var urow := -1
	for r: int in Centroids.units_of(st, _row):
		if st.units.weapon[r] >= 0:
			urow = r
			break
	assert_gt(urow, -1, "the squad has an armed unit")
	var uid := st.units.id_at(urow)
	st.units.set_value(uid, &"reload", 9)
	assert_eq(BattleActivity.hold(st, urow), BattleActivity.Hold.RELOADING)
	var text := "\n".join(_texts(_card(_squad(), _session.inspect(1, _sid))))
	assert_string_contains(text, Glossary.hold_text(BattleActivity.Hold.RELOADING, 9), "the reason in words")
	assert_string_contains(text, "fires in 0.9 s", "ticks converted with the card's tps")
	var vtext := "\n".join(_texts(_card(_squad(), _session.inspect(1, _sid), true)))
	assert_string_contains(vtext, "(9 ticks)", "the exact ticks only at higher verbosity")
	st.units.set_value(uid, &"reload", 0)
	st.units.set_value(uid, &"cooldown", 8)
	assert_eq(BattleActivity.hold(st, urow), BattleActivity.Hold.COOLDOWN)
	text = "\n".join(_texts(_card(_squad(), _session.inspect(1, _sid))))
	assert_string_contains(text, Glossary.hold_text(BattleActivity.Hold.COOLDOWN, 8), "cooldown in words")
	assert_string_contains(text, "fires in 0.8 s", "the mortar-style 'fires in' line")


func test_the_weapon_block_shows_the_sims_numbers() -> void:
	var insp := _session.inspect(1, _sid)
	var u: Dictionary = insp["units"][0]
	var wid := String(u["weapon"])
	var w := int(_session.state.rules.weapon_index[wid])
	var text := "\n".join(_texts(_card(_squad(), insp)))
	assert_string_contains(text, String(_templates.values_of(wid)["name"]), "the weapon's package name")
	assert_string_contains(text, String(_session.state.rules.damage_types[_session.state.rules.wp_type[w]]).capitalize(),
		"the damage type")
	assert_string_contains(text, "Range %s–%s m" % [Fixed.to_display(_session.state.rules.wp_min_range[w]),
		Fixed.to_display(_session.state.rules.wp_range[w])], "the min-max range band")
	assert_string_contains(text, "ammo %d / %d" % [int(u["ammo"]), int(u["magazine"])], "ammo / magazine")
	assert_string_contains(text, "to hit", "the mode's accuracy")
	assert_string_contains(text, "damage", "the mode's damage")
	assert_string_contains(text, "Shots and hits this turn show during playback.",
		"planning omits shots / hits with a note")


# --- the playback moment -----------------------------------------------------

## A hand-built playback record (OverworldSession.playback's shape): two
## frames of a two-unit squad engaging a one-unit enemy at 39 m.
func _rec() -> Dictionary:
	var f0 := {
		101: {"player": 1, "facing": 0, "ids": [1, 2], "units": [Vector2(0, 0), Vector2(2, 0)],
			"tmpls": ["trooper", "trooper"], "hp": [1.0, 1.0], "acts": [0, 0],
			"activity": BattleActivity.Squad.READY,
			"holds": [BattleActivity.Hold.NONE, BattleActivity.Hold.RELOADING],
			"reload": [0, 9], "cooldown": [0, 0], "ammo": [30, 0]},
		202: {"player": 2, "facing": 0, "ids": [99], "units": [Vector2(39, 0)],
			"tmpls": ["trooper"], "hp": [1.0], "acts": [0], "activity": BattleActivity.Squad.IDLE},
	}
	var f1 := {
		101: {"player": 1, "facing": 0, "ids": [1, 2], "units": [Vector2(0, 0), Vector2(2, 0)],
			"tmpls": ["trooper", "trooper"], "hp": [1.0, 1.0], "acts": [0, 0],
			"activity": BattleActivity.Squad.ENGAGED,
			"holds": [BattleActivity.Hold.NONE, BattleActivity.Hold.NONE],
			"reload": [0, 0], "cooldown": [0, 0], "ammo": [29, 30]},
		202: f0[202],
	}
	return {"frames": [f0, f1], "volleys": [[1, 1, 99, true]], "hits": [[1, 99, 3 * ONE, 1]], "shots": []}


func _base() -> Dictionary:
	var squad := {"id": 101, "player": 1, "name": "Rifle squad", "template": "rifle_squad",
		"alive": 2, "size": 2, "hp_max": 20 * ONE, "hp_lost": 0,
		"activity": BattleActivity.Squad.IDLE, "target": -1, "range": 40 * ONE, "sight": 30 * ONE}
	var units := []
	for uid: int in [1, 2]:
		units.append({"id": uid, "template": "trooper", "name": "Trooper", "hp": 10 * ONE, "hp_max": 10 * ONE,
			"stats": [], "weapon": "rifle", "hold": BattleActivity.Hold.NONE, "ammo": 30, "magazine": 30,
			"reload": 0, "cooldown": 0, "victim": -1, "victim_dist": 0})
	return {"squad": squad, "insp": {"id": 101, "activity": BattleActivity.Squad.IDLE, "target": -1, "units": units}}


func test_the_card_follows_the_shown_moment() -> void:
	var rec := _rec()
	var base := _base()
	var m0 := SquadCard.moment(rec, 0.0, 101, 1, base["squad"], base["insp"])
	assert_eq(int(m0["squad"]["activity"]), BattleActivity.Squad.READY, "frame 0's activity")
	var text0 := "\n".join(_texts(_card(m0["squad"], m0["insp"])))
	assert_string_contains(text0, Glossary.activity_text(BattleActivity.Squad.READY), "the moment's activity in words")
	assert_string_contains(text0, Glossary.hold_text(BattleActivity.Hold.RELOADING, 9), "the hold reason at that moment")
	assert_string_contains(text0, "fires in 0.9 s", "the timer at that moment")
	assert_string_contains(text0, "0 shots, 0 hits", "nothing fired yet")
	var m1 := SquadCard.moment(rec, 1.0, 101, 1, base["squad"], base["insp"])
	assert_eq(int(m1["squad"]["activity"]), BattleActivity.Squad.ENGAGED, "frame 1's activity")
	assert_eq(int(m1["squad"]["target"]), 202, "the target comes from the moment's volleys")
	var u1: Dictionary = (m1["insp"]["units"] as Array)[0]
	assert_eq(int(u1["victim"]), 99, "the latest volley's victim")
	assert_eq(int(u1["victim_dist"]), 39 * ONE, "the distance from the frame's positions")
	assert_eq(int(u1["shots"]), 1)
	assert_eq(int(u1["hits"]), 1)
	assert_eq(int(u1["ammo"]), 29, "the frame's ammo, not the end of turn's")
	var ctx := _ctx()
	ctx["target_name"] = "Enemy squad"
	var card1 := SquadCard.build(m1["squad"], m1["insp"], 1, 10, false, ctx)
	autofree(card1)
	var text1 := "\n".join(_texts(card1))
	assert_string_contains(text1, "Firing at Enemy squad", "engaged at the shown moment")
	assert_string_contains(text1, "target 39 m (in range)", "the range band against the target's distance")
	assert_string_contains(text1, "1 shot, 1 hit", "shots and hits up to the shown frame")
	assert_string_contains(text1, "ammo 29 / 30", "the moment's ammo")
	assert_false(text1.contains("Reloading"), "the reload ended before the shown frame")
	# The bases are the API's dicts: presentation never changes them.
	assert_eq(int((base["insp"]["units"] as Array)[0]["ammo"]), 30, "the base inspection is untouched")
	assert_eq(int(base["squad"]["activity"]), BattleActivity.Squad.IDLE, "the base observation is untouched")


func test_the_moment_counts_the_living_and_the_hurt() -> void:
	var rec := _rec()
	var f2: Dictionary = (rec["frames"][1] as Dictionary)[101].duplicate(true)
	f2["hp"] = [1.0, 0.0]
	(rec["frames"] as Array).append({101: f2, 202: (rec["frames"][1] as Dictionary)[202]})
	var base := _base()
	var m := SquadCard.moment(rec, 1.0, 101, 1, base["squad"], base["insp"])
	assert_eq(int(m["squad"]["alive"]), 1, "a unit at 0 HP is not alive at the moment")
	assert_eq(int(m["squad"]["hp_lost"]), 10 * ONE, "the health bar follows the frame's HP fractions")
	assert_eq(int((m["insp"]["units"] as Array)[1]["hp"]), 0, "the unit's HP is the frame's")


func test_a_squad_outside_the_frame_keeps_the_base() -> void:
	var base := _base()
	var m := SquadCard.moment(_rec(), 1.0, 555, 1, base["squad"], base["insp"])
	assert_eq(m["squad"], base["squad"], "no frame entry: the end state is what is left")
	assert_eq(m["insp"], base["insp"])


# --- the timers and the grouped weapon block (sw-ll4.27.7) -------------------

## Every text line of a card model: label text and wrapped body lines.
func _model_lines(m: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for it: Dictionary in m["items"]:
		if it.has("text"):
			out.append(String(it["text"]))
		elif it.has("wrapped"):
			out.append(String(it["wrapped"]))
	return out


func _count_containing(lines: PackedStringArray, needle: String) -> int:
	var n := 0
	for l: String in lines:
		if l.contains(needle):
			n += 1
	return n


func _cool_total(wid: String) -> int:
	var rules := _session.state.rules
	var w := int(rules.weapon_index[wid])
	var cool := 0
	for m in range(rules.wp_mode_start[w], rules.wp_mode_start[w] + rules.wp_mode_count[w]):
		cool = maxi(cool, int(rules.md_cooldown[m]))
	return cool


func test_fires_in_is_the_longer_timer_not_the_sum() -> void:
	# A magazine emptied under a long cooldown: reload 30 and cooldown 60 tick
	# concurrently, so the wait is 60 ticks (6.0 s at 10 tps), never 90.
	var base := _base()
	var u: Dictionary = (base["insp"]["units"] as Array)[0]
	u["weapon"] = "mortar"
	u["hold"] = BattleActivity.Hold.RELOADING
	u["reload"] = 30
	u["cooldown"] = 60
	u["ammo"] = 0
	base["insp"]["units"] = [u]
	var m := SquadCard.model(base["squad"], base["insp"], 1, 10, false, _ctx())
	var lines := _model_lines(m)
	assert_eq(_count_containing(lines, "fires in 6.0 s"), 1, "the wait is the longer timer")
	assert_eq(_count_containing(lines, "fires in 9.0 s"), 0, "never the sum (9.0 s)")
	assert_eq(_count_containing(lines, Glossary.hold_text(BattleActivity.Hold.COOLDOWN, 60)), 1,
		"the longer cooldown's reason, not Reloading")
	assert_eq(_count_containing(lines, Glossary.hold_text(BattleActivity.Hold.RELOADING, 30)), 0,
		"the sim's RELOADING priority does not hide the longer cooldown")
	# The mini-bar tracks the same longer timer: 60 of the cooldown's total.
	var frac := -1.0
	for it: Dictionary in m["items"]:
		if it.has("progress"):
			frac = float((it["progress"] as Dictionary)["frac"])
	assert_almost_eq(frac, 1.0 - 60.0 / float(_cool_total("mortar")), 0.0001, "the bar follows the cooldown, not the reload")
	assert_gte(frac, 0.0, "a bar that is shown is never negative")


func test_the_progress_bar_follows_the_longer_timer() -> void:
	# Reload is the longer timer here: the bar and the line both read reload.
	var u: Dictionary = {"reload": 60, "cooldown": 30}
	var frac := SquadCard._weapon_progress(u, 100, 120)
	assert_almost_eq(frac, 0.4, 0.0001, "reload total 100, 60 left: 40% done")
	assert_eq(SquadCard._weapon_progress({"reload": 0, "cooldown": 0}, 100, 120), -1.0, "no timer, no bar")


func test_identical_units_collapse_to_one_line() -> void:
	var base := _base()
	var one: Dictionary = (base["insp"]["units"] as Array)[0]
	var units := []
	for uid: int in range(1, 9):
		var c: Dictionary = one.duplicate(true)
		c["id"] = uid
		units.append(c)
	base["insp"]["units"] = units
	var lines := _model_lines(SquadCard.model(base["squad"], base["insp"], 1, 10, false, _ctx()))
	assert_eq(_count_containing(lines, "ammo 30 / 30"), 1, "eight identical units, one weapon line")
	assert_eq(_count_containing(lines, "Troopers 1-8:"), 1, "the shared label is a range")


func test_units_that_differ_keep_their_own_line() -> void:
	var base := _base()
	var one: Dictionary = (base["insp"]["units"] as Array)[0]
	var units := []
	for uid: int in [1, 2, 3]:
		var c: Dictionary = one.duplicate(true)
		c["id"] = uid
		if uid == 2:
			c["ammo"] = 12
		units.append(c)
	base["insp"]["units"] = units
	var lines := _model_lines(SquadCard.model(base["squad"], base["insp"], 1, 10, false, _ctx()))
	assert_eq(_count_containing(lines, "Troopers 1, 3:"), 1, "the matching units share a line")
	assert_eq(_count_containing(lines, "Trooper 2:"), 1, "the differing unit keeps its own line")
	assert_eq(_count_containing(lines, "ammo 12 / 30"), 1, "its own ammo")


func test_order_holding_line_is_dropped_and_its_tip_moves() -> void:
	var base := _base()
	base["squad"]["activity"] = BattleActivity.Squad.HOLDING
	base["insp"]["activity"] = BattleActivity.Squad.HOLDING
	var m := SquadCard.model(base["squad"], base["insp"], 1, 10, false, _ctx())
	var lines := _model_lines(m)
	assert_eq(_count_containing(lines, "Order: Holding"), 0, "the activity line already says Holding position")
	var act_tip := ""
	for it: Dictionary in m["items"]:
		if String(it.get("text", "")) == Glossary.activity_text(BattleActivity.Squad.HOLDING):
			act_tip = String(it.get("tip", ""))
	assert_eq(act_tip, OrderTips.tip("hold"), "the order's tooltip moved onto the activity line")
	# Any other order keeps its line.
	base["squad"]["order"] = "attack"
	lines = _model_lines(SquadCard.model(base["squad"], base["insp"], 1, 10, false, _ctx()))
	assert_eq(_count_containing(lines, "Order: "), 1, "a non-hold order still shows its line")
