@tool
class_name WarGraphNodeUI
extends CGEGraphNodeUI
## Draws a trigger-graph node: a box tinted by kind, with a glyph and the
## kind's name so colour is never the only cue.

const STYLE: Dictionary = {
	"event": [Color("3d5a80"), "⚡ on"],
	"trigger": [Color("5a4a7a"), "◆ trigger"],
	"var": [Color("4a6a4a"), "▣ var"],
	"zone": [Color("7a5a3a"), "◎ zone"],
	"feature": [Color("6a6a3a"), "⬡ feature"],
}
const SIZE: Vector2 = Vector2(200, 52)


func _ready() -> void:
	custom_minimum_size = SIZE
	size = SIZE


func _get_minimum_size() -> Vector2:
	return SIZE


func _draw() -> void:
	var n := graph_element as WarGraphNode
	var kind := n.kind if n != null else ""
	var style: Array = STYLE.get(kind, [Color("444444"), kind])
	draw_rect(Rect2(Vector2.ZERO, size), style[0])
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.9, 0.9, 0.9) if selected else Color(0.55, 0.55, 0.55), false, 3.0 if selected else 1.0)
	var font := get_theme_default_font()
	draw_string(font, Vector2(8, 18), style[1], HORIZONTAL_ALIGNMENT_LEFT, size.x - 16, 12, Color(0.85, 0.85, 0.85))
	draw_string(font, Vector2(8, 40), n.node_name if n != null else "", HORIZONTAL_ALIGNMENT_LEFT, size.x - 16, 15, Color.WHITE)


func _update_ui_from_data() -> void:
	queue_redraw()
