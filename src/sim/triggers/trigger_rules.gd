class_name TriggerRules
extends RefCounted
## Triggers compiled for one context, "overworld" or "battle" (GDD 03 §3.5,
## R3Q9, R6Q17): the declarative layer for campaign scripting and Angel
## behaviour. A trigger template:
##   on:        an event type of its context, or "turn_resolved" (once per
##              turn, after everything else; data {"turn"}).
##   where:     event field -> value or list of values it must match;
##              "col" + "row" match the event's "plot" (overworld).
##   if:        checks that must all hold (each may set "not": true).
##   do:        actions, in order.
##   max_fires: how many times it may fire (default 1; 0 = no limit).
##   after_turns: delay the actions by this many whole turns (default 0).
##              The pending run is a "~due.<id>.<n>" variable, so it is
##              saved, hashed and replayed; "$field" values read as their
##              defaults when it runs.
## Checks: var / turn / fired (any context), any (one of "of" holds);
##   overworld: value (a player's Value), owns (features of a template a
##   player controls), feature_at (a feature on col,row); battle:
##   zone_owner, zone_locked, squad_alive ("squad" template, optional
##   "player": living squads), strength ("player": living units),
##   squads_in_zone ("zone", optional "player" and "squad": living squads
##   within the zone's radius). Comparisons use "op" (==, !=, <, <=, >, >=,
##   default >=) against "value" (default 1).
## Actions: set_var, add_var, message (translation "key" with "text"
##   fallback, to "player", 0 = all) and start_dialogue ("dialogue", a
##   dialogue template; "player", 0 = all; pushes dialogue_started) in any
##   context; overworld: add_value,
##   add_feature, remove_feature, end_mission ("outcome" won or lost, with a
##   message "key" / "text"; the first one stands); battle: unlock_zone,
##   lock_zone, end_battle, apply_bundle ("bundle"; to every squad, or of
##   "player" and/or template "squad"), reveal_area ("player", "x", "y",
##   "radius" in cells, "turns", 0 = permanent), spawn_squad ("squad",
##   "player", "x", "y" in cells; default the middle of the player's
##   deployment area; pushes squad_spawned), remove_squad (every living
##   "squad" of "player"; pushes squad_removed), order_squad (same squads;
##   "type" hold, move, attack_move, fall_back or withdraw, "x", "y", "run"),
##   add_score ("player", "amount", "score" value or influence). Overworld: also
##   set_owner (a "feature" at col,row or plot to "owner").
##   Overworld extras: check commander_at (commanders on col,row, optionally
##   of "player" / template "commander"); actions spawn_commander
##   ("commander", "player", col,row), give_squad / give_item ("squad" /
##   "item" + "count" to "target" commander ID or "player"'s commander on
##   col,row; give_squad respects the army cap), start_engagement (col,row).
## Triggers see the events of their own step only, not those their actions
## make (no chains; use variables across turns).

const CONTEXTS: Array[String] = ["overworld", "battle"]
const OPS: Array[String] = ["==", "!=", "<", "<=", ">", ">="]
const COMMON_CHECKS: Array[String] = ["var", "turn", "fired", "any"]
const CHECKS: Dictionary = {
	"overworld": ["value", "owns", "feature_at", "commander_at"],
	"battle": ["zone_owner", "zone_locked", "squad_alive", "strength", "squads_in_zone"],
}
const COMMON_ACTIONS: Array[String] = ["set_var", "add_var", "message", "start_dialogue"]
const ACTIONS: Dictionary = {
	"overworld": ["add_value", "add_feature", "remove_feature", "end_mission", "set_owner",
		"spawn_commander", "give_squad", "give_item", "start_engagement"],
	"battle": ["unlock_zone", "lock_zone", "end_battle", "apply_bundle", "reveal_area",
		"spawn_squad", "remove_squad", "order_squad", "add_score"],
}
const SCORES: Array[String] = ["value", "influence"]
const TURN_RESOLVED: StringName = &"turn_resolved"

var context: String = ""
var errors: PackedStringArray = PackedStringArray()
## Compiled triggers in ID order: {"id", "on" (StringName), "where", "if",
## "do", "max", "after"}.
var triggers: Array[Dictionary] = []
## Event type -> indices into `triggers`.
var by_event: Dictionary = {}


## Compiles the named trigger templates. `zones` (battle) and `features`
## (overworld) are the IDs checks and actions may name.
static func compile(t: TemplateTable, ids: PackedStringArray, ctx: String, names: PackedStringArray = PackedStringArray()) -> TriggerRules:
	var r := TriggerRules.new()
	r.context = ctx
	var sorted := ids.duplicate()
	sorted.sort()
	for tid in sorted:
		if not t.has(tid) or t.kind_of(tid) != "trigger":
			r.errors.append("unknown trigger '%s'" % tid)
			continue
		var v := t.values_of(tid)
		var checks: Array = (v.get("if", []) as Array).duplicate(true)
		var actions: Array = (v.get("do", []) as Array).duplicate(true)
		for c: Dictionary in checks:
			r._check_check(tid, c, names, t)
		for a: Dictionary in actions:
			r._check_action(tid, a, names, t)
		var i := r.triggers.size()
		var on := StringName(String(v["on"]))
		r.triggers.append({"id": tid, "on": on, "where": (v.get("where", {}) as Dictionary).duplicate(true),
			"if": checks, "do": actions, "max": int(v.get("max_fires", 1)), "after": int(v.get("after_turns", 0))})
		if int(v.get("after_turns", 0)) < 0:
			r.errors.append("%s: after_turns can't be negative" % tid)
		var list: Array = r.by_event.get(on, [])
		list.append(i)
		r.by_event[on] = list
	return r


## Variables and fire counts as hash text, in key order.
static func hash_text(vars: Dictionary, fired: Dictionary) -> String:
	var text := ""
	for d: Dictionary in [vars, fired]:
		var keys: Array = d.keys()
		keys.sort()
		for k: String in keys:
			text += "%s=%d;" % [k, d[k]]
		text += "|"
	return text


## Runs these triggers over one step's events (Triggers.fire), plus
## "turn_resolved" unless `turn_end` is false (events after the turn's own
## pass, e.g. battles starting).
func run(state: SimContext, events: Array, turn_end: bool = true) -> void:
	if not triggers.is_empty():
		Triggers.fire(state, triggers, by_event, events, turn_end)


func is_empty() -> bool:
	return triggers.is_empty()


func _check_check(tid: String, c: Dictionary, names: PackedStringArray, t: TemplateTable) -> void:
	var kind := String(c.get("check", ""))
	if not (kind in COMMON_CHECKS or kind in CHECKS[context]):
		errors.append("%s: check '%s' is not available in %s triggers" % [tid, kind, context])
		return
	if String(c.get("op", ">=")) not in OPS:
		errors.append("%s: unknown comparison '%s'" % [tid, c.get("op")])
	if kind == "any":
		for sub: Dictionary in c.get("of", []):
			_check_check(tid, sub, names, t)
	if kind in ["zone_owner", "zone_locked"] and not names.has(String(c.get("zone", ""))):
		errors.append("%s: unknown zone '%s'" % [tid, c.get("zone", "")])
	if kind == "squads_in_zone" and not names.has(String(c.get("zone", ""))):
		errors.append("%s: unknown zone '%s'" % [tid, c.get("zone", "")])
	if kind in ["squad_alive"] and not _is_squad(t, String(c.get("squad", ""))):
		errors.append("%s: unknown squad '%s'" % [tid, c.get("squad", "")])
	if kind in ["owns", "feature_at"] and not names.has(String(c.get("feature", ""))):
		errors.append("%s: unknown feature '%s'" % [tid, c.get("feature", "")])


func _check_action(tid: String, a: Dictionary, names: PackedStringArray, t: TemplateTable) -> void:
	var kind := String(a.get("do", ""))
	if not (kind in COMMON_ACTIONS or kind in ACTIONS[context]):
		errors.append("%s: action '%s' is not available in %s triggers" % [tid, kind, context])
		return
	if kind in ["unlock_zone", "lock_zone"] and not names.has(String(a.get("zone", ""))):
		errors.append("%s: unknown zone '%s'" % [tid, a.get("zone", "")])
	if kind in ["spawn_squad", "remove_squad", "order_squad"] and not _is_squad(t, String(a.get("squad", ""))):
		errors.append("%s: unknown squad '%s'" % [tid, a.get("squad", "")])
	if kind == "order_squad" and String(a.get("type", "hold")) not in BattleOrders.TYPES:
		errors.append("%s: unknown order type '%s'" % [tid, a.get("type", "")])
	if kind == "add_score" and String(a.get("score", "value")) not in SCORES:
		errors.append("%s: add_score score must be value or influence" % tid)
	if kind in ["add_feature", "remove_feature", "set_owner"] and not names.has(String(a.get("feature", ""))):
		errors.append("%s: unknown feature '%s'" % [tid, a.get("feature", "")])
	if kind in ["spawn_commander", "give_squad", "give_item", "apply_bundle"]:
		var key := {"spawn_commander": "commander", "give_squad": "squad", "give_item": "item", "apply_bundle": "bundle"}[kind] as String
		var want := {"commander": "commander", "squad": "squad", "item": "item", "bundle": "bundle"}[key] as String
		var id := String(a.get(key, ""))
		if not t.has(id) or t.kind_of(id) != want:
			errors.append("%s: %s needs a %s, '%s' is not one" % [tid, kind, want, id])
	if kind == "apply_bundle" and a.has("squad") and (not t.has(String(a["squad"])) or t.kind_of(String(a["squad"])) != "squad"):
		errors.append("%s: unknown squad '%s'" % [tid, a["squad"]])
	if kind == "end_mission" and not String(a.get("outcome", "")) in ["won", "lost"]:
		errors.append("%s: end_mission needs an outcome, won or lost" % tid)
	if kind == "start_dialogue" and (not t.has(String(a.get("dialogue", ""))) or t.kind_of(String(a["dialogue"])) != "dialogue"):
		errors.append("%s: unknown dialogue '%s'" % [tid, a.get("dialogue", "")])
	if kind in ["set_var", "add_var"] and String(a.get("name", "")).is_empty():
		errors.append("%s: %s needs a name" % [tid, kind])


static func _is_squad(t: TemplateTable, id: String) -> bool:
	return t.has(id) and t.kind_of(id) == "squad"
