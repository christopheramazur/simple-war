class_name TransferSystem
extends RefCounted
## Moves an entity from one context to another at a pulse boundary.
## A system in the source context posts
##     ctx.post(&"transfer_requested", {"kind": &"squad", "id": id, "to": dest_ctx_id})
## and, at the next flush, this handler removes the entity from the source
## table and spawns it with the same column values (plus optional `set`
## overrides) in the destination table. IDs are per context, so the result
## event maps old to new. GDD 04 §4.3, R7Q13.
##
## Results (bus events):
##   &"transfer_applied" {kind, from, to, old_id, new_id}
##   &"transfer_failed"  {kind, from, to, old_id, reason}

const REQUESTED: StringName = &"transfer_requested"


func attach(bus: PulseBus) -> void:
	bus.register_handler(REQUESTED, _on_requested)


func _on_requested(bus: PulseBus, e: SimEvent) -> void:
	var kind: StringName = e.data.get("kind", &"")
	var old_id: int = e.data.get("id", SoaTable.INVALID_ID)
	var to_id: int = e.data.get("to", 0)
	var src := bus.context(e.source)
	var dst := bus.context(to_id)
	var reason := ""
	if src == null:
		reason = "unknown source context"
	elif dst == null:
		reason = "unknown destination context"
	elif not src.tables.has(kind) or not dst.tables.has(kind):
		reason = "table %s missing" % kind
	elif not src.table(kind).is_alive(old_id):
		reason = "entity not alive"
	if not reason.is_empty():
		bus.post(&"transfer_failed", {"kind": kind, "from": e.source, "to": to_id, "old_id": old_id, "reason": reason})
		return
	var values := src.table(kind).export_row(old_id)
	var overrides: Dictionary = e.data.get("set", {})
	for k: Variant in overrides:
		values[StringName(k)] = overrides[k]
	src.table(kind).despawn(old_id)
	var new_id := dst.table(kind).spawn(values)
	bus.post(&"transfer_applied", {"kind": kind, "from": e.source, "to": to_id, "old_id": old_id, "new_id": new_id})
