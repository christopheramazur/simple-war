class_name NetPacket
extends RefCounted
## Our own binary packet format for lockstep traffic; no JSON on the wire
## (GDD 04 §4.6). Layout: u8 magic, u8 version, u8 kind, then kind fields in
## big-endian order. Order lists are Godot-serialised variants with objects
## disallowed (bytes_to_var never decodes Objects), so a peer cannot inject code.

const MAGIC := 0x53
const VERSION := 1

enum Kind { ORDERS = 1, SEALED = 2, CLAIM_HOST = 3, STATE_HASH = 4 }


static func _start(kind: int) -> StreamPeerBuffer:
	var b := StreamPeerBuffer.new()
	b.big_endian = true
	b.put_u8(MAGIC)
	b.put_u8(VERSION)
	b.put_u8(kind)
	return b


static func _put_var(b: StreamPeerBuffer, v: Variant) -> void:
	var bytes := var_to_bytes(v)
	b.put_u32(bytes.size())
	b.put_data(bytes)


static func _get_var(b: StreamPeerBuffer) -> Variant:
	var n := b.get_u32()
	if n > b.get_available_bytes():
		return null
	var bytes: PackedByteArray = b.get_data(n)[1]
	return bytes_to_var(bytes)


## A peer's orders for a turn, sent to the host.
static func orders(turn: int, epoch: int, order_list: Array) -> PackedByteArray:
	var b := _start(Kind.ORDERS)
	b.put_u32(turn)
	b.put_u32(epoch)
	_put_var(b, order_list)
	return b.data_array


## The host's sealed packet ({turn, epoch, orders}); also the migration resend.
static func sealed(packet: Dictionary) -> PackedByteArray:
	var b := _start(Kind.SEALED)
	b.put_u32(packet["turn"])
	b.put_u32(packet["epoch"])
	var ords: Dictionary = packet["orders"]
	b.put_u16(ords.size())
	for p in ords:
		b.put_32(p)
		_put_var(b, ords[p])
	return b.data_array


static func claim_host(epoch: int) -> PackedByteArray:
	var b := _start(Kind.CLAIM_HOST)
	b.put_u32(epoch)
	return b.data_array


static func state_hash(turn: int, hash_hex: String) -> PackedByteArray:
	var b := _start(Kind.STATE_HASH)
	b.put_u32(turn)
	_put_var(b, hash_hex)
	return b.data_array


## Decode to {kind, ...fields}, or {} for anything malformed or foreign.
static func decode(data: PackedByteArray) -> Dictionary:
	if data.size() < 3:
		return {}
	var b := StreamPeerBuffer.new()
	b.big_endian = true
	b.data_array = data
	if b.get_u8() != MAGIC or b.get_u8() != VERSION:
		return {}
	var kind := b.get_u8()
	match kind:
		Kind.ORDERS:
			if b.get_available_bytes() < 12:
				return {}
			var t := b.get_u32()
			var e := b.get_u32()
			var o: Variant = _get_var(b)
			return {} if typeof(o) != TYPE_ARRAY else {"kind": kind, "turn": t, "epoch": e, "orders": o}
		Kind.SEALED:
			if b.get_available_bytes() < 10:
				return {}
			var t2 := b.get_u32()
			var e2 := b.get_u32()
			var n := b.get_u16()
			var ords := {}
			for i in n:
				if b.get_available_bytes() < 8:
					return {}
				var p := b.get_32()
				var v: Variant = _get_var(b)
				if typeof(v) != TYPE_ARRAY:
					return {}
				ords[p] = v
			return {"kind": kind, "turn": t2, "epoch": e2, "orders": ords}
		Kind.CLAIM_HOST:
			if b.get_available_bytes() < 4:
				return {}
			return {"kind": kind, "epoch": b.get_u32()}
		Kind.STATE_HASH:
			if b.get_available_bytes() < 8:
				return {}
			var t3 := b.get_u32()
			var h: Variant = _get_var(b)
			return {} if typeof(h) != TYPE_STRING else {"kind": kind, "turn": t3, "hash": h}
	return {}
