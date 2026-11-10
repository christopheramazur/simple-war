class_name CommandBuffer
extends RefCounted
## Deferred structural changes (spawn, despawn), applied in recorded order at
## the end of each system phase so systems never iterate a table that is
## changing under them. GDD 04 §4.2.
##
## A spawn may carry a `tag` (any int) so the requester can find the new ID in
## the resulting &"entity_spawned" event.

enum Op { SPAWN, DESPAWN }

var _ops: Array[Array] = []


func spawn(kind: StringName, values: Dictionary = {}, tag: int = 0) -> void:
	_ops.append([Op.SPAWN, kind, values, tag])


func despawn(kind: StringName, id: int) -> void:
	_ops.append([Op.DESPAWN, kind, id])


func size() -> int:
	return _ops.size()


## Applies every queued op to `ctx` in order and emits events for each.
## Despawning a dead ID is ignored (two systems may both kill the same unit).
func apply(ctx: SimContext) -> void:
	var ops := _ops
	_ops = []
	for op in ops:
		var table := ctx.table(op[1])
		match op[0]:
			Op.SPAWN:
				var id := table.spawn(op[2])
				ctx.events.push(&"entity_spawned", {"kind": op[1], "id": id, "tag": op[3]}, ctx.tick)
			Op.DESPAWN:
				if table.despawn(op[2]):
					ctx.events.push(&"entity_despawned", {"kind": op[1], "id": op[2]}, ctx.tick)
