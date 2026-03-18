class_name CombatEvent
extends RefCounted

## One attack attempt: hit or miss. Produced by the Attack Pipeline for
## every roll. Used by TurnLog and the combat log UI for transparency.

var attacker_name: String = ""
var attacker_unit_name: String = ""
var target_name: String = ""
var target_unit_name: String = ""
var attack_name: String = ""
var attack_category: String = "melee"  # "ranged" or "melee"
var distance: float = 0.0
var hit_chance: float = 0.0
var hit: bool = false

# Hit chance breakdown components for transparency
var base_hit_chance: float = 0.0
var range_modifier: float = 0.0
var evasion_factor: float = 0.0
var movement_factor: float = 1.0

var damage_instance: DamageInstance = null  # non-null only when hit
