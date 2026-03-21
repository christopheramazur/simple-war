extends Control
## Battlefield view + input. Game rules and unit state live in [BattlefieldSimulation].

const MENU_OVERLAY_SCRIPT := preload("res://src/ui/menu_overlay.gd")
const BattlefieldLayout := preload("res://src/battle/runtime/battlefield_layout.gd")
const BattlefieldCoordinateMapper := preload("res://src/battle/runtime/battlefield_coordinate_mapper.gd")
const BattlefieldSimulation := preload("res://src/battle/runtime/battlefield_simulation.gd")
const BattleWorldHost := preload("res://src/battle/runtime/battle_world_host.gd")

var _mapper: BattlefieldCoordinateMapper = BattlefieldCoordinateMapper.new()
## Exposed for tests and tooling; prefer API on this Control for gameplay.
var sim: BattlefieldSimulation

var camera_zoom_level: int = 0

var order_info: Label
var engage_button: Button
var execute_button: Button

func _ready() -> void:
	CampaignRuntime.reset_battle_session()
	add_child(BattleWorldHost.new())
	sim = BattlefieldSimulation.new(_mapper)
	sim.camera_zoom_level = camera_zoom_level
	sim.state_changed.connect(_on_sim_state_changed)
	sim.notice.connect(_on_sim_notice)
	add_child(MENU_OVERLAY_SCRIPT.new())
	_create_ui()
	sim.spawn_poc_units()
	_refresh_from_sim()

func get_simulation() -> BattlefieldSimulation:
	return sim

func _on_sim_state_changed() -> void:
	queue_redraw()
	_refresh_from_sim()

func _on_sim_notice(text: String) -> void:
	order_info.text = text

func _refresh_from_sim(_units_without_orders: int = -1) -> void:
	order_info.text = sim.get_status_text(_units_without_orders)
	engage_button.visible = sim.engage_button_visible()
	engage_button.disabled = sim.engage_button_disabled()
	execute_button.visible = sim.execute_button_visible()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			sim.handle_left_drag(event.position)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			sim.handle_left_press(event.position)
		else:
			sim.handle_left_release(event.position)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_show_stage_context_menu()
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			if sim.battle_state.stage == BattleState.Stage.DEPLOYMENT:
				_on_engage_pressed()
			elif sim.battle_state.stage == BattleState.Stage.ENGAGEMENT:
				_on_execute_pressed()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		camera_zoom_level = max(0, camera_zoom_level - 1)
		sim.camera_zoom_level = camera_zoom_level
		queue_redraw()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		camera_zoom_level = min(2, camera_zoom_level + 1)
		sim.camera_zoom_level = camera_zoom_level
		queue_redraw()

func _draw() -> void:
	var board_rect := _mapper.board_rect()
	draw_rect(board_rect, Color(0.18, 0.32, 0.18), true)
	if sim.battle_state.stage == BattleState.Stage.DEPLOYMENT:
		_draw_deployment_zones(board_rect)
		_draw_grid(board_rect)
		_draw_deployment_reserves(board_rect)
	_draw_units(board_rect)
	_draw_previews(board_rect)
	if sim.box_select_active() and sim.battle_state.stage == BattleState.Stage.ENGAGEMENT:
		var r := _mapper.rect_from_points(sim.box_select_start(), sim.box_select_end())
		draw_rect(r, Color(0.3, 0.9, 1.0, 0.12), true)
		draw_rect(r, Color(0.3, 0.9, 1.0, 0.85), false)

func _create_ui() -> void:
	order_info = Label.new()
	order_info.position = Vector2(100, 20)
	order_info.size = Vector2(900, 50)
	add_child(order_info)

	engage_button = Button.new()
	engage_button.text = "Engage Enemy"
	engage_button.position = Vector2(560, 20)
	engage_button.pressed.connect(_on_engage_pressed)
	add_child(engage_button)

	execute_button = Button.new()
	execute_button.text = "Execute Orders"
	execute_button.position = Vector2(1020, 660)
	execute_button.pressed.connect(_on_execute_pressed)
	add_child(execute_button)

func _draw_deployment_zones(board_rect: Rect2) -> void:
	var bottom_zone := Rect2(
		board_rect.position + Vector2(0, board_rect.size.y - (20.0 * BattlefieldLayout.WORLD_SCALE)),
		Vector2(board_rect.size.x, 20.0 * BattlefieldLayout.WORLD_SCALE)
	)
	var top_zone := Rect2(board_rect.position, Vector2(board_rect.size.x, 20.0 * BattlefieldLayout.WORLD_SCALE))
	draw_rect(bottom_zone, Color(0.15, 0.22, 0.55, 0.35), true)
	draw_rect(top_zone, Color(0.55, 0.15, 0.15, 0.35), true)
	var boundary_player_world_y := 20.0
	var boundary_player_screen_y := board_rect.position.y + ((BattlefieldLayout.BATTLEFIELD_HEIGHT - boundary_player_world_y) * BattlefieldLayout.WORLD_SCALE)
	_draw_dotted_horizontal_line(board_rect.position.x, board_rect.end.x, boundary_player_screen_y, Color(0.7, 0.85, 1.0, 0.7))
	var boundary_enemy_world_y := 80.0
	var boundary_enemy_screen_y := board_rect.position.y + ((BattlefieldLayout.BATTLEFIELD_HEIGHT - boundary_enemy_world_y) * BattlefieldLayout.WORLD_SCALE)
	_draw_dotted_horizontal_line(board_rect.position.x, board_rect.end.x, boundary_enemy_screen_y, Color(1.0, 0.75, 0.75, 0.65))

func _draw_dotted_horizontal_line(x0: float, x1: float, y: float, color: Color) -> void:
	var seg_len := 8.0
	var gap_len := 6.0
	var x := x0
	while x <= x1:
		draw_line(Vector2(x, y), Vector2(mini(x + seg_len, x1), y), color, 2.0)
		x += seg_len + gap_len

func _draw_deployment_reserves(_board_rect: Rect2) -> void:
	var reserve_units: Array = sim.reserve_units_ordered()
	if reserve_units.is_empty():
		return
	var panel_origin := _mapper.reserve_units_panel_origin()
	for i in range(reserve_units.size()):
		var pos := panel_origin + Vector2(0, i * BattlefieldLayout.RESERVE_UNIT_SPACING_Y)
		var rect := Rect2(pos - BattlefieldLayout.RESERVE_SLOT_SIZE * 0.5, BattlefieldLayout.RESERVE_SLOT_SIZE)
		var unit = reserve_units[i]
		var selected := sim.selected_reserve_units.has(unit)
		draw_rect(rect, Color(0.25, 0.7, 1.0, 0.35 if selected else 0.2), true)
		draw_rect(rect, Color(0.95, 0.95, 0.4, 1.0) if selected else Color(0.25, 0.7, 1.0, 0.85), false)
		_draw_mini_formation(rect.position + rect.size * 0.5, 0.45, true)

func _formation_offsets_world() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for rank in range(BattlefieldLayout.FORMATION_RANKS):
		for file in range(BattlefieldLayout.FORMATION_FILES):
			var fx := (float(file) - 2.0) * BattlefieldLayout.MODEL_DIAMETER_WORLD
			var fy := (0.5 - float(rank)) * BattlefieldLayout.MODEL_DIAMETER_WORLD
			out.append(Vector2(fx, fy))
	return out

func _formation_offsets_for_unit(unit) -> Array[Vector2]:
	var all := _formation_offsets_world()
	var n: int = mini(unit.model_count, all.size())
	var out: Array[Vector2] = []
	for i in range(n):
		out.append(all[i])
	return out

func _draw_mini_formation(center: Vector2, half_span: float, is_player: bool) -> void:
	var col := Color(0.35, 0.75, 1.0) if is_player else Color(1.0, 0.45, 0.45)
	for rank in range(BattlefieldLayout.FORMATION_RANKS):
		for file in range(BattlefieldLayout.FORMATION_FILES):
			var lx := (float(file) - 2.0) / 2.0 * half_span
			var ly := (0.5 - float(rank)) * 3.5
			draw_circle(center + Vector2(lx, ly), 1.4, col)

func _draw_dotted_line(a: Vector2, b: Vector2, color: Color, width: float) -> void:
	var dist := a.distance_to(b)
	if dist < 0.5:
		return
	var dir := (b - a) / dist
	var seg := 6.0
	var gap := 4.0
	var t := 0.0
	while t < dist:
		var p0 := a + dir * t
		var segment_end: float = minf(t + seg, dist)
		var p1: Vector2 = a + dir * segment_end
		draw_line(p0, p1, color, width)
		t += seg + gap

func _draw_unit_models(_board_rect: Rect2, unit, base_world: Vector2, is_player: bool, ghost: bool) -> void:
	var base_col := Color(0.18, 0.55, 1.0) if is_player else Color(0.92, 0.22, 0.22)
	if ghost:
		base_col.a = 0.28
	else:
		base_col.a = 0.92
	var r_screen := (BattlefieldLayout.MODEL_DIAMETER_WORLD * 0.5) * BattlefieldLayout.WORLD_SCALE * 0.92
	for off in _formation_offsets_for_unit(unit):
		var s := _mapper.world_to_screen(base_world + off)
		draw_circle(s, r_screen, base_col)

func _draw_grid(board_rect: Rect2) -> void:
	var spacing_values: Array[float] = [1.0, 3.0, 6.0]
	var spacing: float = spacing_values[camera_zoom_level]
	var px: float = spacing * BattlefieldLayout.WORLD_SCALE
	var x := board_rect.position.x
	while x <= board_rect.end.x:
		draw_line(Vector2(x, board_rect.position.y), Vector2(x, board_rect.end.y), Color(0.55, 0.55, 0.55, 0.2), 1.0)
		x += px
	var y := board_rect.position.y
	while y <= board_rect.end.y:
		draw_line(Vector2(board_rect.position.x, y), Vector2(board_rect.end.x, y), Color(0.55, 0.55, 0.55, 0.2), 1.0)
		y += px

func _draw_units(board_rect: Rect2) -> void:
	for unit in sim.player_units:
		if not unit.alive:
			continue
		if sim.battle_state.stage == BattleState.Stage.DEPLOYMENT and not unit.deployed:
			continue
		_draw_unit_models(board_rect, unit, unit.position, true, false)
		if unit.selected:
			draw_rect(_mapper.unit_selection_screen_rect(unit), Color(1.0, 0.95, 0.35, 0.9), false)
	for unit in sim.enemy_units:
		if not unit.alive:
			continue
		_draw_unit_models(board_rect, unit, unit.position, false, false)

func _draw_previews(board_rect: Rect2) -> void:
	if sim.battle_state.stage == BattleState.Stage.DEPLOYMENT and sim.deployment_drag_active():
		var batch: Array = sim.selected_reserve_units.duplicate()
		if batch.is_empty():
			return
		for i in range(batch.size()):
			var w := sim.deployment_preview_world() + Vector2(BattlefieldLayout.BATCH_DEPLOY_SPACING_X * float(i), 0.0)
			_draw_unit_models(board_rect, batch[i], w, true, true)
		return
	if sim.battle_state.stage != BattleState.Stage.ENGAGEMENT:
		return
	if sim.engagement_order_drag_active():
		for unit in sim.selected_units:
			if not unit.alive:
				continue
			var a := _mapper.world_to_screen(unit.position)
			var b := _mapper.world_to_screen(sim.engagement_preview_world())
			_draw_dotted_line(a, b, Color(1.0, 1.0, 0.55, 0.85), 2.0)
			_draw_unit_models(board_rect, unit, sim.engagement_preview_world(), true, true)
	for unit in sim.selected_units:
		if not unit.alive or not unit.has_order:
			continue
		var a2 := _mapper.world_to_screen(unit.position)
		var b2 := _mapper.world_to_screen(unit.destination)
		_draw_dotted_line(a2, b2, Color(1.0, 1.0, 0.45, 0.65), 2.0)
		_draw_unit_models(board_rect, unit, unit.destination, true, true)

func _show_stage_context_menu() -> void:
	if sim.battle_state.stage == BattleState.Stage.DEPLOYMENT:
		if not sim.all_player_units_deployed():
			order_info.text = "Deploy all your units first (blue zone y=0..20)."
			return
		var popup := PopupMenu.new()
		popup.add_item("Engage Enemy", 1)
		popup.id_pressed.connect(func(id: int) -> void:
			if id == 1:
				_on_engage_pressed()
		)
		add_child(popup)
		popup.position = get_viewport().get_mouse_position()
		popup.popup()
	elif sim.battle_state.stage == BattleState.Stage.ENGAGEMENT:
		var popup := PopupMenu.new()
		popup.add_item("Execute Orders", 1)
		popup.id_pressed.connect(func(id: int) -> void:
			if id == 1:
				_on_execute_pressed()
		)
		add_child(popup)
		popup.position = get_viewport().get_mouse_position()
		popup.popup()

func _on_engage_pressed() -> void:
	if not sim.try_start_engagement():
		return
	_refresh_from_sim()

func _on_execute_pressed() -> void:
	if sim.try_execute_engagement_turn() < 0:
		return
