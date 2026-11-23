class_name TelemetryClient
extends RefCounted
## Client side of opt-in telemetry (GDD 04 §4.6, R8Q8). Off until the player
## opts in; events carry only allowlisted fields (ResultsService.TELEMETRY_KINDS)
## and no player id. Events queue locally and flush through an injected sender
## Callable(events: Array) -> bool, so the HTTP transport stays outside.

const MAX_QUEUE := 200

var enabled := false
var sender: Callable
var queue: Array = []


func _init(send: Callable = Callable()) -> void:
	sender = send


func set_opt_in(on: bool) -> void:
	enabled = on
	if not on:
		queue.clear()


func record(kind: String, fields: Dictionary = {}) -> bool:
	if not enabled or not ResultsService.TELEMETRY_KINDS.has(kind):
		return false
	var clean := {}
	for f in ResultsService.TELEMETRY_KINDS[kind]:
		if fields.has(f):
			clean[f] = fields[f]
	if queue.size() >= MAX_QUEUE:
		queue.pop_front()
	queue.append({"kind": kind, "fields": clean})
	return true


## Sends the queue; keeps it on failure. Returns events sent.
func flush() -> int:
	if not enabled or queue.is_empty() or not sender.is_valid():
		return 0
	var batch := queue.duplicate()
	if sender.call(batch):
		queue.clear()
		return batch.size()
	return 0
