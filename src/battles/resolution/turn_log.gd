class_name TurnLog
extends RefCounted

## Aggregates all CombatEvents for one turn plus per-side summaries.
## Built by CombatOrchestrator after resolving attacks.

class TurnLogSideSummary:
	extends RefCounted
	var attacks_made: int = 0
	var hits: int = 0
	var misses: int = 0
	var total_damage_dealt: int = 0
	var total_damage_mitigated: int = 0
	var models_killed: int = 0

var turn_number: int = 0
var events: Array[CombatEvent] = []
var attacker_summary: TurnLogSideSummary = null
var defender_summary: TurnLogSideSummary = null
