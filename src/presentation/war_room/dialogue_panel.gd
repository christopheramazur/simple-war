class_name DialoguePanel
extends PanelContainer
## Plays one dialogue (sw-62i): the speaker, the line and a button per
## available choice. It holds no state: it draws the view the session gives
## (OverworldSession.dialogue_view) and emits `picked` (a choice index, or -1
## to go on from a line without choices); the owner sends that to the session
## and calls `show_view` again. Runs standalone (F6) on a sample dialogue.

signal picked(choice: int)
signal closed

var _box: VBoxContainer


func _ready() -> void:
	_box = VBoxContainer.new()
	add_child(_box)
	if get_parent() == get_tree().root:
		_demo()


## Draws a dialogue view; an ended one closes the panel.
func show_view(view: Dictionary) -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	if view.is_empty() or view.get("ended", false):
		visible = false
		closed.emit()
		return
	visible = true
	var who := String(view.get("speaker", ""))
	if not who.is_empty():
		var l := Label.new()
		l.text = who.capitalize()
		_box.add_child(l)
	var line := Label.new()
	line.text = _say(String(view["key"]), String(view["text"]))
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size.x = 420
	_box.add_child(line)
	var choices: Array = view.get("choices", [])
	if choices.is_empty():
		var b := Button.new()
		b.text = "Continue"
		b.pressed.connect(func() -> void: picked.emit(-1))
		_box.add_child(b)
	for c: Dictionary in choices:
		var b := Button.new()
		b.text = _say(String(c["key"]), String(c["text"]))
		var i: int = c["index"]
		b.pressed.connect(func() -> void: picked.emit(i))
		_box.add_child(b)


static func _say(key: String, fallback: String) -> String:
	if key.is_empty():
		return fallback
	var t := TranslationServer.translate(key)
	return fallback if t == key else t


func _demo() -> void:
	var lines := {"a": {"text": "Hello", "choices": [{"index": 0, "text": "Hi"}]}}
	show_view({"speaker": "jeff", "key": "", "text": String(lines["a"]["text"]), "choices": lines["a"]["choices"]})
	picked.connect(func(_i: int) -> void: show_view({"ended": true}))
