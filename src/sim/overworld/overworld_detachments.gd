class_name OverworldDetachments
extends SoaTable
## One row per detachment on the overworld (GDD 02 §2.3, R5Q9, R6Q13):
## squads without a commander. One holding a hex (dropped off, or produced
## with no supply line) has no destination; a convoy has one and moves.
## Squads point here through OverworldSquads.detachment. Written only
## through Detachments and Convoys.

var player := PackedInt64Array()      ## owning player
var plot := PackedInt64Array()        ## the hex it holds
## Engagement the detachment is held in, -1 = none.
var engagement := PackedInt64Array()
## Convoy destination: a plot, or a commander of the same player; both -1
## for a detachment holding its hex.
var dest_plot := PackedInt64Array()
var dest_commander := PackedInt64Array()
## Feature ID of the supply line it travels, -1 = none (a rally).
var line := PackedInt64Array()


func _init() -> void:
	super(&"detachment")
	for c: StringName in [&"player", &"plot"]:
		declare(c, 0)
	declare(&"engagement", -1)
	declare(&"dest_plot", -1)
	declare(&"dest_commander", -1)
	declare(&"line", -1)
