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
## A map to play (with no session given): the war room makes its own
## session and plays `player` against the map's guards and triggers.
@export var map_id: String = ""
@export var map_seed: int = 1
## A skirmish (with `map_id`): every other player is played by this
## controller_profile (data, kind controller_profile) through ProfileController,
## the same AI the factory evolves.
@export var ai_profile: String = ""
## Shown by the "Main menu" button; empty hides it.
@export_file("*.tscn") var menu_scene: String = "res://src/presentation/main_menu/main_menu.tscn"

var session: OverworldSession
## AI opponents: player -> controller (HeadlessOverworld.plan_for/react_for).
var ai: Dictionary = {}
## "turn:phase" the AI last acted in, so it acts once per phase.
var _ai_step: String = ""
## Write a match log (MatchLog) for sessions this room makes from a map.
@export var record_match: bool = true
var match_log: MatchLog
## Battles whose drafts were drawn outside Planning: sent when it returns.
var _pending: Dictionary = {}
var _phase_banner: PanelContainer
var _phase_text: Label
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
var _commander_box: VBoxContainer
var _log_box: VBoxContainer
var _banner: PanelContainer
var _banner_text: Label
## Messages from triggers, newest last: [translated text].
var messages: PackedStringArray = PackedStringArray()
var _log_turn: int = -1


func _ready() -> void:
	if session == null:
		session = demo_session() if map_id.is_empty() else play_session(map_id, map_seed)
		end_turn_requested.connect(_end_turn)
	if ai.is_empty() and not ai_profile.is_empty():
		ai = opponents(session, player, ai_profile, map_seed)
	if record_match and not map_id.is_empty() and match_log == null:
		match_log = MatchLog.start(session, {"human": player, "opponent": ai_profile if not ai.is_empty() else "story"})
		if match_log != null:
			messages.append("Match log: " + match_log.os_path())
	glossary =Glossary.from_templates(session.templates)
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


## A session on a map from the core package, at turn 1.
static func play_session(map: String, seed_value: int) -> OverworldSession:
	var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	return OverworldSession.create(l.templates, l.data_hash, map, seed_value)


## Every player but `human` played by a controller profile (unknown
## profiles fall back to the default utility profile).
static func opponents(s: OverworldSession, human: int, profile: String, seed_value: int) -> Dictionary:
	var values: Dictionary = {}
	if s.templates.has(profile) and s.templates.kind_of(profile) == "controller_profile":
		values = s.templates.values_of(profile)
	var out := {}
	for p in s.players():
		if p != human:
			out[p] = ProfileController.new(p, values, seed_value)
	return out


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
	_commander_box = VBoxContainer.new()
	col.add_child(_commander_box)
	_orders_box = VBoxContainer.new()
	col.add_child(_orders_box)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 180)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_reactions_box = VBoxContainer.new()
	_reactions_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_box = VBoxContainer.new()
	_log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_child(_reactions_box)
	stack.add_child(_log_box)
	scroll.add_child(stack)
	col.add_child(scroll)
	_banner = PanelContainer.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.offset_top = 16
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_text = Label.new()
	_banner_text.add_theme_font_size_override("font_size", 20)
	_banner.add_child(_banner_text)
	_banner.hide()
	stage.add_child(_banner)
	_phase_banner = PanelContainer.new()
	_phase_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_phase_banner.offset_top = 56
	_phase_banner.offset_left = 60
	_phase_banner.offset_right = -60
	_phase_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.1, 0.11, 0.14, 0.92)
	psb.border_color = Color("e6b450")
	psb.set_border_width_all(1)
	psb.set_content_margin_all(8)
	_phase_banner.add_theme_stylebox_override("panel", psb)
	_phase_text = Label.new()
	_phase_text.add_theme_color_override("font_color", Color("e6b450"))
	_phase_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_phase_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_banner.add_child(_phase_text)
	_phase_banner.hide()
	stage.add_child(_phase_banner)
	var end := Button.new()
	end.text = "End turn (Space)"
	end.pressed.connect(func() -> void: end_turn_requested.emit())
	col.add_child(end)
	if not menu_scene.is_empty() and ResourceLoader.exists(menu_scene):
		var back := Button.new()
		back.text = "Main menu"
		back.pressed.connect(func() -> void: get_tree().change_scene_to_file.call_deferred(menu_scene))
		col.add_child(back)


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
		_new_turn()
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
			"contacts": fc.get("contacts", []), "reactable": _reactable(contexts.focus),
			"terrain": _battle_rules(contexts.focus), "pending": _pending.has(contexts.focus)})
	_refresh_pips()
	_refresh_menu()
	_refresh_commanders()
	_refresh_orders()
	_refresh_reactions()
	_refresh_commander()
	_refresh_log()
	_refresh_phase_banner()
	var where := "Overworld" if contexts.focus == ViewContexts.OVERWORLD else battle_name(contexts.focus)
	var follow := "" if contexts.followed < 0 else "  ·  following %d" % contexts.followed
	var armed := "  ·  ATTACK-MOVE: right click a point" if _attack_armed else ""
	if not _hud_note.is_empty():
		armed += "  ·  " + _hud_note
	_hud.text = "  %s%s  ·  %s  ·  zoom %.2f  ·  turn %d%s   [Tab swap · Esc exit · F follow · wheel zoom · Space end turn]" % [
		where, follow, session.phase_name().capitalize(), contexts.zoom, session.turns_resolved() + 1, armed]


## A battle's public rules (its battlefield and terrain), or null.
func _battle_rules(eid: int) -> BattleRules:
	var b: OverworldBattle = session.battles.get(eid)
	return b.state.rules if b != null else null


## The phase banner: during a reaction window, what the player can and
## can't do (sw-ip8.7).
func _refresh_phase_banner() -> void:
	var ph := session.clock.phase
	_phase_banner.visible = ph == PulseClock.Phase.REACTION and session.state.outcome.is_empty()
	if _phase_banner.visible:
		_phase_text.text = "Reaction window: moves are locked. React to the marked contacts (Halt · Fall back · Retarget) or press Space to play the turn. Moves you draw now are queued and sent in the next Planning phase."


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
		pip.view.show_battle(session.observe_battle(player, eid), {"terrain": _battle_rules(eid)})


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
		if _own_selected() >= 0 and p >= 0:
			route_to(p)
		else:
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


## Drafts changed: submit them and refresh the forecast. Outside Planning
## the game takes no orders: the drafts are kept, marked pending, and sent
## when Planning returns (sw-ip8.7).
func _on_draft(eid: int) -> void:
	if not session.battles.has(eid):
		return
	var orders: Array = planner(eid).orders()
	if session.clock.phase == PulseClock.Phase.PLANNING:
		_pending.erase(eid)
		var errs := session.submit_battle_orders(player, eid, orders)
		_forecasts[eid] = session.forecast_battle(player, eid, orders)
		_note("%s orders: %s%s" % [battle_name(eid), _orders_text(orders), "" if errs.is_empty() else " - refused: " + "; ".join(errs)])
	else:
		_pending[eid] = true
		_hud_note = "moves are locked until Planning: your drawn orders are queued"
		_note("%s orders drawn in the %s phase (queued for Planning): %s" % [battle_name(eid), session.phase_name(), _orders_text(orders)])
	_queue_refresh()


## A new turn: forecasts and reactions start over; drafts too, except
## those queued while orders were locked.
func _new_turn() -> void:
	_turn_seen = session.turns_resolved()
	for eid: int in planners:
		if not _pending.has(eid):
			(planners[eid] as BattlePlanner).drafts = {}
	_forecasts = {}
	_reacted = {}
	if match_log != null:
		match_log.turn_resolved()


## Sends drafts queued outside Planning, now that Planning is back.
func _flush_pending() -> void:
	if session.clock.phase != PulseClock.Phase.PLANNING:
		return
	for eid: int in _pending.keys():
		if session.battles.has(eid):
			_note("sending the queued orders for " + battle_name(eid))
			_on_draft(eid)
		else:
			_pending.erase(eid)


func _orders_text(orders: Array) -> String:
	if orders.is_empty():
		return "none"
	var parts := PackedStringArray()
	for o: Dictionary in orders:
		var t := String(o.get("type", "?"))
		if o.has("x"):
			t += " to (%.0f, %.0f)" % [float(o["x"]) / ContextView.ONE, float(o["y"]) / ContextView.ONE]
		if o.has("target"):
			t += " squad %d" % (int(o["target"]) & 0xffff)
		parts.append("squad %d %s" % [int(o["squad"]) & 0xffff, t])
	return ", ".join(parts)


## A UI action for the match log.
func _note(text: String) -> void:
	if match_log != null:
		match_log.note(text)


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
	var err := session.submit_reaction(player, o["engagement"], o["squad"], r, o["trigger"])
	if err.is_empty():
		_reacted[_key(o)] = r
	_note("reaction %s for squad %d in %s%s" % [r, int(o["squad"]) & 0xffff, battle_name(o["engagement"]),
		"" if err.is_empty() else " - refused: %s" % err])
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


# --- overworld orders ----------------------------------------------------------

## The selected commander if it is the player's own, else -1.
func _own_selected() -> int:
	var cid := contexts.selected
	if cid < 0 or not session.state.commanders.is_alive(cid):
		return -1
	return cid if session.state.commanders.get_value(cid, &"player") == player else -1


## Routes the selected commander toward a hex (as far as it gets this
## turn, by the cheapest way the player knows). "" or why not.
func route_to(p: int) -> String:
	var cid := _own_selected()
	if cid < 0:
		return "no commander selected"
	var path := session.path(player, cid, p)
	var here := p == session.state.commanders.get_value(cid, &"plot")
	var err := ("already there" if here else "no way there") if path.is_empty() else session.set_route(player, cid, path)
	_hud_note = err
	var reach := "" if path.is_empty() or path[path.size() - 1] == p else " (gets to %s this turn)" % EventText.hex(path[path.size() - 1], session.rules)
	_note("route %s to %s%s" % [EventText.commander(cid), EventText.hex(p, session.rules), (" - refused: " + err) if not err.is_empty() else reach])
	_queue_refresh()
	return err


var _hud_note: String = ""


## Battleforce for the selected commander: preset "" (strongest first),
## "none" (no battleforce: disperses Angels) or a named preset.
func set_battleforce(preset: String, lead: bool) -> String:
	var cid := _own_selected()
	if cid < 0:
		return "no commander selected"
	var err := session.set_battleforce(player, cid, preset, PackedInt64Array(), lead)
	_hud_note = err
	_note("battleforce of %s: %s, own squad %s%s" % [EventText.commander(cid), "strongest first" if preset.is_empty() else preset,
		"fights" if lead else "stays out", "" if err.is_empty() else " - refused: " + err])
	_queue_refresh()
	return err


func _refresh_commander() -> void:
	_clear(_commander_box)
	var cid := _own_selected()
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
	_commander_box.add_child(_title("Commander %d: battleforce" % (cid & 0xffff)))
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
		set_battleforce(preset, false if preset == OverworldBattleforce.NONE else lead.button_pressed))
	lead.toggled.connect(func(on: bool) -> void: set_battleforce(String(plan.get("preset", "")), on))
	_commander_box.add_child(pick)
	_commander_box.add_child(lead)
	var production: Dictionary = obs.get("production", {})
	if production.is_empty():
		return
	_commander_box.add_child(_title("Supply lines"))
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
		b.pressed.connect(func() -> void:
			_hud_note = session.set_supply_line(player, fid, -1, cid)
			_note("supply line: %s sends to %s%s" % [name, EventText.commander(cid), "" if _hud_note.is_empty() else " - refused: " + _hud_note])
			_queue_refresh())
		_commander_box.add_child(b)


## The event feed (sw-ip8.7): what this player saw happen each turn
## (EventText), trigger messages, and the mission's outcome.
func _refresh_log() -> void:
	if session.turns_resolved() != _log_turn:
		_log_turn = session.turns_resolved()
		var obs := session.observe(player)
		for e: Dictionary in obs.get("events", []):
			var d: Dictionary = e["data"] if e.has("data") else e
			if e["type"] in [&"trigger_message", &"mission_ended"]:
				messages.append(_say(String(d.get("key", "")), String(d.get("text", ""))))
			elif EventText.in_feed(e["type"]):
				_name_feature(d, obs)
				var line := EventText.describe(e, session.rules, player)
				if not line.is_empty():
					messages.append("T%d · %s" % [_log_turn, line])
	_clear(_log_box)
	if not messages.is_empty():
		_log_box.add_child(_title("Events"))
		for i in range(messages.size() - 1, maxi(messages.size() - 14, 0) - 1, -1):
			var l := _title(messages[i])
			l.add_theme_color_override("default_color", Color("dde2ea"))
			_log_box.add_child(l)
	var outcome: Dictionary = session.observe(player).get("outcome", {})
	_banner.visible = not outcome.is_empty()
	if _banner.visible:
		var won: bool = outcome["outcome"] == "won"
		if outcome.has("winner"):  # a built-in win condition names its winner
			won = int(outcome["winner"]) == player
		var head := "✔ Mission won — " if won else ("✖ Mission lost — " if outcome["outcome"] != "drew" else "Draw — ")
		if not ai.is_empty():
			head = "✔ Victory — " if won else ("✖ Defeat — " if outcome["outcome"] != "drew" else "Draw — ")
		_banner_text.text = head + _say(String(outcome["key"]), String(outcome["text"]))
		_banner_text.add_theme_color_override("font_color", Color("74d18a") if won else Color("e8735f"))


## Adds the template of a feature the event names, if the player knows it.
func _name_feature(d: Dictionary, obs: Dictionary) -> void:
	if not d.has("feature") or not d.has("plot"):
		return
	var plot: Dictionary = (obs.get("plots", {}) as Dictionary).get(int(d["plot"]), {})
	for f: Dictionary in plot.get("features", []):
		if int(f["id"]) == int(d["feature"]):
			d["feature_tmpl"] = int(f["tmpl"])


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
	_commander_box.add_child(_title("Commander %d: army %d/%d squads" % [int(me["id"]) & 0xffff, others.size(), cap]))
	for q: Dictionary in army:
		var l := Label.new()
		l.text = "  %s%s  %d/%d units%s" % [EventText.squad_name(r.squad_ids[int(q["tmpl"])]), " (own)" if bool(q.get("own", false)) else "",
			int(q["alive"]), int(q["size"]), "  · battleforce" if fighting.has(int(q["id"])) else ""]
		l.add_theme_color_override("font_color", Color("dde2ea") if fighting.has(int(q["id"])) else DIM)
		l.add_theme_font_size_override("font_size", 13)
		_commander_box.add_child(l)
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
		b.pressed.connect(pick_up.bind(int(det["id"])))
		_commander_box.add_child(b)


## Moves a detachment's squads on the selected commander's hex into its
## army, until the army is full. "" or the first refusal.
func pick_up(detachment_id: int) -> String:
	var cid := _own_selected()
	if cid < 0:
		return "no commander selected"
	var err := ""
	var n := 0
	for det: Dictionary in session.observe(player).get("detachments", []):
		if int(det["id"]) == detachment_id:
			for q: Dictionary in det.get("squads", []):
				err = session.transfer_squad(player, int(q["id"]), cid)
				if not err.is_empty():
					break
				n += 1
	_hud_note = err
	_note("pick up: %s took %d squad%s%s" % [EventText.commander(cid), n, "" if n == 1 else "s", "" if err.is_empty() else " - stopped: " + err])
	contexts.sync(session.observe(player))
	_queue_refresh()
	return err


## A selected hex: what the player knows is there, garrisons and convoys
## included.
func _hex_info(obs: Dictionary) -> void:
	var p := contexts.selected_plot
	if p < 0:
		return
	var r := session.rules
	_commander_box.add_child(_title("Hex %s" % EventText.hex(p, r)))
	var plot: Dictionary = (obs.get("plots", {}) as Dictionary).get(p, {})
	if plot.is_empty():
		_commander_box.add_child(_dim_label("Unexplored."))
		return
	for f: Dictionary in plot.get("features", []):
		var t := int(f["tmpl"])
		var name := r.hf_names[t] if t >= 0 and t < r.hf_names.size() else "feature"
		var owner := int(f.get("owner", 0))
		_commander_box.add_child(_dim_label("  %s%s" % [name, "" if owner <= 0 else " · " + EventText.side(owner, player)]))
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
			_commander_box.add_child(_dim_label("  Your %s%s: %s" % [what, dest, ", ".join(names) if not names.is_empty() else "empty"]))
		else:
			_commander_box.add_child(_dim_label("  %s %s" % [EventText.side(int(det["player"]), player), what]))
	if not plot.get("visible", true):
		_commander_box.add_child(_dim_label("  (last seen; not in sight now)"))


func _dim_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", DIM)
	l.add_theme_font_size_override("font_size", 13)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## A message's translation, its text as the fallback.
static func _say(key: String, fallback: String) -> String:
	var s := String(TranslationServer.translate(key)) if not key.is_empty() else key
	return fallback if s.is_empty() or s == key else s


## Readies every player until planning comes round again, stopping at a
## reaction window that offers this player something. The drafts were
## consumed: the next planning starts clean.
func _end_turn() -> void:
	_hud_note = ""
	_note("end turn (%s)" % session.phase_name())
	for i in 4:
		_ai_act()
		for p in session.players():
			session.ready(p)
		var ph := session.clock.phase
		if ph == PulseClock.Phase.PLANNING:
			break
		if ph == PulseClock.Phase.REACTION and not session.reaction_opportunities(player).is_empty():
			break
	if session.turns_resolved() != _turn_seen:
		_new_turn()
	_flush_pending()
	contexts.sync(session.observe(player))
	_queue_refresh()


## The AI opponents plan or react, once per phase, from the same state the
## player saw (simultaneous turns).
func _ai_act() -> void:
	if ai.is_empty() or not session.state.outcome.is_empty():
		return
	var step := "%d:%d" % [session.turns_resolved(), session.clock.phase]
	if step == _ai_step:
		return
	_ai_step = step
	for p: int in ai:
		match session.clock.phase:
			PulseClock.Phase.PLANNING:
				HeadlessOverworld.plan_for(session, p, ai[p])
			PulseClock.Phase.REACTION:
				HeadlessOverworld.react_for(session, p, ai[p])


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
