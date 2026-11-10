class_name SimEvent
extends RefCounted
## One simulation event. Systems write events; they never call each other or
## touch another context's state. GDD 04 §4.3, R6Q19.

## Event type, e.g. &"entity_spawned", &"transfer_requested".
var type: StringName
## Payload. Values must be ints, StringNames, Strings or nested Arrays /
## Dictionaries of those (no floats), so events hash and serialise identically.
var data: Dictionary
## ID of the context that produced the event (0 = the bus itself).
var source: int = 0
## Emission order within (source, channel). Assigned by the producer.
var seq: int = 0
## Sim tick of the source context when emitted.
var tick: int = 0


func _init(event_type: StringName = &"", payload: Dictionary = {}) -> void:
	type = event_type
	data = payload


func to_dict() -> Dictionary:
	return {"type": type, "data": data, "source": source, "seq": seq, "tick": tick}
