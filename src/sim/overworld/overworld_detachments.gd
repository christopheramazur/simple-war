class_name OverworldDetachments
extends SoaTable
## One row per detachment on the overworld (GDD 02 §2.3, R5Q9): squads a
## commander dropped off, holding a hex without a commander. Squads point
## here through OverworldSquads.detachment. Written only through Detachments.

var player := PackedInt64Array()      ## owning player
var plot := PackedInt64Array()        ## the hex it holds
## Engagement the detachment is held in, -1 = none.
var engagement := PackedInt64Array()


func _init() -> void:
	super(&"detachment")
	for c: StringName in [&"player", &"plot"]:
		declare(c, 0)
	declare(&"engagement", -1)
