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

const DIM: Color = Color("8a93a3")

## Defined terms for the hoverable titles.
var glossary: Glossary
var session: OverworldSession
var player: int = 1
var commander: int = -1
var plot: int = -1


## Shows the selected commander (`commander_id`, -1 for none), or else the
## selected hex (`plot_id`, -1 for none), as `for_player` knows them.
func show_selection(of_session: OverworldSession, for_player: int, commander_id: int, plot_id: int) -> void:
	session = of_session
	player = for_player
	commander = commander_id
	plot = plot_id
	for c in get_children():
		remove_child(c)
		c.queue_free()
	var cid := commander
	var obs := session.observe(player)
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
		var what := "%s at %s (%d squad%s)" % ["convoy" if bool(det["convoy"]) else "garrison", EventText.hex(int(det["plot"]), session.rules), n, "" if n == 1 else "s"]
		if int(det.get("dest_commander", -1)) == cid:
			add_child(_dim_label("On its way here: " + what))
			continue
		var b := Button.new()
		b.text = "Call here: " + what
		b.tooltip_text = "It becomes a convoy that walks to where this commander's route ends each turn, and joins the army when they meet."
		b.pressed.connect(rally_requested.emit.bind(int(det["id"]), -1, cid, what))
		add_child(b)


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
		var l := Label.new()
		l.text = "  %s%s  %d/%d units%s" % [EventText.squad_name(r.squad_ids[int(q["tmpl"])]), " (own)" if bool(q.get("own", false)) else "",
			int(q["alive"]), int(q["size"]), "  · battleforce" if fighting.has(int(q["id"])) else ""]
		l.add_theme_color_override("font_color", Color("dde2ea") if fighting.has(int(q["id"])) else DIM)
		l.add_theme_font_size_override("font_size", 13)
		add_child(l)
	if int(me["engagement"]) >= 0 or session.clock.phase != PulseClock.Phase.PLANNING:
		return
	for det: Dictionary in obs.get("detachments", []):
		if int(det["player"]) != player or int(det["plot"]) != int(me["plot"]) or int(det["engagement"]) >= 0:
			continue
		var sq: Array = det.get("squads", [])
		if sq.is_empty():
			continue
		var b := Button.new()
		b.text = "Pick up %d squad%s from the %s here" % [sq.size(), "" if sq.size() == 1 else "s", "convoy" if bool(det["convoy"]) else "garrison"]
		b.disabled = others.size() >= cap
		b.pressed.connect(pick_up_requested.emit.bind(int(det["id"])))
		add_child(b)


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
		var t := int(f["tmpl"])
		var name := r.hf_names[t] if t >= 0 and t < r.hf_names.size() else "feature"
		var owner := int(f.get("owner", 0))
		add_child(_dim_label("  %s%s" % [name, "" if owner <= 0 else " · " + EventText.side(owner, player)]))
		if (obs.get("production", {}) as Dictionary).has(int(f["id"])) and session.clock.phase == PulseClock.Phase.PLANNING:
			_line_buttons(int(f["id"]), name, obs)
	for det: Dictionary in obs.get("detachments", []):
		if int(det["plot"]) != p:
			continue
		var sq: Array = det.get("squads", [])
		var what := "convoy" if bool(det["convoy"]) else "garrison"
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


## A producing feature's rally point: where its output is sent, and the
## buttons to set or clear it.
func _line_buttons(fid: int, name: String, obs: Dictionary) -> void:
	var line: Dictionary = (obs.get("supply_lines", {}) as Dictionary).get(fid, {})
	var where := "stays here as a garrison"
	if int(line.get("commander", -1)) >= 0:
		where = "goes to " + EventText.commander(int(line["commander"]))
	elif int(line.get("plot", -1)) >= 0:
		where = "goes to " + EventText.hex(int(line["plot"]), session.rules)
	add_child(_dim_label("    What it makes " + where + "."))
	var row := HBoxContainer.new()
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
	add_child(row)


func _dim_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", DIM)
	l.add_theme_font_size_override("font_size", 13)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _title(text: String) -> GlossaryLabel:
	var l := GlossaryLabel.new()
	l.glossary = glossary
	l.add_theme_color_override("default_color", DIM)
	l.set_linked(text)
	return l
