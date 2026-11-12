class_name ReactionRadial
extends Control
## The reaction popup on a reactable squad (GDD 02 §2.2, R3Q4): its reaction
## options in a ring around the squad, each a glyph plus its name (never
## colour alone), and "skip" in the middle. Emits `chosen` and closes; the
## owner submits the reaction.

signal chosen(reaction: String)
signal dismissed

const RADIUS: float = 64.0
## Glyphs for the core reactions; others show their first letter.
const GLYPHS: Dictionary = {"halt": "■", "fall_back": "↶", "retarget": "⌖"}

var reactions: Array = []


## Opens around `at` (this control's parent coordinates) with the
## opportunity's reaction names; `current` is the one already queued.
func open(at: Vector2, names: Array, current: String = "") -> void:
	reactions = names.duplicate()
	for c in get_children():
		remove_child(c)
		c.queue_free()
	position = at
	size = Vector2.ZERO
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var n := names.size()
	for i in n:
		var r: String = names[i]
		var b := Button.new()
		b.text = "%s %s" % [glyph(r), r.capitalize()]
		b.toggle_mode = true
		b.button_pressed = r == current
		b.tooltip_text = r.capitalize()
		var ang := -PI / 2.0 + TAU * i / maxf(n, 1)
		b.position = Vector2(cos(ang), sin(ang)) * RADIUS - Vector2(48, 14)
		b.custom_minimum_size = Vector2(96, 28)
		b.pressed.connect(_pick.bind(r))
		add_child(b)
	var skip := Button.new()
	skip.text = "✕"
	skip.tooltip_text = "Close"
	skip.position = Vector2(-14, -14)
	skip.custom_minimum_size = Vector2(28, 28)
	skip.pressed.connect(_close)
	add_child(skip)
	show()


static func glyph(reaction: String) -> String:
	return GLYPHS.get(reaction, reaction.left(1).to_upper())


func _pick(r: String) -> void:
	hide()
	chosen.emit(r)


func _close() -> void:
	hide()
	dismissed.emit()
