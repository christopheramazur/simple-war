class_name RelationText
extends RefCounted
## Short translated lines for a pair relation (sw-bafi.6, U1 C6a): turns the
## facts from SquadRelation.facts into at most MAX_LINES lines for the tooltip
## and the menu. Pure and static: no state, no UI, no sim calls, so a fixture
## fact list tests it.
##
## Priority, highest first: targeting / under fire / would engage / attack
## order (rank 0), range (1), fleeing / moving (2), contact i.e. sight (3).
## The first line is always the targeting line (the range line when nothing
## targets). A hold-fire reason (the dominant reason an armed unit does not
## fire: MIN_RANGE, NO_LOS, RELOADING, ...) is appended to that first line, so
## the cap never drops "why is my damage low". Each line is one fact's text,
## with duplicates dropped.
##
## Every string goes through a translation key "relation.<kind>.<value>" (hold
## reasons "relation.hold.<reason>"), with the English in EN as the fallback
## until the translation tables exist. "would_engage" reads as "likely": the
## target may still change before the next tick, so it is never a commitment.

const MAX_LINES := 3

## Rank per fact kind (lower shows first).
const RANK: Dictionary = {"targeting": 0, "under_fire": 0, "would_engage": 0, "ordered": 0,
	"range": 1, "fleeing": 2, "moving": 2, "sight": 3}

## Order inside a rank: targeting leads the first line.
const KIND_ORDER: Array[String] = ["targeting", "under_fire", "would_engage", "ordered", "range", "fleeing", "moving", "sight"]

## Range values that are a hold-fire reason (SquadRelation's own-view summary).
const REASON_RANGE_VALUES: Array[String] = ["min_range", "no_line", "out_of_range", "not_spotted"]

const EN: Dictionary = {
	"relation.targeting.firing": "Firing at the enemy",
	"relation.targeting.aiming": "Aiming at the enemy",
	"relation.under_fire.recent": "Under fire",
	"relation.would_engage.likely": "Likely to engage next",
	"relation.ordered.attack": "Ordered to attack",
	"relation.range.in_range": "In range",
	"relation.range.min_range": "Too close to fire",
	"relation.range.no_line": "No line of fire",
	"relation.range.out_of_range": "Out of range",
	"relation.range.out_of_range_gap": "Out of range by {gap} m",
	"relation.range.not_spotted": "Target not spotted",
	"relation.range.unarmed": "Unarmed",
	"relation.fleeing.falling_back": "Falling back",
	"relation.fleeing.withdrawing": "Withdrawing",
	"relation.fleeing.retreating": "Retreating",
	"relation.moving.toward": "Moving toward",
	"relation.moving.away": "Moving away",
	"relation.moving.across": "Moving across",
	"relation.sight.own": "Spotted by its own side",
	"relation.sight.allies": "Spotted by allies",
	"relation.sight.unseen": "Unseen",
	"relation.hold.unarmed": "Unarmed",
	"relation.hold.falling_back": "Falling back, holding fire",
	"relation.hold.reloading": "Reloading",
	"relation.hold.cooldown": "Cooling down",
	"relation.hold.no_moving_fire": "Cannot fire on the move",
	"relation.hold.min_range": "Too close to fire",
	"relation.hold.out_of_range": "Out of range",
	"relation.hold.no_los": "No line of fire",
	"relation.hold.not_spotted": "Target not spotted",
	"relation.hold.no_target": "No target",
	"relation.hold.moving_to_fire": "Moving to a firing position",
}


## The lines for a pair's facts (SquadRelation.facts, either direction), at
## most MAX_LINES. Unknown kinds are skipped; no facts give [].
static func lines(facts: Array) -> PackedStringArray:
	var items: Array = []
	for i in facts.size():
		var d: Dictionary = facts[i]
		var kind := str(d.get("kind", ""))
		if not RANK.has(kind):
			continue
		items.append({"i": i, "kind": kind, "rank": RANK[kind], "text": text_of(d),
			"range_reason": kind == "range" and REASON_RANGE_VALUES.has(str(d.get("value", "")))})
	items.sort_custom(_before)
	var out := PackedStringArray()
	var reason := hold_reason(facts)
	var head := _head(items)
	if head >= 0:
		var text: String = items[head]["text"]
		if reason != "" and reason != text:
			text = "%s; %s" % [text, reason]
		out.append(text)
	for k in items.size():
		if out.size() >= MAX_LINES:
			break
		if k == head:
			continue
		var it: Dictionary = items[k]
		# The reason is already in the first line.
		if reason != "" and it["range_reason"]:
			continue
		if not out.has(it["text"]):
			out.append(it["text"])
	return out


## One fact's translated text. Empty for an unknown kind.
static func text_of(d: Dictionary) -> String:
	var kind := str(d.get("kind", ""))
	var value := str(d.get("value", ""))
	var data: Dictionary = d.get("data", {})
	if not RANK.has(kind):
		return ""
	if kind == "range" and value == "out_of_range" and int(data.get("gap", 0)) > 0:
		return _t("relation.range.out_of_range_gap", {"gap": Fixed.to_int_round(int(data["gap"]))})
	return _t("relation.%s.%s" % [kind, value])


## The dominant hold-fire reason in the facts, "" if none. An aiming squad's
## hold reason wins; otherwise a range fact that is itself a reason.
static func hold_reason(facts: Array) -> String:
	for d: Dictionary in facts:
		if str(d.get("kind", "")) == "targeting" and str(d.get("value", "")) == "aiming":
			var h := _hold_text(int((d.get("data", {}) as Dictionary).get("hold", 0)))
			if h != "":
				return h
	for d: Dictionary in facts:
		if str(d.get("kind", "")) == "range" and REASON_RANGE_VALUES.has(str(d.get("value", ""))):
			return text_of(d)
	return ""


## The translated name of a BattleActivity.Hold value, "" for NONE or unknown.
static func _hold_text(h: int) -> String:
	var names := BattleActivity.Hold.keys()
	if h <= 0 or h >= names.size():
		return ""
	return _t("relation.hold.%s" % String(names[h]).to_lower())


## Index into items of the first line: the first rank-0 fact, else the first
## range fact, else -1.
static func _head(items: Array) -> int:
	for k in items.size():
		if items[k]["rank"] == 0:
			return k
	for k in items.size():
		if items[k]["kind"] == "range":
			return k
	return -1


static func _before(a: Dictionary, b: Dictionary) -> bool:
	if a["rank"] != b["rank"]:
		return a["rank"] < b["rank"]
	var ka := KIND_ORDER.find(a["kind"])
	var kb := KIND_ORDER.find(b["kind"])
	if ka != kb:
		return ka < kb
	return a["i"] < b["i"]


static func _t(key: String, params: Dictionary = {}) -> String:
	var s := String(TranslationServer.translate(key))
	if s == key:
		s = str(EN.get(key, key))
	for p in params:
		s = s.replace("{%s}" % p, str(params[p]))
	return s
