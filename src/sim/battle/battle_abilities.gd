class_name BattleAbilities
extends SoaTable
## One row per (squad, ability) the squad's template lists, created at spawn
## and kept for the whole battle, like squads (GDD 02 §2.13, E3Q6, E3Q7).
## Written only through Abilities and AbilitySystem.

var squad := PackedInt64Array()          ## squad ID
var ability := PackedInt64Array()        ## BattleRules ability index
var on := PackedByteArray()              ## toggled on, readying, or its state held
var since := PackedInt64Array()          ## tick it was switched on or used
var effect := PackedInt64Array()         ## effect instance of its bundle, -1 none
var ready_at := PackedInt64Array()       ## tick readying ends, -1 = not readying
var cooldown_until := PackedInt64Array() ## tick it may be used again
var charges := PackedInt64Array()        ## uses left, -1 = unlimited
var target := PackedInt64Array()         ## squad ID it was used on, -1 none


func _init() -> void:
	super(&"ability")
	for c: StringName in [&"squad", &"ability", &"on", &"since", &"cooldown_until"]:
		declare(c, 0)
	for c: StringName in [&"effect", &"ready_at", &"charges", &"target"]:
		declare(c, -1)
