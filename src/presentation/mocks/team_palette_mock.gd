extends RefCounted
## Mock: CVD-safe team colours (sw-ijp.5). War-room-style tokens and labels
## for both sides and the neutral in one preset, optionally through a
## colour-vision simulation. Render with
## `hx godot mock res://src/presentation/mocks/team_palette_mock.gd`.
## Env picks the variant: TEAM_PALETTE_PRESET (okabe_ito, tol_high_contrast)
## and TEAM_PALETTE_SIM ("" normal, greyscale, protan, deutan). The
## simulation applies the Machado et al. (2009) severity-1.0 matrices in
## linear RGB to every colour drawn, so the flat fills and text show what a
## CVD player sees; greyscale is WCAG luminance.

## Machado, Oliveira & Fernandes 2009, severity 1.0, row-major linear RGB.
const PROTAN: Array = [0.152286, 1.052583, -0.204868, 0.114503, 0.786281, 0.099216, -0.003882, -0.048116, 1.051998]
const DEUTAN: Array = [0.367322, 0.860646, -0.227968, 0.280085, 0.672501, 0.047413, -0.011820, 0.042940, 0.968881]


static func build() -> Control:
	var pid := OS.get_environment("TEAM_PALETTE_PRESET")
	if pid.is_empty():
		pid = TeamPalette.DEFAULT_ID
	var root := Control.new()
	root.custom_minimum_size = Vector2(900, 520)
	var canvas := _Canvas.new()
	canvas.preset_id = pid
	canvas.sim = OS.get_environment("TEAM_PALETTE_SIM")
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(canvas)
	return root


class _Canvas extends Control:
	var preset_id: String = TeamPalette.DEFAULT_ID
	var sim: String = ""


	func _s(col: Color) -> Color:
		if sim.is_empty():
			return col
		var l := col.srgb_to_linear()
		var m: Array = PROTAN if sim == "protan" else DEUTAN
		var out := Color.BLACK
		if sim == "greyscale":
			var y := 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b
			out = Color(y, y, y)
		else:
			out = Color(m[0] * l.r + m[1] * l.g + m[2] * l.b,
				m[3] * l.r + m[4] * l.g + m[5] * l.b,
				m[6] * l.r + m[7] * l.g + m[8] * l.b)
		out = out.linear_to_srgb()
		return Color(clampf(out.r, 0.0, 1.0), clampf(out.g, 0.0, 1.0), clampf(out.b, 0.0, 1.0), col.a)


	func _text(at: Vector2, text: String, col: Color, px: int = 13) -> void:
		draw_string(ThemeDB.fallback_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, _s(col))


	func _draw() -> void:
		var colors: Dictionary = TeamPalette.preset(preset_id)["colors"]
		var fill1 := Color.html(str(colors[1]))
		var fill2 := Color.html(str(colors[2]))
		var neutral := Color.html(str(colors[TeamPalette.NEUTRAL_ID]))
		var p := UiTheme.profile("default")
		var bg := UiTheme.color(p, "background")
		var panel := UiTheme.color(p, "panel")
		var text := UiTheme.color(p, "text")
		var dim := UiTheme.color(p, "dim")
		var field := UiTheme.color(p, "field")
		var tone1 := TeamPalette.text_tone(fill1, panel)
		var tone2 := TeamPalette.text_tone(fill2, panel)
		var tonen := TeamPalette.text_tone(neutral, panel)
		var field1 := TeamPalette.text_tone(fill1, field)
		var field2 := TeamPalette.text_tone(fill2, field)
		draw_rect(Rect2(Vector2.ZERO, size), _s(bg))
		var sim_name: String = {"": "normal vision", "greyscale": "greyscale", "protan": "protanopia (simulated)", "deutan": "deuteranopia (simulated)"}.get(sim, sim)
		_text(Vector2(24, 34), "%s  ·  %s" % [str(TeamPalette.preset(preset_id)["name"]), sim_name], text, 19)
		# The battlefield: a zone, two squads, two commanders, a neutral token.
		draw_rect(Rect2(24, 56, 508, 388), _s(field))
		var zc := Vector2(278, 258)
		draw_circle(zc, 112.0, _s(Color(fill1, 0.10)))
		draw_arc(zc, 112.0, 0, TAU, 64, _s(Color(fill1, 0.8)), 2.0)
		_text(zc + Vector2(-64, 130), "zone A · player 1 taking", field1, 12)
		_squad(Vector2(150, 226), fill1, "Rifle squad 8/8 · P1", field1)
		_squad(Vector2(330, 300), fill2, "Rifle squad 8/8 · P2", field2)
		_commander(Vector2(146, 342), fill1, 1, field)
		_commander(Vector2(412, 150), fill2, 2, field)
		draw_circle(Vector2(278, 392), 9.0, _s(neutral))
		_text(Vector2(294, 397), "neutral (id 30)", TeamPalette.text_tone(neutral, field), 12)
		# The battle panel: scores in the sides' text tones, tokens with labels.
		draw_rect(Rect2(556, 56, 320, 388), _s(panel))
		_text(Vector2(576, 88), "Crossroads  ·  battle turn 4", dim, 13)
		_text(Vector2(576, 118), "You:  influence 12  ·  value 30", tone1, 14)
		_text(Vector2(576, 144), "Enemy (P2):  influence 9  ·  value 21", tone2, 14)
		_text(Vector2(576, 172), "Zone A: You (2 of 3)", dim, 13)
		draw_line(Vector2(576, 190), Vector2(856, 190), _s(dim), 1.0)
		draw_rect(Rect2(584, 214, 16, 16), _s(fill1))
		_text(Vector2(610, 227), "P1 3   (garrison: 3 squads)", text, 13)
		var dc := Vector2(592, 262)
		draw_colored_polygon(PackedVector2Array([dc + Vector2(0, -11), dc + Vector2(11, 0), dc + Vector2(0, 11), dc + Vector2(-11, 0)]), _s(fill2))
		_text(Vector2(610, 267), "P2 2   (convoy: 2 squads)", text, 13)
		draw_circle(Vector2(592, 306), 6.0, _s(fill1))
		draw_rect(Rect2(606, 300, 12, 12), _s(fill2))
		_text(Vector2(628, 311), "plot owners: round P1, square P2", dim, 12)
		draw_rect(Rect2(584, 330, 14, 14), _s(neutral))
		_text(Vector2(610, 342), "Neutral (id 30)", tonen, 13)
		_text(Vector2(576, 380), "Text tones pass WCAG AA (4.5:1)", dim, 12)
		_text(Vector2(576, 400), "on the panel in every preset.", dim, 12)
		_text(Vector2(24, 474), "Side identity is also shape and label: round tokens and P1, square tokens and P2 — never colour alone.", text, 13)
		_text(Vector2(24, 498), "Simulation: Machado et al. 2009 severity-1.0 matrices in linear RGB; greyscale = WCAG luminance.", dim, 12)


	func _squad(at: Vector2, fill: Color, label: String, tone: Color) -> void:
		for i in 5:
			var u := at + Vector2(i * 17.0, 0)
			draw_circle(u, 9.0, _s(Color(fill, 0.22)))
			draw_circle(u, 4.0, _s(fill))
		var centre := at + Vector2(34, 0)
		draw_colored_polygon(PackedVector2Array([centre + Vector2(66, 0), centre + Vector2(54, -6), centre + Vector2(54, 6)]), _s(fill.lightened(0.35)))
		_text(at + Vector2(-14, -18), label, tone, 13)


	func _commander(at: Vector2, fill: Color, player: int, badge_text: Color) -> void:
		draw_circle(at, 16.0, _s(fill))
		var badge := at + Vector2(15, -13)
		draw_circle(badge, 8.0, _s(fill))
		draw_string(ThemeDB.fallback_font, badge + Vector2(-4, 4), str(player), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, _s(badge_text))
