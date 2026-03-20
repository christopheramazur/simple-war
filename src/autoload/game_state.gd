extends Node

const PLAYER_FACTION: String = "Concord"
const ENEMY_FACTION: String = "Opposition"

var selected_army_name: String = ""
var armybuilding_complete: bool = false
var commander_at_battle: bool = false
var engagement_turn: int = 1
var player_units_destroyed: int = 0
var enemy_units_destroyed: int = 0

func reset_quick_play() -> void:
	selected_army_name = ""
	armybuilding_complete = false
	commander_at_battle = false
	engagement_turn = 1
	player_units_destroyed = 0
	enemy_units_destroyed = 0
