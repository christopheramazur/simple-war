class_name HexCard
extends RefCounted
## The card for one overworld hex (sw-ll4.26): what the player knows is
## there, in plain words. It only formats OverworldSession.inspect_plot, the
## one question the game answers about a hex, so the hover card, the
## selection panel and anything later (a pinned window, a tooltip in the
## editor) say the same thing.

const TEXT := Color("dde2ea")
const DIM := Color("8a93a3")
const ACCENT := Color("e6b450")


static func build(info: Dictionary, rules: OverworldRules, viewer: int) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.custom_minimum_size = Vector2(250, 0)
	for line: Array in lines(info, rules, viewer):
		var l := Label.new()
		l.text = line[0]
		l.add_theme_font_size_override("font_size", 14 if line[1] == "head" else 12)
		l.add_theme_color_override("font_color", {"head": ACCENT, "dim": DIM}.get(line[1], TEXT))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(l)
	return col


## The card as [text, "head" | "text" | "dim"] lines.
static func lines(info: Dictionary, rules: OverworldRules, viewer: int) -> Array:
	var out := []
	var cost := int(info.get("cost", -1))
	out.append(["Hex %s  ·  %s" % [EventText.hex(int(info["plot"]), rules), "impassable" if cost < 0 else "costs %d movement" % cost], "dim"])
	if not bool(info.get("visible", false)):
		out.append(["Last seen earlier: not in sight now.", "dim"])
	if bool(info.get("battle", false)):
		out.append(["A battle is being fought here.", "text"])
	for f: Dictionary in info.get("features", []):
		var owner := int(f["owner"])
		var whose := "" if owner <= 0 else "  ·  " + ("yours" if owner == viewer else EventText.side(owner, viewer))
		if owner <= 0 and bool(f["controllable"]):
			whose = "  ·  unclaimed"
		out.append([str(f["name"]) + whose, "head"])
		var guard: PackedStringArray = f["guard"]
		if not guard.is_empty():
			out.append(["Guarded by %d squad%s: %s. Entering starts a battle." % [guard.size(), "" if guard.size() == 1 else "s", ", ".join(guard)], "text"])
		elif bool(f["controllable"]) and owner != viewer:
			out.append(["Move a commander onto it to take it.", "dim"])
		if int(f["value_per_turn"]) != 0:
			out.append(["Gives its owner %d Value a turn." % int(f["value_per_turn"]), "text"])
		if int(f["cache_value"]) > 0:
			out.append(["A cache: %d Value to the first commander here." % int(f["cache_value"]), "text"])
		for p: Dictionary in f.get("produces", []):
			var progress := "" if int(p["progress"]) < 0 else "  (turn %d of %d)" % [int(p["progress"]), int(p["turns"])]
			out.append(["%s %s every %d turn%s for %d Value%s" % ["Makes" if bool(p["selected"]) else "Can make", p["name"], int(p["turns"]),
				"" if int(p["turns"]) == 1 else "s", int(p["cost"]), progress], "text" if bool(p["selected"]) else "dim"])
		var line: Dictionary = f.get("line", {})
		if int(line.get("commander", -1)) >= 0:
			out.append(["Its output goes to %s." % EventText.commander(int(line["commander"])), "dim"])
		elif int(line.get("plot", -1)) >= 0:
			out.append(["Its output goes to %s." % EventText.hex(int(line["plot"]), rules), "dim"])
		for r: Dictionary in f.get("recruits", []):
			out.append(["A commander here can recruit a %s for %d Value." % [r["name"], int(r["cost"])], "dim"])
		for h: Dictionary in f.get("hires", []):
			out.append(["A commander here can hire a new %s for %d Value." % [String(h["name"]).to_lower(), int(h["cost"])], "dim"])
		var acts: PackedStringArray = f["activities"]
		var other := Array(acts).filter(func(a: String) -> bool: return a != "recruit" and a != "hire")
		if not other.is_empty():
			out.append(["A commander ending its move here can: %s." % ", ".join(other), "dim"])
	for c: Dictionary in info.get("commanders", []):
		var mine := int(c["player"]) == viewer
		var army := "" if int(c["squads"]) < 0 else ", %d squad%s" % [int(c["squads"]), "" if int(c["squads"]) == 1 else "s"]
		out.append(["%s %s%s%s" % ["Your" if mine else EventText.side(int(c["player"]), viewer), EventText.commander(int(c["id"])) if mine else "commander",
			army, "  ·  in battle" if int(c["engagement"]) >= 0 else ""], "text"])
	for d: Dictionary in info.get("detachments", []):
		var mine := int(d["player"]) == viewer
		var what := "convoy" if bool(d["convoy"]) else "garrison"
		var squads: PackedStringArray = d["squads"]
		out.append(["%s %s%s" % ["Your" if mine else EventText.side(int(d["player"]), viewer), what,
			"" if squads.is_empty() else ": " + ", ".join(squads)], "text"])
	if out.size() == 1 + (0 if bool(info.get("visible", false)) else 1):
		out.append(["Nothing of note.", "dim"])
	return out
