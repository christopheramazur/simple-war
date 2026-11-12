@tool
extends EditorPlugin
## Adds the "War Data" main screen (WarDataPanel): the data editor and the
## trigger graph view (GDD 04 §4.9, R8Q7).

var _panel: Control


func _enter_tree() -> void:
	_panel = WarDataPanel.new()
	_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	EditorInterface.get_editor_main_screen().add_child(_panel)
	_make_visible(false)


func _exit_tree() -> void:
	if _panel != null:
		_panel.queue_free()
		_panel = null


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if _panel != null:
		_panel.visible = visible


func _get_plugin_name() -> String:
	return "War Data"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("Tree", "EditorIcons")
