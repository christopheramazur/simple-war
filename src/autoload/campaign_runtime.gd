extends Node

const VALIDATOR_SCRIPT := preload("res://src/campaign/systems/commander_intent_validation_system.gd")
const SCRIPT_FLOW := "res://src/campaign/components/c_campaign_flow.gd"
const SCRIPT_AUDIT := "res://src/campaign/components/c_audit_log.gd"
const SCRIPT_COMMANDER := "res://src/campaign/components/c_commander_state.gd"
const SCRIPT_BATTLE := "res://src/campaign/components/c_battle_session.gd"
const CompBattle := preload("res://src/campaign/components/c_battle_session.gd")

var _campaign_entity: Entity = null
var _commander_entity: Entity = null
var validator := VALIDATOR_SCRIPT.new()

## Mirrors battle session component for UI and battlefield (single source: ECS component).
var engagement_turn: int:
	get:
		var b: Variant = _battle_session()
		return b.engagement_turn if b else 1
	set(value):
		var b: Variant = _battle_session()
		if b:
			b.engagement_turn = value as int

var player_units_destroyed: int:
	get:
		var b: Variant = _battle_session()
		return b.player_units_destroyed if b else 0
	set(value):
		var b: Variant = _battle_session()
		if b:
			b.player_units_destroyed = value as int

var enemy_units_destroyed: int:
	get:
		var b: Variant = _battle_session()
		return b.enemy_units_destroyed if b else 0
	set(value):
		var b: Variant = _battle_session()
		if b:
			b.enemy_units_destroyed = value as int

func _ready() -> void:
	if ECS.world != null:
		start_quickplay()
	else:
		ECS.world_changed.connect(_on_world_ready, CONNECT_ONE_SHOT)

func _on_world_ready(_world: World) -> void:
	start_quickplay()

func start_quickplay() -> void:
	if ECS.world == null:
		push_error("CampaignRuntime.start_quickplay: ECS.world is null")
		return
	_cleanup_campaign_entities()
	var c_ent := Entity.new()
	c_ent.name = "Campaign"
	c_ent.add_component(C_CampaignFlow.new())
	c_ent.add_component(C_AuditLog.new())
	c_ent.add_component(CompBattle.new())
	ECS.world.add_entity(c_ent)
	var cmd_ent := Entity.new()
	cmd_ent.name = "Commander"
	cmd_ent.add_component(C_CommanderState.new())
	ECS.world.add_entity(cmd_ent)
	_campaign_entity = c_ent
	_commander_entity = cmd_ent
	reset_battle_session()
	_append_event("campaign.started", {})
	_rebuild_projection()

func _cleanup_campaign_entities() -> void:
	if ECS.world == null:
		return
	if is_instance_valid(_commander_entity):
		ECS.world.remove_entity(_commander_entity)
		_commander_entity = null
	if is_instance_valid(_campaign_entity):
		ECS.world.remove_entity(_campaign_entity)
		_campaign_entity = null

func reset_battle_session() -> void:
	var b: Variant = _battle_session()
	if b:
		b.engagement_turn = 1
		b.player_units_destroyed = 0
		b.enemy_units_destroyed = 0

func submit_intent(intent_type: String, payload: Dictionary = {}) -> Dictionary:
	if not is_instance_valid(_commander_entity) or not is_instance_valid(_campaign_entity):
		return {"ok": false, "reason": "Campaign not initialized"}
	var validation: Dictionary = validator.validate(intent_type, _commander_entity, _campaign_entity)
	if not validation.get("ok", false):
		return validation
	_apply_intent(intent_type, payload)
	_rebuild_projection()
	return {"ok": true}

func get_sector_projection() -> Dictionary:
	var commander: C_CommanderState = _commander()
	var flow: C_CampaignFlow = _flow()
	if commander == null or flow == null:
		return {
			"army_selected": false,
			"moved_to_battle_plot": false,
			"current_plot_id": "armybuilding",
			"can_begin_activity": true,
			"can_move": false,
			"can_start_battle": false,
			"route_target": "res://src/ui/armybuilding.tscn",
			"note_text": "Loading…"
		}
	return {
		"army_selected": commander.army_selected,
		"moved_to_battle_plot": commander.moved_to_battle_plot,
		"current_plot_id": commander.current_plot_id,
		"can_begin_activity": not commander.army_selected,
		"can_move": commander.army_selected and not commander.moved_to_battle_plot,
		"can_start_battle": commander.moved_to_battle_plot,
		"route_target": flow.route_target,
		"note_text": flow.note_text
	}

func get_selected_army_name() -> String:
	var c: C_CommanderState = _commander()
	return c.selected_army_name if c else ""

func get_event_count() -> int:
	var a: C_AuditLog = _audit()
	return a.events.size() if a else 0

func _flow() -> C_CampaignFlow:
	if not is_instance_valid(_campaign_entity):
		return null
	return _campaign_entity.components.get(SCRIPT_FLOW) as C_CampaignFlow

func _commander() -> C_CommanderState:
	if not is_instance_valid(_commander_entity):
		return null
	return _commander_entity.components.get(SCRIPT_COMMANDER) as C_CommanderState

func _audit() -> C_AuditLog:
	if not is_instance_valid(_campaign_entity):
		return null
	return _campaign_entity.components.get(SCRIPT_AUDIT) as C_AuditLog

func _battle_session() -> Variant:
	if not is_instance_valid(_campaign_entity):
		return null
	return _campaign_entity.components.get(SCRIPT_BATTLE)

func _apply_intent(intent_type: String, payload: Dictionary) -> void:
	var commander: C_CommanderState = _commander()
	match intent_type:
		"campaign.embark":
			_append_event("campaign.embarked", {})
		"armybuilding.select":
			var army_name: String = str(payload.get("army_name", "Militia"))
			commander.army_selected = true
			commander.selected_army_name = army_name
			_append_event("armybuilding.selected", {"army_name": army_name})
		"sector.move_to_battle":
			_append_event("sector.move.requested", {"from_plot": commander.current_plot_id, "to_plot": "battle"})
			commander.current_plot_id = "battle"
			commander.moved_to_battle_plot = true
			_append_event("sector.commander.moved", {"to_plot": "battle"})
		"battleplanning.start":
			commander.battle_planning_ready = true
			reset_battle_session()
			_append_event("battleplanning.started", {"army_name": commander.selected_army_name})
			_append_event("battle.started", {})
		"battle.resolve":
			var p_lost: int = int(payload.get("player_units_destroyed", self.player_units_destroyed))
			var e_lost: int = int(payload.get("enemy_units_destroyed", self.enemy_units_destroyed))
			_append_event("battle.resolved", {
				"player_units_destroyed": p_lost,
				"enemy_units_destroyed": e_lost
			})
		_:
			push_warning("CampaignRuntime ignored unknown intent: %s" % intent_type)

func _rebuild_projection() -> void:
	var flow: C_CampaignFlow = _flow()
	var commander: C_CommanderState = _commander()
	if not commander.army_selected:
		flow.phase = "Opening"
		flow.route_target = "res://src/ui/armybuilding.tscn"
		flow.note_text = "We need an army to approach the battle!"
	elif not commander.moved_to_battle_plot:
		flow.phase = "SectorTraversal"
		flow.route_target = "res://src/ui/sector_map.tscn"
		flow.note_text = "Move your Commander to the battle!"
	elif not commander.battle_planning_ready:
		flow.phase = "BattlePreparation"
		flow.route_target = "res://src/ui/battle_planning.tscn"
		flow.note_text = "Better them than us!"
	else:
		flow.phase = "BattleActive"
		flow.route_target = "res://src/ui/battlefield.tscn"
		flow.note_text = "Battle engaged."

func _append_event(event_type: String, payload: Dictionary) -> void:
	var audit_log: C_AuditLog = _audit()
	var event_payload: Dictionary = {
		"seq": audit_log.next_seq,
		"type": event_type,
		"payload": payload.duplicate(true)
	}
	audit_log.events.append(event_payload)
	audit_log.next_seq += 1
