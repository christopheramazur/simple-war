class_name StatRegistry
extends RefCounted
## The stat registry, derived from DataSchema (E3Q4): every numeric field of
## a unit- or squad-scoped template kind is a stat, unless its spec says
## "stat": false. Effects may only touch registered stats (E1Q3).
##
## IDs are "<kind>.<field>[.<key>...]". Maps with a declared key set expand
## to one stat per key; maps with open keys (terrain IDs, fire-mode names)
## register a "*" wildcard that matches any key. Lists of objects that carry
## an enum "id" field (reactions) expand per enum value.

## Kinds that hold per-unit or per-squad values, with their scope.
const SCOPES: Dictionary = {
	"unit": StatDef.SCOPE_UNIT,
	"weapon": StatDef.SCOPE_UNIT,
	"defense": StatDef.SCOPE_UNIT,
	"movement": StatDef.SCOPE_UNIT,
	"squad": StatDef.SCOPE_SQUAD,
	"ability": StatDef.SCOPE_SQUAD,
}

var _defs: Dictionary = {}  # id -> StatDef
var _order: PackedStringArray = PackedStringArray()


## Builds the registry from DataSchema.KINDS / OBJECTS.
static func from_schema() -> StatRegistry:
	var reg := StatRegistry.new()
	for kind: String in SCOPES:
		var spec: Dictionary = DataSchema.KINDS[kind]
		for field: String in spec:
			reg._walk(kind, PackedStringArray([field]), spec[field])
	return reg


func has(id: String) -> bool:
	return find(id) != null


## Exact ID, or the wildcard stat that covers it ("weapon.modes.auto.accuracy"
## resolves to "weapon.modes.*.accuracy"). Null if unregistered.
func find(id: String) -> StatDef:
	if _defs.has(id):
		return _defs[id]
	var parts := id.split(".")
	# Try replacing each segment after the kind with "*".
	for i in range(1, parts.size()):
		var probe := parts.duplicate()
		probe[i] = "*"
		var key := ".".join(probe)
		if _defs.has(key):
			return _defs[key]
	return null


## Registered IDs in schema order.
func ids() -> PackedStringArray:
	return _order


func size() -> int:
	return _order.size()


## Reads a stat's base value (raw fixed) from a flattened template of the
## stat's kind. `keys` fills "*" segments in order. Missing fields give
## `default_value`.
func read_base(def: StatDef, values: Dictionary, keys: PackedStringArray = PackedStringArray(), default_value: int = 0) -> int:
	var v: Variant = values
	var k := 0
	for seg in def.path:
		var want := seg
		if seg == "*":
			if k >= keys.size():
				return default_value
			want = keys[k]
			k += 1
		if typeof(v) == TYPE_ARRAY:
			v = _by_id(v, want)
		elif typeof(v) == TYPE_DICTIONARY:
			v = (v as Dictionary).get(want)
		else:
			return default_value
		if v == null:
			return default_value
	return DataSchema.to_fixed(v, default_value)


func _walk(kind: String, path: PackedStringArray, fs: Dictionary) -> void:
	if fs.get("stat", true) == false:
		return
	var t: String = fs["type"]
	if t == "int" or t == "fixed":
		_add(kind, path, fs, t == "int")
		return
	if t.begins_with("map:"):
		var inner := fs.duplicate()
		inner["type"] = t.substr(4)
		inner.erase("keys")
		var keys: Array = fs.get("keys", ["*"])
		for key: String in keys:
			_walk(kind, path + PackedStringArray([key]), inner)
		return
	if t.begins_with("obj:"):
		var obj: Dictionary = DataSchema.OBJECTS[t.substr(4)]
		for field: String in obj:
			_walk(kind, path + PackedStringArray([field]), obj[field])
		return
	if t.begins_with("list:obj:"):
		var obj: Dictionary = DataSchema.OBJECTS[t.substr(9)]
		var id_spec: Dictionary = obj.get("id", {})
		if not id_spec.has("enum"):
			return  # Composition lists (squad members) are not stats.
		for key: String in id_spec["enum"]:
			for field: String in obj:
				if field != "id":
					_walk(kind, path + PackedStringArray([key, field]), obj[field])


func _add(kind: String, path: PackedStringArray, fs: Dictionary, integral: bool) -> void:
	var def := StatDef.new()
	def.id = kind + "." + ".".join(path)
	def.kind = kind
	def.path = path
	def.scope = SCOPES[kind]
	def.integral = integral
	def.unit = fs.get("unit", _infer_unit(path[path.size() - 1]))
	if fs.has("min"):
		def.has_min = true
		def.min_value = Fixed.from_int(fs["min"])
	if fs.has("max"):
		def.has_max = true
		def.max_value = Fixed.from_int(fs["max"])
	_defs[def.id] = def
	_order.append(def.id)


static func _infer_unit(field: String) -> String:
	if field.ends_with("_pct") or field == "pct":
		return "%"
	if field in ["walk", "run"]:
		return "m/s"
	if field.ends_with("_per_s"):
		return "/s"
	if field.ends_with("_ticks"):
		return "ticks"
	if field in ["range", "min_range", "radius", "sight", "spacing", "aoe_radius"]:
		return "m"
	return ""


static func _by_id(list: Array, id: String) -> Variant:
	for item: Variant in list:
		if typeof(item) == TYPE_DICTIONARY and (item as Dictionary).get("id") == id:
			return item
	return null
