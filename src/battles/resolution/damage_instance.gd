class_name DamageInstance
extends RefCounted

## A Damage Instance produced by the Attack Pipeline on a successful hit.
## Consumed by the Defense Pipeline to apply ArmourComponent mitigation
## and update the target Model Entity's DestructionStateComponent.

var damage_value: int = 0
var damage_type: String = "kinetic"

# Source metadata for transparency / logging
var source_model_id: String = ""
var source_attack_id: String = ""
var source_unit_id: String = ""

# Target metadata
var target_model_id: String = ""
var target_unit_id: String = ""

# Resolution metadata (filled after defense resolves)
var mitigated_value: int = 0
var armour_applied: int = 0
var resulted_in_kill: bool = false
