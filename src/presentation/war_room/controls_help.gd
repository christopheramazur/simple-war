class_name ControlsHelp
extends RefCounted
## The war room's list of every control, by where it works (split from
## war_room.gd, sw-ll4.8). Shown by the "Controls" button.

## The list, with war room keys read from its GUIDE actions (DefaultKeys),
## so help names the keys the game actually binds.
static func help() -> Array:
	var k := DefaultKeys.war_room()
	var end := k.text_of(&"end_turn")
	var cancel := k.text_of(&"cancel")
	var nxt := k.text_of(&"next_battle")
	var prev := k.text_of(&"previous_battle")
	var follow := k.text_of(&"follow")
	var focus := k.text_of(&"focus_controls")
	var deselect := k.text_of(&"deselect_all")
	return [
		["Anywhere", "%s: end the turn (or skip a turn that is playing out)
%s / %s: next / previous battle (with no button focused)
%s: focus the buttons; then Tab / Shift+Tab walk them and Space or Enter presses one. While a button has focus, Tab and Space belong to it; Escape lets go
%s: leave a battle for the overworld (or skip a turn that is playing out)
Mouse wheel: zoom; zooming in on a battle hex enters it
%s: deselect everything" % [end, nxt, prev, focus, cancel, deselect]],
		["Overworld", "Left click: select a commander or a hex (the panel on the right says what is there)
Right click: move the selected commander there. Lit hexes are in reach this turn; the number is the movement cost
%s + right click: add a waypoint, so the route goes there next
Right click the commander itself: clear its route
%s: follow the selected commander
Garrisons, convoys and producing features: select their hex, press \"Send to\", then click a hex or one of your commanders" % [k.text_of(&"route_via"), follow]],
		["Battle", "Left click or drag a box: select your squads (Shift adds, Ctrl toggles, double click selects the type)
Left click any squad: show its card on the left. Hovering shows its weapon range
Right click: move the selection there (Alt: in a new line). Right click an enemy: attack it
%s
%s
%s" % [_planning_line(), "1-9: recall a control group · Ctrl+1-9: make one · Shift+1-9: add to one", "F1-F4: go to a camera bookmark · Ctrl+F1-F4: set one"]],
		["Reaction window", "Marked squads can react to an enemy: click one, or use the Reactions list on the right. Moves are locked until the turn has played"],
		["Playback", "While a turn plays out: %s or %s skips to its end
Left click a squad (yours or a visible enemy): its card shows for the moment being shown
Clicks issue no orders — the turn has already resolved" % [end, cancel]],
	]


## "H hold · A attack-move ..." from the planning context's own keys.
static func _planning_line() -> String:
	var p := PlanningInput.new()
	var parts: PackedStringArray = []
	for a: Array in [[&"hold", "hold"], [&"attack_move", "attack-move (then right click)"], [&"fall_back", "fall back"], [&"run", "run"], [&"withdraw", "withdraw"], [&"abilities", "abilities"]]:
		var ims: Array = []
		for m: GUIDEActionMapping in p.context.mappings:
			if m.action.name == a[0]:
				for im: GUIDEInputMapping in m.input_mappings:
					ims.append(GuideKeys.key_text(im.input))
		parts.append("%s %s" % [" / ".join(ims), a[1]])
	p.free()
	return " · ".join(parts)


## Side margin kept clear of the viewport edge when capping the body width
## (the HelpPanel style adds its own 18px inset on top of this).
const SIDE_MARGIN := 24.0
## The body's design width at 100%; it only ever shrinks to fit the viewport.
const BODY_WIDTH := 640.0


## The list as a window: a centred panel that leaves the keys to the game,
## so it can stay open while playing. Esc or Close shuts it. Like the modal
## dialog it is centred while it fits and scrolls vertically when the window
## is shorter than the list, and the body width is capped to the viewport
## minus margins so a large UI scale wraps the text instead of clipping it
## (sw-opt, XAG 101). Horizontal scroll stays off; the scroll takes no focus.
static func window() -> UiWindow:
	var w := UiWindow.new()
	w.id = &"help"
	w.captures_keys = false
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.focus_mode = Control.FOCUS_NONE
	w.add_child(scroll)
	var centre := CenterContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(centre)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"HelpPanel"
	centre.add_child(panel)
	var col := VBoxContainer.new()
	col.theme_type_variation = &"FormGap"
	panel.add_child(col)
	var bodies: Array[Label] = []
	for part: Array in help():
		col.add_child(UiTheme.label(part[0], "AccentLabel"))
		var body := UiTheme.label(part[1], "SmallLabel", true)
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bodies.append(body)
		col.add_child(body)
	col.add_child(UiTheme.label("Battle orders (hover for details)", "AccentLabel"))
	var pi := PlanningInput.new()
	for id in OrderTips.ids():
		var k := OrderTips.key_of(id, pi)
		var row := UiTheme.label("%s%s" % [OrderTips.name_of(id), (" (%s)" % k) if k != "" else ""], "SmallLabel")
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.tooltip_text = OrderTips.tip(id, pi)
		col.add_child(row)
	pi.free()
	var close := Button.new()
	close.text = "Close"
	close.focus_mode = Control.FOCUS_NONE  # Space stays "end turn"
	close.pressed.connect(w.close)
	col.add_child(close)
	# Cap the body to the viewport minus margins (never wider than the design
	# width), re-capping whenever the window resizes or the UI scale changes.
	var fit := func() -> void:
		var avail := minf(w.size.x - SIDE_MARGIN * 2.0, BODY_WIDTH)
		for b: Label in bodies:
			b.custom_minimum_size.x = maxf(avail, 200.0)
	w.resized.connect(fit)
	return w
