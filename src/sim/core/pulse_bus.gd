class_name PulseBus
extends RefCounted
## Carries events between contexts and out to presentation. Contexts post to
## their outbox at any time; the bus delivers only at fixed pulse points, in
## canonical order: by source context ID, then emission order. Handlers run in
## registration order. Events a handler posts during a flush are delivered in
## the same flush, after the events already queued. GDD 04 §4.3, R7Q12.
##
## Presentation connects to `published` and never posts. The sim side never
## reads anything presentation does.

## Emitted for every delivered event, after sim handlers ran. Read-only.
signal published(event: SimEvent, point: StringName)

var _contexts: Dictionary = {}
var _handlers: Dictionary = {}
var _handler_owners: Array[Object] = []
var _own_seq: int = 0
var _pending_own: Array[SimEvent] = []
## Every event delivered at each flush, as [point, event], for replays and tests.
var history: Array[Array] = []


func register_context(ctx: SimContext) -> void:
	assert(not _contexts.has(ctx.id), "PulseBus: duplicate context %d" % ctx.id)
	_contexts[ctx.id] = ctx


func unregister_context(context_id: int) -> void:
	_contexts.erase(context_id)


func context(context_id: int) -> SimContext:
	return _contexts.get(context_id)


func context_ids() -> Array[int]:
	var ids: Array[int] = []
	for k: int in _contexts:
		ids.append(k)
	ids.sort()
	return ids


## Registers a sim-side handler: func(bus: PulseBus, event: SimEvent) -> void.
## The bus keeps the handler's object alive (a Callable alone does not).
func register_handler(type: StringName, handler: Callable) -> void:
	if not _handlers.has(type):
		_handlers[type] = []
	(_handlers[type] as Array).append(handler)
	var owner_obj := handler.get_object()
	if owner_obj is RefCounted and not _handler_owners.has(owner_obj):
		_handler_owners.append(owner_obj)


## Posts an event from the bus side (e.g. a handler's result). Source 0.
func post(type: StringName, data: Dictionary) -> SimEvent:
	var e := SimEvent.new(type, data)
	e.source = 0
	e.seq = _own_seq
	_own_seq += 1
	_pending_own.append(e)
	return e


## Delivers everything queued, in canonical order. Returns the delivered events.
func flush(point: StringName) -> Array[SimEvent]:
	var queue: Array[SimEvent] = []
	for cid in context_ids():
		queue.append_array((_contexts[cid] as SimContext).take_bus_outbox())
	queue.append_array(_take_own())
	var delivered: Array[SimEvent] = []
	var i := 0
	while i < queue.size():
		var e := queue[i]
		i += 1
		for handler: Callable in _handlers.get(e.type, []):
			handler.call(self, e)
		delivered.append(e)
		history.append([point, e])
		# Anything handlers posted joins the end of this flush, in order.
		for cid in context_ids():
			queue.append_array((_contexts[cid] as SimContext).take_bus_outbox())
		queue.append_array(_take_own())
	for e in delivered:
		published.emit(e, point)
	return delivered


func _take_own() -> Array[SimEvent]:
	var out := _pending_own
	_pending_own = []
	return out
