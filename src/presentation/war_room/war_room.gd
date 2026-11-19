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
## PiP views: click to swap into the main view, drag to move. The line at
## the bottom says what the mouse and keys do right now; "Controls" lists
## them all.
##
## Overworld orders (sw-ll4.19): with a commander selected, the hexes it
## can enter this turn are lit and numbered with their movement cost, and
## hovering a hex previews the route. Right click moves there, shift +
## right click adds a waypoint to the planned route, right click on the
## commander clears it. A garrison, convoy or producing feature on a
## selected hex has a "send to" button: the next hex or commander clicked
## is its destination.
##
## Playback (sw-ll4.19): with `turn_seconds` above 0, a resolved turn is
## played out over that long (commanders and convoys walk their hexes,
## battles replay tick by tick) before the next Planning is shown. Space or
## a click skips it. The game itself has already resolved: playback only
## delays what is drawn.
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

const PIP_SIZE: Vector2 = Vector2(240, 160)

@export var player: int = 1
## Applied once the demo is built (the mock uses it): "", "battle" (focus
## the first battle), "pip" (focus the first, pin the second) or "plan"
## (focus the first, select its squads and draft a move into a new line),
## "move" (select a free commander on the overworld) or "play" (a battle
## turn frozen halfway through its playback).
@export var demo_view: String = ""
## A map to play (with no session given): the war room makes its own
## session and plays `player` against the map's guards and triggers.
@export var map_id: String = ""
@export var map_seed: int = 1
## A skirmish (with `map_id`): every other player is played by this
## controller_profile (data, kind controller_profile) through ProfileController,
## the same AI the factory evolves.
@export var ai_profile: String = ""
## Seconds a resolved turn takes to play out; 0 shows the result at once.
@export var turn_seconds: float = 0.0
## Take `turn_seconds` from the player's saved settings (GameSettings)
## instead; the main menu sets this.
@export var use_settings: bool = false
## Save to the "autosave" slot after every resolved turn (the main menu
## sets this for games started or loaded from it).
@export var autosave: bool = false
## Shown by the "Main menu" button; empty hides it.
@export_file("*.tscn") var menu_scene: String = "res://src/presentation/main_menu/main_menu.tscn"

var session: OverworldSession
## With a `session` given: true makes this room end its turns itself (as it
## does for a session it made), where false leaves that to the owner.
var drives_turns: bool = false
## AI opponents: player -> controller (HeadlessOverworld.plan_for/react_for).
var ai: Dictionary = {}
## Runs the match for this room: the AI seats, ending turns, the match log.
var driver: MatchDriver
## A recorded match to watch (set before the room is ready): ending the
## turn plays the next recorded turn, and the room gives no orders.
var replay: MatchReplay
## Replay: play the next turn as soon as one has been shown.
var auto_play: bool = false
var _end_button: Button
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
var _commander_box: CommandPanel
var _log_box: VBoxContainer
var _banner: PanelContainer
var _banner_text: Label
## Messages from triggers, newest last: [translated text].
var messages: PackedStringArray = PackedStringArray()
var _log_turn: int = -1
## The left column shown in a battle: scores and the squad card.
## Where the panels are (data/ui/layouts/war_room.json).
var layout: UiLayout
var _battle_box: BattlePanel
## The squad whose card is shown (clicked), and the one under the cursor.
var _inspected: int = -1
var _hovered: int = -1
var _hover_plot: int = -1
## Armed "send to": {"kind": "rally" | "line", "id", "what"}; the next hex
## clicked is the destination.
var _target: Dictionary = {}
## The turn being played back ({} when not): {"t", "obs", "walks",
## "battles", "turn"}.
var _play: Dictionary = {}
## The screen's windows (sw-ijp.2): modals, the playback blocker, the hover card.
var ui: UiRoot
var _blocker: UiWindow
## What the player knows about the hex under the cursor.
var _hover_card: PanelContainer
var _hover_win: UiWindow
var _terrain_colors: Dictionary = {}
## The results screen, while it is open.
var results: ResultsScreen
var _results_shown: bool = false


func _ready() -> void:
	if replay != null:
		session = replay.session
		map_id = ""
		ai_profile = ""
		end_turn_requested.connect(_end_turn)
	elif driver != null:  # a loaded game: its session, AI seats and tallies
		session = driver.session
		player = driver.human
		ai = driver.ai
		map_id = ""  # no match log for a loaded game
		end_turn_requested.connect(_end_turn)
	elif session == null:
		session = demo_session() if map_id.is_empty() else MatchDriver.play_session(map_id, map_seed)
		end_turn_requested.connect(_end_turn)
	elif drives_turns:
		end_turn_requested.connect(_end_turn)
	if driver == null:
		driver = MatchDriver.new(session, player)
		driver.meta = {"map": map_id, "seed": map_seed, "profile": ai_profile, "human": player}
	if ai.is_empty() and not ai_profile.is_empty():
		ai = MatchDriver.opponents(session, player, ai_profile, map_seed)
	driver.ai = ai
	driver.autosave = autosave
	if record_match and not map_id.is_empty() and match_log == null:
		match_log = MatchLog.start(session, {"human": player, "opponent": ai_profile if not ai.is_empty() else "story"})
		if match_log != null:
			messages.append("Match log: " + match_log.os_path())
	driver.match_log = match_log
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
		"move":  # the overworld with a free commander selected: its reach
			for cmd: Dictionary in session.observe(player).get("commanders", []):
				if cmd["player"] == player and cmd["engagement"] < 0:
					contexts.select_commander(cmd["id"])
					break
		"play":  # a battle turn frozen halfway through its playback
			if contexts.tab_in():
				_refresh()
				var pl := planner(contexts.focus)
				pl.select(pl.own_squads())
				pl.move_to(pl.selection_centre() + Vector2(35, 8), true)
				turn_seconds = 5.0
				_end_turn()
				if not _play.is_empty():
					_play["t"] = 0.5
					set_process(false)
	set_process(false)
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
	UiTheme.ensure(get_window())  # standalone (F6): the menu did not set it
	var bg := UiTheme.backdrop("ScreenBackgroundPanel")
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	# Every panel is built here and registered by id; where each goes is
	# data (data/ui/layouts/war_room.json, UiLayout).
	var panels := {}
	_battle_box = BattlePanel.new()
	_battle_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panels["battle_panel"] = _battle_box
	_terrain_colors = ContextView.feature_colors(session.templates)
	_main = ContextView.new()
	_main.terrain_colors = _terrain_colors
	_main.art = ArtSet.core()
	_main.commander_ids = session.rules.commander_ids
	_main.hex_clicked.connect(_on_hex_clicked)
	_main.battle_pressed.connect(_on_battle_pressed)
	_main.battle_box.connect(_on_battle_box)
	_main.zoomed.connect(func(f: float) -> void: contexts.zoom_by(f))
	_main.hex_hovered.connect(_on_hex_hovered)
	_main.squad_hovered.connect(_on_squad_hovered)
	panels["map"] = _main
	_pip_layer = Control.new()
	_pip_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panels["pips"] = _pip_layer
	_hover_card = PanelContainer.new()
	_hover_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_card.theme_type_variation = &"HoverCardPanel"
	# Wrapped text measures tall until it has a width: follow it back down.
	_hover_card.minimum_size_changed.connect(_hover_card.reset_size)
	_hover_win = UiWindow.new()
	_hover_win.layer = UiWindow.Layer.HUD
	_hover_win.contexts = PackedStringArray(["overworld"])
	_hover_win.wanted = false
	_hover_win.add_child(_hover_card)
	_radial = ReactionRadial.new()
	_radial.hide()
	_radial.chosen.connect(_on_reaction_chosen)
	panels["radial"] = _radial
	_input = PlanningInput.new()
	_input.command.connect(_on_command)
	add_child(_input)
	_hud = UiTheme.label("", "HudLabel", true)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panels["hud"] = _hud
	panels["battles_title"] = _title("Battles")
	_menu = VBoxContainer.new()
	panels["battles"] = _menu
	panels["commanders_title"] = _title("Commanders")
	_cmds = VBoxContainer.new()
	panels["commanders"] = _cmds
	_commander_box = CommandPanel.new()
	_commander_box.glossary = glossary
	_commander_box.battleforce_chosen.connect(set_battleforce)
	_commander_box.pick_up_requested.connect(pick_up)
	_commander_box.route_clear_requested.connect(clear_route)
	_commander_box.target_armed.connect(arm_target)
	_commander_box.rally_requested.connect(rally)
	_commander_box.supply_line_requested.connect(supply_line)
	_commander_box.activity_requested.connect(set_activity)
	panels["commander"] = _commander_box
	_orders_box = VBoxContainer.new()
	panels["orders"] = _orders_box
	_reactions_box = VBoxContainer.new()
	_reactions_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panels["reactions"] = _reactions_box
	_log_box = VBoxContainer.new()
	_log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panels["events"] = _log_box
	_banner = PanelContainer.new()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.theme_type_variation = &"BannerPanel"
	_banner_text = UiTheme.label("", "HeadingLabel")
	_banner.add_child(_banner_text)
	_banner.hide()
	panels["outcome_banner"] = _banner
	_phase_banner = PanelContainer.new()
	_phase_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_phase_banner.theme_type_variation = &"BannerPanel"
	_phase_text = UiTheme.label("", "AccentLabel", true)
	_phase_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_banner.add_child(_phase_text)
	_phase_banner.hide()
	panels["phase_banner"] = _phase_banner
	var end := Button.new()
	end.text = "End turn (Space)"
	end.pressed.connect(func() -> void: end_turn_requested.emit())
	panels["end_turn"] = end
	_end_button = end
	panels["replay_controls"] = null
	if replay != null:
		end.text = "Next turn (Space)"
		var watch := HBoxContainer.new()
		var auto := Button.new()
		auto.text = "Play all"
		auto.toggle_mode = true
		auto.tooltip_text = "Play the recorded turns one after another"
		auto.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		auto.toggled.connect(func(on: bool) -> void:
			auto_play = on
			if on and _play.is_empty():
				end_turn_requested.emit())
		watch.add_child(auto)
		var side_pick := Button.new()
		side_pick.text = "Other side (V)"
		side_pick.tooltip_text = "Watch as the next player: what that player saw"
		side_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		side_pick.pressed.connect(view_next_player)
		watch.add_child(side_pick)
		panels["replay_controls"] = watch
	var tools := HBoxContainer.new()
	var controls := Button.new()
	controls.text = "Controls"
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.pressed.connect(toggle_help)
	tools.add_child(controls)
	var options := Button.new()
	options.text = "Options"
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options.pressed.connect(func() -> void: if ui.find(&"options") == null: OptionsScreen.open_over(self))
	tools.add_child(options)
	var save := Button.new()
	save.text = "Save"
	save.tooltip_text = "Save the game as it is now. Load it from the main menu."
	save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save.pressed.connect(save_game)
	save.disabled = replay != null
	tools.add_child(save)
	panels["tools"] = tools
	panels["main_menu"] = null
	if not menu_scene.is_empty() and ResourceLoader.exists(menu_scene):
		var back := Button.new()
		back.text = "Main menu"
		back.pressed.connect(func() -> void: get_tree().change_scene_to_file.call_deferred(menu_scene))
		panels["main_menu"] = back
	layout = UiLayout.build(UiLayout.spec("war_room", panels.keys()), panels, self, use_settings)
	var stage: Control = layout.regions.get("stage", self)
	ui = UiRoot.new()  # its own, last, so it draws and hears keys first
	add_child(ui)
	ui.open(_hover_win, stage)
	# While a turn plays out, a click anywhere skips to its end.
	_blocker = UiWindow.new()
	_blocker.layer = UiWindow.Layer.BLOCKER
	_blocker.contexts = PackedStringArray(["playback"])
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_blocker.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			skip_playback())
	ui.open(_blocker)
	_sync_ui_context()


## Opens or closes the controls list.
func toggle_help() -> void:
	ui.toggle(&"help", ControlsHelp.window)


## Tells the windows which view is showing: the overworld, a battle, or a
## turn playing out.
func _sync_ui_context() -> void:
	if ui == null or contexts == null:
		return
	var view := &"overworld" if contexts.focus == ViewContexts.OVERWORLD else &"battle"
	layout.set_view(view)
	ui.context = &"playback" if not _play.is_empty() else view


func _clear(parent: Node) -> void:
	for c in parent.get_children():
		parent.remove_child(c)
		c.queue_free()


## A panel heading; defined terms in it are hoverable.
func _title(text: String) -> GlossaryLabel:
	var l := GlossaryLabel.new()
	l.glossary = glossary
	l.theme_type_variation = &"DimLabel"
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
	_sync_ui_context()
	if not _play.is_empty():
		_show_play()
		return
	_show_main()
	_refresh_pips()
	_refresh_menu()
	_refresh_commanders()
	_refresh_orders()
	_refresh_reactions()
	_commander_box.show_selection(session, player, _own_selected(), contexts.selected_plot, _own_detachment())
	_refresh_log()
	_refresh_phase_banner()
	_refresh_battle_panel()
	_refresh_hud()


## Draws the focused context into the main view (cheap: no panels).
func _show_main() -> void:
	if contexts.focus == ViewContexts.OVERWORLD:
		_main.show_overworld(session.observe(player), session.rules.feature_ids, contexts, _overworld_extra())
		return
	var obs := session.observe_battle(player, contexts.focus)
	var pl := planner(contexts.focus)
	pl.sync(obs)
	_main.title = battle_name(contexts.focus)
	var fc: Dictionary = _forecasts.get(contexts.focus, {})
	_main.show_battle(obs, {"selected": pl.selection, "drafts": pl.drafts, "ghosts": fc.get("ghosts", {}),
		"contacts": fc.get("contacts", []), "reactable": _reactable(contexts.focus), "inspected": _inspected,
		"triggers": _triggers(contexts.focus), "terrain": _battle_rules(contexts.focus), "pending": _pending.has(contexts.focus)})


## The status line and what the mouse and keys do right now.
func _refresh_hud() -> void:
	var where := "Overworld" if contexts.focus == ViewContexts.OVERWORLD else battle_name(contexts.focus)
	var status := "%s  ·  %s  ·  turn %d" % [where, session.phase_name().capitalize(), session.turns_resolved() + 1]
	if contexts.followed >= 0:
		status += "  ·  following commander %d" % (contexts.followed & 0xffff)
	if not _hud_note.is_empty():
		status += "  ·  " + _hud_note
	_hud.text = "%s\n%s" % [status, hints()]


## Watches as another player: that player's fog, battles and armies.
func view_as(p: int) -> void:
	if not session.players().has(p) or p == player:
		return
	player = p
	if contexts.changed.is_connected(_queue_refresh):
		contexts.changed.disconnect(_queue_refresh)
	contexts = ViewContexts.new(player)
	contexts.changed.connect(_queue_refresh)
	planners = {}
	_forecasts = {}
	_inspected = -1
	_log_turn = -1
	messages = PackedStringArray()
	contexts.sync(session.observe(player))
	_queue_refresh()


## Replay: watch as the next player in turn.
func view_next_player() -> void:
	var all := session.players()
	view_as(all[(all.find(player) + 1) % all.size()])


## What the mouse and keys do in the present context, in one line.
func hints() -> String:
	if not _play.is_empty():
		return "Turn %d is playing out.  Space or click: skip to the end" % int(_play["turn"])
	if replay != null:
		var where := "the recording has ended" if replay.at_end() else "turn %d of %d" % [session.turns_resolved() + 1, replay.turns()]
		var odd := "" if replay.diverged_turn < 0 else "  ·  WARNING: turn %d did not match the recording" % replay.diverged_turn
		return "Replay, watching as player %d (%s)%s  ·  Space: next turn  ·  V: the other side  ·  Tab: go to a battle  ·  click a squad, a commander or a hex to inspect it" % [player, where, odd]
	if not _target.is_empty():
		return "Click the hex or one of your commanders to send %s there.  Right click or Esc: cancel" % _target["what"]
	if contexts.focus == ViewContexts.OVERWORLD:
		if _own_detachment() >= 0:
			return "Right click: send the convoy there (it keeps going on later turns; lit hexes are this turn's reach)  ·  Shift+right click: add a waypoint  ·  Right click one of your commanders: join its army  ·  Right click the convoy: halt  ·  Convoys take no hexes and do no activities"
		if _own_selected() >= 0:
			return "Right click: move there (lit hexes are in reach; numbers are movement cost)  ·  Shift+right click: add a waypoint  ·  Right click the commander: clear its route  ·  F: follow  ·  Space: end turn"
		return "Left click: select a commander or a hex  ·  Wheel: zoom (zoom into a battle to enter it)  ·  Tab: go to a battle  ·  Space: end turn"
	if session.clock.phase == PulseClock.Phase.REACTION:
		return "Reaction window: click a marked squad to react  ·  Space: play the turn"
	var pl := _focused_planner()
	if _attack_armed:
		return "ATTACK-MOVE: right click where to go; the squads fight what they meet"
	if pl != null and not pl.selection.is_empty():
		return "Right click: move  ·  Right click an enemy: attack  ·  Alt+right click: new line  ·  H hold  ·  A attack-move  ·  B fall back  ·  R run  ·  Ctrl+1-9: make a group  ·  Space: end turn"
	return "Left click or drag: select squads  ·  Click any squad: its card  ·  Hover: weapon range  ·  Tab: next battle  ·  Esc: overworld  ·  Space: end turn"


## Reach, movement points and the hovered route for the selected commander.
func _overworld_extra() -> Dictionary:
	var did := _own_detachment()
	if did >= 0 and session.clock.phase == PulseClock.Phase.PLANNING:
		var cr := session.convoy_reach(player, did)
		var dx := {"reach": cr.get("reach", {}), "budget": cr.get("budget", 0), "spent": 0}
		var at: int = session.state.detachments.get_value(did, &"plot")
		if _hover_plot >= 0 and _hover_plot != at and not cr.is_empty():
			var via := _convoy_route_of(did) if Input.is_key_pressed(KEY_SHIFT) else PackedInt64Array()
			var path := session.convoy_path(player, did, _hover_plot, via)
			var spent := 0
			for p in path:
				spent += _step_cost(p, {}, {})
			dx["preview"] = path
			dx["preview_to"] = _hover_plot
			dx["preview_from"] = at
			dx["preview_cost"] = spent
		return dx
	var cid := _own_selected()
	if cid < 0 or session.clock.phase != PulseClock.Phase.PLANNING:
		return {}
	var reach := session.reach(player, cid)
	var out := {"reach": reach.get("reach", {}), "budget": reach.get("budget", 0), "spent": reach.get("spent", 0)}
	var here: int = session.state.commanders.get_value(cid, &"plot")
	if _hover_plot >= 0 and _hover_plot != here and (reach["reach"] as Dictionary).size() > 0:
		var via := _route_of(cid) if Input.is_key_pressed(KEY_SHIFT) else PackedInt64Array()
		var path := session.path(player, cid, _hover_plot, via)
		var costs := 0
		var known: Dictionary = reach["reach"]
		var obs_costs := session.observe(player)
		for p in path:
			costs += _step_cost(p, known, obs_costs)
		out["preview"] = path
		out["preview_to"] = _hover_plot
		out["preview_from"] = here
		out["preview_cost"] = costs
	return out


## The movement cost of entering a plot, as the player knows it.
func _step_cost(p: int, _known: Dictionary, _obs: Dictionary) -> int:
	return maxi(OverworldVision.known_costs(session.state, player)[p], 0)


## The selected commander's planned route.
func _route_of(cid: int) -> PackedInt64Array:
	return (session.observe(player).get("routes", {}) as Dictionary).get(cid, PackedInt64Array())


func _on_hex_hovered(p: int) -> void:
	_hover_plot = p
	_refresh_hover_card()
	if _play.is_empty() and contexts.focus == ViewContexts.OVERWORLD and (_own_selected() >= 0 or _own_detachment() >= 0):
		_show_main()


## The battle panel: the scores, the zones, and the squad card.
func _refresh_battle_panel() -> void:
	var eid := contexts.focus
	if eid == ViewContexts.OVERWORLD or not session.battles.has(eid):
		return
	var id := card_squad()
	var r := _battle_rules(eid)
	_battle_box.show_battle(battle_name(eid), session.observe_battle(player, eid), _squad_obs(eid, id) if id >= 0 else {},
		session.inspect_battle(player, eid, id) if id >= 0 else {}, player, r.tps if r != null else 10)


func _on_squad_hovered(id: int) -> void:
	_hovered = id
	if _play.is_empty():
		_refresh_battle_panel()


## The card for the hex under the cursor: what the player knows is there
## (HexCard, from inspect_plot). Hidden over unknown ground, in battles and
## during playback.
func _refresh_hover_card() -> void:
	_clear(_hover_card)
	if ui == null:
		return
	_sync_ui_context()
	var info := session.inspect_plot(player, _hover_plot) if _hover_plot >= 0 and ui.context == &"overworld" else {}
	_hover_win.wanted = bool(info.get("known", false))
	if not _hover_win.wanted:
		return
	_hover_card.add_child(HexCard.build(info, session.rules, player))
	_hover_card.position = Vector2(12.0 + (PIP_SIZE.x + 12.0 if not contexts.pips.is_empty() else 0.0), 12.0)
	_hover_card.reset_size()


## The squad whose card is shown: the one clicked, else the first selected,
## else the one under the cursor. -1 if none of them is in sight.
func card_squad() -> int:
	var eid := contexts.focus
	if eid == ViewContexts.OVERWORLD:
		return -1
	var known := {}
	for sq: Dictionary in session.observe_battle(player, eid).get("squads", []):
		if not (sq.get("destroyed", false) or sq.get("withdrawn", false)):
			known[sq["id"]] = true
	var pl := planner(eid)
	for id: int in [_inspected, pl.selection[0] if not pl.selection.is_empty() else -1, _hovered]:
		if known.has(id):
			return id
	return -1


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
		var pip := PipPanel.new()
		pip.engagement = eid
		pip.size = PIP_SIZE
		pip.view.terrain_colors = _terrain_colors
		pip.view.art = _main.art
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
		var can_join := reserves_ready(m["engagement"])
		if can_join > 0:
			_menu.add_child(UiTheme.label("%d reserve squad%s can join this battle" % [can_join, "" if can_join == 1 else "s"], "SmallAccentLabel", true))
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

func _on_hex_clicked(p: int, button: int, shift: bool = false) -> void:
	if not _target.is_empty():
		if p >= 0 and button == MOUSE_BUTTON_LEFT:
			send_to(p)
		else:
			_target = {}
			_queue_refresh()
		return
	if button == MOUSE_BUTTON_RIGHT and _own_detachment() >= 0:
		_steer(p, shift)
		return
	if button == MOUSE_BUTTON_RIGHT:
		var cid := _own_selected()
		if cid >= 0 and p >= 0:
			if p == session.state.commanders.get_value(cid, &"plot") and not shift:
				clear_route()
			else:
				route_to(p, shift)
		else:
			contexts.deselect_all()
		return
	if p < 0:
		return
	# A commander first; clicking its hex again selects the garrison or
	# convoy there (sw-kys.8).
	var obs := session.observe(player)
	var det := -1
	for d: Dictionary in obs.get("detachments", []):
		if int(d["plot"]) == p and int(d["player"]) == player and int(d["engagement"]) < 0 and int(d["id"]) != contexts.selected_detachment:
			det = int(d["id"])
			break
	for cmd: Dictionary in obs.get("commanders", []):
		if cmd["plot"] == p and cmd["player"] == player:
			if contexts.selected == cmd["id"] and det >= 0:
				contexts.select_detachment(det)
			else:
				contexts.select_commander(cmd["id"])
			return
	if det >= 0:
		contexts.select_detachment(det)
		return
	contexts.select_hex(p)


## The selected detachment if it is the player's own and not fighting, else -1.
func _own_detachment() -> int:
	var did := contexts.selected_detachment
	var row := session.state.detachments.row_of(did) if did >= 0 else -1
	if row < 0 or session.state.detachments.player[row] != player:
		return -1
	return did


## Right click with a detachment selected (sw-kys.8): its own hex halts it,
## a hex with one of the player's commanders sends it to that commander,
## any other hex routes it there (Shift: as a waypoint after its route).
func _steer(p: int, shift: bool) -> String:
	var did := _own_detachment()
	if p < 0:
		contexts.deselect_all()
		return ""
	var here: int = session.state.detachments.get_value(did, &"plot")
	if p == here and not shift:
		return halt_detachment()
	if not shift:
		for cmd: Dictionary in session.observe(player).get("commanders", []):
			if cmd["plot"] == p and cmd["player"] == player:
				rally(did, -1, int(cmd["id"]), "convoy %d" % (did & 0xffff))
				return ""
	return steer_to(p, shift)


## Routes the selected detachment to a hex (the whole way, over as many
## turns as it takes). With `append`, the hex is a waypoint after its
## route. "" or why not.
func steer_to(p: int, append: bool = false) -> String:
	var did := _own_detachment()
	if did < 0:
		return "no convoy selected"
	var via := _convoy_route_of(did) if append else PackedInt64Array()
	var path := session.convoy_path(player, did, p, via)
	var err := "no way there" if path.size() <= via.size() else session.set_convoy_route(player, did, path)
	_hud_note = err
	_note("%s convoy %d to %s%s" % ["waypoint for" if append else "route", did & 0xffff, EventText.hex(p, session.rules),
		(" - refused: " + err) if not err.is_empty() else ""])
	_queue_refresh()
	return err


## Halts the selected detachment where it is. "" or why not.
func halt_detachment() -> String:
	var did := _own_detachment()
	if did < 0:
		return "no convoy selected"
	_hud_note = session.set_convoy_route(player, did, PackedInt64Array())
	_note("convoy %d halted%s" % [did & 0xffff, "" if _hud_note.is_empty() else " - refused: " + _hud_note])
	_queue_refresh()
	return _hud_note


func _convoy_route_of(did: int) -> PackedInt64Array:
	return (session.observe(player).get("convoy_routes", {}) as Dictionary).get(did, PackedInt64Array())


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
	driver.note(text)


func _focused_planner() -> BattlePlanner:
	if contexts.focus == ViewContexts.OVERWORLD:
		return null
	return planner(contexts.focus)


func _on_battle_pressed(at: Vector2, button: int, shift: bool, ctrl: bool, alt: bool, double: bool) -> void:
	var pl := _focused_planner()
	if pl == null:
		return
	var hit := _main.squad_at(at)
	if button == MOUSE_BUTTON_LEFT and (hit >= 0 or not (shift or ctrl)):
		_inspected = hit  # any squad in sight: its card (empty ground closes it)
		_queue_refresh()
	if session.clock.phase == PulseClock.Phase.REACTION:
		if button == MOUSE_BUTTON_LEFT and hit >= 0:
			if pl.own_squads().has(hit):
				pl.select([hit])  # highlights what it would react to
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
		elif hit < 0 and not shift and not ctrl:
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


## How many more squads the player can send into battle `eid` this turn.
func reserves_ready(eid: int) -> int:
	var n := 0
	for g: Dictionary in session.reserves(player, eid):
		var ready := (g["squads"] as Array).filter(func(q: Dictionary) -> bool: return not q["sent"] and String(q["why"]).is_empty())
		n += mini(int(g["open"]), ready.size())
	return n


## The reserves of each of the player's commanders in the battle: a button to
## send each in, or what stops it (sw-dek).
func _add_reserves(eid: int) -> void:
	for g: Dictionary in session.reserves(player, eid):
		var cid: int = g["commander"]
		var open: int = g["open"]
		_orders_box.add_child(_title("%s: reserves (%s)" % [EventText.commander(cid),
			"battleforce full" if open == 0 else "room for %d more" % open]))
		for q: Dictionary in g["squads"]:
			var what := "%s  %d/%d" % [EventText.squad_name(session.rules.squad_ids[int(q["tmpl"])]), int(q["alive"]), int(q["size"])]
			var why := String(q["why"])
			var b := Button.new()
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.disabled = q["sent"] or not why.is_empty()
			if q["sent"]:
				b.text = "✓ %s: joins next battle turn" % what
			elif why.is_empty():
				b.text = "Send in %s" % what
				b.pressed.connect(send_reserve.bind(cid, int(q["squad"])))
			else:
				b.text = "%s: %s" % [what, why]
			_orders_box.add_child(b)


## Sends a squad from the commander's army into its battle.
func send_reserve(cid: int, squad: int) -> String:
	var err := session.reinforce(player, cid, squad)
	_hud_note = err
	_note("%s: send in squad %d%s" % [EventText.commander(cid), squad & 0xffff, "" if err.is_empty() else " - refused: " + err])
	_queue_refresh()
	return err


func _refresh_orders() -> void:
	_clear(_orders_box)
	var pl := _focused_planner()
	if pl == null or session.clock.phase != PulseClock.Phase.PLANNING:
		return
	_add_reserves(contexts.focus)
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


## Own squads with an opportunity in battle eid -> the enemy squads that
## trigger them (all visible: hidden enemies give no opportunity).
func _triggers(eid: int) -> Dictionary:
	var out := {}
	for o: Dictionary in session.reaction_opportunities(player):
		if o["engagement"] == eid:
			var list: Array = out.get(o["squad"], [])
			if not list.has(o["trigger"]):
				list.append(o["trigger"])
			out[o["squad"]] = list
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
	planner(o["engagement"]).select([o["squad"]])
	_open_radial.call_deferred(o["engagement"], o["squad"])


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_TAB:
			contexts.cycle(-1 if k.shift_pressed else 1)
		KEY_ESCAPE:
			if not _target.is_empty():
				_target = {}
				_queue_refresh()
			elif not _play.is_empty():
				skip_playback()
			else:
				contexts.exit()
		KEY_F:
			contexts.follow()
		KEY_V:
			if replay == null:
				return
			view_next_player()
		KEY_BACKSPACE:
			contexts.deselect_all()
		KEY_SPACE:
			if not _play.is_empty():
				skip_playback()
			else:
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
## turn, by the cheapest way the player knows). With `append`, the hex is a
## waypoint: the way there starts where the planned route ends. "" or why
## not.
func route_to(p: int, append: bool = false) -> String:
	var cid := _own_selected()
	if cid < 0:
		return "no commander selected"
	var via := _route_of(cid) if append else PackedInt64Array()
	var path := session.path(player, cid, p, via)
	var from: int = via[via.size() - 1] if not via.is_empty() else session.state.commanders.get_value(cid, &"plot")
	var err := ""
	if path.is_empty():
		err = "already there" if p == from else "no way there"
	elif path.size() == via.size():
		err = "no movement left this turn for another waypoint"
	else:
		err = session.set_route(player, cid, path)
	_hud_note = err
	var reach := "" if path.is_empty() or path[path.size() - 1] == p else " (gets to %s this turn)" % EventText.hex(path[path.size() - 1], session.rules)
	_note("%s %s to %s%s" % ["waypoint for" if append else "route", EventText.commander(cid), EventText.hex(p, session.rules),
		(" - refused: " + err) if not err.is_empty() else reach])
	_queue_refresh()
	return err


## Clears the selected commander's route. "" or why not.
func clear_route() -> String:
	var cid := _own_selected()
	if cid < 0:
		return "no commander selected"
	_hud_note = session.set_route(player, cid, PackedInt64Array())
	_note("route of %s cleared%s" % [EventText.commander(cid), "" if _hud_note.is_empty() else " - refused: " + _hud_note])
	_queue_refresh()
	return _hud_note


## Sends one of the player's detachments to a plot or a commander (both -1
## halts it). "" or why not.
func rally(detachment: int, to_plot: int, to_commander: int, what: String) -> String:
	_hud_note = session.rally(player, detachment, to_plot, to_commander)
	_note("send %s to %s%s" % [what, _dest_text(to_plot, to_commander), "" if _hud_note.is_empty() else " - refused: " + _hud_note])
	_queue_refresh()
	return _hud_note


## Sends a producing feature's output to a plot or a commander (both -1
## clears the line). "" or why not.
func supply_line(feature: int, to_plot: int, to_commander: int, what: String) -> String:
	_hud_note = session.set_supply_line(player, feature, to_plot, to_commander)
	_note("supply line: %s sends to %s%s" % [what, _dest_text(to_plot, to_commander), "" if _hud_note.is_empty() else " - refused: " + _hud_note])
	_queue_refresh()
	return _hud_note


func _dest_text(to_plot: int, to_commander: int) -> String:
	if to_commander >= 0:
		return EventText.commander(to_commander)
	return EventText.hex(to_plot, session.rules) if to_plot >= 0 else "nowhere"


## Arms "send to" for a detachment ("rally") or a producing feature's
## output ("line"): the next hex clicked is where it goes.
func arm_target(kind: String, id: int, what: String) -> void:
	_target = {"kind": kind, "id": id, "what": what}
	_hud_note = ""
	_queue_refresh()


## Sends the armed detachment or supply line to plot p, or to the player's
## commander standing on it. "" or why not.
func send_to(p: int) -> String:
	if _target.is_empty():
		return "nothing to send"
	var cid := -1
	for cmd: Dictionary in session.observe(player).get("commanders", []):
		if cmd["plot"] == p and cmd["player"] == player:
			cid = cmd["id"]
	var err := ""
	if _target["kind"] == "rally":
		err = session.rally(player, _target["id"], -1 if cid >= 0 else p, cid)
	else:
		err = session.set_supply_line(player, _target["id"], -1 if cid >= 0 else p, cid)
	var dest := EventText.commander(cid) if cid >= 0 else EventText.hex(p, session.rules)
	_note("send %s to %s%s" % [_target["what"], dest, "" if err.is_empty() else " - refused: " + err])
	_hud_note = err if not err.is_empty() else "%s goes to %s" % [String(_target["what"]).capitalize(), dest]
	_target = {}
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


## Plans the selected commander's activity where its route ends (recruit,
## hire, refit, ...; "" clears it). Returns "" or why it was refused.
func set_activity(activity: String, option: String = "") -> String:
	var cid := _own_selected()
	if cid < 0:
		return "no commander selected"
	var err := session.set_activity(player, cid, activity, option)
	_hud_note = err
	_note("%s: %s%s" % [EventText.commander(cid), "activity cleared" if activity.is_empty() else "%s %s" % [activity, option.replace("_", " ")],
		"" if err.is_empty() else " - refused: " + err])
	_queue_refresh()
	return err


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
			l.theme_type_variation = &""
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
		_banner_text.theme_type_variation = &"HeadingGoodLabel" if won else &"HeadingBadLabel"
		if not _results_shown and _play.is_empty():
			_results_shown = true
			_open_results("won" if won else ("drew" if outcome["outcome"] == "drew" else "lost"), _say(String(outcome["key"]), String(outcome["text"])))


## The results screen, once, when the match ends.
func _open_results(result: String, reason: String) -> void:
	driver.stats["turns"] = session.turns_resolved()
	var replay := not String(driver.meta.get("map", "")).is_empty() and not String(driver.meta.get("profile", "")).is_empty()
	results = ResultsScreen.open_over(self, result, reason, driver.stats, player, {
		"replay": replay, "menu": not menu_scene.is_empty() and ResourceLoader.exists(menu_scene),
		"note": "" if match_log == null else "Match log: " + match_log.os_path()})
	results.main_menu.connect(func() -> void: get_tree().change_scene_to_file.call_deferred(menu_scene))
	results.play_again.connect(play_again)


## A new game on the same map, seed and opponent, in place of this one.
func play_again() -> void:
	var w := MainMenu.skirmish_room(String(driver.meta["profile"]), String(driver.meta["map"]), int(driver.meta["seed"]))
	w.use_settings = use_settings
	w.autosave = autosave
	w.menu_scene = menu_scene
	var tree := get_tree()
	tree.root.add_child.call_deferred(w)
	tree.set_deferred(&"current_scene", w)
	queue_free()


## Saves the game to a new slot (MatchDriver.save_game). Returns the path
## or "".
func save_game() -> String:
	if replay != null:
		_hud_note = "a replay can't be saved"
		_queue_refresh()
		return ""
	var path := driver.save_game()
	_hud_note = "could not save: " + MatchDriver.last_error if path.is_empty() else "saved as " + path.get_file().get_basename()
	_note(_hud_note)
	_queue_refresh()
	return path


## Adds the template of a feature the event names, if the player knows it.
func _name_feature(d: Dictionary, obs: Dictionary) -> void:
	if not d.has("feature") or not d.has("plot"):
		return
	var plot: Dictionary = (obs.get("plots", {}) as Dictionary).get(int(d["plot"]), {})
	for f: Dictionary in plot.get("features", []):
		if int(f["id"]) == int(d["feature"]):
			d["feature_tmpl"] = int(f["tmpl"])


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


## A message's translation, its text as the fallback.
static func _say(key: String, fallback: String) -> String:
	var s := String(TranslationServer.translate(key)) if not key.is_empty() else key
	return fallback if s.is_empty() or s == key else s


## Readies every player until planning comes round again, stopping at a
## reaction window that offers this player something. The drafts were
## consumed: the next planning starts clean.
func _end_turn() -> void:
	if not _play.is_empty():
		skip_playback()
		return
	_hud_note = ""
	_target = {}
	_note("end turn (%s)" % session.phase_name())
	var before := session.observe(player)
	var resolved := session.turns_resolved()
	session.keep_playback = turn_time() > 0.0
	var played := false
	if replay != null:
		played = replay.step()
		if played:
			driver.tally(session.last_events)
		else:
			auto_play = false
			_hud_note = "the recording has ended"
	else:
		played = driver.end_turn()
	if session.turns_resolved() != _turn_seen:
		_new_turn()
	_flush_pending()
	if played and turn_time() > 0.0:
		_start_play(before, resolved + 1)
		return
	contexts.sync(session.observe(player))
	_queue_refresh()


## Seconds a resolved turn plays out over (0 = at once).
func turn_time() -> float:
	return float(GameSettings.value("turn_seconds")) if use_settings else turn_seconds


## Whether the last turn is being played back.
func playing() -> bool:
	return not _play.is_empty()


## Starts playing back the turn that just resolved. The contexts are not
## synced until it ends, so a battle that ended can still be watched.
func _start_play(before: Dictionary, turn: int) -> void:
	var after := session.observe(player)
	# Movement resolves on a timeline of movement points (GDD 02 §2.9), and
	# the playback keeps it: the turn stands for `span` points, so everyone
	# moves at one speed and a short move ends early.
	var span := session.rules.convoy_mp
	for mp in session.rules.cm_mp:
		span = maxi(span, mp)
	var walks := {"commanders": {}, "detachments": {}, "gone": [], "span": span}
	var owner_of := {}
	for e: Dictionary in after.get("events", []):
		var d: Dictionary = e["data"] if e.has("data") else e
		var kind := ""
		var id := -1
		if e["type"] == &"commander_moved":
			kind = "commanders"
			id = int(d["commander"])
		elif e["type"] == &"convoy_moved":
			kind = "detachments"
			id = int(d["detachment"])
			owner_of[id] = int(d.get("player", 0))
		else:
			continue
		if not (walks[kind] as Dictionary).has(id):
			walks[kind][id] = {"plots": [int(d["from"])], "times": [0]}
		var w: Dictionary = walks[kind][id]
		(w["plots"] as Array).append(int(d["to"]))
		(w["times"] as Array).append(int((w["times"] as Array).back()) + maxi(session.state.move_cost(int(d["to"])), 1))
		walks["span"] = maxi(int(walks["span"]), int((w["times"] as Array).back()))
	# Who is gone afterwards: draw them walking all the same.
	var still := {}
	for det: Dictionary in after.get("detachments", []):
		still[int(det["id"])] = true
	for id: int in walks["detachments"]:
		if not still.has(id):
			(walks["gone"] as Array).append({"player": owner_of.get(id, 0), "convoy": true, "walk": walks["detachments"][id]})
	still = {}
	for cmd: Dictionary in after.get("commanders", []):
		still[int(cmd["id"])] = true
	for cmd: Dictionary in before.get("commanders", []):
		if walks["commanders"].has(int(cmd["id"])) and not still.has(int(cmd["id"])):
			(walks["gone"] as Array).append({"player": int(cmd["player"]), "convoy": false, "walk": walks["commanders"][int(cmd["id"])]})
	_play = {"t": 0.0, "obs": after, "before": before, "walks": walks, "battles": session.playback(player), "turn": turn}
	_radial.hide()
	_refresh_hover_card()
	set_process(true)
	_show_play()


func _process(delta: float) -> void:
	if _play.is_empty():
		set_process(false)
		return
	_play["t"] = float(_play["t"]) + delta / maxf(turn_time(), 0.05)
	if float(_play["t"]) >= 1.0:
		skip_playback()
	else:
		_show_play()


## Draws the moment of the playback in the main view and the PiPs.
func _show_play() -> void:
	var t: float = _play["t"]
	var battles: Dictionary = _play["battles"]
	var eid := contexts.focus
	if eid == ViewContexts.OVERWORLD:
		_main.show_overworld(_play["obs"], session.rules.feature_ids, contexts, {"play": _play["walks"], "t": t})
	elif battles.has(eid):
		_main.title = battle_name(eid)
		_main.show_playback(battles[eid], t, session.observe_battle(player, eid))
	for pip in _pip_layer.get_children():
		if pip is PipPanel and battles.has((pip as PipPanel).engagement):
			var e := (pip as PipPanel).engagement
			(pip as PipPanel).view.show_playback(battles[e], t, session.observe_battle(player, e))
	_phase_banner.show()
	_phase_text.text = "Turn %d is playing out (%d%%).  Space or click to skip." % [int(_play["turn"]), int(t * 100.0)]
	_refresh_hud()


## Ends the playback: the view shows the present again.
func skip_playback() -> void:
	if _play.is_empty():
		return
	_play = {}
	_refresh_hover_card()
	set_process(false)
	contexts.sync(session.observe(player))
	_queue_refresh()
	if auto_play and replay != null and not replay.at_end():
		end_turn_requested.emit.call_deferred()


