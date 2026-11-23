class_name LoopbackTransport
extends NetTransport
## In-memory transport: endpoints made by one `LoopbackTransport.hub()` call see
## each other. Delivery happens in poll(), in send order, so tests are deterministic.

var _id: int
var _net: Dictionary  ## shared: peer id -> LoopbackTransport
var _inbox: Array = []  ## [from, bytes]
var _events: Array = []  ## [connected: bool, peer]


## Make connected endpoints for the given peer ids.
static func hub(ids: PackedInt32Array) -> Array:
	var net := {}
	var out := []
	for id in ids:
		var t := LoopbackTransport.new()
		t._id = id
		t._net = net
		for other: LoopbackTransport in net.values():
			other._events.append([true, id])
			t._events.append([true, other._id])
		net[id] = t
		out.append(t)
	return out


func local_peer() -> int:
	return _id


func peers() -> PackedInt32Array:
	var out := PackedInt32Array()
	for id in _net:
		if id != _id:
			out.append(id)
	return out


func send(to_peer: int, data: PackedByteArray, _reliable: bool = RELIABLE) -> bool:
	if not _net.has(to_peer) or to_peer == _id:
		return false
	_net[to_peer]._inbox.append([_id, data.duplicate()])
	return true


func poll() -> void:
	var ev := _events
	_events = []
	for e in ev:
		if e[0]:
			peer_connected.emit(e[1])
		else:
			peer_disconnected.emit(e[1])
	var box := _inbox
	_inbox = []
	for m in box:
		packet_received.emit(m[0], m[1])


func close() -> void:
	if _net.get(_id) == self:
		_net.erase(_id)
		for other: LoopbackTransport in _net.values():
			other._events.append([false, _id])
	_net = {}  # break the hub cycle so endpoints can be freed
