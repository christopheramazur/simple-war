class_name OverworldItems
extends SoaTable
## One row per stack of identical items on the overworld (GDD 02 §2.9,
## R4Q10). A stack is in exactly one place: a commander's War Chest
## (`holder`), a detachment's or convoy's War Chest (`detachment`), or
## equipped to a squad (`squad`); the other two are -1. Written only
## through WarChest.

var tmpl := PackedInt64Array()        ## OverworldRules item index
var qty := PackedInt64Array()         ## items in the stack, >= 1
var holder := PackedInt64Array()      ## commander ID whose chest holds it
var detachment := PackedInt64Array()  ## detachment ID whose chest holds it
var squad := PackedInt64Array()       ## squad ID it is equipped to


func _init() -> void:
	super(&"ow_item")
	for c: StringName in [&"tmpl", &"qty"]:
		declare(c, 0)
	declare(&"holder", -1)
	declare(&"detachment", -1)
	declare(&"squad", -1)
