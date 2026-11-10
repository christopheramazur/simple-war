class_name EventQueue
extends RefCounted
## Per-context event queue for one tick. Systems running later in the tick
## read events that earlier systems pushed. GDD 04 §4.3, R7Q12.

var _events: Array[SimEvent] = []
var _next_seq: int = 0
var _source: int = 0


func _init(source_id: int = 0) -> void:
	_source = source_id


func push(type: StringName, data: Dictionary, tick: int) -> SimEvent:
	var e := SimEvent.new(type, data)
	e.source = _source
	e.seq = _next_seq
	e.tick = tick
	_next_seq += 1
	_events.append(e)
	return e


func all() -> Array[SimEvent]:
	return _events


func of_type(type: StringName) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for e in _events:
		if e.type == type:
			out.append(e)
	return out


func size() -> int:
	return _events.size()


## Removes and returns every queued event, in emission order.
func drain() -> Array[SimEvent]:
	var out := _events
	_events = []
	return out
