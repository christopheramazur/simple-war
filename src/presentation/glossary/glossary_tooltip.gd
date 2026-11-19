class_name GlossaryTooltip
extends PanelContainer
## One glossary tooltip (GDD 07, R1Q3, R3Q10): the term, its live value for
## the hovered squad (green ▲ when modified for the better, red ▼ for the
## worse: never colour alone), its definition and related terms. Fed by
## Glossary.tooltip; holds no game state.

const WIDTH: float = 300.0

var _title: Label
var _value: Label
var _text: Label
var _see: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme_type_variation = &"TooltipCardPanel"
	custom_minimum_size = Vector2(WIDTH, 0)
	var col := VBoxContainer.new()
	col.theme_type_variation = &"CardGap"
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	_title = _label(col, "")
	_value = _label(col, "ValueLabel")
	_text = _label(col, "SmallDimLabel")
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_see = _label(col, "CaptionDimLabel")
	_see.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


## Shows a Glossary.tooltip result.
func show_tip(tip: Dictionary) -> void:
	_title.text = tip.get("title", "")
	var value: String = tip.get("value", "")
	var change: int = tip.get("change", 0)
	_value.visible = not value.is_empty()
	_value.text = ("▲ " if change > 0 else ("▼ " if change < 0 else "")) + value
	_value.theme_type_variation = &"ValueGoodLabel" if change > 0 else (&"ValueBadLabel" if change < 0 else &"ValueLabel")
	_text.text = tip.get("text", "")
	var see: Array = tip.get("see", [])
	_see.visible = not see.is_empty()
	_see.text = Glossary._f("glossary.see", {"terms": ", ".join(PackedStringArray(see))})
	reset_size()


static func _label(parent: Node, style: String) -> Label:
	var l := UiTheme.label("", style)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.custom_minimum_size = Vector2(WIDTH - 20, 0)
	parent.add_child(l)
	return l
