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
