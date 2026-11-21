class_name TeamPalette
extends RefCounted
## Side colours as one presentation-layer source (sw-ijp.5; GDD 01 Input and
## UI Accessibility: colour-blind-safe palettes, never colour alone). Every
## reader (ContextView, ReplayViewer, BattlePanel, ResultsScreen) resolves
## here at render time; the chosen preset is the `team_palette` setting in
## user://settings.cfg. Never in data/packages or the sim: replays store
## player ids, so the same replay draws in any preset (determinism).
##
## Presets are colour-blind-safe pairs: Okabe-Ito blue vs vermillion by
## default, Tol high-contrast blue vs yellow as the alternate. Every preset
## carries the neutral id 30, a grey picked to stay apart from both sides in
## greyscale too. Fills use `color`; labels use `text_color`, a lighter tone
## of the same hue that passes WCAG AA (4.5:1) against the theme's panel
## colour (raw Okabe-Ito blue fails AA on the dark panel). Side identity is
## also drawn as shape or label — round tokens and "P1" for player 1, square
## tokens and "P2" for player 2 — never colour alone.

const DEFAULT_ID := "okabe_ito"
const NEUTRAL_ID := 30
## WCAG AA contrast for normal text.
const AA := 4.5
const PRESETS: Dictionary = {
	"okabe_ito": {
		"name": "Okabe-Ito (colour-blind safe)",
		"colors": {1: "0072B2", 2: "D55E00", NEUTRAL_ID: "AAAAAA"},
	},
	"tol_high_contrast": {
		"name": "Tol high-contrast",
		"colors": {1: "004488", 2: "DDAA33", NEUTRAL_ID: "888888"},
	},
}


## Preset ids in menu order: the default first, then by name.
static func ids() -> PackedStringArray:
	var rest: Array = PRESETS.keys().filter(func(k: String) -> bool: return k != DEFAULT_ID)
	rest.sort_custom(func(a: String, b: String) -> bool: return str(PRESETS[a]["name"]) < str(PRESETS[b]["name"]))
	var out := PackedStringArray([DEFAULT_ID])
	out.append_array(PackedStringArray(rest))
	return out


## The chosen preset (the `team_palette` setting); unknown ids fall back to
## the default. Pass `id` to look at another preset without switching.
static func preset(id: String = "") -> Dictionary:
	if id.is_empty():
		id = str(GameSettings.value("team_palette"))
	return PRESETS[id] if PRESETS.has(id) else PRESETS[DEFAULT_ID]


static func has(id: int) -> bool:
	return (preset()["colors"] as Dictionary).has(id)


## A side's fill colour. Unlisted ids get `fallback`, or the preset's neutral
## when no fallback is given (pass Color.TRANSPARENT to ask for the neutral).
static func color(id: int, fallback: Color = Color.TRANSPARENT) -> Color:
	var colors: Dictionary = preset()["colors"]
	if colors.has(id):
		return Color.html(str(colors[id]))
	return fallback if fallback != Color.TRANSPARENT else Color.html(str(colors[NEUTRAL_ID]))


## A side's label colour: its fill lightened towards white until it passes
## AA against `bg` (default: the current theme's panel colour). On a light
## panel it darkens instead; the tone keeps the side's hue.
static func text_color(id: int, bg: Color = Color.TRANSPARENT) -> Color:
	if bg == Color.TRANSPARENT:
		bg = UiTheme.color(UiTheme.profile(str(GameSettings.value("ui_theme"))), "panel")
	return text_tone(color(id), bg)


## `base` adjusted towards white (or black on a light background) until it
## passes AA against `bg`. Deterministic: 5% steps, white first.
static func text_tone(base: Color, bg: Color) -> Color:
	if contrast(base, bg) >= AA:
		return base
	for i in 20:
		var lighter := base.lerp(Color.WHITE, float(i + 1) / 20.0)
		if contrast(lighter, bg) >= AA:
			return lighter
	for i in 20:
		var darker := base.lerp(Color.BLACK, float(i + 1) / 20.0)
		if contrast(darker, bg) >= AA:
			return darker
	return Color.WHITE if contrast(Color.WHITE, bg) >= contrast(Color.BLACK, bg) else Color.BLACK


## WCAG contrast ratio (1..21) between two colours. Color components are
## sRGB-encoded (Color.html does not linearise), as WCAG expects.
static func contrast(a: Color, b: Color) -> float:
	var la := luminance(a)
	var lb := luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


## WCAG relative luminance (0..1).
static func luminance(c: Color) -> float:
	return 0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b)


static func _channel(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
