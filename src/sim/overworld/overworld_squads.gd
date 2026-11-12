class_name OverworldSquads
extends SoaTable
## One row per squad held on the overworld (GDD 02 §2.3): commanders'
## armies and detachments (convoys come with sw-o1m.2.5). A squad has either
## a holder or a detachment, the other -1. Written only through
## OverworldArmies and Detachments.

var holder := PackedInt64Array()   ## commander ID holding the squad, -1 = none
## Detachment holding the squad, -1 = none.
var detachment := PackedInt64Array()
var tmpl := PackedInt64Array()     ## OverworldRules squad index
var alive := PackedInt64Array()    ## units alive
var size := PackedInt64Array()     ## units at full strength
## 1 = the commander's own squad: never traded, leads its battleforce.
var own := PackedInt64Array()
## Engagement the squad is deployed in as part of a battleforce, -1 = none.
var deployed := PackedInt64Array()


func _init() -> void:
	super(&"ow_squad")
	for c: StringName in [&"holder", &"tmpl", &"alive", &"size", &"own"]:
		declare(c, 0)
	declare(&"deployed", -1)
	declare(&"detachment", -1)
