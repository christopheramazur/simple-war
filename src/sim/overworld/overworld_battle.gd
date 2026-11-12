class_name OverworldBattle
extends RefCounted
## One battle in progress for an overworld engagement (OverworldBattles).

var engagement: int
var plot: int
var context_id: int
var scenario: String
var rules: BattleRules
var state: BattleState
## Battle squad ID -> overworld squad ID (-1 = a neutral guard).
var links: Dictionary = {}
## Pending battle orders this turn: player -> Array.
var orders: Dictionary = {}
