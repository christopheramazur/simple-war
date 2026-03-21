extends Control

const BATTLEFIELD_WIDTH: float = 200.0
const BATTLEFIELD_HEIGHT: float = 100.0
const WORLD_SCALE: float = 5.0
const BATTLE_STATE_SCRIPT := preload("res://src/battle/runtime/battle_state.gd")
const MOVEMENT_SYSTEM_SCRIPT := preload("res://src/battle/systems/movement_system.gd")
const DEPLOYMENT_SYSTEM_SCRIPT := preload("res://src/battle/systems/deployment_system.gd")
const COMBAT_SYSTEM_SCRIPT := preload("res://src/battle/systems/combat_system_minimal.gd")
const UNIT_RUNTIME_SCRIPT := preload("res://src/battle/runtime/unit_runtime.gd")
const MENU_OVERLAY_SCRIPT := preload("res://src/ui/menu_overlay.gd")

var battle_state = BATTLE_STATE_SCRIPT.new()
var movement_system = MOVEMENT_SYSTEM_SCRIPT.new()
var deployment_system = DEPLOYMENT_SYSTEM_SCRIPT.new()
var combat_system = COMBAT_SYSTEM_SCRIPT.new()

var player_units: Array = []
var enemy_units: Array = []
var selected_units: Array = []

var camera_zoom_level: int = 0 # 0 => 1, 1 => 3, 2 => 6
var order_info: Label
var engage_button: Button
var execute_button: Button
var battle_resolved_emitted: bool = false

# Simple "reserve" visualization so the player can see deployable units.
const RESERVE_PANEL_X_OFFSET: float = 60.0
const RESERVE_PANEL_Y_OFFSET: float = 120.0
const RESERVE_UNIT_SPACING_Y: float = 26.0
const RESERVE_SLOT_SIZE := Vector2(28, 16)

# Model footprint (Movement rules 320.x): 1 distance unit diameter per model; default 5×2 block for 10 models.
const MODEL_DIAMETER_WORLD: float = 1.0
const FORMATION_FILES: int = 5
const FORMATION_RANKS: int = 2

# Interaction (PoC: multi-select, drag-move, drag-deploy)
const DRAG_THRESHOLD_PX: float = 8.0
const BATCH_DEPLOY_SPACING_X: float = 4.0

var selected_reserve_units: Array = []

var _left_press_screen: Vector2 = Vector2.ZERO
var _left_press_reserve_unit = null # UnitRuntime or null
var _left_press_on_board: bool = false

var _box_select_active: bool = false
var _box_select_start: Vector2 = Vector2.ZERO
var _box_select_end: Vector2 = Vector2.ZERO

var _deployment_drag_active: bool = false
var _deployment_preview_world: Vector2 = Vector2.ZERO

var _engagement_order_drag_active: bool = false
var _engagement_preview_world: Vector2 = Vector2.ZERO

func _ready() -> void:
	CampaignRuntime.reset_battle_session()
	add_child(MENU_OVERLAY_SCRIPT.new())
	_create_ui()
	_spawn_poc_units()
	_refresh_buttons()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_handle_left_drag(event.position)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_handle_left_press(event.position)
		else:
			_handle_left_release(event.position)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_show_stage_context_menu()
	if event is InputEventKey and event.pressed:
		# PoC parity: Enter triggers Engage/Execute.
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			if battle_state.stage == BATTLE_STATE_SCRIPT.Stage.DEPLOYMENT:
				_on_engage_pressed()
			elif battle_state.stage == BATTLE_STATE_SCRIPT.Stage.ENGAGEMENT:
				_on_execute_pressed()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		camera_zoom_level = max(0, camera_zoom_level - 1)
		queue_redraw()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		camera_zoom_level = min(2, camera_zoom_level + 1)
		queue_redraw()

func _draw() -> void:
	var board_rect := _get_board_rect()
	draw_rect(board_rect, Color(0.18, 0.32, 0.18), true)
	if battle_state.stage == BATTLE_STATE_SCRIPT.Stage.DEPLOYMENT:
		_draw_deployment_zones(board_rect)
		_draw_grid(board_rect)
		_draw_deployment_reserves(board_rect)
	_draw_units(board_rect)
	_draw_previews(board_rect)
	if _box_select_active and battle_state.stage == BATTLE_STATE_SCRIPT.Stage.ENGAGEMENT:
		var r := _rect_from_points(_box_select_start, _box_select_end)
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

func _get_board_rect() -> Rect2:
	return Rect2(Vector2(100, 80), Vector2(BATTLEFIELD_WIDTH * WORLD_SCALE, BATTLEFIELD_HEIGHT * WORLD_SCALE))

func _rect_from_points(a: Vector2, b: Vector2) -> Rect2:
	var mn := Vector2(min(a.x, b.x), min(a.y, b.y))
	var mx := Vector2(max(a.x, b.x), max(a.y, b.y))
	return Rect2(mn, mx - mn)

func _spawn_poc_units() -> void:
	player_units.clear()
	enemy_units.clear()
	selected_units.clear()
	battle_resolved_emitted = false
	for i in range(5):
		var unit = UNIT_RUNTIME_SCRIPT.new(
			"player_riflemen_%d" % i,
			"Riflemen %d" % (i + 1),
			"Human",
			10.0,
			10,
			10,
			Vector2(-10, 8 + (i * 2))
		)
		unit.deployed = false
		player_units.append(unit)
	for i in range(5):
		var enemy = UNIT_RUNTIME_SCRIPT.new(
			"enemy_riflemen_%d" % i,
			"Enemy %d" % (i + 1),
			"Chaos",
			10.0,
			10,
			10,
			Vector2(30 + (i * 8), 92)
		)
		enemy.deployed = true
		enemy_units.append(enemy)
	selected_reserve_units.clear()
	_reset_interaction_state()
	_update_status_label()

func _reset_interaction_state() -> void:
	_left_press_reserve_unit = null
	_left_press_on_board = false
	_box_select_active = false
	_deployment_drag_active = false
	_engagement_order_drag_active = false

func _world_to_screen(board_rect: Rect2, world_position: Vector2) -> Vector2:
	return Vector2(
		board_rect.position.x + (world_position.x * WORLD_SCALE),
		board_rect.position.y + ((BATTLEFIELD_HEIGHT - world_position.y) * WORLD_SCALE)
	)

func _screen_to_world(board_rect: Rect2, screen_position: Vector2) -> Vector2:
	return Vector2(
		(screen_position.x - board_rect.position.x) / WORLD_SCALE,
		BATTLEFIELD_HEIGHT - ((screen_position.y - board_rect.position.y) / WORLD_SCALE)
	)

func _draw_deployment_zones(board_rect: Rect2) -> void:
	var bottom_zone := Rect2(
		board_rect.position + Vector2(0, board_rect.size.y - (20.0 * WORLD_SCALE)),
		Vector2(board_rect.size.x, 20.0 * WORLD_SCALE)
	)
	var top_zone := Rect2(board_rect.position, Vector2(board_rect.size.x, 20.0 * WORLD_SCALE))
	draw_rect(bottom_zone, Color(0.15, 0.22, 0.55, 0.35), true)
	draw_rect(top_zone, Color(0.55, 0.15, 0.15, 0.35), true)
	# Dotted deployment boundary at y=20 (player) and y=80 (enemy) (PoC)
	var boundary_player_world_y := 20.0
	var boundary_player_screen_y := board_rect.position.y + ((BATTLEFIELD_HEIGHT - boundary_player_world_y) * WORLD_SCALE)
	_draw_dotted_horizontal_line(board_rect.position.x, board_rect.end.x, boundary_player_screen_y, Color(0.7, 0.85, 1.0, 0.7))
	var boundary_enemy_world_y := 80.0
	var boundary_enemy_screen_y := board_rect.position.y + ((BATTLEFIELD_HEIGHT - boundary_enemy_world_y) * WORLD_SCALE)
	_draw_dotted_horizontal_line(board_rect.position.x, board_rect.end.x, boundary_enemy_screen_y, Color(1.0, 0.75, 0.75, 0.65))

func _draw_dotted_horizontal_line(x0: float, x1: float, y: float, color: Color) -> void:
	var seg_len := 8.0
	var gap_len := 6.0
	var x := x0
	while x <= x1:
		draw_line(Vector2(x, y), Vector2(min(x + seg_len, x1), y), color, 2.0)
		x += seg_len + gap_len

func _draw_deployment_reserves(board_rect: Rect2) -> void:
	# Show how many player units are still in reserve (not yet deployed on the board).
	var reserve_units: Array = []
	for unit in player_units:
		if unit.alive and not unit.deployed:
			reserve_units.append(unit)

	if reserve_units.is_empty():
		return

	var panel_origin := Vector2(board_rect.end.x + RESERVE_PANEL_X_OFFSET, board_rect.position.y + RESERVE_PANEL_Y_OFFSET)
	for i in range(reserve_units.size()):
		var pos := panel_origin + Vector2(0, i * RESERVE_UNIT_SPACING_Y)
		var rect := Rect2(pos - RESERVE_SLOT_SIZE * 0.5, RESERVE_SLOT_SIZE)
		var unit = reserve_units[i]
		var selected := selected_reserve_units.has(unit)
		draw_rect(rect, Color(0.25, 0.7, 1.0, 0.35 if selected else 0.2), true)
		draw_rect(rect, Color(0.95, 0.95, 0.4, 1.0) if selected else Color(0.25, 0.7, 1.0, 0.85), false)
		_draw_mini_formation(rect.position + rect.size * 0.5, 0.45, true)

func _formation_offsets_world() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for rank in range(FORMATION_RANKS):
		for file in range(FORMATION_FILES):
			var fx := (float(file) - 2.0) * MODEL_DIAMETER_WORLD
			var fy := (0.5 - float(rank)) * MODEL_DIAMETER_WORLD
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
	for rank in range(FORMATION_RANKS):
		for file in range(FORMATION_FILES):
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

func _draw_unit_models(board_rect: Rect2, unit, base_world: Vector2, is_player: bool, ghost: bool) -> void:
	var base_col := Color(0.18, 0.55, 1.0) if is_player else Color(0.92, 0.22, 0.22)
	if ghost:
		base_col.a = 0.28
	else:
		base_col.a = 0.92
	var r_screen := (MODEL_DIAMETER_WORLD * 0.5) * WORLD_SCALE * 0.92
	for off in _formation_offsets_for_unit(unit):
		var s := _world_to_screen(board_rect, base_world + off)
		draw_circle(s, r_screen, base_col)

func _unit_selection_screen_rect(board_rect: Rect2, unit) -> Rect2:
	var center := _world_to_screen(board_rect, unit.position)
	return Rect2(center - Vector2(24, 18), Vector2(48, 36))

func _draw_grid(board_rect: Rect2) -> void:
	var spacing_values: Array[float] = [1.0, 3.0, 6.0]
	var spacing: float = spacing_values[camera_zoom_level]
	var px: float = spacing * WORLD_SCALE
	var x := board_rect.position.x
	while x <= board_rect.end.x:
		draw_line(Vector2(x, board_rect.position.y), Vector2(x, board_rect.end.y), Color(0.55, 0.55, 0.55, 0.2), 1.0)
		x += px
	var y := board_rect.position.y
	while y <= board_rect.end.y:
		draw_line(Vector2(board_rect.position.x, y), Vector2(board_rect.end.x, y), Color(0.55, 0.55, 0.55, 0.2), 1.0)
		y += px

func _draw_units(board_rect: Rect2) -> void:
	for unit in player_units:
		if not unit.alive:
			continue
		if battle_state.stage == BATTLE_STATE_SCRIPT.Stage.DEPLOYMENT and not unit.deployed:
			continue
		_draw_unit_models(board_rect, unit, unit.position, true, false)
		if unit.selected:
			draw_rect(_unit_selection_screen_rect(board_rect, unit), Color(1.0, 0.95, 0.35, 0.9), false)
	for unit in enemy_units:
		if not unit.alive:
			continue
		_draw_unit_models(board_rect, unit, unit.position, false, false)

func _draw_previews(board_rect: Rect2) -> void:
	if battle_state.stage == BATTLE_STATE_SCRIPT.Stage.DEPLOYMENT and _deployment_drag_active:
		var batch: Array = selected_reserve_units.duplicate()
		if batch.is_empty():
			return
		for i in range(batch.size()):
			var w := _deployment_preview_world + Vector2(BATCH_DEPLOY_SPACING_X * float(i), 0.0)
			_draw_unit_models(board_rect, batch[i], w, true, true)
		return
	if battle_state.stage != BATTLE_STATE_SCRIPT.Stage.ENGAGEMENT:
		return
	if _engagement_order_drag_active:
		for unit in selected_units:
			if not unit.alive:
				continue
			var a := _world_to_screen(board_rect, unit.position)
			var b := _world_to_screen(board_rect, _engagement_preview_world)
			_draw_dotted_line(a, b, Color(1.0, 1.0, 0.55, 0.85), 2.0)
			_draw_unit_models(board_rect, unit, _engagement_preview_world, true, true)
	for unit in selected_units:
		if not unit.alive or not unit.has_order:
			continue
		var a2 := _world_to_screen(board_rect, unit.position)
		var b2 := _world_to_screen(board_rect, unit.destination)
		_draw_dotted_line(a2, b2, Color(1.0, 1.0, 0.45, 0.65), 2.0)
		_draw_unit_models(board_rect, unit, unit.destination, true, true)

func _reserve_unit_at_screen(board_rect: Rect2, screen_pos: Vector2):
	var reserve_units: Array = _reserve_units_ordered()
	var panel_origin := Vector2(board_rect.end.x + RESERVE_PANEL_X_OFFSET, board_rect.position.y + RESERVE_PANEL_Y_OFFSET)
	for i in range(reserve_units.size()):
		var pos := panel_origin + Vector2(0, i * RESERVE_UNIT_SPACING_Y)
		var rect := Rect2(pos - RESERVE_SLOT_SIZE * 0.5, RESERVE_SLOT_SIZE)
		if rect.has_point(screen_pos):
			return reserve_units[i]
	return null

func _reserve_units_ordered() -> Array:
	var reserve_units: Array = []
	for unit in player_units:
		if unit.alive and not unit.deployed:
			reserve_units.append(unit)
	return reserve_units

func _handle_left_press(screen_pos: Vector2) -> void:
	_left_press_screen = screen_pos
	var board_rect := _get_board_rect()
	match battle_state.stage:
		BATTLE_STATE_SCRIPT.Stage.DEPLOYMENT:
			_left_press_reserve_unit = _reserve_unit_at_screen(board_rect, screen_pos)
			_left_press_on_board = board_rect.has_point(screen_pos)
			if _left_press_reserve_unit != null:
				var shift_down := Input.is_key_pressed(KEY_SHIFT)
				if shift_down:
					var idx := selected_reserve_units.find(_left_press_reserve_unit)
					if idx >= 0:
						selected_reserve_units.remove_at(idx)
					else:
						selected_reserve_units.append(_left_press_reserve_unit)
				else:
					selected_reserve_units = [_left_press_reserve_unit]
				queue_redraw()
		BATTLE_STATE_SCRIPT.Stage.ENGAGEMENT:
			_left_press_on_board = board_rect.has_point(screen_pos)
			var clicked: Variant = _pick_player_unit_at(board_rect, screen_pos)
			if clicked != null:
				var shift_down := Input.is_key_pressed(KEY_SHIFT)
				if shift_down:
					var idx2 := selected_units.find(clicked)
					if idx2 >= 0:
						selected_units.remove_at(idx2)
						clicked.selected = false
					else:
						selected_units.append(clicked)
						clicked.selected = true
				else:
					_clear_selection()
					clicked.selected = true
					selected_units = [clicked]
				queue_redraw()
				return
			if _left_press_on_board:
				_box_select_active = true
				_box_select_start = screen_pos
				_box_select_end = screen_pos
				queue_redraw()

func _handle_left_drag(screen_pos: Vector2) -> void:
	var board_rect := _get_board_rect()
	match battle_state.stage:
		BATTLE_STATE_SCRIPT.Stage.DEPLOYMENT:
			var started_on_reserve := _reserve_unit_at_screen(board_rect, _left_press_screen) != null
			if not selected_reserve_units.is_empty() and started_on_reserve:
				if _left_press_screen.distance_to(screen_pos) >= DRAG_THRESHOLD_PX:
					_deployment_drag_active = true
			if _deployment_drag_active and board_rect.has_point(screen_pos):
				var raw := _screen_to_world(board_rect, screen_pos)
				_deployment_preview_world = movement_system.snap_to_grid(raw, 1.0)
				queue_redraw()
		BATTLE_STATE_SCRIPT.Stage.ENGAGEMENT:
			if _box_select_active:
				_box_select_end = screen_pos
				queue_redraw()
			elif selected_units.size() > 0 and _left_press_on_board:
				if _left_press_screen.distance_to(screen_pos) >= DRAG_THRESHOLD_PX:
					_engagement_order_drag_active = true
			if _engagement_order_drag_active and board_rect.has_point(screen_pos):
				var spacing_values: Array[float] = [1.0, 3.0, 6.0]
				var spacing: float = spacing_values[camera_zoom_level]
				var snapped_world := movement_system.snap_to_grid(_screen_to_world(board_rect, screen_pos), spacing)
				_engagement_preview_world = movement_system.clamp_to_battlefield(
					snapped_world, BATTLEFIELD_WIDTH, BATTLEFIELD_HEIGHT
				)
				queue_redraw()

func _handle_left_release(screen_pos: Vector2) -> void:
	var board_rect := _get_board_rect()
	var dist := _left_press_screen.distance_to(screen_pos)
	match battle_state.stage:
		BATTLE_STATE_SCRIPT.Stage.DEPLOYMENT:
			if _deployment_drag_active:
				if deployment_system.is_player_deployment_legal(_deployment_preview_world, BATTLEFIELD_WIDTH):
					_deploy_selected_reserves_at_anchor(_deployment_preview_world)
				else:
					order_info.text = "Release inside your deployment zone (y=0..20)."
				_deployment_drag_active = false
				queue_redraw()
			elif dist < DRAG_THRESHOLD_PX and board_rect.has_point(screen_pos):
				var w := movement_system.snap_to_grid(_screen_to_world(board_rect, screen_pos), 1.0)
				if deployment_system.is_player_deployment_legal(w, BATTLEFIELD_WIDTH):
					if not selected_reserve_units.is_empty():
						_deploy_selected_reserves_at_anchor(w)
					else:
						_deploy_single_next_at(w)
			_left_press_reserve_unit = null
			_left_press_on_board = false
		BATTLE_STATE_SCRIPT.Stage.ENGAGEMENT:
			if _engagement_order_drag_active:
				for unit in selected_units:
					if unit.alive:
						unit.destination = _engagement_preview_world
						unit.has_order = true
				_engagement_order_drag_active = false
				queue_redraw()
			elif _box_select_active:
				if dist >= DRAG_THRESHOLD_PX:
					_apply_box_selection(board_rect)
				_box_select_active = false
				queue_redraw()
			_left_press_on_board = false
	_left_press_screen = Vector2.ZERO

func _deploy_single_next_at(world_pos: Vector2) -> void:
	var unit_to_deploy = _next_undeployed_player_unit()
	if unit_to_deploy == null:
		return
	unit_to_deploy.position = movement_system.clamp_to_battlefield(world_pos, BATTLEFIELD_WIDTH, BATTLEFIELD_HEIGHT)
	unit_to_deploy.deployed = true
	order_info.text = "Deployed %s (no reserve selection — next in queue)." % unit_to_deploy.display_name
	_update_status_label()
	_refresh_buttons()
	queue_redraw()

func _deploy_selected_reserves_at_anchor(anchor_world: Vector2) -> void:
	if selected_reserve_units.is_empty():
		return
	var to_place: Array = selected_reserve_units.duplicate()
	to_place.sort_custom(func(a, b): return str(a.id) < str(b.id))
	for i in range(to_place.size()):
		var w := anchor_world + Vector2(BATCH_DEPLOY_SPACING_X * float(i), 0.0)
		w = movement_system.snap_to_grid(w, 1.0)
		if not deployment_system.is_player_deployment_legal(w, BATTLEFIELD_WIDTH):
			order_info.text = "Batch does not fit in zone from this anchor — try fewer units or another spot."
			queue_redraw()
			return
		var u = to_place[i]
		u.position = movement_system.clamp_to_battlefield(w, BATTLEFIELD_WIDTH, BATTLEFIELD_HEIGHT)
		u.deployed = true
	selected_reserve_units.clear()
	order_info.text = "Deployed %d unit(s). Shift-click reserves to multi-select; drag onto zone to place." % to_place.size()
	_update_status_label()
	_refresh_buttons()
	queue_redraw()

func _apply_box_selection(board_rect: Rect2) -> void:
	var r := _rect_from_points(_box_select_start, _box_select_end)
	if not Input.is_key_pressed(KEY_SHIFT):
		_clear_selection()
	for unit in player_units:
		if not unit.alive or not unit.deployed:
			continue
		var ur := _unit_selection_screen_rect(board_rect, unit)
		if r.intersects(ur):
			if selected_units.find(unit) < 0:
				selected_units.append(unit)
				unit.selected = true
	queue_redraw()

func _show_stage_context_menu() -> void:
	# Minimal PoC parity: right-click Battlefield for the most important actions.
	if battle_state.stage == BATTLE_STATE_SCRIPT.Stage.DEPLOYMENT:
		if not _all_player_units_deployed():
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
	elif battle_state.stage == BATTLE_STATE_SCRIPT.Stage.ENGAGEMENT:
		var popup := PopupMenu.new()
		popup.add_item("Execute Orders", 1)
		popup.id_pressed.connect(func(id: int) -> void:
			if id == 1:
				_on_execute_pressed()
		)
		add_child(popup)
		popup.position = get_viewport().get_mouse_position()
		popup.popup()

func _pick_player_unit_at(board_rect: Rect2, screen_position: Vector2) -> Variant:
	for unit in player_units:
		if not unit.alive:
			continue
		if battle_state.stage == BATTLE_STATE_SCRIPT.Stage.DEPLOYMENT and not unit.deployed:
			continue
		if _unit_selection_screen_rect(board_rect, unit).has_point(screen_position):
			return unit
	return null

func _on_engage_pressed() -> void:
	if not _all_player_units_deployed():
		_update_status_label()
		return
	battle_state.start_engagement()
	CampaignRuntime.engagement_turn = 1
	_update_status_label()
	_refresh_buttons()
	queue_redraw()

func _on_execute_pressed() -> void:
	if battle_state.stage != BATTLE_STATE_SCRIPT.Stage.ENGAGEMENT:
		return
	var units_without_orders := 0
	for unit in player_units:
		if unit.alive and not unit.has_order:
			units_without_orders += 1
	for unit in player_units:
		if not unit.alive:
			continue
		if unit.has_order:
			unit.position = movement_system.move_toward_with_budget(unit.position, unit.destination, unit.speed)
		unit.has_order = false
	for unit in enemy_units:
		if not unit.alive:
			continue
		var closest = combat_system.pick_closest_enemy(unit.position, player_units)
		if closest != null:
			unit.position = movement_system.move_toward_with_budget(unit.position, closest.position, unit.speed)
	_resolve_combat_step()
	if _all_dead(enemy_units) or _all_dead(player_units):
		battle_state.move_to_consolidation()
		_emit_battle_resolved_once()
	else:
		battle_state.next_turn()
		CampaignRuntime.engagement_turn = battle_state.turn
	_update_status_label(units_without_orders)
	_refresh_buttons()
	queue_redraw()

func _emit_battle_resolved_once() -> void:
	if battle_resolved_emitted:
		return
	battle_resolved_emitted = true
	CampaignRuntime.submit_intent(
		"battle.resolve",
		{
			"player_units_destroyed": CampaignRuntime.player_units_destroyed,
			"enemy_units_destroyed": CampaignRuntime.enemy_units_destroyed
		}
	)

func _resolve_combat_step() -> void:
	var alive_players: Array = []
	var alive_enemies: Array = []
	for unit in player_units:
		if unit.alive:
			alive_players.append(unit)
	for unit in enemy_units:
		if unit.alive:
			alive_enemies.append(unit)

	var pending_damage := {}
	for attacker in alive_players:
		var target = combat_system.pick_closest_enemy(attacker.position, alive_enemies)
		if target == null:
			continue
		var damage: int = combat_system.queued_damage(attacker, target)
		if damage <= 0:
			continue
		var target_id: String = target.id
		pending_damage[target_id] = int(pending_damage.get(target_id, 0)) + damage
	for attacker in alive_enemies:
		var target = combat_system.pick_closest_enemy(attacker.position, alive_players)
		if target == null:
			continue
		var damage: int = combat_system.queued_damage(attacker, target)
		if damage <= 0:
			continue
		var target_id: String = target.id
		pending_damage[target_id] = int(pending_damage.get(target_id, 0)) + damage

	for unit in player_units:
		var dealt: int = int(pending_damage.get(unit.id, 0))
		if dealt <= 0:
			continue
		unit.durability -= dealt
		if unit.alive and unit.durability <= 0:
			unit.alive = false
			CampaignRuntime.player_units_destroyed += 1
	for unit in enemy_units:
		var dealt: int = int(pending_damage.get(unit.id, 0))
		if dealt <= 0:
			continue
		unit.durability -= dealt
		if unit.alive and unit.durability <= 0:
			unit.alive = false
			CampaignRuntime.enemy_units_destroyed += 1

func _all_dead(units: Array) -> bool:
	for unit in units:
		if unit.alive:
			return false
	return true

func _clear_selection() -> void:
	for unit in player_units:
		unit.selected = false
	selected_units.clear()

func _update_status_label(units_without_orders: int = -1) -> void:
	if battle_state.stage == BATTLE_STATE_SCRIPT.Stage.DEPLOYMENT:
		var remaining: int = _count_undeployed_player_units()
		order_info.text = "Deployment Stage: click inside your zone (y=0..20) to deploy next. %d units remaining." % remaining
	elif battle_state.stage == BATTLE_STATE_SCRIPT.Stage.ENGAGEMENT:
		var warning := ""
		if units_without_orders > 0:
			warning = " (%d units had no order)" % units_without_orders
		order_info.text = "Engagement Stage: Turn %d%s" % [battle_state.turn, warning]
	else:
		order_info.text = "Consolidation: Player destroyed %d, Enemy destroyed %d" % [CampaignRuntime.enemy_units_destroyed, CampaignRuntime.player_units_destroyed]

func _refresh_buttons() -> void:
	engage_button.visible = battle_state.stage == BATTLE_STATE_SCRIPT.Stage.DEPLOYMENT
	engage_button.disabled = not _all_player_units_deployed()
	execute_button.visible = battle_state.stage == BATTLE_STATE_SCRIPT.Stage.ENGAGEMENT

func _next_undeployed_player_unit():
	for unit in player_units:
		if unit.alive and not unit.deployed:
			return unit
	return null

func _count_undeployed_player_units() -> int:
	var remaining := 0
	for unit in player_units:
		if unit.alive and not unit.deployed:
			remaining += 1
	return remaining

func _all_player_units_deployed() -> bool:
	return _count_undeployed_player_units() == 0
