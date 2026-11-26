class_name OverworldBattle
extends RefCounted
## One battle in progress for an overworld engagement (OverworldBattles).

var engagement: int
var plot: int
var context_id: int
var scenario: String
var rules: BattleRules
## The scenario's deployment areas ({facing, deploy}), for sides that join later.
var areas: Array = []
var state: BattleState
## Battle squad ID -> overworld squad ID (-1 = a neutral guard).
var links: Dictionary = {}
## Pending battle orders this turn: player -> Array.
var orders: Dictionary = {}
## Pending deployment placements while the battle is deploying: player ->
## Array (BattleDeploy), applied at Reveal.
var deploys: Dictionary = {}
