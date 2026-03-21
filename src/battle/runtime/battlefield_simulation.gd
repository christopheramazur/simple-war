extends RefCounted
class_name BattlefieldSimulation
## Headless battle rules + unit state for the PoC battlefield. No drawing or Control nodes.
## View maps input to screen positions and calls these methods; reads units/battle_state for rendering.

const BattlefieldLayout := preload("res://src/battle/runtime/battlefield_layout.gd")
const BattlefieldCoordinateMapper := preload("res://src/battle/runtime/battlefield_coordinate_mapper.gd")

signal state_changed
signal notice(text: String)

const DRAG_THRESHOLD_PX: float = 8.0

const BATTLE_STATE_SCRIPT := preload("res://src/battle/runtime/battle_state.gd")
const MOVEMENT_SYSTEM_SCRIPT := preload("res://src/battle/systems/movement_system.gd")
const DEPLOYMENT_SYSTEM_SCRIPT := preload("res://src/battle/systems/deployment_system.gd")
const COMBAT_SYSTEM_SCRIPT := preload("res://src/battle/systems/combat_system_minimal.gd")
const UNIT_RUNTIME_SCRIPT := preload("res://src/battle/runtime/unit_runtime.gd")

var battle_state: BattleState
var movement_system: MovementSystem
var deployment_system: DeploymentSystem
var combat_system: CombatSystemMinimal

var player_units: Array = []
var enemy_units: Array = []
var selected_units: Array = []
var selected_reserve_units: Array = []

var battle_resolved_emitted: bool = false
## Last "units without orders" count from [method try_execute_engagement_turn] (for status line when refreshing from [signal state_changed]).
var last_units_without_orders: int = 0

var camera_zoom_level: int = 0

var _mapper: BattlefieldCoordinateMapper

var _left_press_screen: Vector2 = Vector2.ZERO
var _left_press_reserve_unit = null
var _left_press_on_board: bool = false
var _box_select_active: bool = false
var _box_select_start: Vector2 = Vector2.ZERO
var _box_select_end: Vector2 = Vector2.ZERO
var _deployment_drag_active: bool = false
var _deployment_preview_world: Vector2 = Vector2.ZERO
var _engagement_order_drag_active: bool = false
var _engagement_preview_world: Vector2 = Vector2.ZERO

func _init(mapper: BattlefieldCoordinateMapper) -> void:
	_mapper = mapper
	battle_state = BATTLE_STATE_SCRIPT.new()
	movement_system = MOVEMENT_SYSTEM_SCRIPT.new()
	deployment_system = DEPLOYMENT_SYSTEM_SCRIPT.new()
	combat_system = COMBAT_SYSTEM_SCRIPT.new()

func _emit() -> void:
	state_changed.emit()

func spawn_poc_units() -> void:
	player_units.clear()
	enemy_units.clear()
	selected_units.clear()
	battle_resolved_emitted = false
	last_units_without_orders = 0
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
	reset_interaction_state()
	_emit()

func reset_interaction_state() -> void:
	_left_press_reserve_unit = null
	_left_press_on_board = false
	_box_select_active = false
	_deployment_drag_active = false
	_engagement_order_drag_active = false

func reserve_units_ordered() -> Array:
	var reserve_units: Array = []
	for unit in player_units:
		if unit.alive and not unit.deployed:
			reserve_units.append(unit)
	return reserve_units

func deployment_preview_world() -> Vector2:
	return _deployment_preview_world

func engagement_preview_world() -> Vector2:
	return _engagement_preview_world

func box_select_active() -> bool:
	return _box_select_active

func box_select_start() -> Vector2:
	return _box_select_start

func box_select_end() -> Vector2:
	return _box_select_end

func deployment_drag_active() -> bool:
	return _deployment_drag_active

func engagement_order_drag_active() -> bool:
	return _engagement_order_drag_active

func handle_left_press(screen_pos: Vector2) -> void:
	_left_press_screen = screen_pos
	var board_rect := _mapper.board_rect()
	match battle_state.stage:
		BattleState.Stage.DEPLOYMENT:
			_left_press_reserve_unit = _mapper.reserve_unit_at_screen(screen_pos, reserve_units_ordered())
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
				_emit()
		BattleState.Stage.ENGAGEMENT:
			_left_press_on_board = board_rect.has_point(screen_pos)
			var clicked: Variant = pick_player_unit_at_screen(screen_pos)
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
					clear_selection()
					clicked.selected = true
					selected_units = [clicked]
				_emit()
				return
			if _left_press_on_board:
				_box_select_active = true
				_box_select_start = screen_pos
				_box_select_end = screen_pos
				_emit()

func handle_left_drag(screen_pos: Vector2) -> void:
	var board_rect := _mapper.board_rect()
	match battle_state.stage:
		BattleState.Stage.DEPLOYMENT:
			var started_on_reserve := _mapper.reserve_unit_at_screen(_left_press_screen, reserve_units_ordered()) != null
			if not selected_reserve_units.is_empty() and started_on_reserve:
				if _left_press_screen.distance_to(screen_pos) >= DRAG_THRESHOLD_PX:
					_deployment_drag_active = true
			if _deployment_drag_active and board_rect.has_point(screen_pos):
				var raw := _mapper.screen_to_world(screen_pos)
				_deployment_preview_world = movement_system.snap_to_grid(raw, 1.0)
				_emit()
		BattleState.Stage.ENGAGEMENT:
			if _box_select_active:
				_box_select_end = screen_pos
				_emit()
			elif selected_units.size() > 0 and _left_press_on_board:
				if _left_press_screen.distance_to(screen_pos) >= DRAG_THRESHOLD_PX:
					_engagement_order_drag_active = true
			if _engagement_order_drag_active and board_rect.has_point(screen_pos):
				var spacing_values: Array[float] = [1.0, 3.0, 6.0]
				var spacing: float = spacing_values[camera_zoom_level]
				var snapped_world := movement_system.snap_to_grid(_mapper.screen_to_world(screen_pos), spacing)
				_engagement_preview_world = movement_system.clamp_to_battlefield(
					snapped_world, BattlefieldLayout.BATTLEFIELD_WIDTH, BattlefieldLayout.BATTLEFIELD_HEIGHT
				)
				_emit()

func _deferred_notice(msg: String) -> void:
	notice.emit(msg)

func handle_left_release(screen_pos: Vector2) -> void:
	var board_rect := _mapper.board_rect()
	var dist := _left_press_screen.distance_to(screen_pos)
	match battle_state.stage:
		BattleState.Stage.DEPLOYMENT:
			if _deployment_drag_active:
				if deployment_system.is_player_deployment_legal(_deployment_preview_world, BattlefieldLayout.BATTLEFIELD_WIDTH):
					deploy_selected_reserves_at_anchor(_deployment_preview_world)
					_deployment_drag_active = false
				else:
					_deployment_drag_active = false
					_emit()
					call_deferred("_deferred_notice", "Release inside your deployment zone (y=0..20).")
					return
			elif dist < DRAG_THRESHOLD_PX and board_rect.has_point(screen_pos):
				var w := movement_system.snap_to_grid(_mapper.screen_to_world(screen_pos), 1.0)
				if deployment_system.is_player_deployment_legal(w, BattlefieldLayout.BATTLEFIELD_WIDTH):
					if not selected_reserve_units.is_empty():
						deploy_selected_reserves_at_anchor(w)
					else:
						deploy_single_next_at(w)
			_left_press_reserve_unit = null
			_left_press_on_board = false
		BattleState.Stage.ENGAGEMENT:
			if _engagement_order_drag_active:
				for unit in selected_units:
					if unit.alive:
						unit.destination = _engagement_preview_world
						unit.has_order = true
				_engagement_order_drag_active = false
				_emit()
			elif _box_select_active:
				if dist >= DRAG_THRESHOLD_PX:
					apply_box_selection_screen()
				_box_select_active = false
				_emit()
			_left_press_on_board = false
	_left_press_screen = Vector2.ZERO

func deploy_single_next_at(world_pos: Vector2) -> void:
	var unit_to_deploy = next_undeployed_player_unit()
	if unit_to_deploy == null:
		return
	unit_to_deploy.position = movement_system.clamp_to_battlefield(world_pos, BattlefieldLayout.BATTLEFIELD_WIDTH, BattlefieldLayout.BATTLEFIELD_HEIGHT)
	unit_to_deploy.deployed = true
	_emit()

func deploy_selected_reserves_at_anchor(anchor_world: Vector2) -> void:
	if selected_reserve_units.is_empty():
		return
	var to_place: Array = selected_reserve_units.duplicate()
	to_place.sort_custom(func(a, b): return str(a.id) < str(b.id))
	for i in range(to_place.size()):
		var w := anchor_world + Vector2(BattlefieldLayout.BATCH_DEPLOY_SPACING_X * float(i), 0.0)
		w = movement_system.snap_to_grid(w, 1.0)
		if not deployment_system.is_player_deployment_legal(w, BattlefieldLayout.BATTLEFIELD_WIDTH):
			_emit()
			call_deferred("_deferred_notice", "Batch does not fit in zone from this anchor — try fewer units or another spot.")
			return
		var u = to_place[i]
		u.position = movement_system.clamp_to_battlefield(w, BattlefieldLayout.BATTLEFIELD_WIDTH, BattlefieldLayout.BATTLEFIELD_HEIGHT)
		u.deployed = true
	selected_reserve_units.clear()
	_emit()

func apply_box_selection_screen() -> void:
	var r := _mapper.rect_from_points(_box_select_start, _box_select_end)
	if not Input.is_key_pressed(KEY_SHIFT):
		clear_selection()
	for unit in player_units:
		if not unit.alive or not unit.deployed:
			continue
		var ur := _mapper.unit_selection_screen_rect(unit)
		if r.intersects(ur):
			if selected_units.find(unit) < 0:
				selected_units.append(unit)
				unit.selected = true
	_emit()

func pick_player_unit_at_screen(screen_position: Vector2) -> Variant:
	for unit in player_units:
		if not unit.alive:
			continue
		if battle_state.stage == BattleState.Stage.DEPLOYMENT and not unit.deployed:
			continue
		if _mapper.unit_selection_screen_rect(unit).has_point(screen_position):
			return unit
	return null

func try_start_engagement() -> bool:
	if not all_player_units_deployed():
		_emit()
		return false
	battle_state.start_engagement()
	CampaignRuntime.engagement_turn = 1
	_emit()
	return true

func try_execute_engagement_turn() -> int:
	if battle_state.stage != BattleState.Stage.ENGAGEMENT:
		return -1
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
	resolve_combat_step()
	last_units_without_orders = units_without_orders
	if all_dead(enemy_units) or all_dead(player_units):
		battle_state.move_to_consolidation()
		emit_battle_resolved_once()
	else:
		battle_state.next_turn()
		CampaignRuntime.engagement_turn = battle_state.turn
	_emit()
	return units_without_orders

func emit_battle_resolved_once() -> void:
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

func resolve_combat_step() -> void:
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

func all_dead(units: Array) -> bool:
	for unit in units:
		if unit.alive:
			return false
	return true

func clear_selection() -> void:
	for unit in player_units:
		unit.selected = false
	selected_units.clear()

func get_status_text(units_without_orders: int = -1) -> String:
	if battle_state.stage == BattleState.Stage.DEPLOYMENT:
		var remaining: int = count_undeployed_player_units()
		return "Deployment Stage: click inside your zone (y=0..20) to deploy next. %d units remaining." % remaining
	if battle_state.stage == BattleState.Stage.ENGAGEMENT:
		var uwo: int = units_without_orders if units_without_orders >= 0 else last_units_without_orders
		var warning := ""
		if uwo > 0:
			warning = " (%d units had no order)" % uwo
		return "Engagement Stage: Turn %d%s" % [battle_state.turn, warning]
	return "Consolidation: Player destroyed %d, Enemy destroyed %d" % [CampaignRuntime.enemy_units_destroyed, CampaignRuntime.player_units_destroyed]

func engage_button_visible() -> bool:
	return battle_state.stage == BattleState.Stage.DEPLOYMENT

func engage_button_disabled() -> bool:
	return not all_player_units_deployed()

func execute_button_visible() -> bool:
	return battle_state.stage == BattleState.Stage.ENGAGEMENT

func next_undeployed_player_unit():
	for unit in player_units:
		if unit.alive and not unit.deployed:
			return unit
	return null

func count_undeployed_player_units() -> int:
	var remaining := 0
	for unit in player_units:
		if unit.alive and not unit.deployed:
			remaining += 1
	return remaining

func all_player_units_deployed() -> bool:
	return count_undeployed_player_units() == 0
