extends Control

## Battlefield scene: displays Unit Entities as colored circles, resolves
## combat turn-by-turn using the Combat System pipeline, shows results.

const FIELD_WIDTH := 200.0
const FIELD_HEIGHT := 100.0
const DEPLOY_ZONE_DEPTH := 20.0
const PIXELS_PER_UNIT := 5.0

var _scenario_id: String = ""
var _attacker_units: Array[UnitData] = []
var _defender_units: Array[UnitData] = []
var _orchestrator := CombatOrchestrator.new()
var _bot := SimpleBot.new()
var _current_turn := 0
var _battle_over := false

@onready var field_panel: Panel = %FieldPanel
@onready var turn_label: Label = %TurnLabel
@onready var status_label: Label = %StatusLabel
@onready var engage_btn: Button = %EngageButton
@onready var next_turn_btn: Button = %NextTurnButton
@onready var back_btn: Button = %BackButton
@onready var unit_display: Control = %UnitDisplay
@onready var combat_log_label: RichTextLabel = %CombatLogLabel
@onready var combat_log_scroll: ScrollContainer = %ScrollContainer
@onready var unit_status_bar: HBoxContainer = %UnitStatusBar
@onready var orders_label: Label = %OrdersLabel
@onready var move_closer_btn: Button = %MoveCloserButton
@onready var move_away_btn: Button = %MoveAwayButton
@onready var attack_btn: Button = %AttackButton

var _attacker_order_override: String = ""  # "move_closer", "move_away", "attack", or "" for auto


func _ready() -> void:
	_scenario_id = GameData.selected_scenario_id if not GameData.selected_scenario_id.is_empty() else "mirror_match"
	engage_btn.pressed.connect(_on_engage)
	next_turn_btn.pressed.connect(_on_next_turn)
	back_btn.pressed.connect(_on_back)
	move_closer_btn.pressed.connect(_on_order_move_closer)
	move_away_btn.pressed.connect(_on_order_move_away)
	attack_btn.pressed.connect(_on_order_attack)
	next_turn_btn.visible = false
	orders_label.visible = false
	move_closer_btn.visible = false
	move_away_btn.visible = false
	attack_btn.visible = false

	_setup_battle()


func _setup_battle() -> void:
	var raw := DataLoader.load_scenarios()
	var scenarios: Array = raw.get("scenarios", [])
	var scenario_def: Dictionary = {}
	for s: Dictionary in scenarios:
		if s.get("id", "") == _scenario_id:
			scenario_def = s
			break

	if scenario_def.is_empty():
		status_label.text = "Scenario not found: %s" % _scenario_id
		return

	_attacker_units = _build_force(scenario_def, "attacker")
	_defender_units = _build_force(scenario_def, "defender")

	_bot.deploy_units(_defender_units, DEPLOY_ZONE_DEPTH / 2.0, FIELD_WIDTH)
	status_label.text = "Deploy and Engage!"
	turn_label.text = "Deployment"
	combat_log_label.text = "[color=gray]Deploy and press Engage to start combat.[/color]"
	_update_display()


func _build_force(scenario_def: Dictionary, side: String) -> Array[UnitData]:
	var units: Array[UnitData] = []
	var forces: Array = scenario_def.get("forces", [])
	var y_base := FIELD_HEIGHT - DEPLOY_ZONE_DEPTH / 2.0 if side == "attacker" else DEPLOY_ZONE_DEPTH / 2.0
	for force: Dictionary in forces:
		if force.get("side", "") != side:
			continue
		for entry: Dictionary in force.get("units", []):
			var unit_id: String = entry.get("unit_id", "")
			var count: int = int(entry.get("count", 1))
			for _j in range(count):
				var unit := GameData.unit_factory.create_unit(unit_id)
				if unit != null:
					unit.position = Vector2(
						40.0 + units.size() * 30.0,
						y_base
					)
					units.append(unit)
	return units


func _on_engage() -> void:
	engage_btn.visible = false
	next_turn_btn.visible = true
	orders_label.visible = true
	move_closer_btn.visible = true
	move_away_btn.visible = true
	attack_btn.visible = true
	_current_turn = 1
	turn_label.text = "Engagement: Turn %d" % _current_turn
	status_label.text = "Choose orders (or leave auto), then Next Turn"


func _on_next_turn() -> void:
	if _battle_over:
		return

	# Reset per-turn movement tracking
	for u in _attacker_units:
		u.distance_moved_this_turn = 0.0
	for u in _defender_units:
		u.distance_moved_this_turn = 0.0

	# Set orders: defender uses auto (attack if in range else move_closer)
	_bot.set_orders(_defender_units, _attacker_units)
	# Attacker: use player override if set, else auto
	if _attacker_order_override.is_empty():
		_bot.set_orders(_attacker_units, _defender_units)
	else:
		for u in _attacker_units:
			if not u.is_destroyed():
				u.order = _attacker_order_override

	# Move only units that chose move_closer (not attacking)
	_bot.advance_units(_attacker_units, _defender_units, 3.0)
	_bot.advance_units(_defender_units, _attacker_units, 3.0)

	# Resolve attacks for units that chose attack (uses actual unit positions for range)
	var turn_result := _orchestrator.resolve_single_exchange(
		_attacker_units, _defender_units, 0.0
	)

	var atk_alive := 0
	for u in _attacker_units:
		atk_alive += u.get_alive_count()
	var def_alive := 0
	for u in _defender_units:
		def_alive += u.get_alive_count()

	status_label.text = "Turn %d: Attacker %d models | Defender %d models | Dmg dealt: %d" % [
		_current_turn, atk_alive, def_alive, turn_result.total_damage_dealt
	]

	if atk_alive <= 0 or def_alive <= 0:
		_battle_over = true
		next_turn_btn.visible = false
		var winner := "Attacker" if def_alive <= 0 else "Defender"
		if atk_alive <= 0 and def_alive <= 0:
			winner = "Draw"
		turn_label.text = "Battle Over - %s Wins!" % winner
		status_label.text = "Attacker lost %d models | Defender lost %d models" % [
			turn_result.attacker_models_lost, turn_result.defender_models_lost
		]
	else:
		_current_turn += 1
		turn_label.text = "Engagement: Turn %d" % _current_turn

	for turn_log in turn_result.turn_logs:
		_append_turn_log(turn_log)
	_scroll_combat_log_to_bottom()
	_update_display()


func _update_display() -> void:
	for child in unit_display.get_children():
		child.queue_free()

	_draw_units(_attacker_units, Color(0.2, 0.4, 0.8, 0.8))
	_draw_units(_defender_units, Color(0.8, 0.2, 0.2, 0.8))
	_update_unit_status_bar()


func _draw_units(units: Array[UnitData], color: Color) -> void:
	for unit in units:
		var alive := unit.get_alive_models()
		var cols := ceili(sqrt(float(alive.size())))
		for i in range(alive.size()):
			var row: int = i / maxi(cols, 1)
			var col: int = i % maxi(cols, 1)
			var circle := ColorRect.new()
			circle.size = Vector2(6, 6)
			circle.color = color
			circle.position = Vector2(
				unit.position.x * PIXELS_PER_UNIT + col * 8,
				unit.position.y * PIXELS_PER_UNIT + row * 8
			)
			unit_display.add_child(circle)


func _append_turn_log(turn_log: TurnLog) -> void:
	var lines: PackedStringArray = []
	lines.append("[b]--- Turn %d ---[/b]" % turn_log.turn_number)

	for evt in turn_log.events:
		var base_pct := int(roundf(evt.base_hit_chance * 100.0))
		var range_pct := int(roundf(evt.range_modifier * 100.0))
		var evasion_pct := int(roundf(evt.evasion_factor * 100.0))
		var final_pct := int(roundf(evt.hit_chance * 100.0))
		var move_pct := int(roundf(evt.movement_factor * 100.0))
		var range_str := ""
		if range_pct >= 0:
			range_str = "+%d%%" % range_pct
		else:
			range_str = "%d%%" % range_pct

		var line := "[%s] %s → %s \"%s\" (%d%% base %s range - %d%% evasion) × %d%% move = %d%% hit) — " % [
			evt.attacker_unit_name, evt.attacker_name, evt.target_name, evt.attack_name,
			base_pct, range_str, evasion_pct, move_pct, final_pct
		]
		if evt.hit and evt.damage_instance != null:
			var dmg: DamageInstance = evt.damage_instance
			line += "[color=#aaffaa]HIT: %d %s[/color]" % [dmg.damage_value, dmg.damage_type]
			if dmg.armour_applied > 0:
				line += ", [color=yellow]%d mitigated[/color] → %d applied" % [dmg.armour_applied, dmg.mitigated_value]
			else:
				line += " → %d applied" % dmg.mitigated_value
			if dmg.resulted_in_kill:
				line += " [color=red][b]*** KILLED ***[/b][/color]"
		else:
			line += "[color=gray]MISS[/color]"
		lines.append(line)

	if turn_log.attacker_summary != null:
		var atk_s: TurnLog.TurnLogSideSummary = turn_log.attacker_summary
		lines.append("")
		lines.append("[color=#88aaff]Attacker: %d attacks, %d hits, %d miss | %d dmg dealt | %d kills[/color]" % [
			atk_s.attacks_made, atk_s.hits, atk_s.misses, atk_s.total_damage_dealt, atk_s.models_killed
		])
	if turn_log.defender_summary != null:
		var def_s: TurnLog.TurnLogSideSummary = turn_log.defender_summary
		lines.append("[color=#ff8888]Defender: %d attacks, %d hits, %d miss | %d dmg dealt | %d kills[/color]" % [
			def_s.attacks_made, def_s.hits, def_s.misses, def_s.total_damage_dealt, def_s.models_killed
		])
	lines.append("")

	combat_log_label.text += "\n".join(lines)


func _scroll_combat_log_to_bottom() -> void:
	await get_tree().process_frame
	var vbar := combat_log_scroll.get_v_scroll_bar()
	if vbar != null:
		combat_log_scroll.set_deferred("scroll_vertical", int(vbar.max_value))


func _update_unit_status_bar() -> void:
	for child in unit_status_bar.get_children():
		child.queue_free()

	for unit in _attacker_units:
		unit_status_bar.add_child(_make_unit_status_card(unit, Color(0.2, 0.4, 0.8)))
	for unit in _defender_units:
		unit_status_bar.add_child(_make_unit_status_card(unit, Color(0.8, 0.2, 0.2)))


func _make_unit_status_card(unit: UnitData, color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var label := Label.new()
	var alive := unit.get_alive_count()
	var total := unit.get_total_models()
	var hp_pool := 0
	for model in unit.get_alive_models():
		hp_pool += model.get_remaining_durability()
	var name_str := unit.display_name if unit.display_name else unit.id
	label.text = "%s: %d/%d models | %d HP" % [name_str, alive, total, hp_pool]
	label.add_theme_color_override("font_color", color if alive > 0 else Color(0.4, 0.4, 0.4))
	panel.add_child(label)
	return panel


func _on_order_move_closer() -> void:
	_attacker_order_override = "move_closer"
	_apply_attacker_order_override()


func _on_order_move_away() -> void:
	_attacker_order_override = "move_away"
	_apply_attacker_order_override()


func _on_order_attack() -> void:
	_attacker_order_override = "attack"
	_apply_attacker_order_override()


func _apply_attacker_order_override() -> void:
	if _attacker_order_override.is_empty():
		return
	for u in _attacker_units:
		if not u.is_destroyed():
			u.order = _attacker_order_override


func _on_back() -> void:
	get_tree().change_scene_to_file("res://src/ui/scenario_select.tscn")
