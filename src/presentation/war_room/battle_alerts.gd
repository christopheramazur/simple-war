class_name BattleAlerts
extends VBoxContainer
## The war room's persistent battle-alert panel (sw-9un): battle start, end
## and breaking alerts, kept after the player looks away so an alert raised
## in an unwatched battle is still there on return. Fed `add` lines built
## from the event feed (it reads no simulation state); each carries a word
## and a symbol as well as a colour. An alert is "NEW" until the player
## focuses its battle, dismisses it, or the notification time
## (GameSettings `alert_seconds`; 0 = until dismissed) runs out.

const KEEP: int = 12
const KINDS: Dictionary = {
	"start": {"mark": "⚔ BATTLE START", "style": "AccentLabel"},
	"end": {"mark": "■ BATTLE END", "style": "DimLabel"},
	"alert": {"mark": "⚠ ALERT", "style": "HeadingBadLabel"},
}

## {"kind", "text", "eid", "turn", "age" (seconds), "new"}, oldest first.
var entries: Array[Dictionary] = []
## How long an alert stays NEW (seconds; 0 = until dismissed).
var seconds: float = 6.0


func _ready() -> void:
	seconds = float(GameSettings.value("alert_seconds"))
	_rebuild()


## Records an alert. `watched`: the player is looking at that battle now.
func add(kind: String, text: String, eid: int, turn: int, watched: bool) -> void:
	entries.append({"kind": kind, "text": text, "eid": eid, "turn": turn, "age": 0.0, "new": not watched})
	while entries.size() > KEEP:
		entries.pop_front()
	_rebuild()


## The player now looks at battle `eid`: its alerts are seen.
func focus_changed(eid: int) -> void:
	var changed := false
	for e in entries:
		if e["new"] and int(e["eid"]) == eid:
			e["new"] = false
			changed = true
	if changed:
		_rebuild()


func dismiss_all() -> void:
	entries.clear()
	_rebuild()


func new_count() -> int:
	var n := 0
	for e in entries:
		if e["new"]:
			n += 1
	return n


## Advances the NEW timers by `dt` real seconds.
func tick(dt: float) -> void:
	if seconds <= 0.0:
		return
	var changed := false
	for e in entries:
		if e["new"]:
			e["age"] = float(e["age"]) + dt
			if float(e["age"]) >= seconds:
				e["new"] = false
				changed = true
	if changed:
		_rebuild()


func _process(delta: float) -> void:
	tick(delta)


func _rebuild() -> void:
	if not is_inside_tree() and get_child_count() == 0 and entries.is_empty():
		return
	for c in get_children():
		remove_child(c)
		c.queue_free()
	if entries.is_empty():
		return
	var head := HBoxContainer.new()
	var t := UiTheme.label("Battle alerts%s" % ("" if new_count() == 0 else " (%d new)" % new_count()), "AccentLabel")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var b := Button.new()
	b.name = "DismissAll"
	b.text = "Dismiss"
	b.pressed.connect(dismiss_all)
	head.add_child(b)
	add_child(head)
	for i in range(entries.size() - 1, -1, -1):
		var e := entries[i]
		var k: Dictionary = KINDS.get(e["kind"], KINDS["alert"])
		var l := UiTheme.label("%s%s · T%d · %s" % ["NEW  " if e["new"] else "", k["mark"], int(e["turn"]), e["text"]],
			k["style"] if e["new"] else "SmallDimLabel", true)
		l.name = "Alert%d" % i
		add_child(l)
