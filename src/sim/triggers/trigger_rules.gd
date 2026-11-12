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
## Checks: var / turn / fired (any context), any (one of "of" holds);
##   overworld: value (a player's Value), owns (features of a template a
##   player controls), feature_at (a feature on col,row); battle:
##   zone_owner, zone_locked. Comparisons use "op" (==, !=, <, <=, >, >=,
##   default >=) against "value" (default 1).
## Actions: set_var, add_var, message (translation "key" with "text"
##   fallback, to "player", 0 = all) in any context; overworld: add_value,
##   add_feature, remove_feature; battle: unlock_zone, lock_zone,
##   end_battle.
## Triggers see the events of their own step only, not those their actions
## make (no chains; use variables across turns).

const CONTEXTS: Array[String] = ["overworld", "battle"]
const OPS: Array[String] = ["==", "!=", "<", "<=", ">", ">="]
const COMMON_CHECKS: Array[String] = ["var", "turn", "fired", "any"]
const CHECKS: Dictionary = {
	"overworld": ["value", "owns", "feature_at"],
	"battle": ["zone_owner", "zone_locked"],
}
const COMMON_ACTIONS: Array[String] = ["set_var", "add_var", "message"]
const ACTIONS: Dictionary = {
	"overworld": ["add_value", "add_feature", "remove_feature"],
	"battle": ["unlock_zone", "lock_zone", "end_battle"],
}
const TURN_RESOLVED: StringName = &"turn_resolved"

var context: String = ""
var errors: PackedStringArray = PackedStringArray()
## Compiled triggers in ID order: {"id", "on" (StringName), "where", "if",
## "do", "max"}.
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
			r._check_check(tid, c, names)
		for a: Dictionary in actions:
			r._check_action(tid, a, names)
		var i := r.triggers.size()
		var on := StringName(String(v["on"]))
		r.triggers.append({"id": tid, "on": on, "where": (v.get("where", {}) as Dictionary).duplicate(true),
			"if": checks, "do": actions, "max": int(v.get("max_fires", 1))})
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


## Runs these triggers over one step's events (Triggers.fire).
func run(state: SimContext, events: Array) -> void:
	if not triggers.is_empty():
		Triggers.fire(state, triggers, by_event, events)


func is_empty() -> bool:
	return triggers.is_empty()


func _check_check(tid: String, c: Dictionary, names: PackedStringArray) -> void:
	var kind := String(c.get("check", ""))
	if not (kind in COMMON_CHECKS or kind in CHECKS[context]):
		errors.append("%s: check '%s' is not available in %s triggers" % [tid, kind, context])
		return
	if String(c.get("op", ">=")) not in OPS:
		errors.append("%s: unknown comparison '%s'" % [tid, c.get("op")])
	if kind == "any":
		for sub: Dictionary in c.get("of", []):
			_check_check(tid, sub, names)
	if kind in ["zone_owner", "zone_locked"] and not names.has(String(c.get("zone", ""))):
		errors.append("%s: unknown zone '%s'" % [tid, c.get("zone", "")])
	if kind in ["owns", "feature_at"] and not names.has(String(c.get("feature", ""))):
		errors.append("%s: unknown feature '%s'" % [tid, c.get("feature", "")])


func _check_action(tid: String, a: Dictionary, names: PackedStringArray) -> void:
	var kind := String(a.get("do", ""))
	if not (kind in COMMON_ACTIONS or kind in ACTIONS[context]):
		errors.append("%s: action '%s' is not available in %s triggers" % [tid, kind, context])
		return
	if kind in ["unlock_zone", "lock_zone"] and not names.has(String(a.get("zone", ""))):
		errors.append("%s: unknown zone '%s'" % [tid, a.get("zone", "")])
	if kind in ["add_feature", "remove_feature"] and not names.has(String(a.get("feature", ""))):
		errors.append("%s: unknown feature '%s'" % [tid, a.get("feature", "")])
	if kind in ["set_var", "add_var"] and String(a.get("name", "")).is_empty():
		errors.append("%s: %s needs a name" % [tid, kind])
