class_name BattleUnits
extends SoaTable
## One row per simulated model (Unit). GDD 02 §2.1, 03 §3.2.
## Owner: the battle systems; only systems write these columns.

var squad := PackedInt64Array()        ## owning squad ID
var tmpl := PackedInt64Array()         ## BattleRules unit template index
var slot := PackedInt64Array()         ## formation slot within the squad
var x := PackedInt64Array()            ## fixed
var y := PackedInt64Array()            ## fixed
var facing := PackedInt64Array()       ## binary angle
var speed := PackedInt64Array()        ## current speed, fixed per tick
var moving := PackedByteArray()        ## moved this tick
var hp := PackedInt64Array()
var temp_hp := PackedInt64Array()      ## wards and shields (R7Q1)
var cooldown := PackedInt64Array()     ## ticks until it may fire
var ammo := PackedInt64Array()
var reload := PackedInt64Array()       ## ticks of reload left
var acc_hit := PackedInt64Array()      ## accuracy accumulator, fixed (R2Q6)
var acc_evade := PackedInt64Array()    ## evasion accumulator, percent points
var acc_block := PackedInt64Array()    ## block accumulator, percent points
var hits := PackedInt64Array()         ## hits landed, for "every Nth" crits
var fired_tick := PackedInt64Array()   ## last tick it fired, -1 never


func _init() -> void:
	super(&"unit")
	for c: StringName in [&"squad", &"tmpl", &"slot", &"x", &"y", &"facing", &"speed", &"moving",
			&"hp", &"temp_hp", &"cooldown", &"ammo", &"reload", &"acc_hit", &"acc_evade",
			&"acc_block", &"hits"]:
		declare(c, 0)
	declare(&"fired_tick", -1)
