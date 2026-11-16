class_name ControlsHelp
extends RefCounted
## The war room's list of every control, by where it works (split from
## war_room.gd, sw-ll4.8). Shown by the "Controls" button.

const HELP: Array = [
	["Anywhere", "Space: end the turn (or skip a turn that is playing out)\nTab / Shift+Tab: next / previous battle\nEsc: leave a battle for the overworld\nMouse wheel: zoom; zooming in on a battle hex enters it\nBackspace: deselect everything"],
	["Overworld", "Left click: select a commander or a hex (the panel on the right says what is there)\nRight click: move the selected commander there. Lit hexes are in reach this turn; the number is the movement cost\nShift + right click: add a waypoint, so the route goes there next\nRight click the commander itself: clear its route\nF: follow the selected commander\nGarrisons, convoys and producing features: select their hex, press \"Send to\", then click a hex or one of your commanders"],
	["Battle", "Left click or drag a box: select your squads (Shift adds, Ctrl toggles, double click selects the type)\nLeft click any squad: show its card on the left. Hovering shows its weapon range\nRight click: move the selection there (Alt: in a new line). Right click an enemy: attack it\nH hold · A attack-move (then right click) · B fall back · R run · Shift+W withdraw · Q abilities\n1-9: recall a control group · Ctrl+1-9: make one · Shift+1-9: add to one\nF1-F4: go to a camera bookmark · Ctrl+F1-F4: set one"],
	["Reaction window", "Marked squads can react to an enemy: click one, or use the Reactions list on the right. Moves are locked until the turn has played"],
]


## The list as a centred panel; `on_close` is called by its Close button.
static func build(on_close: Callable) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.1, 0.13, 0.97)
	sb.border_color = Color("e6b450")
	sb.set_border_width_all(1)
	sb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	for part: Array in HELP:
		var head := Label.new()
		head.text = part[0]
		head.add_theme_color_override("font_color", Color("e6b450"))
		col.add_child(head)
		var body := Label.new()
		body.text = part[1]
		body.add_theme_font_size_override("font_size", 13)
		body.custom_minimum_size = Vector2(640, 0)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(body)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(on_close)
	col.add_child(close)
	return panel
