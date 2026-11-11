class_name BattleEffects
extends SoaTable
## One row per active bundle instance (GDD 02 §2.13). Written only through
## Effects (apply/remove) and EffectSystem.

var bundle := PackedInt64Array()        ## EffectRules index
var holder_squad := PackedInt64Array()  ## squad ID it sits on
var holder_unit := PackedInt64Array()   ## unit ID, -1 = on the whole squad
var source := PackedInt64Array()        ## squad ID that applied it, -1 none
var stacks := PackedInt64Array()
var applied := PackedInt64Array()       ## tick applied or last refreshed
var expires := PackedInt64Array()       ## tick it ends, -1 = lasts the battle
var depth := PackedInt64Array()         ## 0 = applied directly; 1 = by a hook
var acc := PackedInt64Array()           ## accumulator value, fixed
var acc_last := PackedInt64Array()      ## tick of the last counted event
var hook_ready := PackedInt64Array()    ## tick hooks may fire again


func _init() -> void:
	super(&"effect")
	for c: StringName in [&"bundle", &"holder_squad", &"stacks", &"applied", &"depth", &"acc", &"acc_last", &"hook_ready"]:
		declare(c, 0)
	for c: StringName in [&"holder_unit", &"source", &"expires"]:
		declare(c, -1)
