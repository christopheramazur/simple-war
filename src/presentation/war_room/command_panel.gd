class_name CommandPanel
extends VBoxContainer
## The war room's panel for what is selected on the overworld (split from
## war_room.gd, sw-ll4.8): a commander's army, movement, battleforce and
## supply lines, or a hex's features, garrisons and convoys. It only reads
## the session (observe, reach) and never orders anything itself: every
## button emits a signal the war room turns into an order.

signal battleforce_chosen(preset: String, lead: bool)
signal pick_up_requested(detachment: int)
signal route_clear_requested
## "Send to": the next hex clicked is the destination ("rally" a
## detachment, or a producing feature's "line").
signal target_armed(kind: String, id: int, what: String)
## Send a detachment to a plot or a commander (both -1 halts it).
signal rally_requested(detachment: int, plot: int, commander: int, what: String)
## Send a feature's output to a plot or a commander (both -1 clears it).
signal supply_line_requested(feature: int, plot: int, commander: int, what: String)
## Plan (or, with "", clear) the commander's activity where its route ends:
## recruit a squad, hire a commander (option = template ID), refit, ...
signal activity_requested(activity: String, option: String)
## A feature row was clicked: select that site (U1Q23), on its hex.
signal feature_selected(feature: int, plot: int)
## The pointer entered (feature ID) or left (-1) a feature row, so the map
## rings that site; set_hover_feature is the other way round.
signal feature_hovered(feature: int)

## Feature rows are selection, not orders: playback's lock leaves them on.
const SELECT_ROW := &"select_row"


## Defined terms for the hoverable titles.
var glossary: Glossary
var session: OverworldSession
var player: int = 1
var commander: int = -1
var plot: int = -1
var detachment: int = -1
## The selected feature (ViewContexts.selected_feature; -1 = none).
var feature: int = -1
## Feature ID -> its row button, for linked hover.
var _rows: Dictionary = {}
var _hover_feature: int = -1
## While a turn plays out: the reason every action control here is disabled
## ("Available in Planning"); "" in Planning (sw-bafi.9 U1 C8). The panel
## still shows everything, so the selection can be inspected.
var locked_reason: String = ""


## Shows the selected commander (`commander_id`, -1 for none), or else the
## selected hex (`plot_id`, -1 for none), as `for_player` knows them.
func show_selection(of_session: OverworldSession, for_player: int, commander_id: int, plot_id: int, detachment_id: int = -1, feature_id: int = -1) -> void:
	session = of_session
	player = for_player
	commander = commander_id
	plot = plot_id
	detachment = detachment_id
	feature = feature_id
	_rows = {}
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_build()
	if not locked_reason.is_empty():
		_lock(self)


## Disables every action control under `node`, its tooltip saying why.
func _lock(node: Node) -> void:
	for c in node.get_children():
		if c is BaseButton and not c.has_meta(SELECT_ROW):
			(c as BaseButton).disabled = true
			(c as Control).tooltip_text = locked_reason
		_lock(c)


func _build() -> void:
	var cid := commander
	var obs := session.observe(player)
	if cid < 0 and detachment >= 0:
		_detachment_info(obs)
		return
	if cid < 0:
		_hex_info(obs)
		return
	var me := {}
	for c: Dictionary in obs["commanders"]:
		if c["id"] == cid:
			me = c
	if me.is_empty():
		return
	_army_info(me, obs)
	if session.clock.phase != PulseClock.Phase.PLANNING:
		return
	_movement_info(me, obs)
	_activity_info(me, obs)
	add_child(_title("Commander %d: battleforce" % (cid & 0xffff)))
	var plan: Dictionary = me.get("battleforce_plan", {})
	var pick := OptionButton.new()
	var choices: Array = [["Strongest first", ""], ["No battleforce (disperses Angels)", OverworldBattleforce.NONE]]
	for pid in session.rules.preset_ids:
		choices.append([String(pid).trim_prefix("preset_").capitalize(), String(pid)])
	for i in choices.size():
		pick.add_item(choices[i][0])
		pick.set_item_metadata(i, choices[i][1])
		if choices[i][1] == String(plan.get("preset", "")):
			pick.select(i)
	var lead := CheckBox.new()
	lead.text = "Commander's own squad fights"
	lead.button_pressed = bool(plan.get("lead", true))
	pick.item_selected.connect(func(i: int) -> void:
		var preset: String = pick.get_item_metadata(i)
		battleforce_chosen.emit(preset, false if preset == OverworldBattleforce.NONE else lead.button_pressed))
	lead.toggled.connect(func(on: bool) -> void: battleforce_chosen.emit(String(plan.get("preset", "")), on))
	add_child(pick)
	add_child(lead)
	var production: Dictionary = obs.get("production", {})
	if production.is_empty():
		return
	add_child(_title("Supply lines"))
	var lines: Dictionary = obs.get("supply_lines", {})
	var fids: Array = production.keys()
	fids.sort()
	for fid: int in fids:
		var row := session.state.features.row_of(fid)
		var b := Button.new()
		var fp := session.state.features.plot[row]
		var name := "%s (%d,%d)" % [session.rules.hf_names[session.state.features.tmpl[row]], fp % session.rules.width, fp / session.rules.width]
		var to_me: bool = lines.has(fid) and lines[fid]["commander"] == cid
		b.text = ("✓ %s sends to this commander" if to_me else "%s: send output here") % name
		b.disabled = to_me
		b.pressed.connect(supply_line_requested.emit.bind(fid, -1, cid, name))
		add_child(b)


## The selected commander's movement points and route, and the player's
## garrisons and convoys elsewhere that it can call to itself.
func _movement_info(me: Dictionary, obs: Dictionary) -> void:
	var cid := int(me["id"])
	var reach := session.reach(player, cid)
	var route: PackedInt64Array = (obs.get("routes", {}) as Dictionary).get(cid, PackedInt64Array())
	add_child(_title("Movement"))
	if int(me["engagement"]) >= 0:
		add_child(_dim_label("In a battle: it can't move until the battle ends."))
	else:
		add_child(_dim_label("%d of %d movement points planned. Right click a lit hex to move; Shift+right click adds a waypoint." % [
			int(reach.get("spent", 0)), int(reach.get("budget", 0))]))
	if not route.is_empty():
		var clear := Button.new()
		clear.text = "Clear route (%d hex%s)" % [route.size(), "" if route.size() == 1 else "es"]
		clear.pressed.connect(route_clear_requested.emit)
		add_child(clear)
	for det: Dictionary in obs.get("detachments", []):
		if int(det["player"]) != player or int(det["engagement"]) >= 0 or int(det["plot"]) == int(me["plot"]):
			continue
		var n := (det.get("squads", []) as Array).size()
		if n == 0:
			continue
		var what := "%s at %s (%d squad%s)" % [band_word(det), EventText.hex(int(det["plot"]), session.rules), n, "" if n == 1 else "s"]
		if int(det.get("dest_commander", -1)) == cid:
			add_child(_dim_label("On its way here: " + what))
			continue
		var b := Button.new()
		b.text = "Call here: " + what
		b.tooltip_text = "It becomes a convoy that walks to where this commander's route ends each turn, and joins the army when they meet."
		b.pressed.connect(rally_requested.emit.bind(int(det["id"]), -1, cid, what))
		add_child(b)


## What the commander can do where its route ends (GDD 02 §2.9): the
## planned activity, and a button per option the hex offers (recruit a
## squad, hire a commander, refit, convert, battle). Costs are paid when
## the turn resolves.
func _activity_info(me: Dictionary, obs: Dictionary) -> void:
	if int(me["engagement"]) >= 0:
		return
	var cid := int(me["id"])
	var route: PackedInt64Array = (obs.get("routes", {}) as Dictionary).get(cid, PackedInt64Array())
	var dest := int(me["plot"]) if route.is_empty() else route[route.size() - 1]
	var planned: Dictionary = (obs.get("activities", {}) as Dictionary).get(cid, {})
	var buttons: Array[Button] = []
	for f: Dictionary in session.inspect_plot(player, dest).get("features", []):
		var acts: PackedStringArray = f["activities"]
		for r: Dictionary in f.get("recruits", []):
			buttons.append(_activity_button("recruit", String(r["id"]), "Recruit %s (%d Value)" % [r["name"], int(r["cost"])], planned))
		for h: Dictionary in f.get("hires", []):
			buttons.append(_activity_button("hire", String(h["id"]), "Hire a %s (%d Value)" % [String(h["name"]).to_lower(), int(h["cost"])], planned))
		for a in acts:
			if a != "recruit" and a != "hire":
				buttons.append(_activity_button(a, "", "%s at %s" % [a.capitalize(), f["name"]], planned))
	if buttons.is_empty() and planned.is_empty():
		return
	add_child(_title("Activity at %s" % EventText.hex(dest, session.rules)))
	add_child(_dim_label("Value: %d. Performed after moving, if the commander ends its route here." % int(obs.get("value", 0))))
	for b in buttons:
		add_child(b)
	if not planned.is_empty():
		var clear := Button.new()
		clear.text = "Cancel planned %s" % String(planned["activity"])
		clear.pressed.connect(activity_requested.emit.bind("", ""))
		add_child(clear)


func _activity_button(activity: String, option: String, text: String, planned: Dictionary) -> Button:
	var b := Button.new()
	var chosen := String(planned.get("activity", "")) == activity and String(planned.get("option", "")) == option
	b.text = ("✓ " if chosen else "") + text
	b.disabled = chosen
	b.pressed.connect(activity_requested.emit.bind(activity, option))
	return b


## The selected commander's army: every squad, whether it fights, and a
## garrison on its hex it can pick up (sw-ip8.7).
func _army_info(me: Dictionary, obs: Dictionary) -> void:
	var r := session.rules
	var army: Array = me.get("army", [])
	var fighting := {}
	for id: int in me.get("battleforce", []):
		fighting[id] = true
	var cap: int = r.cm_army_cap[int(me["tmpl"])]
	var others := army.filter(func(q: Dictionary) -> bool: return not bool(q.get("own", false)))
	add_child(_title("Commander %d: army %d/%d squads" % [int(me["id"]) & 0xffff, others.size(), cap]))
	for q: Dictionary in army:
		add_child(UiTheme.label("  %s%s  %d/%d units%s" % [EventText.squad_name(r.squad_ids[int(q["tmpl"])]), " (own)" if bool(q.get("own", false)) else "",
			int(q["alive"]), int(q["size"]), "  · battleforce" if fighting.has(int(q["id"])) else ""],
			"SmallLabel" if fighting.has(int(q["id"])) else "SmallDimLabel"))
	if int(me["engagement"]) >= 0 or session.clock.phase != PulseClock.Phase.PLANNING:
		return
	for det: Dictionary in obs.get("detachments", []):
		if int(det["player"]) != player or int(det["plot"]) != int(me["plot"]) or int(det["engagement"]) >= 0:
			continue
		var sq: Array = det.get("squads", [])
		if sq.is_empty():
			continue
		var b := Button.new()
		b.text = "Pick up %d squad%s from the %s here" % [sq.size(), "" if sq.size() == 1 else "s", band_word(det)]
		b.disabled = others.size() >= cap
		b.pressed.connect(pick_up_requested.emit.bind(int(det["id"])))
		add_child(b)


## A selected garrison or convoy of the player's (sw-kys.8): its squads,
## where it is going, and Halt. It moves like a commander, but takes no
## hexes and does no activities.
func _detachment_info(obs: Dictionary) -> void:
	var me := {}
	for d: Dictionary in obs.get("detachments", []):
		if int(d["id"]) == detachment:
			me = d
	if me.is_empty():
		return
	var r := session.rules
	var convoy := bool(me["convoy"])
	add_child(_title("%s %d at %s" % [band_word(me).capitalize(), detachment & 0xffff, EventText.hex(int(me["plot"]), r)]))
	for q: Dictionary in me.get("squads", []):
		add_child(_dim_label("  %s  %d/%d units" % [EventText.squad_name(r.squad_ids[int(q["tmpl"])]), int(q.get("alive", 0)), int(q.get("size", 0))]))
	var route: PackedInt64Array = (obs.get("convoy_routes", {}) as Dictionary).get(detachment, PackedInt64Array())
	if int(me.get("dest_commander", -1)) >= 0:
		add_child(_dim_label("Heading to %s, to join its army." % EventText.commander(int(me["dest_commander"]))))
	elif int(me.get("dest_plot", -1)) >= 0:
		add_child(_dim_label("Heading to %s%s." % [EventText.hex(int(me["dest_plot"]), r),
			"" if route.is_empty() else " (%d hex%s to go)" % [route.size(), "" if route.size() == 1 else "es"]]))
	else:
		add_child(_dim_label("Holding this hex."))
	if me.has("sight"):
		add_child(_dim_label("Sees %d hex%s." % [int(me["sight"]["value"]), "" if int(me["sight"]["value"]) == 1 else "es"]))
	add_child(_dim_label("Moves %d points a turn. Right click a hex to send it; it keeps going on later turns. Convoys take no hexes and do no activities." % r.convoy_mp))
	if convoy and int(me["engagement"]) < 0 and session.clock.phase == PulseClock.Phase.PLANNING:
		var halt := Button.new()
		halt.text = "Halt here"
		halt.pressed.connect(rally_requested.emit.bind(detachment, -1, -1, "convoy %d" % (detachment & 0xffff)))
		add_child(halt)


## A selected hex: what the player knows is there, garrisons and convoys
## included.
func _hex_info(obs: Dictionary) -> void:
	var p := plot
	if p < 0:
		return
	var r := session.rules
	add_child(_title("Hex %s" % EventText.hex(p, r)))
	var plot: Dictionary = (obs.get("plots", {}) as Dictionary).get(p, {})
	if plot.is_empty():
		add_child(_dim_label("Unexplored."))
		return
	for f: Dictionary in plot.get("features", []):
		_feature_row(f, p, obs)
	for det: Dictionary in obs.get("detachments", []):
		if int(det["plot"]) != p:
			continue
		var sq: Array = det.get("squads", [])
		var what := band_word(det)
		if int(det["player"]) == player:
			var names := sq.map(func(q: Dictionary) -> String: return EventText.squad_name(r.squad_ids[int(q["tmpl"])]))
			var dest := ""
			if int(det.get("dest_commander", -1)) >= 0:
				dest = " to " + EventText.commander(int(det["dest_commander"]))
			elif int(det.get("dest_plot", -1)) >= 0:
				dest = " to " + EventText.hex(int(det["dest_plot"]), r)
			add_child(_dim_label("  Your %s%s: %s" % [what, dest, ", ".join(names) if not names.is_empty() else "empty"]))
			if int(det["engagement"]) < 0 and session.clock.phase == PulseClock.Phase.PLANNING and not names.is_empty():
				var row := HBoxContainer.new()
				var send := Button.new()
				send.text = "Send this %s to…" % what
				send.tooltip_text = "Then click a hex, or one of your commanders to have it join that army."
				send.pressed.connect(target_armed.emit.bind("rally", int(det["id"]), "the " + what))
				row.add_child(send)
				if bool(det["convoy"]):
					var halt := Button.new()
					halt.text = "Halt"
					halt.pressed.connect(rally_requested.emit.bind(int(det["id"]), -1, -1, "the " + what))
					row.add_child(halt)
				add_child(row)
		else:
			add_child(_dim_label("  %s %s" % [EventText.side(int(det["player"]), player), what]))
	if not plot.get("visible", true):
		add_child(_dim_label("  (last seen; not in sight now)"))


## One feature of the selected hex (sw-63wt.7, U1Q23): a row that selects
## it (hover rings it on the map), with a producing own site's rally point
## buttons on the same row. The selected one lists what it does below
## (HexCard.feature_lines), and "last seen" when out of sight.
func _feature_row(f: Dictionary, p: int, obs: Dictionary) -> void:
	var r := session.rules
	var fid := int(f["id"])
	var t := int(f["tmpl"])
	var name := r.hf_names[t] if t >= 0 and t < r.hf_names.size() else "feature"
	var owner := int(f.get("owner", 0))
	var chosen := fid == feature
	var row := HBoxContainer.new()
	var pick := Button.new()
	pick.flat = not chosen
	pick.toggle_mode = true
	pick.button_pressed = chosen
	pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.text = "%s%s%s" % ["▸ " if chosen else "  ", name, "" if owner <= 0 else " · " + EventText.side(owner, player)]
	pick.tooltip_text = "Select this site." if not chosen else "Selected."
	pick.set_meta(SELECT_ROW, true)
	pick.pressed.connect(feature_selected.emit.bind(fid, p))
	pick.mouse_entered.connect(feature_hovered.emit.bind(fid))
	pick.mouse_exited.connect(feature_hovered.emit.bind(-1))
	row.add_child(pick)
	_rows[fid] = pick
	add_child(row)
	var producing := (obs.get("production", {}) as Dictionary).has(fid)
	if producing and session.clock.phase == PulseClock.Phase.PLANNING:
		_line_buttons(fid, name, obs, row)
	_paint_row(fid)
	if not chosen:
		return
	var info := session.inspect_feature(player, fid)
	var detail := HexCard.feature_lines(info, r, player) if not info.is_empty() else []
	for l: Array in detail.slice(1):
		add_child(_dim_label("    " + String(l[0])))
	for l: Array in HexCard.selection_notes(info, player, int(obs.get("turn", -1))):
		add_child(_dim_label("    " + String(l[0])))
	if producing and session.clock.phase == PulseClock.Phase.PLANNING:
		add_child(_dim_label("    Right click a hex, or one of your commanders, to set its rally point."))


## A producing feature's rally point: where its output is sent (a line
## under the row), and the buttons to set or clear it on its row.
func _line_buttons(fid: int, name: String, obs: Dictionary, row: HBoxContainer) -> void:
	var line: Dictionary = (obs.get("supply_lines", {}) as Dictionary).get(fid, {})
	var where := "stays here as a garrison"
	if int(line.get("commander", -1)) >= 0:
		where = "goes to " + EventText.commander(int(line["commander"]))
	elif int(line.get("plot", -1)) >= 0:
		where = "goes to " + EventText.hex(int(line["plot"]), session.rules)
	var send := Button.new()
	send.text = "Set rally point…"
	send.tooltip_text = "Then click a hex, or one of your commanders to supply that army."
	send.pressed.connect(target_armed.emit.bind("line", fid, "what the %s makes" % name))
	row.add_child(send)
	if not line.is_empty():
		var clear := Button.new()
		clear.text = "Clear"
		clear.pressed.connect(supply_line_requested.emit.bind(fid, -1, -1, name))
		row.add_child(clear)
	add_child(_dim_label("    What it makes " + where + "."))


## Highlights a feature's row from outside (its site hovered on the map;
## -1 clears), without rebuilding the panel.
func set_hover_feature(fid: int) -> void:
	var was := _hover_feature
	_hover_feature = fid
	_paint_row(was)
	_paint_row(fid)


func _paint_row(fid: int) -> void:
	var b: Button = _rows.get(fid)
	if b != null and is_instance_valid(b):
		b.modulate = Color(1.25, 1.2, 0.9) if fid == _hover_feature and fid != feature else Color.WHITE


## Whether a feature row is lit as hovered (tests).
func row_hovered(fid: int) -> bool:
	return _rows.has(fid) and fid == _hover_feature


func _dim_label(text: String) -> Label:
	return UiTheme.label(text, "SmallDimLabel", true)


func _title(text: String) -> GlossaryLabel:
	var l := GlossaryLabel.new()
	l.glossary = glossary
	l.theme_type_variation = &"DimLabel"
	l.set_linked(text)
	return l


## "convoy" for a caravan (moving or halted, U1Q27), else "garrison".
static func band_word(det: Dictionary) -> String:
	if det.has("band"):
		return "convoy" if String(det["band"]) == OverworldRules.BAND_CARAVAN else "garrison"
	return "convoy" if bool(det.get("convoy", false)) else "garrison"
