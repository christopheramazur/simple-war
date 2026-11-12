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
## Player IDs in this battle, ascending.
var players: PackedInt64Array = PackedInt64Array()
## Zone runtime (index = rules zone index). owner 0 = nobody.
var zone_owner: PackedInt64Array = PackedInt64Array()
var zone_amount: PackedInt64Array = PackedInt64Array()
## 1 = locked (scripted objectives): no influence, no score.
var zone_locked: PackedByteArray = PackedByteArray()
## Trigger variables and fire counts (Triggers).
var vars: Dictionary = {}
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


func _snapshot_extra(snap: Dictionary) -> void:
	snap["battle"] = {
		"turn": turn, "players": players.duplicate(),
		"zone_owner": zone_owner.duplicate(), "zone_amount": zone_amount.duplicate(),
		"influence": influence.duplicate(), "value_score": value_score.duplicate(),
		"ledger": ledger.duplicate(), "result": result.duplicate(true),
		"zone_locked": zone_locked.duplicate(), "vars": vars.duplicate(), "fired": fired.duplicate(),
	}


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
	if zone_locked.size() > 0:
		h.update(zone_locked)
	h.update(text.to_utf8_buffer())
	return h.finish()
