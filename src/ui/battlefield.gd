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

func _ready() -> void:
	add_child(MENU_OVERLAY_SCRIPT.new())
	_create_ui()
	_spawn_poc_units()
	_refresh_buttons()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if battle_state.stage == BATTLE_STATE_SCRIPT.Stage.DEPLOYMENT:
			_handle_deployment_click(event.position)
		elif battle_state.stage == BATTLE_STATE_SCRIPT.Stage.ENGAGEMENT:
			_handle_engagement_click(event.position)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		camera_zoom_level = max(0, camera_zoom_level - 1)
		queue_redraw()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		camera_zoom_level = min(2, camera_zoom_level + 1)
		queue_redraw()

func _draw() -> void:
	var board_rect := Rect2(Vector2(100, 80), Vector2(BATTLEFIELD_WIDTH * WORLD_SCALE, BATTLEFIELD_HEIGHT * WORLD_SCALE))
	draw_rect(board_rect, Color(0.18, 0.32, 0.18), true)
	if battle_state.stage == BATTLE_STATE_SCRIPT.Stage.DEPLOYMENT:
		_draw_deployment_zones(board_rect)
	_draw_grid(board_rect)
	_draw_units(board_rect)
	_draw_previews(board_rect)

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
			Vector2(10 + (i * 8), 8)
		)
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
		enemy_units.append(enemy)
	_update_status_label()

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
		var pos := _world_to_screen(board_rect, unit.position)
		var color := Color(0.3, 0.65, 1.0) if unit.selected else Color(0.15, 0.45, 0.9)
		draw_rect(Rect2(pos - Vector2(18, 12), Vector2(36, 24)), color, true)
	for unit in enemy_units:
		if not unit.alive:
			continue
		var pos := _world_to_screen(board_rect, unit.position)
		draw_rect(Rect2(pos - Vector2(18, 12), Vector2(36, 24)), Color(0.85, 0.25, 0.25), true)

func _draw_previews(board_rect: Rect2) -> void:
	if battle_state.stage != BATTLE_STATE_SCRIPT.Stage.ENGAGEMENT:
		return
	for unit in selected_units:
		if not unit.alive or not unit.has_order:
			continue
		var a := _world_to_screen(board_rect, unit.position)
		var b := _world_to_screen(board_rect, unit.destination)
		draw_line(a, b, Color(1.0, 1.0, 0.5, 0.7), 2.0)
		draw_rect(Rect2(b - Vector2(18, 12), Vector2(36, 24)), Color(1.0, 1.0, 1.0, 0.3), true)

func _handle_deployment_click(screen_position: Vector2) -> void:
	var board_rect := Rect2(Vector2(100, 80), Vector2(BATTLEFIELD_WIDTH * WORLD_SCALE, BATTLEFIELD_HEIGHT * WORLD_SCALE))
	if not board_rect.has_point(screen_position):
		return
	var world := _screen_to_world(board_rect, screen_position)
	var snapped := movement_system.snap_to_grid(world, 1.0)
	for unit in player_units:
		if unit.alive:
			unit.position = movement_system.clamp_to_battlefield(snapped, BATTLEFIELD_WIDTH, BATTLEFIELD_HEIGHT)
			break
	_refresh_buttons()
	queue_redraw()

func _handle_engagement_click(screen_position: Vector2) -> void:
	var board_rect := Rect2(Vector2(100, 80), Vector2(BATTLEFIELD_WIDTH * WORLD_SCALE, BATTLEFIELD_HEIGHT * WORLD_SCALE))
	if not board_rect.has_point(screen_position):
		return
	var clicked_unit = _pick_player_unit_at(board_rect, screen_position)
	if clicked_unit != null:
		_clear_selection()
		clicked_unit.selected = true
		selected_units = [clicked_unit]
		queue_redraw()
		return
	if selected_units.is_empty():
		return
	var world := _screen_to_world(board_rect, screen_position)
	var spacing_values: Array[float] = [1.0, 3.0, 6.0]
	var spacing: float = spacing_values[camera_zoom_level]
	var snapped := movement_system.snap_to_grid(world, spacing)
	for unit in selected_units:
		unit.destination = movement_system.clamp_to_battlefield(snapped, BATTLEFIELD_WIDTH, BATTLEFIELD_HEIGHT)
		unit.has_order = true
	_refresh_buttons()
	queue_redraw()

func _pick_player_unit_at(board_rect: Rect2, screen_position: Vector2):
	for unit in player_units:
		if not unit.alive:
			continue
		var pos := _world_to_screen(board_rect, unit.position)
		var rect := Rect2(pos - Vector2(20, 14), Vector2(40, 28))
		if rect.has_point(screen_position):
			return unit
	return null

func _on_engage_pressed() -> void:
	battle_state.start_engagement()
	GameState.engagement_turn = 1
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
	battle_state.next_turn()
	GameState.engagement_turn = battle_state.turn
	if _all_dead(enemy_units) or _all_dead(player_units):
		battle_state.move_to_consolidation()
		_emit_battle_resolved_once()
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
			"player_units_destroyed": GameState.player_units_destroyed,
			"enemy_units_destroyed": GameState.enemy_units_destroyed
		}
	)

func _resolve_combat_step() -> void:
	for unit in player_units:
		if not unit.alive:
			continue
		var target = combat_system.pick_closest_enemy(unit.position, enemy_units)
		if combat_system.resolve_attack(unit, target):
			GameState.enemy_units_destroyed += 1
	for unit in enemy_units:
		if not unit.alive:
			continue
		var target = combat_system.pick_closest_enemy(unit.position, player_units)
		if combat_system.resolve_attack(unit, target):
			GameState.player_units_destroyed += 1

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
		order_info.text = "Deployment Stage: place units wholly in your zone, then Engage Enemy."
	elif battle_state.stage == BATTLE_STATE_SCRIPT.Stage.ENGAGEMENT:
		var warning := ""
		if units_without_orders > 0:
			warning = " (%d units had no order)" % units_without_orders
		order_info.text = "Engagement Stage: Turn %d%s" % [battle_state.turn, warning]
	else:
		order_info.text = "Consolidation: Player destroyed %d, Enemy destroyed %d" % [GameState.enemy_units_destroyed, GameState.player_units_destroyed]

func _refresh_buttons() -> void:
	engage_button.visible = battle_state.stage == BATTLE_STATE_SCRIPT.Stage.DEPLOYMENT
	execute_button.visible = battle_state.stage == BATTLE_STATE_SCRIPT.Stage.ENGAGEMENT
