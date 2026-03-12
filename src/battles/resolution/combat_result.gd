class_name CombatResult
extends RefCounted

## Collects the full outcome of a combat exchange between forces.

var damage_instances: Array[DamageInstance] = []
var models_destroyed: int = 0
var total_damage_dealt: int = 0
var total_damage_mitigated: int = 0

# Per-side results
var attacker_models_lost: int = 0
var defender_models_lost: int = 0
var attacker_models_remaining: int = 0
var defender_models_remaining: int = 0

# Turn tracking
var turns_elapsed: int = 0

# Per-turn event logs for transparent display (single exchange has one; full battle has one per turn)
var turn_logs: Array[TurnLog] = []


func get_winner() -> String:
	if attacker_models_remaining > 0 and defender_models_remaining <= 0:
		return "attacker"
	elif defender_models_remaining > 0 and attacker_models_remaining <= 0:
		return "defender"
	elif attacker_models_remaining <= 0 and defender_models_remaining <= 0:
		return "draw"
	return "ongoing"
