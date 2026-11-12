class_name OverworldEngagements
extends SoaTable
## One row per engagement on the overworld: a hex where a battle is pending
## or running (a "battle tile", R4Q13). Commanders join by entering the hex;
## OverworldCommanders.engagement points back here. Battles are created from
## engagements at the start of a turn (R2Q1); results end them.

const GUARD: int = 1       ## a neutral guard on the hex fights
const COMMANDERS: int = 2  ## hostile commanders met
const ACTIVITY: int = 4    ## a commander-led battle activity (R4Q12)
const DETACHMENTS: int = 8 ## a hostile detachment met (R5Q9)

var plot := PackedInt64Array()
var kinds := PackedInt64Array()   ## GUARD | COMMANDERS | ACTIVITY | DETACHMENTS bits
var turn := PackedInt64Array()    ## overworld turn it began


func _init() -> void:
	super(&"engagement")
	for c: StringName in [&"plot", &"kinds", &"turn"]:
		declare(c, 0)
