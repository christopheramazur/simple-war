class_name SteamTransport
extends NetTransport
## GodotSteam transport: a Steam lobby for matchmaking and membership, Steam
## Networking Sockets (relayed by SDR) for packets (GDD 04 §4.6, sw-5x6.2).
## GodotSteam is not vendored yet, so the singleton is looked up by name and
## `is_available()` is false without it; nothing else in the game imports Steam.
## Peer ids are slots: lobby members sorted by Steam id, numbered from 1, so
## every peer derives the same ids without a handshake. Untested against live
## Steam; the API names follow GodotSteam 4.x and may need a version pass.

const CHANNEL := 0
const SEND_RELIABLE := 8  ## k_nSteamNetworkingSend_Reliable
const SEND_UNRELIABLE := 0

var _steam: Object
var _lobby_id: int = 0
var _me: int = -1
var _slot_to_steam: Dictionary = {}  ## peer id -> steam id
var _steam_to_slot: Dictionary = {}


static func is_available() -> bool:
	return Engine.has_singleton("Steam")


func _init() -> void:
	if is_available():
		_steam = Engine.get_singleton("Steam")


func local_peer() -> int:
	return _me


func peers() -> PackedInt32Array:
	var out := PackedInt32Array()
	for s in _slot_to_steam:
		if s != _me:
			out.append(s)
	out.sort()
	return out


## Bind to a lobby already created or joined by the menu flow; derives slots
## from the member list. Call again when membership changes.
func attach_lobby(lobby_id: int) -> bool:
	if _steam == null:
		return false
	_lobby_id = lobby_id
	var ids: Array = []
	for i in int(_steam.getNumLobbyMembers(lobby_id)):
		ids.append(int(_steam.getLobbyMemberByIndex(lobby_id, i)))
	ids.sort()
	var mine := int(_steam.getSteamID())
	var old := _steam_to_slot.duplicate()
	_slot_to_steam.clear()
	_steam_to_slot.clear()
	for i in ids.size():
		_slot_to_steam[i + 1] = ids[i]
		_steam_to_slot[ids[i]] = i + 1
	_me = _steam_to_slot.get(mine, -1)
	for sid in _steam_to_slot:
		if not old.has(sid) and _steam_to_slot[sid] != _me:
			peer_connected.emit(_steam_to_slot[sid])
	for sid in old:
		if not _steam_to_slot.has(sid):
			peer_disconnected.emit(old[sid])
	return _me != -1


func send(to_peer: int, data: PackedByteArray, reliable: bool = RELIABLE) -> bool:
	if _steam == null or not _slot_to_steam.has(to_peer):
		return false
	var flags := SEND_RELIABLE if reliable else SEND_UNRELIABLE
	var r: Variant = _steam.sendMessageToUser(str(_slot_to_steam[to_peer]), data, flags, CHANNEL)
	return typeof(r) != TYPE_DICTIONARY or int(r.get("result", 1)) == 1


func poll() -> void:
	if _steam == null:
		return
	for m: Dictionary in _steam.receiveMessagesOnChannel(CHANNEL, 64):
		var sid := int(str(m.get("identity", m.get("remote_steam_id", 0))))
		if _steam_to_slot.has(sid):  # drop anything from outside the lobby
			packet_received.emit(_steam_to_slot[sid], m.get("payload", PackedByteArray()))


func close() -> void:
	if _steam != null and _lobby_id != 0:
		_steam.leaveLobby(_lobby_id)
	_lobby_id = 0
	_slot_to_steam.clear()
	_steam_to_slot.clear()
