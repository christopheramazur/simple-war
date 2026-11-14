class_name EventText
extends RefCounted
## Plain-language lines for overworld events (sw-ip8.7): the war room's event
## feed (as one player saw them) and the match log (everything). Reads only
## the event's data and the public rules (names, map width).
##
## `viewer` is the player reading (their own side reads "You"), or 0 for an
## omniscient record (sides read "P1", "P2"; guards "Guards").

const GUARDS: int = 30
## Events too frequent or too internal for the feed (the match log keeps
## what it is given).
const QUIET: Array[StringName] = [&"value_changed", &"commander_moved", &"convoy_moved", &"engagement_started",
	&"engagement_ended", &"activity_performed", &"battleforce_deployed", &"commander_engaged"]


## A line for one event ({"type", "data"} as OverworldSession.observe
## returns them), or "" for events with nothing to say.
static func describe(e: Dictionary, rules: OverworldRules, viewer: int = 0) -> String:
	var t := StringName(e.get("type", ""))
	var d: Dictionary = e.get("data", {})
	var who := side(int(d.get("player", 0)), viewer)
	var at := "at " + hex(int(d.get("plot", -1)), rules) if d.has("plot") else ""
	match t:
		&"battle_started":
			return "A battle begins %s." % at
		&"battle_resolved":
			if not d.has("winner"):
				return "The battle %s ended." % at
			var w := int(d["winner"])
			var why := String(d.get("reason", ""))
			return "The battle %s ended: %s.%s" % [at, ("nobody won" if w == 0 else side(w, viewer) + (" win" if w == viewer else " won")),
				"" if why.is_empty() else " (%s)" % why.replace("_", " ")]
		&"squads_lost":
			var names: Array = Array(d.get("squads", PackedStringArray())).map(func(n: String) -> String: return squad_name(n))
			var n := int(d.get("count", names.size()))
			return "%s lost %d squad%s in the battle %s%s." % [who, n, "" if n == 1 else "s", at,
				"" if names.is_empty() else ": " + ", ".join(names)]
		&"squad_reinforced":
			return "%s sent a reserve squad into a battle." % who
		&"commander_defeated":
			var n := int(d.get("scattered", -1))
			return "%s %s defeated %s%s." % [who if who != "You" else "Your", commander(int(d.get("commander", -1))), at,
				"" if n < 0 else "; its army of %d squad%s scattered" % [n, "" if n == 1 else "s"]]
		&"commander_left_battle":
			return "%s %s left the battle %s." % [who, commander(int(d.get("commander", -1))), at]
		&"squad_recruited":
			return "%s recruited a %s %s." % [commander(int(d.get("commander", -1))), squad_name(_tmpl(d, rules)), at]
		&"squad_produced":
			var where := "garrison" if int(d.get("detachment", -1)) >= 0 else "army"
			return "%s produced a %s %s (it waits in the %s there)." % [_feature(d, rules, who), squad_name(_tmpl(d, rules)), at, where] \
				if d.has("tmpl") else "%s produced a squad %s." % [who, at]
		&"item_produced":
			return "%s produced supplies %s." % [_feature(d, rules, who), at]
		&"squad_picked_up":
			return "%s picked up a squad %s." % [commander(int(d["commander"])) if d.has("commander") else who, at]
		&"squad_transferred":
			return "%s moved a squad between armies." % who
		&"convoy_delivered":
			return "A convoy joined %s's army %s." % [commander(int(d["commander"])) if d.has("commander") else who, at]
		&"convoy_arrived":
			return "%s convoy arrived %s and now holds it." % [_possessive(who), at]
		&"convoy_halted":
			return "%s convoy halted %s (its commander's army is full or gone)." % [_possessive(who), at]
		&"convoys_merged":
			return "%s convoys merged %s." % [_possessive(who), at]
		&"convoy_rallied":
			return "Survivors rallied to %s %s." % [commander(int(d["commander"])) if d.has("commander") else who, at]
		&"battleforce_dropped":
			return "%s left part of its army %s." % [commander(int(d["commander"])) if d.has("commander") else who, at]
		&"detachment_disbanded":
			return "%s detachment %s was disbanded%s." % [_possessive(who), at,
				"" if String(d.get("reason", "")).is_empty() else " (%s)" % String(d["reason"]).replace("_", " ")]
		&"feature_captured":
			var from := int(d.get("from", 0))
			return "%s captured %s %s%s." % [who, _feature_name(d, rules), at, "" if from <= 0 else " from " + side(from, viewer)]
		&"feature_converted":
			return "%s converted the hex %s." % [who, at]
		&"cache_picked":
			return "%s took a cache %s." % [commander(int(d["commander"])) if d.has("commander") else who, at]
		&"guard_cleared":
			return "The guards %s were cleared by %s." % [at, who]
		&"guard_dispersed":
			return "The guards %s dispersed." % at
		&"guard_returned":
			return "Guards returned %s." % at
		&"activity_cancelled":
			return "%s's activity was cancelled." % commander(int(d.get("commander", -1)))
		&"army_refitted":
			return "%s's army refitted." % commander(int(d.get("commander", -1)))
		&"items_picked", &"items_taken", &"items_seized", &"item_given", &"item_equipped", &"item_unequipped":
			return "%s: %s." % [who, String(t).replace("_", " ")]
		&"commander_moved":
			return "%s moved %s → %s." % [commander(int(d.get("commander", -1))), hex(int(d.get("from", -1)), rules),
				hex(int(d.get("to", -1)), rules)]
		&"commander_engaged":
			return "%s engaged %s." % [commander(int(d.get("commander", -1))), at]
		&"engagement_started":
			return "Forces met %s." % at
		&"engagement_ended":
			return "The engagement %s is over." % at
		&"mission_ended":
			var w := int(d.get("winner", 0))
			return "Game over: %s (%s)." % ["a draw" if w <= 0 else side(w, viewer) + (" win" if w == viewer else " wins"),
				String(d.get("key", d.get("outcome", ""))).replace("_", " ")]
		&"value_changed":
			var amt := int(d.get("amount", 0))
			var src := String(d.get("source", "")).replace("_", " ")
			return "%s %s %d Value%s." % [who, "gained" if amt >= 0 else "spent", absi(amt), "" if src.is_empty() else " (%s)" % src]
		&"battleforce_deployed":
			var n := (d.get("squads", []) as Array).size()
			return "%s committed %s to the battle." % [commander(int(d["commander"])) if d.has("commander") else who,
				"%d squad%s" % [n, "" if n == 1 else "s"] if d.has("squads") else "its battleforce"]
	return ""


## Whether the feed shows this event type.
static func in_feed(type: StringName) -> bool:
	return not QUIET.has(type) and type != &"trigger_message" and type != &"mission_ended"


static func side(p: int, viewer: int) -> String:
	if p == GUARDS:
		return "Guards"
	if p <= 0:
		return "Someone"
	if viewer > 0 and p == viewer:
		return "You"
	return "Enemy (P%d)" % p if viewer > 0 else "P%d" % p


static func commander(cid: int) -> String:
	return "Commander %d" % (cid & 0xffff) if cid >= 0 else "A commander"


## "(col,row)" for a plot.
static func hex(p: int, rules: OverworldRules) -> String:
	return "?" if p < 0 or rules == null else "(%d,%d)" % [p % rules.width, p / rules.width]


## "rifle_squad" -> "Rifle squad".
static func squad_name(id: String) -> String:
	return id.replace("_", " ").capitalize().replace(" Squad", " squad")


static func _tmpl(d: Dictionary, rules: OverworldRules) -> String:
	var t: Variant = d.get("tmpl", "")
	if t is int and rules != null and int(t) >= 0 and int(t) < rules.squad_ids.size():
		return rules.squad_ids[int(t)]
	return String(t) if t is String or t is StringName else "squad"


static func _feature_name(d: Dictionary, rules: OverworldRules) -> String:
	var t: Variant = d.get("feature_tmpl", -1)
	if t is int and rules != null and int(t) >= 0 and int(t) < rules.hf_names.size():
		return rules.hf_names[int(t)]
	return "a feature"


static func _feature(d: Dictionary, rules: OverworldRules, who: String) -> String:
	var n := _feature_name(d, rules)
	return ("%s %s" % [_possessive(who), n.trim_prefix("a ")]) if n != "a feature" else "%s feature" % _possessive(who)


static func _possessive(who: String) -> String:
	return "Your" if who == "You" else who + "'s"
