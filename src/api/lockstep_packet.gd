class_name LockstepPacket
extends RefCounted
## Binary wire format for LockstepSession messages (GDD 04 §4.6, sw-5x6.7).
## Layout: magic "SW" (2 bytes), version (u8), type (u8), then the body as a
## Godot binary variant (var_to_bytes; never JSON, objects refused on decode).
## The sender is not in the packet: the transport knows the peer (Steam id),
## so a peer cannot spoof another's identity.

enum Type { ORDERS = 1, SEALED = 2, HOST_CLAIM = 3, HASH = 4 }

const MAGIC_0 := 0x53  # 'S'
const MAGIC_1 := 0x57  # 'W'
const VERSION := 1
const HEADER_SIZE := 4
const MAX_BYTES := 1 << 20  ## Larger packets are dropped unparsed.


static func orders(for_turn: int, for_epoch: int, order_list: Array) -> PackedByteArray:
	return _pack(Type.ORDERS, {"turn": for_turn, "epoch": for_epoch, "orders": order_list})


## `packet` is what LockstepSession.seal / resend_packet return.
static func sealed(packet: Dictionary) -> PackedByteArray:
	return _pack(Type.SEALED, packet)


static func host_claim(for_epoch: int) -> PackedByteArray:
	return _pack(Type.HOST_CLAIM, {"epoch": for_epoch})


static func state_hash(for_turn: int, hash_hex: String) -> PackedByteArray:
	return _pack(Type.HASH, {"turn": for_turn, "hash": hash_hex})


## Returns {type, body} or {} for anything malformed, oversized, of another
## version, or whose body lacks the fields (and types) its message needs.
static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < HEADER_SIZE or bytes.size() > MAX_BYTES:
		return {}
	if bytes[0] != MAGIC_0 or bytes[1] != MAGIC_1 or bytes[2] != VERSION:
		return {}
	var type := int(bytes[3])
	# The body must start with a Dictionary type tag (low 16 bits of the first
	# u32); this rejects truncated and object bodies before the engine decodes.
	if bytes.size() < HEADER_SIZE + 4 or (bytes.decode_u32(HEADER_SIZE) & 0xFFFF) != TYPE_DICTIONARY:
		return {}
	var body: Variant = bytes_to_var(bytes.slice(HEADER_SIZE))  # objects not allowed
	if not body is Dictionary or not _valid(type, body):
		return {}
	return {"type": type, "body": body}


static func _pack(type: int, body: Dictionary) -> PackedByteArray:
	var out := PackedByteArray([MAGIC_0, MAGIC_1, VERSION, type])
	out.append_array(var_to_bytes(body))
	return out


static func _is_int(d: Dictionary, key: String) -> bool:
	return d.get(key) is int


static func _valid(type: int, b: Dictionary) -> bool:
	match type:
		Type.ORDERS:
			return _is_int(b, "turn") and _is_int(b, "epoch") and b.get("orders") is Array
		Type.SEALED:
			return _is_int(b, "turn") and _is_int(b, "epoch") and b.get("orders") is Dictionary
		Type.HOST_CLAIM:
			return _is_int(b, "epoch")
		Type.HASH:
			return _is_int(b, "turn") and b.get("hash") is String
	return false
