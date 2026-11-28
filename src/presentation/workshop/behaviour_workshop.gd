class_name BehaviourWorkshop
extends Control
## The behaviour workshop (sw-tho3.8, U1 B8, GDD 04 §4.9, GDD 05 §5.7): steps
## through one workshop scenario's variant to show why units do what they
## do. Runs standalone (F6, `hx godot run`).
##
## It plays a WorkshopRun recorded with debug frames: ContextView.show_playback
## (with BattleFx) of the whole run, the DebugOverlay (B6) over it, the
## scenario's probes (click one to seek to its tick and inspect its squad),
## and a SquadCard for the clicked squad, read by Inspection from the exact
## state at that frame (WorkshopRun.state_at: the turn's BattleCursor, B7).
## Presentation only: the run and its cursors are the API's; this keeps the
## playback position, the speed and which squad is inspected.
##
## Source, in order: the `scenario_path` export, `--scenario=<id or path>`
## (and `--variant=<name>`) after `--`, else the first file in
## data/sim/workshop. Keys (GUIDE, DefaultKeys.workshop): Space play/pause,
## +/- speed, comma/period a tick back/on, Left/Right a turn, Home the
## start, F5 reload the file; the slider scrubs, the wheel zooms.

## A frame was shown (after a seek or while playing): its index.
signal frame_shown(frame: int)

const SPEEDS: Array[float] = [0.25, 0.5, 1.0, 2.0, 4.0, 8.0]
## Probe result marks.
const MARK: Dictionary = {"pass": "✓", "fail": "✗", "report": "·", "error": "!"}

@export_file("*.json") var scenario_path: String = ""
@export var variant: String = WorkshopScenario.BASE

var playing: bool = false
var speed_index: int = 2
## Playback position in frames (presentation time; float for smooth play).
var position_frames: float = 0.0
## The squad whose card shows (-1 = none).
var inspected: int = -1
var run: WorkshopRun
## What went wrong loading ("" when the run plays).
var error: String = ""
var keys: GuideKeys

var view: ContextView
var overlay: DebugOverlay
var _rec: Dictionary = {}
var _obs: Dictionary = {}
var _paths: PackedStringArray = PackedStringArray()
var _scenario_pick: OptionButton
var _variant_pick: OptionButton
var _probes: ItemList
## Per probe row: the frame it seeks to and the squad key it measures.
var _probe_frames: PackedInt64Array = PackedInt64Array()
var _probe_squads: PackedStringArray = PackedStringArray()
var _slider: HSlider
var _hud: Label
var _card_box: VBoxContainer
var _layer_box: HFlowContainer
var _shown_frame: int = -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiTheme.ensure(get_window())
	_build_ui()
	var path := scenario_path
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario="):
			path = arg.substr(11)
		elif arg.begins_with("--variant="):
			variant = arg.substr(10)
	if not path.is_empty() and not path.ends_with(".json"):
		path = "%s/%s.json" % [WorkshopScenario.DIR, path]
	if path.is_empty() and not _paths.is_empty():
		path = _paths[0]
	_bind_keys()
	load_scenario(path, variant)


func _exit_tree() -> void:
	if keys != null:
		keys.disable(self)


func _bind_keys() -> void:
	keys = DefaultKeys.workshop()
	keys.on(&"replay_toggle", toggle_play)
	keys.on(&"replay_faster", func() -> void: speed_index = mini(speed_index + 1, SPEEDS.size() - 1); _show())
	keys.on(&"replay_slower", func() -> void: speed_index = maxi(speed_index - 1, 0); _show())
	keys.on(&"replay_next_turn", func() -> void: seek_turn(current_turn() + 1))
	keys.on(&"replay_prev_turn", func() -> void: seek_turn(current_turn() - 1))
	keys.on(&"replay_restart", func() -> void: seek_frame(0))
	keys.on(&"workshop_next_tick", func() -> void: step(1))
	keys.on(&"workshop_prev_tick", func() -> void: step(-1))
	keys.on(&"workshop_reload", reload)
	keys.enable(self)


# --- loading -----------------------------------------------------------------

## Runs `path`'s variant `variant_name` (base when it has none of that name)
## and shows its first frame, or `keep` frame when given (a reload).
func load_scenario(path: String, variant_name: String = WorkshopScenario.BASE, keep: int = 0) -> void:
	scenario_path = path
	run = null
	_rec = {}
	error = ""
	var sc := WorkshopScenario.load_file(path) if not path.is_empty() else null
	_select_path(path)
	_variant_pick.clear()
	if sc == null:
		error = "no workshop scenario to load"
	elif not sc.is_valid():
		error = "\n".join(sc.errors)
	else:
		var names := sc.variant_names()
		variant = variant_name if variant_name in names else WorkshopScenario.BASE
		for i in names.size():
			_variant_pick.add_item(names[i])
			if names[i] == variant:
				_variant_pick.select(i)
		run = WorkshopRun.execute(sc, variant, true, true)
		if not run.is_ok():
			error = "\n".join(run.errors)
		if run.frame_turn.is_empty():
			run = null
	if run != null:
		_rec = run.playback()
		_obs = BattleSession.observe_state(run.state, 0)
		view.terrain_colors = ContextView.feature_colors(WorkshopRun.loader_for(sc.package).templates)
		view.title = "%s · %s" % [sc.id, variant]
		_slider.max_value = maxi(run.frame_turn.size() - 1, 0)
	_fill_probes()
	playing = false
	if run != null and not inspected in run.sids.values():
		inspected = -1
	_shown_frame = -1
	seek_frame(keep)


## Re-reads the scenario file and runs it again, at the same frame (F5).
func reload() -> void:
	load_scenario(scenario_path, variant, current_frame())


func _select_path(path: String) -> void:
	for i in _paths.size():
		if _paths[i] == path:
			_scenario_pick.select(i)
			return
	_scenario_pick.select(-1)


# --- transport -----------------------------------------------------------------

func frame_count() -> int:
	return run.frame_turn.size() if run != null else 0


func current_frame() -> int:
	return int(position_frames)


func current_turn() -> int:
	return run.frame_turn[current_frame()] if run != null else 0


func toggle_play() -> void:
	if run == null:
		return
	if not playing and current_frame() >= frame_count() - 1:
		position_frames = 0.0
	playing = not playing
	_show()


func seek_frame(frame: int) -> void:
	position_frames = clampf(frame, 0, maxi(frame_count() - 1, 0))
	_show()


## A tick (frame) back or on; pauses.
func step(delta: int) -> void:
	playing = false
	seek_frame(current_frame() + delta)


## The first frame of `turn` (0 = the start), as the replay viewer seeks.
func seek_turn(turn: int) -> void:
	if run == null:
		return
	playing = false
	for f in frame_count():
		if run.frame_turn[f] >= turn:
			seek_frame(f)
			return
	seek_frame(frame_count() - 1)


func _process(delta: float) -> void:
	if not playing or run == null:
		return
	var last := float(frame_count() - 1)
	position_frames = minf(position_frames + delta * run.rules.tps * SPEEDS[speed_index], last)
	if position_frames >= last:
		playing = false
	_show()


# --- showing -------------------------------------------------------------------

func _show() -> void:
	if run == null:
		view.title = "Behaviour workshop"
		_hud.text = "Behaviour workshop: %s" % error
		_fill_card()
		return
	var f := current_frame()
	var n := frame_count()
	view.show_playback(_rec, position_frames / float(maxi(n - 1, 1)), _obs, inspected)
	overlay.show_frame(run.debug_frames.get(f, {}))
	_slider.set_value_no_signal(f)
	var k := run.frame_tick[f]
	var when := "start" if run.frame_turn[f] == 0 else ("turn %d resolved" % run.frame_turn[f] if k < 0 else "turn %d tick %d" % [run.frame_turn[f], k])
	var lines := PackedStringArray(["%s   frame %d/%d   %sx%s" % [when, f, n - 1, str(SPEEDS[speed_index]), "" if playing else "  (paused)"]])
	if not error.is_empty():
		lines.append(error)
	lines.append("Space play   +/- speed   , . tick   Left/Right turn   Home start   F5 reload   wheel zoom")
	_hud.text = "\n".join(lines)
	if f != _shown_frame:
		_shown_frame = f
		_fill_card()
		frame_shown.emit(f)


## Unit ID -> point (metres) the view shows at the current frame.
func shown_positions() -> Dictionary:
	var out := {}
	if _rec.is_empty():
		return out
	var frame: Dictionary = _rec["frames"][current_frame()]
	for sid: int in frame:
		var d: Dictionary = frame[sid]
		for j in (d["ids"] as Array).size():
			out[d["ids"][j]] = d["units"][j]
	return out


## Shows `squad`'s card (-1 hides it) and highlights it.
func inspect(squad: int) -> void:
	inspected = squad
	_shown_frame = -1
	_show()


func _fill_card() -> void:
	for c in _card_box.get_children():
		_card_box.remove_child(c)
		c.queue_free()
	if run == null or inspected < 0:
		_card_box.add_child(UiTheme.label("Click a squad to inspect it at this tick.", "SmallLabel", true))
		return
	var f := current_frame()
	var st := run.state_at(f)
	if st == null:
		_card_box.add_child(UiTheme.label("No exact state at this frame: %s" % run.cursor_reason(f), "SmallBadLabel", true))
		return
	var entry := {}
	for s: Dictionary in BattleSession.observe_state(st, 0)["squads"]:
		if int(s["id"]) == inspected:
			entry = s
	if entry.is_empty():
		_card_box.add_child(UiTheme.label("That squad is out of the battle at this tick.", "SmallLabel", true))
		return
	var insp := Inspection.squad(st, inspected, 0)
	_card_box.add_child(SquadCard.build(entry, insp, int(entry["player"]), st.rules.tps, true, {"rules": st.rules}))


func _fill_probes() -> void:
	_probes.clear()
	_probe_frames = PackedInt64Array()
	_probe_squads = PackedStringArray()
	if run == null:
		return
	for p: Dictionary in run.scenario.probes:
		var m := WorkshopProbes.measure(run, p)
		var applies: bool = variant in (p["variants"] as PackedStringArray) and p["expect"] != null
		var res := "report"
		if m["error"] != "":
			res = "error"
		elif applies:
			res = "pass" if WorkshopProbes.check(p["kind"], p["expect"], m["value"]) else "fail"
		var f := 0
		if p.has("at"):
			f = run.frame_at(p["at"]["turn"], p["at"]["tick"])
		else:
			var over := run.frames_over(p["over"])
			f = over[0] if not over.is_empty() else -1
		var value := JSON.stringify(WorkshopProbes.to_json(p["kind"], m["value"]))
		_probes.add_item("%s %s  %s %s = %s%s" % [MARK[res], p["id"], p["kind"], WorkshopReport._when(p), value,
			"  (pending)" if p["pending"] else ""])
		var row := _probes.item_count - 1
		_probes.set_item_tooltip(row, m["error"] if m["error"] != "" else String(p.get("doc", "")))
		_probe_frames.append(f)
		_probe_squads.append(p["squad"])


## Seeks to probe `row`'s tick (a window's first) and inspects its squad.
func pick_probe(row: int) -> void:
	if run == null or row < 0 or row >= _probe_frames.size():
		return
	playing = false
	inspected = int(run.sids.get(_probe_squads[row], -1))
	_shown_frame = -1
	if _probe_frames[row] >= 0:
		seek_frame(_probe_frames[row])
	else:
		_show()


func probe_count() -> int:
	return _probes.item_count


# --- layout --------------------------------------------------------------------

func _build_ui() -> void:
	var bg := UiTheme.backdrop("ScreenBackgroundPanel")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var split := HSplitContainer.new()
	split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	split.split_offset = 380
	add_child(split)
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(360, 0)
	split.add_child(side)
	side.add_child(UiTheme.label("Behaviour workshop", "CardHeadLabel"))
	_scenario_pick = OptionButton.new()
	_paths = WorkshopScenario.list()
	for p in _paths:
		_scenario_pick.add_item(p.get_file().get_basename())
	_scenario_pick.item_selected.connect(func(i: int) -> void: load_scenario(_paths[i], WorkshopScenario.BASE))
	side.add_child(_scenario_pick)
	_variant_pick = OptionButton.new()
	_variant_pick.item_selected.connect(func(i: int) -> void: load_scenario(scenario_path, _variant_pick.get_item_text(i), current_frame()))
	side.add_child(_variant_pick)
	_layer_box = HFlowContainer.new()
	side.add_child(_layer_box)
	side.add_child(UiTheme.label("Probes", "SmallLabel"))
	_probes = ItemList.new()
	_probes.custom_minimum_size = Vector2(0, 160)
	_probes.item_clicked.connect(func(i: int, _at: Vector2, _b: int) -> void: pick_probe(i))
	side.add_child(_probes)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)
	_card_box = VBoxContainer.new()
	_card_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_card_box)
	var main := VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(main)
	view = ContextView.new()
	view.art = ArtSet.core()
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.custom_minimum_size = Vector2(480, 320)
	view.battle_camera.connect(func(z: float, c: Vector2) -> void: view.set_camera(z, c))
	view.battle_pressed.connect(_on_pressed)
	main.add_child(view)
	overlay = DebugOverlay.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.add_child(overlay)
	overlay.attach(view)
	for layer in DebugOverlay.LAYERS:
		var cb := CheckBox.new()
		cb.text = layer
		cb.button_pressed = overlay.is_layer_on(layer)
		cb.focus_mode = Control.FOCUS_NONE
		cb.toggled.connect(func(on: bool) -> void: overlay.set_layer(layer, on))
		_layer_box.add_child(cb)
	_slider = HSlider.new()
	_slider.step = 1.0
	_slider.focus_mode = Control.FOCUS_NONE
	_slider.value_changed.connect(func(v: float) -> void: playing = false; seek_frame(int(v)))
	main.add_child(_slider)
	_hud = UiTheme.label("", "SmallLabel", true)
	main.add_child(_hud)


func _on_pressed(at: Vector2, button: int, _shift: bool, _ctrl: bool, _alt: bool, _double: bool) -> void:
	if button == MOUSE_BUTTON_LEFT:
		inspect(view.squad_at(at))
