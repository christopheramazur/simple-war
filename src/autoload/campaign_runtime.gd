extends Node

const FLOW_COMPONENT := preload("res://src/campaign/components/c_campaign_flow.gd")
const COMMANDER_COMPONENT := preload("res://src/campaign/components/c_commander_state.gd")
const AUDIT_COMPONENT := preload("res://src/campaign/components/c_audit_log.gd")
const VALIDATOR_SCRIPT := preload("res://src/campaign/systems/commander_intent_validation_system.gd")

var campaign_entity: Dictionary = {}
var commander_entity: Dictionary = {}
var validator := VALIDATOR_SCRIPT.new()

func _ready() -> void:
	start_quickplay()

func start_quickplay() -> void:
	campaign_entity = {
		"flow": FLOW_COMPONENT.new(),
		"audit": AUDIT_COMPONENT.new()
	}
	commander_entity = {
		"commander": COMMANDER_COMPONENT.new()
	}
	_append_event("campaign.started", {})
	_rebuild_projection()

func submit_intent(intent_type: String, payload: Dictionary = {}) -> Dictionary:
	var validation: Dictionary = validator.validate(intent_type, commander_entity, campaign_entity)
	if not validation.get("ok", false):
		return validation
	_apply_intent(intent_type, payload)
	_rebuild_projection()
	return {"ok": true}

func get_sector_projection() -> Dictionary:
	var commander = commander_entity.get("commander")
	var flow = campaign_entity.get("flow")
	return {
		"army_selected": commander.army_selected,
		"moved_to_battle_plot": commander.moved_to_battle_plot,
		"can_begin_activity": not commander.army_selected,
		"can_move": commander.army_selected and not commander.moved_to_battle_plot,
		"can_start_battle": commander.moved_to_battle_plot,
		"route_target": flow.route_target,
		"note_text": flow.note_text
	}

func get_selected_army_name() -> String:
	var commander = commander_entity.get("commander")
	return commander.selected_army_name

func get_event_count() -> int:
	var log = campaign_entity.get("audit")
	return log.events.size()

func _apply_intent(intent_type: String, payload: Dictionary) -> void:
	var commander = commander_entity.get("commander")
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
			_append_event("battleplanning.started", {"army_name": commander.selected_army_name})
			_append_event("battle.started", {})
		"battle.resolve":
			var player_units_destroyed: int = int(payload.get("player_units_destroyed", 0))
			var enemy_units_destroyed: int = int(payload.get("enemy_units_destroyed", 0))
			_append_event("battle.resolved", {
				"player_units_destroyed": player_units_destroyed,
				"enemy_units_destroyed": enemy_units_destroyed
			})
		_:
			push_warning("CampaignRuntime ignored unknown intent: %s" % intent_type)

func _rebuild_projection() -> void:
	var flow = campaign_entity.get("flow")
	var commander = commander_entity.get("commander")
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
	var log = campaign_entity.get("audit")
	var event_payload: Dictionary = {
		"seq": log.next_seq,
		"type": event_type,
		"payload": payload.duplicate(true)
	}
	log.events.append(event_payload)
	log.next_seq += 1
