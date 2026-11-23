class_name Telegraph
extends RefCounted
## Enemy attack telegraph text and colour (sw-7o7). The number goes through
## BattleFx.damage_text, so a telegraph reads exactly like the floating
## damage in playback (sw-ll4.21).

const COLOR := Color(1.0, 0.45, 0.3)


## "▶ 12" (damage predicted for one committed enemy attack); with kills,
## "▶ 12 · 2 down". The ▶ and the box carry the meaning, not the colour.
static func label(t: Dictionary) -> String:
	var s := "▶ " + BattleFx.damage_text(int(t["damage"]))
	var k := int(t.get("kills", 0))
	if k > 0:
		s += " · %d down" % k
	return s


## Shown wherever a contact forecast is, not only in a tooltip (sw-abk).
const CAVEAT := "Forecast assumes the enemy keeps its current orders."


## The mark on a forecast contact (IntentForecast "contacts"; Options "Forecast
## detail", sw-czg): the summary says
## who comes out ahead; numbers (same damage_text as playback) only at
## higher verbosity, so planning isn't a hunt for the exact best number.
static func contact_label(ct: Dictionary, numbers: bool = false) -> String:
	var dealt := int(ct.get("dealt", 0))
	var taken := int(ct.get("taken", 0))
	if not numbers:
		if dealt == 0 and taken == 0:
			return "⚔"
		return "⚔ " + ("favourable" if dealt > taken else "costly" if taken > dealt else "even")
	var parts := PackedStringArray()
	if ct.has("tick"):
		parts.append("t%d" % int(ct["tick"]))
	if ct.has("dealt") or ct.has("taken"):
		parts.append("deal %s" % BattleFx.damage_text(dealt))
		parts.append("take %s" % BattleFx.damage_text(taken))
	var r: Array = ct.get("reactions", [])
	if not r.is_empty():
		parts.append("%d reaction%s" % [r.size(), "" if r.size() == 1 else "s"])
	return "⚔ " + " · ".join(parts) if not parts.is_empty() else "⚔"
