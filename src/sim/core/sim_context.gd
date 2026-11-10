class_name SimContext
extends RefCounted
## The full simulation state of one context: a battle or the overworld.
## Contexts never reference each other; anything that crosses contexts goes
## out through `post()` to the pulse bus. GDD 04 §4.2-4.3, R6Q19, R7Q13.

## Unique, stable ID; the pulse bus orders contexts by it.
var id: int
## &"battle" or &"overworld" (free-form; used for hashing and routing).
var kind: StringName
## Sim ticks completed in this context.
var tick: int = 0
## Entity tables by kind, e.g. &"squad" -> SquadTable.
var tables: Dictionary = {}
## Within-tick events for this context's systems.
var events: EventQueue
## Deferred spawns and despawns.
var commands: CommandBuffer = CommandBuffer.new()
## Content-generation / harness PRNG (never used for hidden gameplay chance).
var rng: SimRng
## Every within-tick event of the current turn, in order (for playback and
## replays). Cleared by `begin_turn()`.
var turn_log: Array[SimEvent] = []

var _bus_outbox: Array[SimEvent] = []
var _bus_seq: int = 0


func _init(context_id: int, context_kind: StringName, seed_value: int = 0) -> void:
	id = context_id
	kind = context_kind
	events = EventQueue.new(context_id)
	rng = SimRng.new(seed_value)


func add_table(t: SoaTable) -> SoaTable:
	assert(not tables.has(t.kind), "SimContext: duplicate table %s" % t.kind)
	tables[t.kind] = t
	return t


func table(table_kind: StringName) -> SoaTable:
	assert(tables.has(table_kind), "SimContext %d: no table %s" % [id, table_kind])
	return tables[table_kind]


## Queues an event for the pulse bus (cross-context or presentation-facing).
## It is delivered at the next pulse point, never mid-tick.
func post(type: StringName, data: Dictionary) -> SimEvent:
	var e := SimEvent.new(type, data)
	e.source = id
	e.seq = _bus_seq
	e.tick = tick
	_bus_seq += 1
	_bus_outbox.append(e)
	return e


## Called by the pulse bus only.
func take_bus_outbox() -> Array[SimEvent]:
	var out := _bus_outbox
	_bus_outbox = []
	return out


## Ends a tick: moves this tick's events into the turn log and advances.
func end_tick() -> void:
	turn_log.append_array(events.drain())
	tick += 1


func begin_turn() -> void:
	turn_log = []


## Full state as plain data, taken at a tick boundary (queues must be empty).
## Subclasses extend `_snapshot_extra` / `_restore_extra` for their fields.
func snapshot() -> Dictionary:
	assert(events.size() == 0 and commands.size() == 0, "SimContext.snapshot: mid-tick")
	var tabs := {}
	for k: StringName in tables:
		tabs[String(k)] = (tables[k] as SoaTable).snapshot()
	var snap := {
		"id": id, "kind": String(kind), "tick": tick, "bus_seq": _bus_seq,
		"rng": rng.get_state(), "tables": tabs, "outbox": _events_to_data(_bus_outbox),
	}
	_snapshot_extra(snap)
	return snap


func restore(snap: Dictionary) -> void:
	assert(int(snap["id"]) == id, "SimContext.restore: id mismatch")
	tick = snap["tick"]
	_bus_seq = snap["bus_seq"]
	rng.set_state(snap["rng"])
	var tabs: Dictionary = snap["tables"]
	for k: StringName in tables:
		(tables[k] as SoaTable).restore(tabs[String(k)])
	_bus_outbox = _events_from_data(snap.get("outbox", []))
	turn_log = []
	_restore_extra(snap)


func _snapshot_extra(_snap: Dictionary) -> void:
	pass


func _restore_extra(_snap: Dictionary) -> void:
	pass


static func _events_to_data(list: Array[SimEvent]) -> Array:
	var out := []
	for e in list:
		out.append(e.to_dict())
	return out


static func _events_from_data(list: Array) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for d: Dictionary in list:
		var e := SimEvent.new(d["type"], d["data"])
		e.source = d["source"]
		e.seq = d["seq"]
		e.tick = d["tick"]
		out.append(e)
	return out


## SHA-256 of the whole context state, in canonical order.
func state_hash() -> PackedByteArray:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(String(kind).to_utf8_buffer())
	h.update(PackedInt64Array([id, tick, _bus_seq]).to_byte_array())
	h.update(rng.get_state().to_byte_array())
	var kinds: Array = tables.keys()
	kinds.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for k: StringName in kinds:
		(tables[k] as SoaTable).hash_into(h)
	return h.finish()


func state_hash_hex() -> String:
	return state_hash().hex_encode()
