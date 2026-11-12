class_name GlossaryTooltip
extends PanelContainer
## One glossary tooltip (GDD 07, R1Q3, R3Q10): the term, its live value for
## the hovered squad (green ▲ when modified for the better, red ▼ for the
## worse: never colour alone), its definition and related terms. Fed by
## Glossary.tooltip; holds no game state.

const BG: Color = Color("1d2128")
const LINE: Color = Color("323a46")
const TEXT: Color = Color("dde2ea")
const DIM: Color = Color("8a93a3")
const UP: Color = Color("74d18a")
const DOWN: Color = Color("e8735f")
const WIDTH: float = 300.0

var _title: Label
var _value: Label
var _text: Label
var _see: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.border_color = LINE
	sb.set_border_width_all(1)
	sb.set_content_margin_all(10)
	sb.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(WIDTH, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	_title = _label(col, TEXT, 16)
	_value = _label(col, TEXT, 15)
	_text = _label(col, DIM, 13)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_see = _label(col, DIM, 12)
	_see.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


## Shows a Glossary.tooltip result.
func show_tip(tip: Dictionary) -> void:
	_title.text = tip.get("title", "")
	var value: String = tip.get("value", "")
	var change: int = tip.get("change", 0)
	_value.visible = not value.is_empty()
	_value.text = ("▲ " if change > 0 else ("▼ " if change < 0 else "")) + value
	_value.add_theme_color_override("font_color", UP if change > 0 else (DOWN if change < 0 else TEXT))
	_text.text = tip.get("text", "")
	var see: Array = tip.get("see", [])
	_see.visible = not see.is_empty()
	_see.text = Glossary._f("glossary.see", {"terms": ", ".join(PackedStringArray(see))})
	reset_size()


static func _label(parent: Node, color: Color, font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.custom_minimum_size = Vector2(WIDTH - 20, 0)
	parent.add_child(l)
	return l
