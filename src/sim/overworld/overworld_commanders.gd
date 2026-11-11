class_name OverworldCommanders
extends SoaTable
## One row per commander on the overworld (GDD 02 §2.3, §2.9). Written only
## through Commanders, OverworldOrders and OverworldMovement.

var player := PackedInt64Array()      ## owning player
var tmpl := PackedInt64Array()        ## OverworldRules commander index
var plot := PackedInt64Array()        ## current plot
## Movement points banked last turn, usable this turn only (R6Q11).
var banked := PackedInt64Array()
## Engagement ID the commander is held in, -1 = free to move.
var engagement := PackedInt64Array()


func _init() -> void:
	super(&"commander")
	for c: StringName in [&"player", &"tmpl", &"plot", &"banked"]:
		declare(c, 0)
	declare(&"engagement", -1)
