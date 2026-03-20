extends RefCounted
class_name BattleState

enum Stage { DEPLOYMENT, ENGAGEMENT, CONSOLIDATION }

var stage: Stage = Stage.DEPLOYMENT
var turn: int = 1

func start_engagement() -> void:
	stage = Stage.ENGAGEMENT
	turn = 1

func next_turn() -> void:
	turn += 1

func move_to_consolidation() -> void:
	stage = Stage.CONSOLIDATION
