class_name BattleRules
extends RefCounted
## Read-only battle data compiled once from flattened templates into flat
## integer arrays, so systems never touch Dictionaries or Strings on hot paths.
## All distances are fixed (Fixed.ONE per battlefield unit); all rates are per
## tick. GDD 03 §3.2-3.5.

const DAMAGE_TYPES: Array[String] = DataSchema.DAMAGE_TYPES
const SYSTEMS: Array[String] = DataSchema.SIMPL
const BANDS: Array[String] = DataSchema.BANDS
const SHAPES: Array[String] = ["line", "column", "wedge", "blob"]
const ARCHETYPES: Array[String] = ["", "damage", "tank", "scout", "sapper", "support"]
const TARGETING: Array[String] = ["none", "self", "squad", "point"]

var errors: PackedStringArray = PackedStringArray()
## Stat registry (shared, derived from the schema) and compiled bundles.
var stats: StatRegistry
var fx: EffectRules

static var _registry: StatRegistry
var scenario_id: String
var data_hash: String

# --- ruleset ---
var tps: int = 10
var band_floor_pct: PackedInt64Array = PackedInt64Array([0, 15, 40, 65, 90])
var morale_interval: int = 10
## Morale generated per interval, fixed points.
var morale_gen: int = 0
var morale_leech_pct: int = 10
var sinks: Dictionary = {}
var floats: Dictionary = {}

# --- features / terrain ---
var feature_ids: PackedStringArray = PackedStringArray()
var f_blocks_los: PackedByteArray = PackedByteArray()
var f_cover_evasion: PackedInt64Array = PackedInt64Array()
var f_concealment: PackedInt64Array = PackedInt64Array()
var width: int = 0
var height: int = 0
## Feature index per 1x1 cell, row-major.
var terrain: PackedByteArray = PackedByteArray()

# --- movement profiles ---
## Walk / run speeds in metres per second (fixed): the bases of the
## movement.walk / movement.run stats. MovementSystem converts per tick
## after modifiers, so effects are written in m/s like the data.
var mv_walk_s: PackedInt64Array = PackedInt64Array()
var mv_run_s: PackedInt64Array = PackedInt64Array()
var mv_accel: PackedInt64Array = PackedInt64Array()
var mv_turn: PackedInt64Array = PackedInt64Array()
## [profile * feature_count + feature] -> cost percent (100 = normal, 0 = impassable).
var mv_cost: PackedInt64Array = PackedInt64Array()

# --- defense profiles ---
var df_evasion: PackedInt64Array = PackedInt64Array()
var df_block_chance: PackedInt64Array = PackedInt64Array()
var df_block_amount: PackedInt64Array = PackedInt64Array()
var df_flat: PackedInt64Array = PackedInt64Array()
var df_percent: PackedInt64Array = PackedInt64Array()
## [profile * DAMAGE_TYPES.size() + type]
var df_resist: PackedInt64Array = PackedInt64Array()
var df_floor: PackedInt64Array = PackedInt64Array()
var df_absorb_flat: PackedInt64Array = PackedInt64Array()
var df_absorb_pct: PackedInt64Array = PackedInt64Array()

# --- weapons and fire modes ---
var wp_range: PackedInt64Array = PackedInt64Array()
var wp_min_range: PackedInt64Array = PackedInt64Array()
var wp_type: PackedInt64Array = PackedInt64Array()
var wp_magazine: PackedInt64Array = PackedInt64Array()
var wp_reload: PackedInt64Array = PackedInt64Array()
## First mode index for weapon w is wp_mode_start[w], count wp_mode_count[w].
var wp_mode_start: PackedInt64Array = PackedInt64Array()
var wp_mode_count: PackedInt64Array = PackedInt64Array()
var md_name: PackedStringArray = PackedStringArray()
var md_shots: PackedInt64Array = PackedInt64Array()
var md_cooldown: PackedInt64Array = PackedInt64Array()
var md_accuracy: PackedInt64Array = PackedInt64Array()
var md_damage: PackedInt64Array = PackedInt64Array()
var md_moving: PackedByteArray = PackedByteArray()
var md_aoe: PackedInt64Array = PackedInt64Array()
var md_crit_every: PackedInt64Array = PackedInt64Array()
var md_crit_bonus: PackedInt64Array = PackedInt64Array()

# --- abilities (E2Q10, E3Q6, E3Q7) ---
var ab_ids: PackedStringArray = PackedStringArray()
var ab_names: PackedStringArray = PackedStringArray()
## EffectRules index of the ability's bundle (its active or readied state).
var ab_bundle: PackedInt64Array = PackedInt64Array()
## Per ability, 5 pools (SIMPL order), fixed: cost on use, upkeep per
## second. Activation numbers are bases for the ability.activation.* stats;
## Abilities reads them through Stats.
var ab_costs: Array[PackedInt64Array] = []
var ab_upkeep: Array[PackedInt64Array] = []
var ab_auto_off_band: PackedInt64Array = PackedInt64Array()
var ab_toggle: PackedByteArray = PackedByteArray()
var ab_reaction: PackedByteArray = PackedByteArray()
## Toggles that sink nothing start on (R7Q4).
var ab_default_on: PackedByteArray = PackedByteArray()
var ab_cooldown_s: PackedInt64Array = PackedInt64Array()   ## fixed seconds
var ab_charges: PackedInt64Array = PackedInt64Array()      ## -1 = unlimited
var ab_ready_s: PackedInt64Array = PackedInt64Array()      ## fixed seconds, 0 = acts at once
var ab_ready_prowess: PackedInt64Array = PackedInt64Array()  ## Prowess Vacuum per second while readying, fixed
var ab_lose_on: Array[PackedStringArray] = []
var ab_range: PackedInt64Array = PackedInt64Array()        ## fixed, -1 = unlimited
var ab_targeting: PackedInt64Array = PackedInt64Array()    ## TARGETING index
## True when some ability is lost on damage or casualties (HealthSystem
## only reports to Abilities then).
var ab_lost_on_hits: bool = false

# --- unit templates ---
var unit_ids: PackedStringArray = PackedStringArray()
var ut_names: PackedStringArray = PackedStringArray()
var ut_hp: PackedInt64Array = PackedInt64Array()
var ut_defense: PackedInt64Array = PackedInt64Array()
var ut_movement: PackedInt64Array = PackedInt64Array()
var ut_weapon: PackedInt64Array = PackedInt64Array()
## Template ID -> index, for gear that overrides a unit's (War Chest items).
var weapon_index: Dictionary = {}
var defense_index: Dictionary = {}
var ut_proficiency: PackedInt64Array = PackedInt64Array()
var ut_leader: PackedByteArray = PackedByteArray()

# --- squad templates ---
var squad_ids: PackedStringArray = PackedStringArray()
var sq_names: PackedStringArray = PackedStringArray()
var sq_value: PackedInt64Array = PackedInt64Array()
var sq_cr: PackedInt64Array = PackedInt64Array()
var sq_sight: PackedInt64Array = PackedInt64Array()
var sq_shape: PackedInt64Array = PackedInt64Array()
var sq_spacing: PackedInt64Array = PackedInt64Array()
var sq_archetype: PackedInt64Array = PackedInt64Array()
## Member unit template indices, expanded (one entry per model), leader first.
var sq_members: Array[PackedInt64Array] = []
## Innate bundles (EffectRules indices) applied at spawn, per template.
var sq_bundles: Array[PackedInt64Array] = []
var ut_bundles: Array[PackedInt64Array] = []
var sq_keywords: Array[PackedStringArray] = []
## Ability indices per squad template, in template order.
var sq_abilities: Array[PackedInt64Array] = []
## Bases for the concealment and detection stats (R7Q4), fixed.
var sq_concealment: PackedInt64Array = PackedInt64Array()
var sq_detection: PackedInt64Array = PackedInt64Array()
## Pool parameters per squad template, [squad * 5 + system], fixed points.
var sq_pool_cap: PackedInt64Array = PackedInt64Array()
var sq_pool_start: PackedInt64Array = PackedInt64Array()
var sq_pool_neutral: PackedInt64Array = PackedInt64Array()
var sq_pool_drift: PackedInt64Array = PackedInt64Array()

# --- scenario ---
var ticks_per_turn: int = 100
var zone_ids: PackedStringArray = PackedStringArray()
var zn_x: PackedInt64Array = PackedInt64Array()
var zn_y: PackedInt64Array = PackedInt64Array()
var zn_radius: PackedInt64Array = PackedInt64Array()
var zn_decay: PackedInt64Array = PackedInt64Array()
var zn_threshold: PackedInt64Array = PackedInt64Array()
var zn_buffer: PackedInt64Array = PackedInt64Array()
var zn_vp: PackedInt64Array = PackedInt64Array()
## 1 = the zone starts locked (no influence, no score) until a trigger opens it.
var zn_locked: PackedByteArray = PackedByteArray()
## Scripted triggers (TriggerRules, battle context).
var triggers: TriggerRules
## Per side: {player, deploy: [x, y, w, h] fixed, facing, squads: PackedInt64Array}
var sides: Array[Dictionary] = []
var turn_limit: int = 10
var primary_influence: bool = true
var score_target: int = 0
var annihilation: bool = true
var withdrawal: bool = true
var loser_hook: String = "scatter"


static func compile(t: TemplateTable, scenario: String, hash_hex: String = "") -> BattleRules:
	var r := BattleRules.new()
	r.scenario_id = scenario
	r.data_hash = hash_hex
	r._compile(t, scenario)
	return r


func is_valid() -> bool:
	return errors.is_empty()


func feature_count() -> int:
	return feature_ids.size()


func feature_at(x: int, y: int) -> int:
	var cx := clampi(Fixed.to_int_floor(x), 0, width - 1)
	var cy := clampi(Fixed.to_int_floor(y), 0, height - 1)
	return terrain[cy * width + cx]


func band_of(value: int, capacity: int) -> int:
	var pct := Fixed.round_div(value * 100, capacity) if capacity > 0 else 0
	var band := 0
	for b in BANDS.size():
		if pct >= band_floor_pct[b]:
			band = b
	return band


## Line of sight between two points: blocked when more than LOS_DEPTH
## blocking cells lie strictly between the endpoint cells (so squads can see
## a little way into and out of forests and ruins). R3Q8, R8Q1.
const LOS_DEPTH: int = 2
## Within this distance terrain never blocks line of sight (close-quarters
## awareness). Concealment still applies to Sight.
const AWARENESS: int = 8 * Fixed.ONE


func los(ax: int, ay: int, bx: int, by: int) -> bool:
	if Fixed.distance(ax, ay, bx, by) <= AWARENESS:
		return true
	var x0 := clampi(Fixed.to_int_floor(ax), 0, width - 1)
	var y0 := clampi(Fixed.to_int_floor(ay), 0, height - 1)
	var x1 := clampi(Fixed.to_int_floor(bx), 0, width - 1)
	var y1 := clampi(Fixed.to_int_floor(by), 0, height - 1)
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	var blocked := 0
	var x := x0
	var y := y0
	while true:
		if (x != x0 or y != y0) and (x != x1 or y != y1):
			if f_blocks_los[terrain[y * width + x]] == 1:
				blocked += 1
				if blocked > LOS_DEPTH:
					return false
		if x == x1 and y == y1:
			return true
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy
	return true


## Longest weapon range among a squad template's members (fixed).
func squad_range(squad_tmpl: int) -> int:
	var best := 0
	for ui in sq_members[squad_tmpl]:
		var w := ut_weapon[ui]
		if w >= 0:
			best = maxi(best, wp_range[w])
	return best


## Fire mode for a weapon: moving -> first mode usable on the move; standing
## -> first mode not flagged moving, else any. Modes are sorted by name. -1 none.
func pick_mode(weapon: int, is_moving: bool) -> int:
	var start := wp_mode_start[weapon]
	var fallback := -1
	for m in range(start, start + wp_mode_count[weapon]):
		if is_moving:
			if md_moving[m] == 1:
				return m
		else:
			if md_moving[m] == 0:
				return m
			if fallback < 0:
				fallback = m
	return fallback


func sink(key: String) -> int:
	return int(sinks.get(key, 0))


func flt(key: String) -> int:
	return int(floats.get(key, 0))


## Squad index lookup by template id, or -1.
func squad_index(tid: String) -> int:
	return Array(squad_ids).find(tid)


# --- compilation -----------------------------------------------------------

func _compile(t: TemplateTable, scenario: String) -> void:
	if not t.has(scenario) or t.kind_of(scenario) != "scenario":
		errors.append("unknown scenario '%s'" % scenario)
		return
	var sc := t.values_of(scenario)
	_compile_ruleset(t.values_of(sc["ruleset"]))
	var by_kind := {}
	for tid in t.ids():
		if t.is_abstract(tid):
			continue
		var k := t.kind_of(tid)
		var list: PackedStringArray = by_kind.get(k, PackedStringArray())
		list.append(tid)
		by_kind[k] = list
	for k: String in by_kind:
		var sorted_list: PackedStringArray = by_kind[k]
		sorted_list.sort()
		by_kind[k] = sorted_list
	if _registry == null:
		_registry = StatRegistry.from_schema()
	stats = _registry
	_compile_features(t, by_kind.get("feature", PackedStringArray()))
	fx = EffectRules.compile(t, stats, tps, feature_ids)
	errors.append_array(fx.errors)
	var mv_index := _compile_movement(t, by_kind.get("movement", PackedStringArray()))
	var df_index := _compile_defense(t, by_kind.get("defense", PackedStringArray()))
	var wp_index := _compile_weapons(t, by_kind.get("weapon", PackedStringArray()))
	weapon_index = wp_index
	defense_index = df_index
	var ab_index := _compile_abilities(t, by_kind.get("ability", PackedStringArray()))
	var ut_index := _compile_units(t, by_kind.get("unit", PackedStringArray()), mv_index, df_index, wp_index)
	_compile_squads(t, by_kind.get("squad", PackedStringArray()), ut_index, ab_index)
	_compile_scenario(sc)
	triggers = TriggerRules.compile(t, PackedStringArray(sc.get("triggers", [])), "battle", zone_ids)
	errors.append_array(triggers.errors)


func _bundle_list(v: Dictionary) -> PackedInt64Array:
	var out := PackedInt64Array()
	for b: String in v.get("bundles", []):
		out.append(fx.index_of(b))
	return out


func _compile_ruleset(rs: Dictionary) -> void:
	tps = int(rs.get("ticks_per_second", 10))
	var floors: Dictionary = rs.get("band_floor_pct", {})
	for b in BANDS.size():
		if floors.has(BANDS[b]):
			band_floor_pct[b] = int(floors[BANDS[b]])
	morale_interval = int(rs.get("morale_interval_ticks", 10))
	morale_gen = Fixed.round_div(DataSchema.to_fixed(rs.get("morale_rate_per_s"), 0) * morale_interval, tps)
	morale_leech_pct = int(rs.get("morale_leech_pct", 10))
	sinks = rs.get("sinks", {})
	floats = rs.get("floats", {})
	_pool_defaults = rs.get("pool_defaults", {})


var _pool_defaults: Dictionary = {}


func _compile_features(t: TemplateTable, ids: PackedStringArray) -> void:
	for tid in ids:
		var v := t.values_of(tid)
		feature_ids.append(tid)
		f_blocks_los.append(1 if v.get("blocks_los", false) else 0)
		f_cover_evasion.append(int(v.get("cover_evasion_pct", 0)))
		f_concealment.append(int(v.get("concealment_pct", 0)))


func _compile_movement(t: TemplateTable, ids: PackedStringArray) -> Dictionary:
	var index := {}
	for tid in ids:
		var v := t.values_of(tid)
		index[tid] = mv_walk_s.size()
		mv_walk_s.append(DataSchema.to_fixed(v["walk"]))
		mv_run_s.append(DataSchema.to_fixed(v["run"]))
		mv_accel.append(Fixed.round_div(DataSchema.to_fixed(v.get("accel", 1000)), tps * tps))
		mv_turn.append(maxi(1, Fixed.round_div(int(v.get("turn_deg_per_s", 360)) * Fixed.ANGLE_FULL, 360 * tps)))
		var costs: Dictionary = v.get("terrain_cost_pct", {})
		for f in feature_ids:
			mv_cost.append(int(costs.get(f, 100)))
	return index


func _compile_defense(t: TemplateTable, ids: PackedStringArray) -> Dictionary:
	var index := {}
	for tid in ids:
		var v := t.values_of(tid)
		index[tid] = df_evasion.size()
		df_evasion.append(int(v.get("evasion_pct", 0)))
		df_block_chance.append(int(v.get("block_chance_pct", 0)))
		df_block_amount.append(int(v.get("block_amount_pct", 0)))
		df_flat.append(DataSchema.to_fixed(v.get("flat", 0)))
		df_percent.append(int(v.get("percent", 0)))
		var res: Dictionary = v.get("resist_pct", {})
		var flo: Dictionary = v.get("floor", {})
		var ab: Dictionary = v.get("absorb", {})
		for dt in DAMAGE_TYPES:
			df_resist.append(int(res.get(dt, 0)))
			df_floor.append(DataSchema.to_fixed(flo.get(dt, 0)))
			var a: Dictionary = ab.get(dt, {})
			df_absorb_flat.append(DataSchema.to_fixed(a.get("flat", 0)))
			df_absorb_pct.append(int(a.get("pct", 0)))
	return index


func _compile_weapons(t: TemplateTable, ids: PackedStringArray) -> Dictionary:
	var index := {}
	for tid in ids:
		var v := t.values_of(tid)
		index[tid] = wp_range.size()
		wp_range.append(DataSchema.to_fixed(v["range"]))
		wp_min_range.append(DataSchema.to_fixed(v.get("min_range", 0)))
		wp_type.append(DAMAGE_TYPES.find(v["damage_type"]))
		wp_magazine.append(int(v.get("magazine", 0)))
		wp_reload.append(int(v.get("reload_ticks", 0)))
		var modes: Dictionary = v["modes"]
		var names: Array = modes.keys()
		names.sort()
		wp_mode_start.append(md_shots.size())
		wp_mode_count.append(names.size())
		for n: String in names:
			var m: Dictionary = modes[n]
			md_name.append(n)
			md_shots.append(int(m["shots"]))
			md_cooldown.append(int(m["cooldown_ticks"]))
			md_accuracy.append(DataSchema.to_fixed(m["accuracy"]))
			md_damage.append(DataSchema.to_fixed(m["damage"]))
			md_moving.append(1 if m.get("moving", false) else 0)
			md_aoe.append(DataSchema.to_fixed(m.get("aoe_radius", 0)))
			md_crit_every.append(int(m.get("crit_every", 0)))
			md_crit_bonus.append(int(m.get("crit_bonus_pct", 0)))
	return index


func _compile_abilities(t: TemplateTable, ids: PackedStringArray) -> Dictionary:
	var index := {}
	for tid in ids:
		var v := t.values_of(tid)
		var act: Dictionary = v.get("activation", {})
		index[tid] = ab_ids.size()
		ab_ids.append(tid)
		ab_names.append(str(v.get("name", tid)))
		var b := fx.index_of(str(v.get("bundle", "")))
		if b < 0:
			errors.append("%s: unknown bundle '%s'" % [tid, v.get("bundle", "")])
		ab_bundle.append(b)
		var reaction: bool = act.get("timing", "order") == "reaction"
		var toggle: bool = act.get("toggle", false)
		var costs_in: Dictionary = act.get("costs", {})
		if reaction and costs_in.is_empty():
			costs_in = {"instinct": sink("instinct_reaction")}
		var upkeep_in: Dictionary = act.get("upkeep_per_s", {})
		var costs := PackedInt64Array()
		var upkeep := PackedInt64Array()
		var sinks_any := false
		for p in SYSTEMS:
			costs.append(DataSchema.to_fixed(costs_in.get(p, 0)))
			var u := DataSchema.to_fixed(upkeep_in.get(p, 0))
			upkeep.append(u)
			sinks_any = sinks_any or u > 0
		ab_costs.append(costs)
		ab_upkeep.append(upkeep)
		ab_auto_off_band.append(BANDS.find(act.get("auto_off_band", "broken")))
		ab_toggle.append(1 if toggle else 0)
		ab_reaction.append(1 if reaction else 0)
		ab_default_on.append(1 if toggle and not sinks_any else 0)
		ab_cooldown_s.append(DataSchema.to_fixed(act.get("cooldown_s", 0)))
		ab_charges.append(int(act.get("charges", -1)))
		var ready := DataSchema.to_fixed(act.get("ready_s", 0))
		ab_ready_s.append(ready)
		ab_ready_prowess.append(DataSchema.to_fixed(act.get("readying_prowess_per_s", sink("prowess_readying_per_s"))))
		var lose := PackedStringArray(act.get("lose_on", []))
		ab_lose_on.append(lose)
		ab_lost_on_hits = ab_lost_on_hits or lose.has("damaged") or lose.has("casualty")
		ab_range.append(DataSchema.to_fixed(act["range"]) if act.has("range") else -1)
		var targeting := TARGETING.find(act.get("targeting", "none"))
		ab_targeting.append(targeting)
		if reaction and (toggle or ready > 0):
			errors.append("%s: a reaction acts at once (no toggle, no ready_s)" % tid)
		if TARGETING[targeting] == "squad" and toggle:
			errors.append("%s: a toggle acts on its own squad" % tid)
	return index


func _compile_units(t: TemplateTable, ids: PackedStringArray, mv: Dictionary, df: Dictionary, wp: Dictionary) -> Dictionary:
	var index := {}
	for tid in ids:
		var v := t.values_of(tid)
		index[tid] = unit_ids.size()
		unit_ids.append(tid)
		ut_names.append(str(v.get("name", tid)))
		ut_hp.append(DataSchema.to_fixed(v["hp"]))
		ut_defense.append(df[v["defense"]])
		ut_movement.append(mv[v["movement"]])
		ut_weapon.append(wp[v["weapon"]] if v.has("weapon") else -1)
		ut_proficiency.append(int(v.get("proficiency_pct", 100)))
		ut_leader.append(1 if (v.get("tags", []) as Array).has("leader") else 0)
		ut_bundles.append(_bundle_list(v))
	return index


func _compile_squads(t: TemplateTable, ids: PackedStringArray, ut: Dictionary, ab: Dictionary) -> void:
	for tid in ids:
		var v := t.values_of(tid)
		squad_ids.append(tid)
		sq_names.append(str(v.get("name", tid)))
		sq_value.append(int(v["value"]))
		sq_cr.append(int(v.get("capture_rate", 0)))
		sq_sight.append(DataSchema.to_fixed(v["sight"]))
		var form: Dictionary = v.get("formation", {})
		sq_shape.append(maxi(SHAPES.find(form.get("shape", "line")), 0))
		sq_spacing.append(DataSchema.to_fixed(form.get("spacing", 2)))
		sq_archetype.append(maxi(ARCHETYPES.find(v.get("legend_archetype", "")), 0))
		# Members: leaders first, then template order (R6Q5).
		var leaders := PackedInt64Array()
		var others := PackedInt64Array()
		for m: Dictionary in v["members"]:
			var ui: int = ut[m["unit"]]
			for _i in int(m["count"]):
				if ut_leader[ui] == 1:
					leaders.append(ui)
				else:
					others.append(ui)
		leaders.append_array(others)
		sq_members.append(leaders)
		sq_bundles.append(_bundle_list(v))
		sq_keywords.append(PackedStringArray(v.get("keywords", [])))
		var abl := PackedInt64Array()
		for a: String in v.get("abilities", []):
			abl.append(ab[a])
		sq_abilities.append(abl)
		sq_concealment.append(DataSchema.to_fixed(v.get("concealment_pct", 0)))
		sq_detection.append(DataSchema.to_fixed(v.get("detection_radius", 0)))
		var pools: Dictionary = v.get("pools", {})
		for s in SYSTEMS:
			var d: Dictionary = _pool_defaults.get(s, {})
			var o: Dictionary = pools.get(s, {})
			var cap := int(o.get("capacity", d.get("capacity", 100)))
			sq_pool_cap.append(Fixed.from_int(cap))
			sq_pool_start.append(Fixed.round_div(Fixed.from_int(cap) * int(o.get("start_pct", d.get("start_pct", 52))), 100))
			sq_pool_neutral.append(Fixed.round_div(Fixed.from_int(cap) * int(o.get("neutral_pct", d.get("neutral_pct", 52))), 100))
			var drift_pct := DataSchema.to_fixed(o.get("drift_pct_per_s", d.get("drift_pct_per_s", 1)))
			sq_pool_drift.append(Fixed.round_div(drift_pct * cap, 100 * tps))


func _compile_scenario(sc: Dictionary) -> void:
	width = int(sc["width"])
	height = int(sc["height"])
	ticks_per_turn = int(sc["ticks_per_turn"])
	terrain.resize(width * height)
	terrain.fill(Array(feature_ids).find(sc["terrain_default"]))
	for r: Dictionary in sc.get("terrain", []):
		var fi := Array(feature_ids).find(r["feature"])
		for y in range(int(r["y"]), mini(int(r["y"]) + int(r["h"]), height)):
			for x in range(int(r["x"]), mini(int(r["x"]) + int(r["w"]), width)):
				terrain[y * width + x] = fi
	for z: Dictionary in sc.get("zones", []):
		zone_ids.append(z["id"])
		zn_x.append(DataSchema.to_fixed(z["x"]))
		zn_y.append(DataSchema.to_fixed(z["y"]))
		zn_radius.append(DataSchema.to_fixed(z["radius"]))
		zn_decay.append(int(z.get("decay", 10)))
		zn_threshold.append(int(z.get("threshold", 10)))
		zn_buffer.append(int(z.get("buffer", 10)))
		zn_vp.append(int(z.get("vp", 1)))
		zn_locked.append(1 if z.get("locked", false) else 0)
	for s: Dictionary in sc["sides"]:
		var d: Dictionary = s["deploy"]
		var squads := PackedInt64Array()
		for sid: String in s["squads"]:
			squads.append(squad_index(sid))
		sides.append({
			"player": int(s["player"]),
			"facing": int(s.get("facing", 0)) & Fixed.ANGLE_MASK,
			"deploy": PackedInt64Array([DataSchema.to_fixed(d["x"]), DataSchema.to_fixed(d["y"]), DataSchema.to_fixed(d["w"]), DataSchema.to_fixed(d["h"])]),
			"squads": squads,
		})
	var vic: Dictionary = sc["victory"]
	turn_limit = int(vic.get("turn_limit", 10))
	primary_influence = vic.get("primary", "influence") == "influence"
	score_target = int(vic.get("score_target", 0))
	annihilation = vic.get("annihilation", true)
	withdrawal = vic.get("withdrawal", true)
	loser_hook = (sc.get("end_hooks", {}) as Dictionary).get("loser", "scatter")
