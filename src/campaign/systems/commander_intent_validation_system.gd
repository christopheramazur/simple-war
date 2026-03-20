class_name CommanderIntentValidationSystem
extends RefCounted

const FLOW_COMPONENT := preload("res://src/campaign/components/c_campaign_flow.gd")
const COMMANDER_COMPONENT := preload("res://src/campaign/components/c_commander_state.gd")

func validate(intent_type: String, commander_entity: Dictionary, campaign_entity: Dictionary) -> Dictionary:
	var flow = campaign_entity.get("flow")
	var commander = commander_entity.get("commander")
	match intent_type:
		"armybuilding.select":
			return {"ok": true}
		"sector.move_to_battle":
			if not commander.army_selected:
				return {"ok": false, "reason": "Army must be selected before movement."}
			if commander.moved_to_battle_plot:
				return {"ok": false, "reason": "Commander is already at the battle plot."}
			return {"ok": true}
		"battleplanning.start":
			if not commander.moved_to_battle_plot:
				return {"ok": false, "reason": "Move the commander to battle before starting battle planning."}
			return {"ok": true}
		"battle.resolve":
			if flow.phase != "BattleActive":
				return {"ok": false, "reason": "Battle can only be resolved while active."}
			return {"ok": true}
		"campaign.embark":
			return {"ok": true}
		_:
			return {"ok": false, "reason": "Unknown intent: %s" % intent_type}
