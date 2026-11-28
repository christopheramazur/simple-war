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
## Playback (sw-ll4.19, sw-ll4.27.4): with `turn_seconds` above 0, a resolved
## turn is played out over that long (commanders and convoys walk their hexes,
## battles replay tick by tick) before the next Planning is shown. Space or
## Esc skips it; a left click inspects the squad under it (its card shows)
## and selects it as Planning does (sw-bafi.2), but no click or key issues
## orders ("Orders open in Planning"). The game itself has already resolved: playback
## only delays what is drawn.
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
## Replay: the side watched before the all-seeing view (player 0).
var _watched: int = 1
var _turn_slider: HSlider
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
## Observations shared by the panels of one refresh (state cannot change inside it).
var _obs_cache: Dictionary = {}
var _caching: bool = false
## Engagement ID -> BattlePlanner, and -> its latest forecast.
var planners: Dictionary = {}
var _forecasts: Dictionary = {}
## Planning forecasts run on a worker thread (sw-j4u), at most one per
## battle: engagement ID -> {"task", "token", "out" (the result lands in
## out["result"]), "again" (drafts changed meanwhile: forecast again)}.
var _forecast_jobs: Dictionary = {}
var _forecast_token: int = 0
## Off: forecasts run at once on the main thread (it stalls ~0.1 s).
var threaded_forecasts: bool = true
## Reactions queued this window: "eid,squad,trigger" -> reaction name.
var _reacted: Dictionary = {}
var _turn_seen: int = -1
var _attack_armed: bool = false
var _planning_input: PlanningInput
var _radial: ReactionRadial
var _radial_opp: Dictionary = {}
var _orders_box: VBoxContainer
var _reactions_box: VBoxContainer
var _commander_box: CommandPanel
var _log_box: VBoxContainer
var _alerts: BattleAlerts
var _banner: PanelContainer
var _banner_text: Label
## Messages from triggers, newest last: [translated text].
var messages: PackedStringArray = PackedStringArray()
var _log_turn: int = -1
## Dialogues a trigger started and not yet played (sw-62i): dialogue IDs.
var _dialogues: PackedStringArray = PackedStringArray()
var _dialogue_panel: DialoguePanel
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
## The playback frame the battle panel's card was last built for (-1 none):
## the card rebuilds only when the shown moment changes (sw-ll4.27.3).
var _play_card_frame: int = -1
## The screen's windows (sw-ijp.2): modals, the playback blocker, the hover card.
var ui: UiRoot
var _blocker: PlaybackBlocker
## The side column's scrolling list (commanders, the commander panel, battles):
## open during overworld playback (sw-bafi.9).
var _side_scroll: Control
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
	_bind_keys()
	_turn_seen = session.turns_resolved()
	contexts = ViewContexts.new(player)
	contexts.changed.connect(_queue_refresh)
	contexts.camera_changed.connect(_on_camera_changed)
	contexts.sync(_obs())
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
			for cmd: Dictionary in _obs().get("commanders", []):
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
	if keys != null:
		keys.disable(self)
	wait_forecasts()
	if contexts != null and contexts.changed.is_connected(_queue_refresh):
		contexts.changed.disconnect(_queue_refresh)
		contexts.camera_changed.disconnect(_on_camera_changed)


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
	_main.feature_info = ContextView.hex_feature_info(session.templates)
	_main.art = ArtSet.core()
	_main.commander_ids = session.rules.commander_ids
	_main.hex_clicked.connect(_on_hex_clicked)
	_main.battle_pressed.connect(_on_battle_pressed)
	_main.battle_box.connect(_on_battle_box)
	_main.deploy_dragged.connect(_on_deploy_dragged)
	_main.deploy_faced.connect(_on_deploy_faced)
	_main.zoomed.connect(func(f: float) -> void: contexts.zoom_by(f))
	_main.battle_camera.connect(func(z: float, c: Vector2) -> void: contexts.set_battle_camera(z, c))
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
	_hover_win.contexts = PackedStringArray(["overworld", "playback"])
	_hover_win.wanted = false
	_hover_win.add_child(_hover_card)
	_radial = ReactionRadial.new()
	_radial.hide()
	_radial.chosen.connect(_on_reaction_chosen)
	panels["radial"] = _radial
	_planning_input = PlanningInput.new()
	_planning_input.command.connect(_on_command)
	add_child(_planning_input)
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
	_alerts = BattleAlerts.new()
	_alerts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panels["alerts"] = _alerts
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
		var all_seeing := Button.new()
		all_seeing.name = "AllSeeing"
		all_seeing.text = "No fog"
		all_seeing.tooltip_text = "See everything, as no player does"
		all_seeing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		all_seeing.pressed.connect(toggle_all_seeing)
		watch.add_child(all_seeing)
		var back := Button.new()
		back.name = "StepBack"
		back.text = "Back a turn"
		back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		back.pressed.connect(step_back)
		watch.add_child(back)
		var slider := HSlider.new()
		slider.name = "TurnSlider"
		slider.min_value = 1
		slider.max_value = replay.turns() + 1
		slider.step = 1
		slider.value = 1
		slider.custom_minimum_size = Vector2(120, 0)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.tooltip_text = "Jump to the start of a turn"
		slider.value_changed.connect(func(v: float) -> void:
			if int(v) != session.turns_resolved() + 1:
				go_to_turn(int(v)))
		_turn_slider = slider
		watch.add_child(slider)
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
	options.pressed.connect(func() -> void:
		if ui.find(&"options") == null:
			var o := OptionsScreen.open_over(self)
			# Palette and theme changes redraw the views and panels (sw-ijp.5).
			o.setting_changed.connect(func(_key: String) -> void: _queue_refresh())
			o.closed.connect(_queue_refresh))
	tools.add_child(options)
	var save := Button.new()
	save.text = "Save"
	save.tooltip_text = "Save the game as it is now. Load it from the main menu."
	save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var save_name := LineEdit.new()
	save_name.name = "SaveName"
	save_name.placeholder_text = "Save name (optional)"
	save_name.editable = replay == null
	save.pressed.connect(func() -> void: save_game(save_name.text))
	save.disabled = replay != null
	tools.add_child(save_name)
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
	_dialogue_panel = DialoguePanel.new()
	_dialogue_panel.visible = false
	_dialogue_panel.z_index = 100
	_dialogue_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_dialogue_panel.picked.connect(_on_dialogue_picked)
	_dialogue_panel.closed.connect(_next_dialogue)
	add_child(_dialogue_panel)
	ui = UiRoot.new()  # its own, last, so it draws and hears keys first
	add_child(ui)
	ui.open(_hover_win, stage)
	# While a turn plays out, the blocker keeps input from the side panels (no
	# orders mid-turn). Over a battle the stage is left to the view: a left
	# click inspects the squad under it, the wheel zooms and middle-drag pans
	# (sw-bafi.1). Space and Esc still skip.
	_side_scroll = _commander_box
	while _side_scroll != null and not _side_scroll is ScrollContainer:
		_side_scroll = _side_scroll.get_parent() as Control
	_blocker = PlaybackBlocker.new()
	_blocker.layer = UiWindow.Layer.BLOCKER
	_blocker.contexts = PackedStringArray(["playback"])
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.open(_blocker)
	_sync_ui_context()


## The dialogue on screen, "" when none.
func current_dialogue() -> String:
	return _dialogues[0] if _dialogue_panel != null and _dialogue_panel.visible and not _dialogues.is_empty() else ""


## Queues a started dialogue and shows it if none is open.
func queue_dialogue(id: String) -> void:
	if replay != null or session.locked or id in _dialogues or session.state.dialogues.get(id, "") == Dialogue.END:
		return
	_dialogues.append(id)
	if _dialogues.size() == 1:
		_show_dialogue()


func _show_dialogue() -> void:
	if _dialogues.is_empty():
		return
	var err := session.dialogue_begin(player, _dialogues[0])
	if not err.is_empty():
		_note(err)
		_dialogues.remove_at(0)
		_show_dialogue()
		return
	_dialogue_panel.show_view(session.dialogue_view(_dialogues[0]))


func _on_dialogue_picked(choice: int) -> void:
	var id := _dialogues[0]
	var err := session.dialogue_pick(player, id, choice)
	if not err.is_empty():
		_note(err)
	_dialogue_panel.show_view(session.dialogue_view(id))


func _next_dialogue() -> void:
	if not _dialogues.is_empty():
		_dialogues.remove_at(0)
	_show_dialogue()


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
	# A battle's stage stays open during playback (inspect, zoom, pan;
	# sw-bafi.1). On the overworld the side panels' lists open too, so the
	# commanders, hexes and battles can be inspected: every planning control
	# in them is disabled with the reason (sw-bafi.9). The footer stays covered.
	if _blocker != null:
		var open: Array[Control] = []
		var stage: Control = layout.regions.get("stage")
		if stage != null:
			open.append(stage)
		if contexts.focus == ViewContexts.OVERWORLD and _side_scroll != null:
			open.append(_side_scroll)
		_blocker.uncovered = open


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


var _log_key := 0  ## hash of the events shown, so the log rebuilds only when it changes


func _refresh() -> void:
	PerfRecorder.begin(&"ui_refresh")
	_obs_cache = {}
	_caching = true
	_refresh_inner()
	_caching = false
	_obs_cache = {}
	PerfRecorder.end(&"ui_refresh")


## session.observe(player), computed once per refresh (read-only for callers).
func _obs() -> Dictionary:
	if not _caching:
		return session.observe(player)
	if not _obs_cache.has(-2):
		_obs_cache[-2] = session.observe(player)
	return _obs_cache[-2]


## session.observe_battle(player, eid), computed once per refresh.
func _obs_battle(eid: int) -> Dictionary:
	if not _caching:
		return _read_battle(eid)
	if not _obs_cache.has(eid):
		_obs_cache[eid] = _read_battle(eid)
	return _obs_cache[eid]


## The battle as this player sees it: observe_battle with, in Planning, the
## squads of its arriving at the next Reveal merged in (_merge_arrival); a
## joining side, with no battle observation yet, sees only those.
func _read_battle(eid: int) -> Dictionary:
	return _merge_arrival(eid, session.observe_battle(player, eid))


## Adds this player's arrivals in Planning (sw-bafi.18 joiners, sw-bafi.19
## reinforcements of a side already fighting) to a battle observation: the
## squads of session.arrival as own squads at their shown places, marked
## "arriving", under display IDs (ARRIVAL_BASE + overworld ID, so they never
## meet a battle squad's ID), and the area as "arrival_area". The planner
## places them like deployment; _on_deploy maps the IDs back for
## submit_arrival. A joiner's view (no observation) is built from the arrival
## alone and marked "arrival", so it sends no orders. `obs` unchanged when
## nothing of this player's arrives there in Planning.
func _merge_arrival(eid: int, obs: Dictionary) -> Dictionary:
	if session.clock.phase != PulseClock.Phase.PLANNING:
		return obs
	var a := session.arrival(player, eid)
	var r := _battle_rules(eid)
	if a.is_empty() or r == null:
		return obs
	var squads := []
	for q: Dictionary in a["squads"]:
		var st := int(q["tmpl"])
		var size: int = r.sq_members[st].size()
		squads.append({"id": ARRIVAL_BASE + int(q["squad"]), "player": player, "template": r.squad_ids[st],
			"name": r.sq_names[st], "size": size, "alive": size, "destroyed": false, "withdrawn": false,
			"abilities": [], "x": q["x"], "y": q["y"], "facing": q["facing"], "placed": q["placed"], "arriving": true})
	var out := obs.duplicate()
	if obs.is_empty():
		out = {"engagement": eid, "player": player, "phase": session.phase_name(), "arrival": true,
			"width": r.width, "height": r.height, "deploying": false, "areas": [], "squads": [], "units": []}
	out["squads"] = (out.get("squads", []) as Array) + squads
	out["arrival_area"] = a["area"]
	return out


## Arrival placements from the planner (display IDs) for submit_arrival
## (overworld IDs).
static func _arrival_placements(placements: Array) -> Array:
	var out := []
	for d: Dictionary in placements:
		var e := d.duplicate()
		e["squad"] = int(d["squad"]) - ARRIVAL_BASE
		out.append(e)
	return out


func _refresh_inner() -> void:
	_dirty = false
	if not is_inside_tree():
		return
	if session.turns_resolved() != _turn_seen:
		_new_turn()
	_alerts.focus_changed(contexts.focus)
	for eid: int in planners.keys():
		if not session.battles.has(eid):
			planners.erase(eid)
			_forecasts.erase(eid)
	if session.clock.phase != PulseClock.Phase.REACTION:
		_radial.hide()
	_sync_ui_context()
	if not _play.is_empty():
		_refresh_playback_side()
		_show_play()
		return
	_show_main()
	_refresh_pips()
	_refresh_menu()
	_refresh_commanders()
	_refresh_orders()
	_refresh_reactions()
	_commander_box.locked_reason = ""
	_commander_box.show_selection(session, player, _own_selected(), contexts.selected_plot, _own_detachment())
	_refresh_log()
	_refresh_phase_banner()
	_refresh_battle_panel()
	_refresh_hud()


## Overworld playback leaves the side lists open (sw-bafi.9): they show the
## selection as it is now, to inspect, with every planning control disabled
## and the reason on it. The event log waits for the end of the playback. A
## battle's playback keeps the side panels covered and as they were (C1).
func _refresh_playback_side() -> void:
	if contexts.focus != ViewContexts.OVERWORLD:
		return
	_refresh_menu()
	_refresh_commanders()
	_refresh_orders()
	_refresh_reactions()
	_commander_box.locked_reason = PLANNING_ONLY_NOTE
	_commander_box.show_selection(session, player, _own_selected(), contexts.selected_plot, _own_detachment())


## The battle camera moved: only the main view redraws.
func _on_camera_changed() -> void:
	if not _play.is_empty():
		_show_play()
	else:
		_show_main()


## Draws the focused context into the main view (cheap: no panels).
func _show_main() -> void:
	PerfRecorder.set_context("overworld" if contexts.focus == ViewContexts.OVERWORLD else "battle")
	_main.set_camera(contexts.zoom, contexts.battle_centre)
	if contexts.focus == ViewContexts.OVERWORLD:
		var extra := _overworld_extra()
		extra["summaries"] = _battle_summaries()
		_main.show_overworld(_obs(), session.rules.feature_ids, contexts, extra)
		return
	var obs := _obs_battle(contexts.focus)
	var pl := planner(contexts.focus)
	pl.sync(obs)
	_main.title = battle_name(contexts.focus)
	var fc: Dictionary = _forecasts.get(contexts.focus, {})
	var deploy := _deploy_overlay(pl)
	if not deploy.is_empty():
		obs = pl.deploy_view(obs)
	_main.show_battle(obs, {"deploy": deploy, "selected": pl.selection, "drafts": pl.drafts, "ghosts": fc.get("ghosts", {}),
		"contacts": fc.get("contacts", []), "reactable": _reactable(contexts.focus), "inspected": _inspected,
		"triggers": _triggers(contexts.focus), "telegraphs": session.telegraphs(player, contexts.focus), "terrain": _battle_rules(contexts.focus), "pending": _pending.has(contexts.focus)})


## The status line and what the mouse and keys do right now.
func _refresh_hud() -> void:
	if _turn_slider != null:
		_turn_slider.set_value_no_signal(session.turns_resolved() + 1)
	var where := "Overworld" if contexts.focus == ViewContexts.OVERWORLD else battle_name(contexts.focus)
	var status := "%s  ·  %s  ·  turn %d" % [where, session.phase_name().capitalize(), session.turns_resolved() + 1]
	if contexts.followed >= 0:
		status += "  ·  following commander %d" % (contexts.followed & 0xffff)
	if not _hud_note.is_empty():
		status += "  ·  " + _hud_note
	_hud.text = "%s\n%s" % [status, hints()]


## Watches as another player: that player's fog, battles and armies.
func view_as(p: int) -> void:
	if (p != 0 or replay == null) and not session.players().has(p) or p == player:
		return
	player = p
	_reset_view()


## Replay: the all-seeing view (player 0, no fog) on and off; off goes back
## to the player watched before.
func toggle_all_seeing() -> void:
	if replay == null:
		return
	if player == 0:
		view_as(_watched if session.players().has(_watched) else int(session.players()[0]))
	else:
		_watched = player
		view_as(0)


## Replay: goes to the start of turn `n` (1 = the beginning), going back by
## running the recording again from the start.
func go_to_turn(n: int) -> void:
	if replay == null:
		return
	if not _play.is_empty():
		skip_playback()
	var replaced := replay.seek(n - 1)
	if replaced:
		session = replay.session
		driver.session = session
		driver.stats = {"turns": 0, "battles": 0, "players": {}}
		_results_shown = false
	_turn_seen = session.turns_resolved()
	auto_play = false
	_hud_note = ""
	_reset_view()


func step_back() -> void:
	go_to_turn(session.turns_resolved())


func _reset_view() -> void:
	if contexts.changed.is_connected(_queue_refresh):
		contexts.changed.disconnect(_queue_refresh)
		contexts.camera_changed.disconnect(_on_camera_changed)
	contexts = ViewContexts.new(player)
	contexts.changed.connect(_queue_refresh)
	contexts.camera_changed.connect(_on_camera_changed)
	planners = {}
	_forecasts = {}
	_inspected = -1
	_log_turn = -1
	messages = PackedStringArray()
	if _alerts != null:
		_alerts.dismiss_all()
	contexts.sync(_obs())
	_queue_refresh()


## Replay: watch as the next player in turn.
func view_next_player() -> void:
	var all := session.players()
	view_as(all[(all.find(player) + 1) % all.size()])


## What the mouse and keys do in the present context, in one line.
func hints() -> String:
	if not _play.is_empty():
		if contexts.focus == ViewContexts.OVERWORLD:
			return "Turn %d is playing out.  Space or Esc: skip to the end  ·  click a commander or a hex: inspect it  ·  wheel: zoom  ·  routes and orders: %s" % [int(_play["turn"]), PLANNING_ONLY_NOTE]
		return "Turn %d is playing out.  Space or Esc: skip to the end  ·  click a squad: its card" % int(_play["turn"])
	if replay != null:
		var where := "the recording has ended" if replay.at_end() else "turn %d of %d" % [session.turns_resolved() + 1, replay.turns()]
		var odd := "" if replay.diverged_turn < 0 else "  ·  WARNING: turn %d did not match the recording" % replay.diverged_turn
		return "Replay, watching %s (%s)%s  ·  Space: next turn  ·  V: the other side  ·  Tab: go to a battle  ·  click a squad, a commander or a hex to inspect it" % ["with no fog" if player == 0 else "as player %d" % player, where, odd]
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
	if deploying_now(pl) and not pl.deploying and not _attack_armed:
		if pl.selection.is_empty():
			return ARRIVAL_HINT
		if not pl.selection.filter(pl.can_place).is_empty():
			return "Arrival: drag a selected arriving squad to place the group (offsets kept)  ·  Drag the knob or E / Shift+E: turn (8 directions)  ·  Arrows or left stick: nudge  ·  Arriving squads take orders after the Reveal  ·  Space: end turn"
	elif deploying_now(pl) and not _attack_armed:
		if pl.selection.is_empty():
			return "Deployment: drag one of your squads inside your lit area to place it  ·  Left click or drag a box: select squads  ·  Turn-1 orders work as in Planning  ·  Space: end turn (squads you leave keep their automatic places)"
		return "Deployment: drag a selected squad to place the group (offsets kept)  ·  Drag the knob or E / Shift+E: turn (8 directions)  ·  Arrows or left stick: nudge  ·  Right click: turn-1 move  ·  Space: end turn"
	if _attack_armed:
		return "ATTACK-MOVE: right click where to go; the squads fight what they meet"
	if pl != null and not pl.selection.is_empty():
		return "Right click: move  ·  Right click an enemy: attack  ·  Alt+right click: new line  ·  H hold  ·  A attack-move  ·  B fall back  ·  R run  ·  Ctrl+1-9: make a group  ·  Space: end turn"
	return "Left click or drag: select squads  ·  Click any squad: its card  ·  Wheel: zoom  ·  Middle drag or arrows: pan  ·  Tab: next battle  ·  Esc: overworld  ·  Space: end turn"


## Reach, movement points and the hovered route for the selected commander.
func _overworld_extra() -> Dictionary:
	var did := _own_detachment()
	if did >= 0 and session.clock.phase == PulseClock.Phase.PLANNING:
		var cr := session.convoy_reach(player, did)
		var dx := {"reach": cr.get("reach", {}), "budget": cr.get("budget", 0), "spent": 0}
		var at: int = session.state.detachments.get_value(did, &"plot")
		if _hover_plot >= 0 and _hover_plot != at and not cr.is_empty():
			var via := _convoy_route_of(did) if _route_via_held() else PackedInt64Array()
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
		var via := _route_of(cid) if _route_via_held() else PackedInt64Array()
		var path := session.path(player, cid, _hover_plot, via)
		var costs := 0
		var known: Dictionary = reach["reach"]
		var obs_costs := _obs()
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
	return (_obs().get("routes", {}) as Dictionary).get(cid, PackedInt64Array())


func _on_hex_hovered(p: int) -> void:
	_hover_plot = p
	_refresh_hover_card()
	if _play.is_empty() and contexts.focus == ViewContexts.OVERWORLD and (_own_selected() >= 0 or _own_detachment() >= 0):
		_show_main()


## The battle panel: the scores, the zones, and the squad card. During
## playback the card follows the shown moment (SquadCard.moment), not the
## end-of-turn state (sw-ll4.27.3).
func _refresh_battle_panel() -> void:
	var eid := contexts.focus
	if eid == ViewContexts.OVERWORLD or not session.battles.has(eid):
		return
	var id := card_squad()
	var r := _battle_rules(eid)
	var squad := _squad_obs(eid, id) if id >= 0 else {}
	var insp := session.inspect_battle(player, eid, id) if id >= 0 else {}
	if id >= 0 and not _play.is_empty():
		var rec: Dictionary = (_play["battles"] as Dictionary).get(eid, {})
		if not rec.is_empty():
			var m := SquadCard.moment(rec, float(_play["t"]), id, player, squad, insp)
			squad = m["squad"]
			insp = m["insp"]
			if r == null:
				r = rec["rules"]
	var ctx := {"rules": r, "weapon_names": _weapon_names(r), "glossary": glossary}
	var bobs := _obs_battle(eid)
	if id >= 0 and _play.is_empty() and int(squad.get("player", -1)) == player:
		for p: int in (bobs.get("scores", {}) as Dictionary):
			if p != player:  # what an opponent that can see this squad is shown (E2Q12)
				var theirs := session.inspect_battle(p, eid, id)
				if not theirs.is_empty():
					ctx["opponent_insp"] = theirs
				break
	_battle_box.show_battle(battle_name(eid), bobs, squad, insp, player,
		r.tps if r != null else 10, false, ctx)


## Weapon display names from the content packages (the rules carry only
## IDs): weapon ID -> name, for the squad card's weapon block.
func _weapon_names(r: BattleRules) -> Dictionary:
	var out := {}
	if r == null:
		return out
	for wid: String in r.weapon_index:
		out[wid] = String(session.templates.values_of(wid).get("name", wid))
	return out


## The squad under the cursor changed: its card shows (planning, and during
## playback too, where the card is for the shown moment). The view emits only
## on a change; a repeat of the same id is ignored (sw-bafi.1).
func _on_squad_hovered(id: int) -> void:
	if id == _hovered:
		return
	_hovered = id
	_refresh_battle_panel()


## The card for the hex under the cursor: what the player knows is there
## (HexCard, from inspect_plot). Hidden over unknown ground, in battles and
## during playback.
func _refresh_hover_card() -> void:
	_clear(_hover_card)
	if ui == null:
		return
	_sync_ui_context()
	# Overworld playback too: the hex shows what the player knows now (sw-bafi.9).
	var over := ui.context == &"overworld" or (ui.context == &"playback" and contexts.focus == ViewContexts.OVERWORLD)
	var info := session.inspect_plot(player, _hover_plot) if _hover_plot >= 0 and over else {}
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
	for sq: Dictionary in _obs_battle(eid).get("squads", []):
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
	if session.state.outcome.is_empty() and deploying_now(_focused_planner()):
		_phase_banner.visible = true
		_phase_text.text = DEPLOY_BANNER if _focused_planner().deploying else ARRIVAL_BANNER
		return
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
		var sum := session.battle_summary(player, eid)
		pip.view.title = battle_name(eid) + ("" if sum.is_empty() else " · " + EventText.battle_summary(sum))
		pip.view.show_battle(_obs_battle(eid), {"terrain": _battle_rules(eid)})


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
		var sum := session.battle_summary(player, m["engagement"])
		if not sum.is_empty():
			var l := _title(EventText.battle_summary(sum))
			l.theme_type_variation = &"SmallAccentLabel"
			l.tooltip_text = "Worst SIMPL band across your squads in this battle: %s (%s, squad %d).\nThe trend compares with the last recorded turn%s." % [
				EventText.band_word(String(sum["band"])), EventText.pool_word(String(sum["pool"])), int(sum["squad"]) & 0xffff,
				"" if String(sum["prev_band"]).is_empty() else " (was %s)" % EventText.band_word(String(sum["prev_band"]))]
			_menu.add_child(l)
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


## Each of the player's battles' glance summary (battle_summary), for the
## overworld's battle tiles.
func _battle_summaries() -> Dictionary:
	var out := {}
	for eid: int in contexts.battles():
		var sum := session.battle_summary(player, eid)
		if not sum.is_empty():
			out[eid] = sum
	return out


func _refresh_commanders() -> void:
	_clear(_cmds)
	for cmd: Dictionary in _obs().get("commanders", []):
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
	if not _play.is_empty():
		# Playback: a left click selects to inspect (the panels show it with
		# their actions disabled); a right click would plan, so it is refused
		# with the reason (sw-bafi.9 U1 C8).
		_target = {}
		if button == MOUSE_BUTTON_LEFT and p >= 0:
			_select_at(p)
		elif button == MOUSE_BUTTON_RIGHT:
			_refused_in_playback()
		return
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
	if p >= 0:
		_select_at(p)


## A left click on hex p: a commander first; clicking its hex again selects
## the garrison or convoy there (sw-kys.8); else the hex.
func _select_at(p: int) -> void:
	var obs := _obs()
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
		for cmd: Dictionary in _obs().get("commanders", []):
			if cmd["plot"] == p and cmd["player"] == player:
				rally(did, -1, int(cmd["id"]), "convoy %d" % (did & 0xffff))
				return ""
	return steer_to(p, shift)


## Routes the selected detachment to a hex (the whole way, over as many
## turns as it takes). With `append`, the hex is a waypoint after its
## route. "" or why not.
func steer_to(p: int, append: bool = false) -> String:
	if _refused_in_playback():
		return PLANNING_ONLY_NOTE
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
	if _refused_in_playback():
		return PLANNING_ONLY_NOTE
	var did := _own_detachment()
	if did < 0:
		return "no convoy selected"
	_hud_note = session.set_convoy_route(player, did, PackedInt64Array())
	_note("convoy %d halted%s" % [did & 0xffff, "" if _hud_note.is_empty() else " - refused: " + _hud_note])
	_queue_refresh()
	return _hud_note


func _convoy_route_of(did: int) -> PackedInt64Array:
	return (_obs().get("convoy_routes", {}) as Dictionary).get(did, PackedInt64Array())


# --- planning ------------------------------------------------------------------

## The planner for one of the player's battles (made on first use).
func planner(eid: int) -> BattlePlanner:
	if not planners.has(eid):
		var pl := BattlePlanner.new(player)
		pl.rules = _battle_rules(eid)
		pl.sync(_obs_battle(eid))
		pl.changed.connect(_on_draft.bind(eid))
		pl.deploy_changed.connect(_on_deploy.bind(eid))
		pl.selection_changed.connect(_on_selection.bind(eid))
		planners[eid] = pl
	return planners[eid]


## The selection changed. In Planning it goes through the drafts as it always
## has (submit and forecast, which keeps the forecast warm); elsewhere it only
## redraws, so a selection never queues orders (sw-bafi.2).
func _on_selection(eid: int) -> void:
	if _play.is_empty() and session.clock.phase == PulseClock.Phase.PLANNING:
		_on_draft(eid)
	else:
		_queue_refresh()


## Drafts changed: submit them and refresh the forecast. Outside Planning
## the game takes no orders: the drafts are kept, marked pending, and sent
## when Planning returns (sw-ip8.7).
func _on_draft(eid: int) -> void:
	if not session.battles.has(eid):
		return
	if _obs_battle(eid).get("arrival", false):
		_queue_refresh()  # a joiner gives no orders before Reveal, only placements
		return
	var orders: Array = planner(eid).orders()
	if session.clock.phase == PulseClock.Phase.PLANNING:
		_pending.erase(eid)
		var errs := session.submit_battle_orders(player, eid, orders)
		_forecast(eid, orders)
		_note("%s orders: %s%s" % [battle_name(eid), _orders_text(orders), "" if errs.is_empty() else " - refused: " + "; ".join(errs)])
	else:
		_pending[eid] = true
		_hud_note = "moves are locked until Planning: your drawn orders are queued"
		_note("%s orders drawn in the %s phase (queued for Planning): %s" % [battle_name(eid), session.phase_name(), _orders_text(orders)])
	_queue_refresh()


## Whether the player can place squads in the focused battle now: Planning
## of a deploying battle with an own area, not watching a replay or playback.
func deploying_now(pl: BattlePlanner) -> bool:
	return pl != null and pl.can_deploy() and replay == null and _play.is_empty() 		and session.clock.phase == PulseClock.Phase.PLANNING


## The battle view's deployment overlay ({} unless deploying_now).
func _deploy_overlay(pl: BattlePlanner) -> Dictionary:
	if not deploying_now(pl):
		return {}
	return {"player": player, "areas": pl.areas, "own": pl.placeable(), "snap": pl.snap}


## Deployment placements changed: submit them. Battle squads' placements go
## through submit_battle_deployment while the battle deploys, arriving
## squads' through submit_arrival (their only ways to the game). The draft
## stays in the planner either way.
func _on_deploy(eid: int) -> void:
	var pl: BattlePlanner = planners.get(eid)
	if pl == null or not session.battles.has(eid) or session.clock.phase != PulseClock.Phase.PLANNING:
		return
	var errs := PackedStringArray()
	var parts := PackedStringArray()
	if pl.deploying and pl.area.size != Vector2.ZERO:
		var placements := pl.deployment()
		var e := session.submit_battle_deployment(player, eid, placements)
		errs.append_array(e)
		parts.append("deployment: %s%s" % [_placements_text(placements), "" if e.is_empty() else " - refused: " + "; ".join(e)])
	if pl.arrival_area.size != Vector2.ZERO:
		var placements := _arrival_placements(pl.arrival())
		var e := session.submit_arrival(player, eid, placements)
		errs.append_array(e)
		parts.append("arrival: %s%s" % [_placements_text(placements), "" if e.is_empty() else " - refused: " + "; ".join(e)])
	if not _obs_battle(eid).get("arrival", false):
		_forecast(eid, pl.orders())  # the ghosts start from the placed squads (sw-bafi.17)
	_hud_note = "" if errs.is_empty() else "placement refused: " + "; ".join(errs)
	_note("%s %s" % [battle_name(eid), "; ".join(parts)])
	_queue_refresh()


func _placements_text(placements: Array) -> String:
	if placements.is_empty():
		return "automatic"
	var parts := PackedStringArray()
	for d: Dictionary in placements:
		parts.append("squad %d at (%.0f, %.0f) facing %d°" % [int(d["squad"]) & 0xffff, float(d["x"]) / ContextView.ONE,
			float(d["y"]) / ContextView.ONE, roundi(float(d["facing"]) / Fixed.ANGLE_FULL * 360.0)])
	return ", ".join(parts)


## A squad (or the selected group) dragged in the battle view while deploying.
func _on_deploy_dragged(ids: Array, anchor: int, delta: Vector2) -> void:
	var pl := _focused_planner()
	if deploying_now(pl):
		pl.drag(ids, anchor, delta)


## The facing handle dragged while deploying.
func _on_deploy_faced(ids: Array, toward: Vector2) -> void:
	var pl := _focused_planner()
	if deploying_now(pl):
		pl.face(ids, toward)


## "Reset to automatic": the focused battle's placements dropped.
func reset_deployment() -> void:
	var pl := _focused_planner()
	if deploying_now(pl):
		pl.reset_deployment()


## Forecasts a battle's drafts on a worker thread; the ghosts show when it
## is done. A forecast already running for the battle runs once more
## afterwards, with the drafts as they are then.
func _forecast(eid: int, orders: Array) -> void:
	if not threaded_forecasts:
		_forecasts[eid] = session.forecast_battle(player, eid, orders)
		return
	if _forecast_jobs.has(eid):
		_forecast_jobs[eid]["again"] = true
		return
	PerfRecorder.begin(&"forecast_snapshot")
	var job := session.forecast_job(player, eid, orders)
	PerfRecorder.end(&"forecast_snapshot")
	if not job.is_valid():
		_forecasts.erase(eid)
		return
	_forecast_token += 1
	var token := _forecast_token
	var out := {}
	var task := WorkerThreadPool.add_task(func() -> void:
		out["result"] = job.call()
		_forecast_done.call_deferred(eid, token), false, "intent forecast")
	_forecast_jobs[eid] = {"task": task, "token": token, "out": out, "again": false}


## A forecast finished: its ghosts show, and if the drafts changed while it
## ran, the battle is forecast again.
func _forecast_done(eid: int, token: int) -> void:
	var j: Dictionary = _forecast_jobs.get(eid, {})
	if j.is_empty() or j["token"] != token:
		return  # already collected by wait_forecasts
	_forecast_jobs.erase(eid)
	WorkerThreadPool.wait_for_task_completion(j["task"])
	if not session.battles.has(eid) or session.clock.phase != PulseClock.Phase.PLANNING:
		return
	_forecasts[eid] = j["out"].get("result", {})
	if j["again"] and planners.has(eid):
		_forecast(eid, (planners[eid] as BattlePlanner).orders())
	_show_main()


## Waits for every running forecast and keeps its result. The turn must not
## resolve while one runs, and tests use it to see the ghosts at once.
func wait_forecasts() -> void:
	for eid: int in _forecast_jobs.keys():
		var j: Dictionary = _forecast_jobs[eid]
		_forecast_jobs.erase(eid)
		WorkerThreadPool.wait_for_task_completion(j["task"])
		if session != null and session.battles.has(eid) and session.clock.phase == PulseClock.Phase.PLANNING:
			_forecasts[eid] = j["out"].get("result", {})


## A new turn: forecasts and reactions start over; drafts too, except
## those queued while orders were locked.
func _new_turn() -> void:
	_obs_cache = {}
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
	if not _play.is_empty():
		# Playback: selection and inspection, never orders (sw-bafi.2). The
		# card is for the moment shown, so it is built now (sw-bafi.1).
		if button == MOUSE_BUTTON_LEFT:
			_playback_click(pl, hit, shift, ctrl)
		else:
			_refuse_orders()
		_refresh_battle_panel()
		return
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
	if pl == null:
		return
	if not _play.is_empty():
		# Playback: the squads drawn inside the box (their metres are the
		# moment's, not the planner's last Planning).
		pl.select(_main.squads_in(rect), add)
	elif session.clock.phase == PulseClock.Phase.PLANNING:
		pl.select_box(rect, add)


## A left click on the battlefield during playback selects like Planning does:
## an own squad (shift adds, ctrl toggles), empty ground clears (sw-bafi.2).
func _playback_click(pl: BattlePlanner, hit: int, shift: bool, ctrl: bool) -> void:
	if hit >= 0:
		if _selectable(pl).has(hit):
			pl.select([hit], shift, ctrl)
	elif not shift and not ctrl:
		pl.deselect()


## The own squads a selection may take now. In playback, only those drawn at
## the moment shown: a squad that died this turn stays in the planner's list
## until the next Planning (sw-bafi.2).
func _selectable(pl: BattlePlanner) -> Array[int]:
	if _play.is_empty():
		return pl.own_squads()
	var drawn := _main.drawn_ids()
	var out: Array[int] = []
	for id: int in pl.own_squads():
		if drawn.has(id):
			out.append(id)
	return out


## An order action during playback is refused, with the reason shown in the
## status line (sw-bafi.2).
func _refuse_orders() -> void:
	_hud_note = ORDERS_LOCKED_NOTE
	_queue_refresh()


## A planning or activity action (route, rally, supply line, battleforce,
## activity, pick-up, reaction, reinforcement) while a turn plays out: it is
## refused, with the reason in the status line (sw-bafi.9 U1 C8). True if
## refused; nothing in the session or the drafts changes.
func _refused_in_playback() -> bool:
	if _play.is_empty():
		return false
	_hud_note = PLANNING_ONLY_NOTE
	_queue_refresh()
	return true


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
	if pl == null:
		return
	if name == &"recall_group":
		pl.recall_group(arg)  # a selection, not an order: any time (sw-bafi.2)
		return
	if not _play.is_empty():
		_refuse_orders()
		return
	if session.clock.phase != PulseClock.Phase.PLANNING:
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
		&"rotate", &"rotate_back":
			if deploying_now(pl):
				pl.rotate(pl.selection, arg)
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
	var panel := UiPanel.build("reserves", reserves_model(eid))
	panel.action_invoked.connect(_on_panel_action)
	_orders_box.add_child(panel)


## The reserves panel's view model (read-only): per commander a title and a
## row per squad with its text, whether it is disabled and the ids to send.
func reserves_model(eid: int) -> Dictionary:
	var groups := []
	for g: Dictionary in session.reserves(player, eid):
		var cid: int = g["commander"]
		var open: int = g["open"]
		var squads := []
		for q: Dictionary in g["squads"]:
			var what := "%s  %d/%d" % [EventText.squad_name(session.rules.squad_ids[int(q["tmpl"])]), int(q["alive"]), int(q["size"])]
			var why := String(q["why"])
			var text := "%s: %s" % [what, why]
			if q["sent"]:
				text = "✓ %s: joins next battle turn" % what
			elif why.is_empty():
				text = "Send in %s" % what
			squads.append({"text": text, "disabled": q["sent"] or not why.is_empty(), "commander": cid, "squad": int(q["squad"])})
		groups.append({"title": "%s: reserves (%s)" % [EventText.commander(cid),
			"battleforce full" if open == 0 else "room for %d more" % open], "squads": squads})
	return {"groups": groups}


## Actions by id from data-driven panels.
func _on_panel_action(action: String, args: Array) -> void:
	if action == "send_reserve":
		send_reserve(int(args[0]), int(args[1]))


## Sends a squad from the commander's army into its battle.
func send_reserve(cid: int, squad: int) -> String:
	if _refused_in_playback():
		return PLANNING_ONLY_NOTE
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
	if deploying_now(pl):
		var what := "Deployment" if pl.deploying else "Arrival"
		_orders_box.add_child(_title("%s (%d placed)" % [what, pl.placements.size()]))
		var reset := Button.new()
		reset.name = "ResetDeployment"
		reset.text = "Reset to automatic"
		reset.tooltip_text = "Put every squad back in its automatic place in your %s area" % what.to_lower()
		reset.disabled = pl.placements.is_empty()
		reset.pressed.connect(reset_deployment)
		_orders_box.add_child(reset)
	_orders_box.add_child(_title("Orders (%d selected)" % pl.selection.size()))
	if pl.selection.is_empty():
		return
	var row := HFlowContainer.new()
	for c: Array in [["Hold (H)", &"hold"], ["Attack-move (A)", &"attack_move"], ["Fall back (B)", &"fall_back"],
			["Withdraw (⇧W)", &"withdraw"], ["Run (R)", &"run"]]:
		var b := Button.new()
		b.text = c[0]
		b.tooltip_text = OrderTips.tip(String(c[1]))
		b.pressed.connect(_on_command.bind(c[1], 0))
		row.add_child(b)
	_orders_box.add_child(row)
	var menu := pl.ability_menu()
	if menu.is_empty():
		return
	var abt := _title("Abilities (Q)")
	abt.tooltip_text = OrderTips.tip("abilities")
	_orders_box.add_child(abt)
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
	for sq: Dictionary in _obs_battle(eid).get("squads", []):
		if sq["id"] == squad:
			return sq
	return {}


func _on_reaction_chosen(r: String) -> void:
	_react(_radial_opp, r)


func _react(o: Dictionary, r: String) -> void:
	if o.is_empty() or _refused_in_playback():
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
			if not _play.is_empty():
				b.disabled = true
				b.tooltip_text = PLANNING_ONLY_NOTE
			b.pressed.connect(_react.bind(o, r))
			row.add_child(b)
		line.add_child(row)
		_reactions_box.add_child(line)


func _jump_to_reaction(o: Dictionary) -> void:
	contexts.focus_battle(o["engagement"])
	planner(o["engagement"]).select([o["squad"]])
	_open_radial.call_deferred(o["engagement"], o["squad"])


## Standard button semantics win while a control has focus (sw-hk0): Tab and
## Shift+Tab walk the controls, Space and Enter press the focused button, and
## the Tab / Space hotkeys stand down (_hotkey_free). Any other war-room key
## first drops a button's focus, so the hotkey acts as it always did.
func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_TAB, KEY_SPACE]:
		return
	var owner := get_viewport().gui_get_focus_owner()
	if not owner is BaseButton:
		return
	# A window that keeps the keys (options, dialogs) keeps its focus too.
	var n: Node = owner
	while n != null and n != self:
		if n is UiWindow and (n as UiWindow).captures_keys:
			return
		n = n.get_parent()
	owner.release_focus()


## Arrow keys: how far one press (or key repeat) pans the battle camera.
const PAN_STEP: float = 60.0

## The phase banner while the focused battle deploys (sw-bafi.12).
const DEPLOY_BANNER: String = "Deployment: place your squads; the enemy can't see them until Reveal"
## The banner while only arriving squads can be placed (sw-bafi.19).
const ARRIVAL_BANNER: String = "Arrival: place your arriving squads in your arrival area; they enter the battle at the Reveal"
const ARRIVAL_HINT: String = "Arrival: drag an arriving squad inside your lit arrival area to place it  ·  Left click or drag a box: select squads  ·  Space: end turn (squads you leave arrive at their automatic places)"
## Display IDs of arriving squads in the battle view: this plus the overworld
## squad ID, above any battle squad ID (_merge_arrival).
const ARRIVAL_BASE: int = 1 << 48

## The status line's reason when an order is asked for during playback (sw-bafi.2).
const ORDERS_LOCKED_NOTE: String = "Orders open in Planning"

## The reason on every overworld planning or activity control while a turn
## plays out (disabled buttons' tooltips, refused actions; sw-bafi.9).
const PLANNING_ONLY_NOTE: String = "Available in Planning"

## The war room's GUIDE actions (DefaultKeys.war_room), enabled while it is
## in the tree. Name -> GUIDEAction is `keys.actions`.
var keys: GuideKeys


func _bind_keys() -> void:
	keys = DefaultKeys.war_room()
	for dir: Array in [[&"pan_left", Vector2.LEFT], [&"pan_right", Vector2.RIGHT], [&"pan_up", Vector2.UP], [&"pan_down", Vector2.DOWN]]:
		keys.on(dir[0], _on_pan.bind(dir[1]))
	keys.on(&"next_battle", func() -> void: _hotkey_free(func() -> void: contexts.cycle(1)))
	keys.on(&"previous_battle", func() -> void: _hotkey_free(func() -> void: contexts.cycle(-1)))
	keys.on(&"focus_controls", _focus_first_control)
	keys.on(&"cancel", func() -> void: _key_command(_on_cancel_key))
	keys.on(&"follow", func() -> void: _key_command(contexts.follow))
	keys.on(&"next_player", func() -> void: _key_command(_on_next_player_key))
	keys.on(&"deselect_all", func() -> void: _key_command(contexts.deselect_all))
	keys.on(&"end_turn", func() -> void: _hotkey_free(_on_end_turn_key))
	keys.on(&"zoom_in", func() -> void: _key_command(func() -> void: contexts.zoom_by(1.25)))
	keys.on(&"zoom_out", func() -> void: _key_command(func() -> void: contexts.zoom_by(0.8)))
	keys.on(&"next_squad", func() -> void: _hotkey_free(_cycle_squad.bind(1)))
	keys.on(&"previous_squad", func() -> void: _hotkey_free(_cycle_squad.bind(-1)))
	keys.on(&"inspect_squad", func() -> void: _hotkey_free(_toggle_inspect))
	keys.enable(self)


## A window that keeps the keys (options, dialogs) keeps them from the war room.
func _keys_free() -> bool:
	var w := ui.top() if ui != null else null
	return w == null or not w.captures_keys


func _key_command(fn: Callable) -> void:
	if contexts != null and _keys_free():
		fn.call()


## Hotkeys that share a key with GUI focus handling (Tab, Space): they only
## act while no button has the keyboard focus.
func _hotkey_free(fn: Callable) -> void:
	if not get_viewport().gui_get_focus_owner() is BaseButton:
		_key_command(fn)


## F6: put the keyboard focus on the first visible button, so Tab can walk
## the controls (with no focus, Tab cycles battles instead).
func _focus_first_control() -> void:
	if not _keys_free():
		return
	var queue: Array[Node] = [self]
	while not queue.is_empty():
		var n: Node = queue.pop_front()
		var c := n as Control
		if c is BaseButton and c.is_visible_in_tree() and c.focus_mode == Control.FOCUS_ALL and not (c as BaseButton).disabled:
			c.grab_focus()
			return
		queue.append_array(n.get_children())


func _on_pan(dir: Vector2) -> void:
	if contexts == null or not _keys_free() or contexts.focus == ViewContexts.OVERWORLD:
		return
	# Deploying with squads selected: the arrows and the left stick nudge
	# them instead (pad placement until sw-wut).
	var pl := _focused_planner()
	if deploying_now(pl) and not pl.selection.filter(pl.can_place).is_empty():
		pl.nudge(dir)
		return
	_main.pan_camera(dir * PAN_STEP)


## Gamepad / key squad selection (sw-dqq): steps through the focused
## battle's own squads, selects the one reached and shows its card. Selection
## works in playback too (sw-bafi.2), over the squads drawn at the moment shown.
func _cycle_squad(dir: int) -> void:
	var pl := _focused_planner()
	if pl == null:
		return
	var ids := _selectable(pl)
	if ids.is_empty():
		return
	var cur: int = _inspected if ids.has(_inspected) else (pl.selection[0] if not pl.selection.is_empty() else -1)
	var i := ids.find(cur)
	var next: int = ids[posmod(i + dir, ids.size())] if i >= 0 else ids[0 if dir > 0 else ids.size() - 1]
	_inspected = next
	if not _play.is_empty() or session.clock.phase in [PulseClock.Phase.PLANNING, PulseClock.Phase.REACTION]:
		pl.select([next])
	_queue_refresh()


## The card button: shows the selected squad's card, or hides it again.
func _toggle_inspect() -> void:
	var pl := _focused_planner()
	if pl == null:
		return
	if _inspected >= 0:
		_inspected = -1
	elif not pl.selection.is_empty():
		_inspected = pl.selection[0]
	_queue_refresh()


func _on_cancel_key() -> void:
	if not _target.is_empty():
		_target = {}
		_queue_refresh()
	elif not _play.is_empty():
		skip_playback()
	else:
		contexts.exit()


func _on_next_player_key() -> void:
	if replay != null:
		view_next_player()


func _on_end_turn_key() -> void:
	if not _play.is_empty():
		skip_playback()
	else:
		end_turn_requested.emit()


## Whether the "route via" modifier (Shift by default) is held.
func _route_via_held() -> bool:
	return keys != null and (keys.actions[&"route_via"] as GUIDEAction).value_bool


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
	if _refused_in_playback():
		return PLANNING_ONLY_NOTE
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
	if _refused_in_playback():
		return PLANNING_ONLY_NOTE
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
	if _refused_in_playback():
		return PLANNING_ONLY_NOTE
	_hud_note = session.rally(player, detachment, to_plot, to_commander)
	_note("send %s to %s%s" % [what, _dest_text(to_plot, to_commander), "" if _hud_note.is_empty() else " - refused: " + _hud_note])
	_queue_refresh()
	return _hud_note


## Sends a producing feature's output to a plot or a commander (both -1
## clears the line). "" or why not.
func supply_line(feature: int, to_plot: int, to_commander: int, what: String) -> String:
	if _refused_in_playback():
		return PLANNING_ONLY_NOTE
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
	if _refused_in_playback():
		return
	_target = {"kind": kind, "id": id, "what": what}
	_hud_note = ""
	_queue_refresh()


## Sends the armed detachment or supply line to plot p, or to the player's
## commander standing on it. "" or why not.
func send_to(p: int) -> String:
	if _refused_in_playback():
		return PLANNING_ONLY_NOTE
	if _target.is_empty():
		return "nothing to send"
	var cid := -1
	for cmd: Dictionary in _obs().get("commanders", []):
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
	if _refused_in_playback():
		return PLANNING_ONLY_NOTE
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
	if _refused_in_playback():
		return PLANNING_ONLY_NOTE
	var cid := _own_selected()
	if cid < 0:
		return "no commander selected"
	var err := session.set_activity(player, cid, activity, option)
	_hud_note = err
	_note("%s: %s%s" % [EventText.commander(cid), "activity cleared" if activity.is_empty() else "%s %s" % [activity, option.replace("_", " ")],
		"" if err.is_empty() else " - refused: " + err])
	_queue_refresh()
	return err


## Battle start/end and losses go to the persistent alert panel (sw-9un).
func _alert_from(e: Dictionary, d: Dictionary, line: String) -> void:
	var kind := ""
	match StringName(e["type"]):
		&"battle_started":
			kind = "start"
		&"battle_resolved":
			kind = "end"
		&"squads_lost", &"commander_defeated":
			kind = "alert"
	if kind.is_empty():
		return
	var eid := int(d.get("engagement", -1))
	_alerts.add(kind, line, eid, _log_turn, contexts.focus == eid)


## The event feed (sw-ip8.7): what this player saw happen each turn
## (EventText), trigger messages, and the mission's outcome.
func _refresh_log() -> void:
	if session.turns_resolved() != _log_turn:
		_log_turn = session.turns_resolved()
		var obs := _obs()
		for e: Dictionary in obs.get("events", []):
			var d: Dictionary = e["data"] if e.has("data") else e
			if e["type"] == &"dialogue_started":
				if int(d.get("player", 0)) in [0, player]:
					queue_dialogue(String(d.get("dialogue", "")))
			elif e["type"] in [&"trigger_message", &"mission_ended"]:
				messages.append(_say(String(d.get("key", "")), String(d.get("text", ""))))
			elif EventText.in_feed(e["type"]):
				_name_feature(d, obs)
				var line := EventText.describe(e, session.rules, player)
				if not line.is_empty():
					messages.append("T%d · %s" % [_log_turn, line])
					_alert_from(e, d, line)
	var log_key := hash(messages)
	if log_key != _log_key or _log_box.get_child_count() == 0 and not messages.is_empty():
		_log_key = log_key
		_clear(_log_box)
		if not messages.is_empty():
			_log_box.add_child(_title("Events"))
			for i in range(messages.size() - 1, maxi(messages.size() - 14, 0) - 1, -1):
				var l := _title(messages[i])
				l.theme_type_variation = &""
				_log_box.add_child(l)
	var outcome: Dictionary = _obs().get("outcome", {})
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


## Saves the game to a slot (MatchDriver.save_game; a blank name makes one
## from the map and the turn). Returns the path or "".
func save_game(slot: String = "") -> String:
	if replay != null:
		_hud_note = "a replay can't be saved"
		_queue_refresh()
		return ""
	var path := driver.save_game(slot.strip_edges())
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
	if _refused_in_playback():
		return PLANNING_ONLY_NOTE
	var cid := _own_selected()
	if cid < 0:
		return "no commander selected"
	var err := ""
	var n := 0
	for det: Dictionary in _obs().get("detachments", []):
		if int(det["id"]) == detachment_id:
			for q: Dictionary in det.get("squads", []):
				err = session.transfer_squad(player, int(q["id"]), cid)
				if not err.is_empty():
					break
				n += 1
	_hud_note = err
	_note("pick up: %s took %d squad%s%s" % [EventText.commander(cid), n, "" if n == 1 else "s", "" if err.is_empty() else " - stopped: " + err])
	contexts.sync(_obs())
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
	wait_forecasts()
	_hud_note = ""
	_target = {}
	_note("end turn (%s)" % session.phase_name())
	var before := session.observe(player)
	var resolved := session.turns_resolved()
	# A recording keeps its turns for the relations at a frame (sw-bafi.5).
	session.keep_playback = turn_time() > 0.0 or replay != null
	var played := false
	if replay != null:
		played = replay.step()
		if played:
			driver.tally(session.last_events)
		else:
			auto_play = false
			_hud_note = "the recording has ended"
	else:
		PerfRecorder.begin(&"end_turn_driver")
		played = driver.end_turn()
		PerfRecorder.end(&"end_turn_driver")
		PerfRecorder.mark("turn %d resolved=%s" % [session.turns_resolved(), played])
	if session.turns_resolved() != _turn_seen:
		_new_turn()
	_flush_pending()
	if played and turn_time() > 0.0:
		_start_play(before, resolved + 1)
		return
	contexts.sync(_obs())
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
	_play_card_frame = -1
	_radial.hide()
	_refresh_hover_card()
	_refresh_battle_panel()  # the card shows the turn being played, not the last planning
	_refresh_playback_side()  # the side lists lock at once (sw-bafi.9)
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
	PerfRecorder.set_context("playback_overworld" if contexts.focus == ViewContexts.OVERWORLD else "playback_battle")
	var t: float = _play["t"]
	var battles: Dictionary = _play["battles"]
	var eid := contexts.focus
	if eid == ViewContexts.OVERWORLD:
		_main.show_overworld(_play["obs"], session.rules.feature_ids, contexts, {"play": _play["walks"], "t": t})
	elif battles.has(eid):
		_main.title = battle_name(eid)
		_main.set_camera(contexts.zoom, contexts.battle_centre)
		var selected: Array = (planners[eid] as BattlePlanner).selection if planners.has(eid) else []
		_main.show_playback(battles[eid], t, _obs_battle(eid), _inspected, selected)
		# The squad card follows the shown moment: rebuild it when the frame
		# changes, not on every draw (sw-ll4.27.3).
		var frames: Array = (battles[eid] as Dictionary).get("frames", [])
		var last := maxi(frames.size() - 1, 0)
		var fi := mini(int(t * last), last)
		if fi != _play_card_frame:
			_play_card_frame = fi
			if card_squad() >= 0:
				_refresh_battle_panel()
	for pip in _pip_layer.get_children():
		if pip is PipPanel and battles.has((pip as PipPanel).engagement):
			var e := (pip as PipPanel).engagement
			(pip as PipPanel).view.show_playback(battles[e], t, _obs_battle(e))
	_phase_banner.show()
	_phase_text.text = "Turn %d is playing out (%d%%).  Space or Esc to skip." % [int(_play["turn"]), int(t * 100.0)]
	_refresh_hud()


## Ends the playback: the view shows the present again.
func skip_playback() -> void:
	if _play.is_empty():
		return
	_play = {}
	_play_card_frame = -1
	if _hud_note in [ORDERS_LOCKED_NOTE, PLANNING_ONLY_NOTE]:
		_hud_note = ""  # the refusal was for playback; Planning takes orders again
	_refresh_hover_card()
	set_process(false)
	contexts.sync(_obs())
	_queue_refresh()
	if auto_play and replay != null and not replay.at_end():
		end_turn_requested.emit.call_deferred()


