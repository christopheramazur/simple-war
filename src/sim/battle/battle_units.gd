class_name BattleUnits
extends SoaTable
## One row per simulated model (Unit). GDD 02 §2.1, 03 §3.2.
## Owner: the battle systems; only systems write these columns.

var squad := PackedInt64Array()        ## owning squad ID
var tmpl := PackedInt64Array()         ## BattleRules unit template index
## Weapon (-1 = none) and defense profile indices: the template's, or an
## item's from the War Chest (R3Q7).
var weapon := PackedInt64Array()
var defense := PackedInt64Array()
var slot := PackedInt64Array()         ## formation slot within the squad
var x := PackedInt64Array()            ## fixed
var y := PackedInt64Array()            ## fixed
var facing := PackedInt64Array()       ## binary angle
var speed := PackedInt64Array()        ## current speed, fixed per tick
var moving := PackedByteArray()        ## moved this tick
var hp := PackedInt64Array()            ## fixed; dead at <= 0 (E3Q1)
var hp_max := PackedInt64Array()        ## fixed; effects change it via Health.set_max
var temp_hp := PackedInt64Array()      ## wards and shields (R7Q1)
var cooldown := PackedInt64Array()     ## ticks until it may fire
var ammo := PackedInt64Array()
var reload := PackedInt64Array()       ## ticks of reload left
var acc_hit := PackedInt64Array()      ## accuracy accumulator, fixed (R2Q6)
var acc_evade := PackedInt64Array()    ## evasion accumulator, percent points
var acc_block := PackedInt64Array()    ## block accumulator, percent points
## Prowess fire policy accumulators (TargetPolicy, sw-pd2l.5), fixed: the
## carried fraction of the focus width K, and coordination percent points.
var acc_focus := PackedInt64Array()
var acc_coord := PackedInt64Array()
var hits := PackedInt64Array()         ## hits landed, for "every Nth" crits
var fired_tick := PackedInt64Array()   ## last tick it fired, -1 never
## Firing position under attack orders (FiringPositions, sw-txnj.5): fpos is
## FiringPositions.NONE / HAS / LACKS / UNACHIEVABLE; fx, fy the point (fixed)
## while HAS.
var fpos := PackedByteArray()
var fx := PackedInt64Array()
var fy := PackedInt64Array()
## 1 while a unit of another squad stands within 1.5 x their separation
## distance (Separation, sw-txnj.12; set by each tick's separation pass).
var crowded := PackedByteArray()


func _init() -> void:
	super(&"unit")
	for c: StringName in [&"squad", &"tmpl", &"weapon", &"defense", &"slot", &"x", &"y", &"facing", &"speed", &"moving",
			&"hp", &"hp_max", &"temp_hp", &"cooldown", &"ammo", &"reload", &"acc_hit", &"acc_evade",
			&"acc_block", &"acc_focus", &"acc_coord", &"hits", &"fpos", &"fx", &"fy", &"crowded"]:
		declare(c, 0)
	declare(&"fired_tick", -1)
