class_name GlossaryLabel
extends RichTextLabel
## Text whose defined terms are hoverable (GDD 07, 01 pillar 3): every term
## the Glossary knows is underlined, and hovering one shows its tooltip with
## the live value for `context` (see Glossary.tooltip). Presentation only.

var glossary: Glossary
## What the hovered values are read from (Glossary.tooltip's ctx).
var context: Dictionary = {}

var _tip: GlossaryTooltip
var _plain: String = ""


func _init() -> void:
	bbcode_enabled = true
	fit_content = true
	scroll_active = false
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	meta_underlined = true
	mouse_filter = Control.MOUSE_FILTER_PASS
	meta_hover_started.connect(_on_hover)
	meta_hover_ended.connect(_on_unhover)


## Sets plain text; defined terms become links.
func set_linked(plain: String) -> void:
	_plain = plain
	text = glossary.bbcode(plain) if glossary != null else plain.replace("[", "[lb]")


func get_linked() -> String:
	return _plain


## The tooltip for a link's meta ("term:<id>"), or {}.
func tip_for(meta: Variant) -> Dictionary:
	var m := str(meta)
	if glossary == null or not m.begins_with("term:"):
		return {}
	return glossary.tooltip(m.substr(5), context)


func _on_hover(meta: Variant) -> void:
	var tip := tip_for(meta)
	if tip.is_empty():
		return
	if _tip == null:
		_tip = GlossaryTooltip.new()
		_tip.top_level = true
		add_child(_tip)
	_tip.show_tip(tip)
	_tip.global_position = get_global_mouse_position() + Vector2(14, 18)
	_tip.show()


func _on_unhover(_meta: Variant) -> void:
	if _tip != null:
		_tip.hide()
