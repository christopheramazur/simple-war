class_name SoaTable
extends RefCounted
## Structure-of-arrays storage for one entity kind. GDD 04 §4.2.
##
## Each column is a Packed*Array member of a subclass, one row per live
## entity, packed with no holes (swap-remove). IDs are 64-bit and generational:
## `(generation << 32) | slot`. A stale ID (its entity despawned) never matches
## a new entity in the same slot.
##
## Subclasses declare columns in `_init()`:
##     var hp := PackedInt64Array()
##     func _init() -> void:
##         super(&"unit")
##         declare(&"hp", 10)
##
## WRITING COLUMNS: Packed arrays are copy-on-write. `table.hp[row] = v` from
## outside the table copies the whole column on every write. Systems must use
##     var hp: PackedInt64Array = table.take_column(&"hp")
##     ... hp[row] = v ...
##     table.put_column(&"hp", hp)
## Reading `table.hp[row]` directly is fine.
##
## Only integer column types are allowed (no floats in the simulation).

const SLOT_MASK: int = 0xFFFFFFFF
const INVALID_ID: int = -1

const _ALLOWED_TYPES: Array[int] = [
	TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_BYTE_ARRAY,
]

var kind: StringName

var _column_names: Array[StringName] = []
var _defaults: Array[int] = []
var _slot_row: PackedInt32Array = PackedInt32Array()
var _slot_gen: PackedInt32Array = PackedInt32Array()
var _row_slot: PackedInt32Array = PackedInt32Array()
var _free_slots: PackedInt32Array = PackedInt32Array()


func _init(kind_name: StringName = &"") -> void:
	kind = kind_name


## Registers an existing Packed*Array member as a column with a default value.
func declare(column: StringName, default_value: int = 0) -> void:
	assert(not _column_names.has(column), "SoaTable: duplicate column %s" % column)
	var col: Variant = get(column)
	assert(col != null, "SoaTable: no member named %s" % column)
	assert(_ALLOWED_TYPES.has(typeof(col)), "SoaTable: column %s must be an integer Packed array" % column)
	assert(_row_slot.size() == 0, "SoaTable: declare columns before spawning")
	_column_names.append(column)
	_defaults.append(default_value)


func columns() -> Array[StringName]:
	return _column_names.duplicate()


func count() -> int:
	return _row_slot.size()


static func make_id(slot: int, generation: int) -> int:
	return (generation << 32) | (slot & SLOT_MASK)


static func slot_of(id: int) -> int:
	return id & SLOT_MASK


static func generation_of(id: int) -> int:
	return id >> 32


func is_alive(id: int) -> bool:
	if id < 0:
		return false
	var slot := slot_of(id)
	return slot < _slot_row.size() and _slot_gen[slot] == generation_of(id) and _slot_row[slot] >= 0


## Row index of a live entity, or -1.
func row_of(id: int) -> int:
	return _slot_row[slot_of(id)] if is_alive(id) else -1


## ID of the entity in a row.
func id_at(row: int) -> int:
	var slot := _row_slot[row]
	return make_id(slot, _slot_gen[slot])


## IDs of all live entities, in row order.
func ids() -> PackedInt64Array:
	var out := PackedInt64Array()
	out.resize(_row_slot.size())
	for row in _row_slot.size():
		out[row] = id_at(row)
	return out


## Spawns an entity. `values` maps column names to ints; missing columns get
## their default. Structural change: call only from a command buffer or setup.
func spawn(values: Dictionary = {}) -> int:
	for key: Variant in values:
		assert(_column_names.has(StringName(key)), "SoaTable %s: unknown column %s" % [kind, key])
	var slot: int
	if _free_slots.size() > 0:
		slot = _free_slots[_free_slots.size() - 1]
		_free_slots.resize(_free_slots.size() - 1)
	else:
		slot = _slot_row.size()
		_slot_row.append(-1)
		_slot_gen.append(0)
	_slot_gen[slot] += 1
	var row := _row_slot.size()
	_slot_row[slot] = row
	_row_slot.append(slot)
	for i in _column_names.size():
		var name := _column_names[i]
		var col: Variant = take_column(name)
		col.append(int(values.get(name, values.get(String(name), _defaults[i]))))
		put_column(name, col)
	return make_id(slot, _slot_gen[slot])


## Despawns by swap-remove. Returns false for a dead or stale ID.
func despawn(id: int) -> bool:
	if not is_alive(id):
		return false
	var slot := slot_of(id)
	var row := _slot_row[slot]
	var last := _row_slot.size() - 1
	if row != last:
		var moved_slot := _row_slot[last]
		_row_slot[row] = moved_slot
		_slot_row[moved_slot] = row
	for name in _column_names:
		var col: Variant = take_column(name)
		if row != last:
			col[row] = col[last]
		col.resize(last)
		put_column(name, col)
	_row_slot.resize(last)
	_slot_row[slot] = -1
	_free_slots.append(slot)
	return true


## Removes a column from the table for in-place writing. Pair with put_column.
func take_column(column: StringName) -> Variant:
	var col: Variant = get(column)
	set(column, col.slice(0, 0))
	return col


func put_column(column: StringName, col: Variant) -> void:
	set(column, col)


func get_value(id: int, column: StringName) -> int:
	var row := row_of(id)
	assert(row >= 0, "SoaTable %s: dead id %d" % [kind, id])
	return get(column)[row]


## Single-value write. Copies nothing: uses take/put internally.
func set_value(id: int, column: StringName, value: int) -> void:
	var row := row_of(id)
	assert(row >= 0, "SoaTable %s: dead id %d" % [kind, id])
	var col: Variant = take_column(column)
	col[row] = value
	put_column(column, col)


## All column values of one entity, for transfers and inspection.
func export_row(id: int) -> Dictionary:
	var row := row_of(id)
	assert(row >= 0, "SoaTable %s: dead id %d" % [kind, id])
	var out := {}
	for name in _column_names:
		out[name] = get(name)[row]
	return out


## Feeds the table's full state (ID mapping and columns) into a hash.
## Every section is length-prefixed, so empty arrays still hash distinctly.
func hash_into(ctx: HashingContext) -> void:
	_feed(ctx, String(kind).to_utf8_buffer())
	_feed(ctx, _row_slot.to_byte_array())
	_feed(ctx, _slot_gen.to_byte_array())
	_feed(ctx, _free_slots.to_byte_array())
	for name in _column_names:
		_feed(ctx, String(name).to_utf8_buffer())
		var col: Variant = get(name)
		_feed(ctx, col if typeof(col) == TYPE_PACKED_BYTE_ARRAY else col.to_byte_array())


static func _feed(ctx: HashingContext, bytes: PackedByteArray) -> void:
	ctx.update(PackedInt64Array([bytes.size()]).to_byte_array())
	if bytes.size() > 0:
		ctx.update(bytes)
