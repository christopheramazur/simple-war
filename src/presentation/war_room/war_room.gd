class_name WarRoom
extends Control
## The multi-battle view (GDD 04 §4.8, R2Q19, R3Q20, R4Q15): the overworld
## or a focused battle in the main view, picture-in-picture battle views,
## the battles menu and the player's commanders. Presentation only: what is
## shown lives in ViewContexts; the session is read through observe /
## observe_battle. Runs standalone (F6) on a demo session with two battles.
##
## Controls: Tab / Shift+Tab swap battles (Tab tabs in from the overworld),
## Esc exits a battle, F follows the selected commander, Backspace or a
## right click deselects all, mouse wheel zooms (zooming in on a battle hex
## enters it), left click selects a commander or hex, Space ends the turn.
## PiP views: click to swap into the main view, drag to move.
##
## Planning in the focused battle (sw-ip8.3, GDD 01 Input and UI, 02 §2.2):
## a BattlePlanner per battle keeps the selection, control groups and
## drafted orders; drafts are submitted as they change, and the forecast
## (forecast_battle) draws intent ghosts and coming contacts. Left click
## selects (shift adds, ctrl toggles, double click selects the type), drag
## box-selects, right click moves (alt: into a new line formation) or
## attacks the enemy under the cursor. GUIDE actions (PlanningInput,
## remappable): H hold, A attack-move, B fall back, Shift+W withdraw, R run,
## Q ability menu, 0-9 recall / Ctrl+n assign / Shift+n add control groups,
## F1-F4 recall / Ctrl+F1-F4 set camera bookmarks.
## Reaction window: reactable squads are marked; clicking one opens the
## reaction radial, and the side panel lists every opportunity across
## battles as a scrollable reaction queue.

## Emitted for the Space key / End turn button; the owner advances the
## session. The demo handles it itself.
signal end_turn_requested

const SIDE_W: float = 250.0
const PIP_SIZE: Vector2 = Vector2(240, 160)
const PANEL: Color = Color("1d2128")
const DIM: Color = Color("8a93a3")

@export var player: int = 1
## Applied once the demo is built (the mock uses it): "", "battle" (focus
## the first battle), "pip" (focus the first, pin the second) or "plan"
## (focus the first, select its squads and draft a move into a new line).
@export var demo_view: String = ""

var session: OverworldSession
var contexts: ViewContexts
## Defined terms for the panel's hoverable titles (sw-ip8.4).
var glossary: Glossary

var _main: ContextView
var _pip_layer: Control
var _menu: VBoxContainer
var _cmds: VBoxContainer
var _hud: Label
var _dirty: bool = false
## Engagement ID -> BattlePlanner, and -> its latest forecast.
var planners: Dictionary = {}
var _forecasts: Dictionary = {}
## Reactions queued this window: "eid,squad,trigger" -> reaction name.
var _reacted: Dictionary = {}
var _turn_seen: int = -1
var _attack_armed: bool = false
var _input: PlanningInput
var _radial: ReactionRadial
var _radial_opp: Dictionary = {}
var _orders_box: VBoxContainer
var _reactions_box: VBoxContainer


func _ready() -> void:
	if session == null:
		session = demo_session()
		end_turn_requested.connect(_demo_end_turn)
	glossary = Glossary.from_templates(session.templates)
	_build_ui()
	_turn_seen = session.turns_resolved()
	contexts = ViewContexts.new(player)
	contexts.changed.connect(_queue_refresh)
	contexts.sync(session.observe(player))
	match demo_view:
		"battle":
			contexts.tab_in()
		"pip":
			var all := contexts.battles()
			if all.size() >= 2:
				contexts.focus_battle(all[0])
				contexts.pin(all[1])
				contexts.select_commander(contexts.menu()[0]["commanders"][0])
		"plan":
			if contexts.tab_in():
				var pl := planner(contexts.focus)
				pl.select(pl.own_squads())
				pl.move_to(pl.selection_centre() + Vector2(35, 8), true)
	_refresh()


func _exit_tree() -> void:
	if contexts != null and contexts.changed.is_connected(_queue_refresh):
		contexts.changed.disconnect(_queue_refresh)


## A demo: test_vale with player 1 fighting the bandit camp and player 2's
## commander at once.
static func demo_session() -> OverworldSession:
	var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	var s := OverworldSession.create(l.templates, l.data_hash, "test_vale", 7)
	var w := s.rules.width
	var a := Commanders.spawn(s.state, 1, "field_commander", Hex.plot(12, 4, w))
	s.set_route(1, a, PackedInt64Array([Hex.plot(11, 3, w)]))
	var b := Commanders.spawn(s.state, 1, "field_commander", Hex.plot(5, 5, w))
	Commanders.spawn(s.state, 2, "field_commander", Hex.plot(6, 5, w))
	s.set_route(1, b, PackedInt64Array([Hex.plot(6, 5, w)]))
	for i in 2:  # planning -> intermission -> planning: the battles begin
		for p in s.players():
			s.ready(p)
	return s


# --- building ----------------------------------------------------------------

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 0)
	add_child(row)
	var stage := Control.new()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(stage)
	_main = ContextView.new()
	_main.set_anchors_preset(Control.PRESET_FULL_RECT)
	_main.hex_clicked.connect(_on_hex_clicked)
	_main.battle_pressed.connect(_on_battle_pressed)
	_main.battle_box.connect(_on_battle_box)
	_main.zoomed.connect(func(f: float) -> void: contexts.zoom_by(f))
	stage.add_child(_main)
	_pip_layer = Control.new()
	_pip_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pip_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(_pip_layer)
	_radial = ReactionRadial.new()
	_radial.hide()
	_radial.chosen.connect(_on_reaction_chosen)
	stage.add_child(_radial)
	_input = PlanningInput.new()
	_input.command.connect(_on_command)
	add_child(_input)
	_hud = Label.new()
	_hud.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hud.offset_top = -26
	_hud.add_theme_color_override("font_color", DIM)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(_hud)
	var side := PanelContainer.new()
	side.custom_minimum_size = Vector2(SIDE_W, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 10
	side.add_theme_stylebox_override("panel", sb)
	row.add_child(side)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	side.add_child(col)
	col.add_child(_title("Battles"))
	_menu = VBoxContainer.new()
	col.add_child(_menu)
	col.add_child(_title("Commanders"))
	_cmds = VBoxContainer.new()
	col.add_child(_cmds)
	_orders_box = VBoxContainer.new()
	col.add_child(_orders_box)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 180)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_reactions_box = VBoxContainer.new()
	_reactions_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_reactions_box)
	col.add_child(scroll)
	var end := Button.new()
	end.text = "End turn (Space)"
	end.pressed.connect(func() -> void: end_turn_requested.emit())
	col.add_child(end)


func _clear(parent: Node) -> void:
	for c in parent.get_children():
		parent.remove_child(c)
		c.queue_free()


## A panel heading; defined terms in it are hoverable.
func _title(text: String) -> GlossaryLabel:
	var l := GlossaryLabel.new()
	l.glossary = glossary
	l.add_theme_color_override("default_color", DIM)
	l.set_linked(text)
	return l


# --- projection ----------------------------------------------------------------

## Redraws once per frame, after the input that changed the contexts (a
## button may not be freed while it emits).
func _queue_refresh() -> void:
	if not _dirty:
		_dirty = true
		_refresh.call_deferred()


func _refresh() -> void:
	_dirty = false
	if not is_inside_tree():
		return
	if session.turns_resolved() != _turn_seen:
		_turn_seen = session.turns_resolved()
		for eid: int in planners:
			(planners[eid] as BattlePlanner).drafts = {}
		_forecasts = {}
		_reacted = {}
	for eid: int in planners.keys():
		if not session.battles.has(eid):
			planners.erase(eid)
			_forecasts.erase(eid)
	if session.clock.phase != PulseClock.Phase.REACTION:
		_radial.hide()
	if contexts.focus == ViewContexts.OVERWORLD:
		_main.show_overworld(session.observe(player), session.rules.feature_ids, contexts)
	else:
		var obs := session.observe_battle(player, contexts.focus)
		var pl := planner(contexts.focus)
		pl.sync(obs)
		_main.title = battle_name(contexts.focus)
		var fc: Dictionary = _forecasts.get(contexts.focus, {})
		_main.show_battle(obs, {"selected": pl.selection, "drafts": pl.drafts, "ghosts": fc.get("ghosts", {}),
			"contacts": fc.get("contacts", []), "reactable": _reactable(contexts.focus)})
	_refresh_pips()
	_refresh_menu()
	_refresh_commanders()
	_refresh_orders()
	_refresh_reactions()
	var where := "Overworld" if contexts.focus == ViewContexts.OVERWORLD else battle_name(contexts.focus)
	var follow := "" if contexts.followed < 0 else "  ·  following %d" % contexts.followed
	var armed := "  ·  ATTACK-MOVE: right click a point" if _attack_armed else ""
	_hud.text = "  %s%s  ·  %s  ·  zoom %.2f  ·  turn %d%s   [Tab swap · Esc exit · F follow · wheel zoom · Space end turn]" % [
		where, follow, session.phase_name().capitalize(), contexts.zoom, session.turns_resolved() + 1, armed]


func _refresh_pips() -> void:
	_clear(_pip_layer)
	for i in contexts.pips.size():
		var eid := contexts.pips[i]
		var pip := _PipPanel.new()
		pip.engagement = eid
		pip.size = PIP_SIZE
		var home := Vector2(12, 12 + i * (PIP_SIZE.y + 10))
		pip.position = home + contexts.pip_offsets.get(eid, Vector2.ZERO)
		pip.home = home
		pip.chosen.connect(func(e: int) -> void: contexts.focus_battle(e))
		pip.moved.connect(func(e: int, off: Vector2) -> void: contexts.move_pip(e, off))
		_pip_layer.add_child(pip)
		pip.view.title = battle_name(eid)
		pip.view.show_battle(session.observe_battle(player, eid))


func _refresh_menu() -> void:
	_clear(_menu)
	for m: Dictionary in contexts.menu():
		var line := HBoxContainer.new()
		var go := Button.new()
		go.text = ("▶ " if m["focused"] else "") + "%s (%d commander%s)" % [battle_name(m["engagement"]), m["commanders"].size(),
			"" if m["commanders"].size() == 1 else "s"]
		go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		go.pressed.connect(contexts.focus_battle.bind(m["engagement"]))
		line.add_child(go)
		var pin := Button.new()
		pin.text = "Unpin" if m["pinned"] else "PiP"
		pin.disabled = m["focused"]
		pin.pressed.connect(contexts.toggle_pin.bind(m["engagement"]))
		line.add_child(pin)
		_menu.add_child(line)
	if contexts.focus != ViewContexts.OVERWORLD:
		var back := Button.new()
		back.text = "Exit to overworld (Esc)"
		back.pressed.connect(contexts.exit)
		_menu.add_child(back)


## A short, stable name for a battle while it lasts (its engagement slot).
static func battle_name(eid: int) -> String:
	return "Battle %d" % ((eid & 0xffffffff) + 1)


func _refresh_commanders() -> void:
	_clear(_cmds)
	for cmd: Dictionary in session.observe(player).get("commanders", []):
		if cmd["player"] != player:
			continue
		var b := Button.new()
		var tags := []
		if cmd["id"] == contexts.selected:
			tags.append("selected")
		if cmd["id"] == contexts.followed:
			tags.append("followed")
		if cmd["engagement"] >= 0:
			tags.append("in battle")
		b.text = "Commander %d%s" % [cmd["id"] & 0xffff, "" if tags.is_empty() else " (%s)" % ", ".join(tags)]
		b.pressed.connect(contexts.select_commander.bind(cmd["id"]))
		_cmds.add_child(b)


# --- input ---------------------------------------------------------------------

func _on_hex_clicked(p: int, button: int) -> void:
	if button == MOUSE_BUTTON_RIGHT:
		contexts.deselect_all()
		return
	if p < 0:
		return
	for cmd: Dictionary in session.observe(player).get("commanders", []):
		if cmd["plot"] == p and cmd["player"] == player:
			contexts.select_commander(cmd["id"])
			return
	contexts.select_hex(p)


# --- planning ------------------------------------------------------------------

## The planner for one of the player's battles (made on first use).
func planner(eid: int) -> BattlePlanner:
	if not planners.has(eid):
		var pl := BattlePlanner.new(player)
		pl.sync(session.observe_battle(player, eid))
		pl.changed.connect(_on_draft.bind(eid))
		planners[eid] = pl
	return planners[eid]


## Drafts changed: submit them and refresh the forecast (Planning only).
func _on_draft(eid: int) -> void:
	if session.clock.phase == PulseClock.Phase.PLANNING and session.battles.has(eid):
		var orders: Array = planner(eid).orders()
		session.submit_battle_orders(player, eid, orders)
		_forecasts[eid] = session.forecast_battle(player, eid, orders)
	_queue_refresh()


func _focused_planner() -> BattlePlanner:
	if contexts.focus == ViewContexts.OVERWORLD:
		return null
	return planner(contexts.focus)


func _on_battle_pressed(at: Vector2, button: int, shift: bool, ctrl: bool, alt: bool, double: bool) -> void:
	var pl := _focused_planner()
	if pl == null:
		return
	var hit := _main.squad_at(at)
	if session.clock.phase == PulseClock.Phase.REACTION:
		if button == MOUSE_BUTTON_LEFT and hit >= 0:
			_open_radial(contexts.focus, hit)
		return
	if session.clock.phase != PulseClock.Phase.PLANNING:
		return
	if button == MOUSE_BUTTON_LEFT:
		if hit >= 0 and pl.own_squads().has(hit):
			if double:
				pl.select_type(hit, Rect2(Vector2.ZERO, Vector2(1e9, 1e9)), shift)
			else:
				pl.select([hit], shift, ctrl)
		elif not shift and not ctrl:
			pl.deselect()
		return
	if button != MOUSE_BUTTON_RIGHT:
		return
	if pl.selection.is_empty():
		contexts.deselect_all()
		return
	if hit >= 0 and not pl.own_squads().has(hit):
		pl.attack(hit)
	else:
		pl.move_to(at, alt, _attack_armed)
	_attack_armed = false


func _on_battle_box(rect: Rect2, add: bool) -> void:
	var pl := _focused_planner()
	if pl != null and session.clock.phase == PulseClock.Phase.PLANNING:
		pl.select_box(rect, add)


## GUIDE commands (PlanningInput).
func _on_command(name: StringName, arg: int) -> void:
	match name:
		&"recall_bookmark":
			contexts.recall_bookmark(arg)
			return
		&"set_bookmark":
			contexts.set_bookmark(arg)
			return
	var pl := _focused_planner()
	if pl == null or session.clock.phase != PulseClock.Phase.PLANNING:
		return
	match name:
		&"hold", &"fall_back", &"withdraw":
			pl.order(String(name))
		&"attack_move":
			_attack_armed = not pl.selection.is_empty()
			_queue_refresh()
		&"run":
			pl.toggle_run()
		&"abilities":
			_queue_refresh()
		&"recall_group":
			pl.recall_group(arg)
		&"assign_group":
			pl.assign_group(arg)
		&"add_group":
			pl.assign_group(arg, true)


func _refresh_orders() -> void:
	_clear(_orders_box)
	var pl := _focused_planner()
	if pl == null or session.clock.phase != PulseClock.Phase.PLANNING:
		return
	_orders_box.add_child(_title("Orders (%d selected)" % pl.selection.size()))
	if pl.selection.is_empty():
		return
	var row := HFlowContainer.new()
	for c: Array in [["Hold (H)", &"hold"], ["Attack-move (A)", &"attack_move"], ["Fall back (B)", &"fall_back"],
			["Withdraw (⇧W)", &"withdraw"], ["Run (R)", &"run"]]:
		var b := Button.new()
		b.text = c[0]
		b.pressed.connect(_on_command.bind(c[1], 0))
		row.add_child(b)
	_orders_box.add_child(row)
	var menu := pl.ability_menu()
	if menu.is_empty():
		return
	_orders_box.add_child(_title("Abilities (Q)"))
	var abl := HFlowContainer.new()
	for m: Dictionary in menu:
		var b := Button.new()
		var state := ""
		if m["toggle"]:
			state = " · on" if m["on"] else " · off"
		b.text = "%s ×%d%s" % [m["name"], (m["squads"] as Array).size(), state]
		b.pressed.connect(pl.use_ability.bind(m["id"]))
		abl.add_child(b)
	_orders_box.add_child(abl)


# --- reactions -------------------------------------------------------------------

## Own squads with an opportunity in battle eid -> the reaction queued for
## them ("" = none yet). Empty outside the reaction window.
func _reactable(eid: int) -> Dictionary:
	var out := {}
	for o: Dictionary in session.reaction_opportunities(player):
		if o["engagement"] == eid:
			out[o["squad"]] = _reacted.get(_key(o), out.get(o["squad"], ""))
	return out


static func _key(o: Dictionary) -> String:
	return "%d,%d,%d" % [o["engagement"], o["squad"], o["trigger"]]


func _open_radial(eid: int, squad: int) -> void:
	for o: Dictionary in session.reaction_opportunities(player):
		if o["engagement"] == eid and o["squad"] == squad:
			_radial_opp = o
			var sq := _squad_obs(eid, squad)
			var at := _main.to_view(Vector2(sq.get("x", 0) / ContextView.ONE, sq.get("y", 0) / ContextView.ONE))
			_radial.open(at, o["reactions"], _reacted.get(_key(o), ""))
			return


func _squad_obs(eid: int, squad: int) -> Dictionary:
	for sq: Dictionary in session.observe_battle(player, eid).get("squads", []):
		if sq["id"] == squad:
			return sq
	return {}


func _on_reaction_chosen(r: String) -> void:
	_react(_radial_opp, r)


func _react(o: Dictionary, r: String) -> void:
	if o.is_empty():
		return
	if session.submit_reaction(player, o["engagement"], o["squad"], r, o["trigger"]).is_empty():
		_reacted[_key(o)] = r
	_queue_refresh()


## The reaction queue: every opportunity across battles, scrollable.
func _refresh_reactions() -> void:
	_clear(_reactions_box)
	var opps := session.reaction_opportunities(player)
	if opps.is_empty():
		return
	_reactions_box.add_child(_title("Reactions (%d)" % opps.size()))
	for o: Dictionary in opps:
		var line := VBoxContainer.new()
		var head := Button.new()
		var queued: String = _reacted.get(_key(o), "")
		head.text = "%s · squad %d ↔ %d%s" % [battle_name(o["engagement"]), o["squad"] & 0xffff, o["trigger"] & 0xffff,
			"" if queued.is_empty() else "  ✓ " + queued.capitalize()]
		head.flat = true
		head.alignment = HORIZONTAL_ALIGNMENT_LEFT
		head.pressed.connect(_jump_to_reaction.bind(o))
		line.add_child(head)
		var row := HFlowContainer.new()
		for r: String in o["reactions"]:
			var b := Button.new()
			b.text = "%s %s" % [ReactionRadial.glyph(r), r.capitalize()]
			b.toggle_mode = true
			b.button_pressed = r == queued
			b.pressed.connect(_react.bind(o, r))
			row.add_child(b)
		line.add_child(row)
		_reactions_box.add_child(line)


func _jump_to_reaction(o: Dictionary) -> void:
	contexts.focus_battle(o["engagement"])
	_open_radial.call_deferred(o["engagement"], o["squad"])


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_TAB:
			contexts.cycle(-1 if k.shift_pressed else 1)
		KEY_ESCAPE:
			contexts.exit()
		KEY_F:
			contexts.follow()
		KEY_BACKSPACE:
			contexts.deselect_all()
		KEY_SPACE:
			end_turn_requested.emit()
		_:
			return
	get_viewport().set_input_as_handled()


## Readies every player until planning comes round again, stopping at a
## reaction window that offers this player something.
func _demo_end_turn() -> void:
	for i in 4:
		for p in session.players():
			session.ready(p)
		var ph := session.clock.phase
		if ph == PulseClock.Phase.PLANNING:
			break
		if ph == PulseClock.Phase.REACTION and not session.reaction_opportunities(player).is_empty():
			break
	contexts.sync(session.observe(player))
	_queue_refresh()


## A movable picture-in-picture battle view: click to swap it in, drag to
## move it.
class _PipPanel extends Panel:
	signal chosen(engagement: int)
	signal moved(engagement: int, offset: Vector2)

	var engagement: int = -1
	var home: Vector2 = Vector2.ZERO
	var view: ContextView
	var _drag_from: Vector2 = Vector2.ZERO
	var _dragged: bool = false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("12151a")
		sb.border_color = Color("e6b450")
		sb.set_border_width_all(2)
		add_theme_stylebox_override("panel", sb)
		view = ContextView.new()
		view.compact = true
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		view.set_anchors_preset(Control.PRESET_FULL_RECT)
		view.offset_left = 2
		view.offset_top = 2
		view.offset_right = -2
		view.offset_bottom = -2
		add_child(view)

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag_from = mb.global_position
				_dragged = false
			elif _dragged:
				moved.emit(engagement, position - home)
			else:
				chosen.emit(engagement)
			accept_event()
			return
		var mm := event as InputEventMouseMotion
		if mm != null and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			if mm.global_position.distance_to(_drag_from) > 4.0:
				_dragged = true
			position += mm.relative
			accept_event()
