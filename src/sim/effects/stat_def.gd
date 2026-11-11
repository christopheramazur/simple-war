class_name StatDef
extends RefCounted
## One registered stat (GDD 02 §2.13 Stats, E1Q3, E3Q4). Built by
## StatRegistry from the data schema; read-only after that.

const SCOPE_UNIT: StringName = &"unit"
const SCOPE_SQUAD: StringName = &"squad"

## Dotted ID, e.g. "unit.hp", "defense.resist_pct.kinetic",
## "weapon.modes.*.accuracy" ("*" matches any key of a dynamic map).
var id: String = ""
## Template kind the base value comes from.
var kind: String = ""
## Path inside that kind's template values, e.g. ["resist_pct", "kinetic"].
var path: PackedStringArray = PackedStringArray()
var scope: StringName = SCOPE_UNIT
## Display unit: "%", "m", "ticks", "/s" or "".
var unit: String = ""
## Integral stats round once, to a whole number, at the end of a calculation.
var integral: bool = true
var has_min: bool = false
var has_max: bool = false
## Bounds as raw fixed values.
var min_value: int = 0
var max_value: int = 0


## Localisation key of the stat's glossary name.
func name_key() -> String:
	return "stat." + id


func to_dict() -> Dictionary:
	var d := {"id": id, "kind": kind, "scope": scope, "unit": unit, "integral": integral}
	if has_min:
		d["min"] = min_value
	if has_max:
		d["max"] = max_value
	return d
