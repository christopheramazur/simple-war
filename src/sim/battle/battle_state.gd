class_name BattleState
extends SimContext
## One battle: tables, compiled rules, zones, scores and the pressure ledger.
## GDD 02 §2.4-2.5, 04 §4.2.

var rules: BattleRules
var units: BattleUnits
var squads: BattleSquads
var effects: BattleEffects
var abilities: BattleAbilities
## Turns resolved so far.
var turn: int = 0
## True from the build of a battle whose scenario deployment is open until
## Reveal applies the placements (BattleDeploy). While set, players see no
## enemy squad. Saved, and hashed only while set (so a battle with no
## deployment step hashes as before).
var deploying: bool = false
## Player IDs in this battle, ascending.
var players: PackedInt64Array = PackedInt64Array()
## Zone runtime (index = rules zone index). owner 0 = nobody.
var zone_owner: PackedInt64Array = PackedInt64Array()
var zone_amount: PackedInt64Array = PackedInt64Array()
## 1 = locked (scripted objectives): no influence, no score.
var zone_locked: PackedByteArray = PackedByteArray()
## Scripted reveals (trigger reveal_area): [player, x, y, radius, expires_turn]
## in fixed point; expires_turn -1 = permanent. Squads inside count as seen by
## the player while the reveal lasts (VisionSystem).
var reveals: Array = []
## Trigger variables and fire counts (Triggers).
var vars: Dictionary = {}
## Player-configured auto-off rules (R8Q2): player -> {ability id -> {"turns":
## int, 0 = none; "band": int index into DataSchema.BANDS, -1 = none}}. Match
## inputs: hashed and saved. The data band stays the fallback default.
var auto_off_rules: Dictionary = {}
var fired: Dictionary = {}
## player -> Victory Points from zones (Influence score).
var influence: Dictionary = {}
## player -> enemy Value destroyed (Value score).
var value_score: Dictionary = {}
## "squad_id|pool|source" -> net fixed points (R6Q3). Read by analytics and
## Legend consequence selection.
var ledger: Dictionary = {}
## Empty while running; set once the battle ends.
var result: Dictionary = {}
## Hits queued this tick for HealthSystem (Health.STRIDE ints each). Filled by
## combat and drained in the same phase, so it is empty at every tick
## boundary: never hashed or saved.
var damage_queue: PackedInt64Array = PackedInt64Array()
## Derived caches rebuilt by EffectSystem at the start of every tick (never
## hashed or saved): squad ID / unit ID -> {stat: Array[StatModifier]},
## "stat|squad|unit" keys of restoring modifiers, and hook events listened to.
var squad_mods: Dictionary = {}
var unit_mods: Dictionary = {}
var mod_restores: Dictionary = {}
var fx_listening: Dictionary = {}
## Whether last tick had modifiers (maxima must return to base when they end).
var fx_had_mods: bool = false
## Derived cache, rebuilt every tick by Centroids: squad row -> unit rows.
## Not state: never hashed or saved.
var squad_units: Dictionary = {}
## Presentation trace (sw-aba), off unless a viewer asks: when `trace_shots`,
## combat appends every shot (SHOT_STRIDE: tick, shooter unit, victim unit,
## hit 0/1) to `shot_trace`, and health every hit applied (HIT_STRIDE: tick,
## victim unit, damage dealt to HP and temp HP, by unit) to `hit_trace`.
## Write-only for the sim: never read by a system, hashed or saved.
var trace_shots: bool = false
var shot_trace: PackedInt64Array = PackedInt64Array()
var hit_trace: PackedInt64Array = PackedInt64Array()
const SHOT_STRIDE: int = 4
const HIT_STRIDE: int = 4


func _init(context_id: int, battle_rules: BattleRules, seed_value: int = 0) -> void:
	super(context_id, &"battle", seed_value)
	rules = battle_rules
	units = BattleUnits.new()
	squads = BattleSquads.new()
	effects = BattleEffects.new()
	abilities = BattleAbilities.new()
	add_table(units)
	add_table(squads)
	add_table(effects)
	add_table(abilities)
	zone_owner.resize(rules.zone_ids.size())
	zone_amount.resize(rules.zone_ids.size())
	zone_locked = rules.zn_locked.duplicate()
	for side in rules.sides:
		players.append(side["player"])
		influence[side["player"]] = 0
		value_score[side["player"]] = 0
	players.sort()


func is_over() -> bool:
	return not result.is_empty()


func record_flow(squad_id: int, pool: int, source: StringName, amount: int) -> void:
	if amount == 0:
		return
	var key := "%d|%d|%s" % [squad_id, pool, source]
	ledger[key] = int(ledger.get(key, 0)) + amount


## One squad pool's ledger: [{"source": String, "amount": int (fixed)}], the
## net flow per source over the battle, sorted by source (sw-1jy.6). Read-only.
func ledger_of(squad_id: int, pool: int) -> Array:
	var prefix := "%d|%d|" % [squad_id, pool]
	var out := []
	for k: String in ledger:
		if k.begins_with(prefix):
			out.append({"source": k.substr(prefix.length()), "amount": int(ledger[k])})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["source"]) < String(b["source"]))
	return out


func _snapshot_extra(snap: Dictionary) -> void:
	snap["battle"] = {
		"turn": turn, "players": players.duplicate(),
		"zone_owner": zone_owner.duplicate(), "zone_amount": zone_amount.duplicate(),
		"influence": influence.duplicate(), "value_score": value_score.duplicate(),
		"ledger": ledger.duplicate(), "result": result.duplicate(true),
		"zone_locked": zone_locked.duplicate(), "vars": vars.duplicate(), "fired": fired.duplicate(),
		"auto_off_rules": auto_off_rules.duplicate(true), "reveals": reveals.duplicate(true),
		"fx_had_mods": fx_had_mods,
	}
	if deploying:
		snap["battle"]["deploying"] = true


func _restore_extra(snap: Dictionary) -> void:
	var b: Dictionary = snap["battle"]
	turn = b["turn"]
	players = (b["players"] as PackedInt64Array).duplicate()
	zone_owner = (b["zone_owner"] as PackedInt64Array).duplicate()
	zone_amount = (b["zone_amount"] as PackedInt64Array).duplicate()
	influence = (b["influence"] as Dictionary).duplicate()
	value_score = (b["value_score"] as Dictionary).duplicate()
	ledger = (b["ledger"] as Dictionary).duplicate()
	result = (b["result"] as Dictionary).duplicate(true)
	zone_locked = (b.get("zone_locked", rules.zn_locked) as PackedByteArray).duplicate()
	vars = (b.get("vars", {}) as Dictionary).duplicate()
	fired = (b.get("fired", {}) as Dictionary).duplicate()
	auto_off_rules = (b.get("auto_off_rules", {}) as Dictionary).duplicate(true)
	reveals = (b.get("reveals", []) as Array).duplicate(true)
	# Not hashed, but EffectSystem reads it on the next tick: a restore that
	# lost it would skip returning maxima to base (sw-tho3.7).
	fx_had_mods = bool(b.get("fx_had_mods", false))
	deploying = bool(b.get("deploying", false))


## Hash includes battle-level state beyond the tables.
func state_hash() -> PackedByteArray:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(super.state_hash())
	h.update(PackedInt64Array([turn]).to_byte_array())
	if zone_owner.size() > 0:
		h.update(zone_owner.to_byte_array())
		h.update(zone_amount.to_byte_array())
	var keys: Array = ledger.keys()
	keys.sort()
	var text := ""
	for k: String in keys:
		text += "%s=%d;" % [k, ledger[k]]
	for p in players:
		text += "P%d:%d:%d;" % [p, influence[p], value_score[p]]
	text += JSON.stringify(result, "", true)
	text += TriggerRules.hash_text(vars, fired)
	if not auto_off_rules.is_empty():
		text += "AO" + JSON.stringify(auto_off_rules, "", true)
	if zone_locked.size() > 0:
		h.update(zone_locked)
	if not reveals.is_empty():
		text += "RV" + JSON.stringify(reveals)
	if deploying:
		text += "DEPLOYING;"
	h.update(text.to_utf8_buffer())
	return h.finish()
