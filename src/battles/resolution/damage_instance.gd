class_name DamageInstance
extends RefCounted

## A single instance of damage produced by an attack hitting its target.
## Consumed by the defense resolver to determine model survival.

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
