class_name NetTransport
extends RefCounted
## Transport interface for lockstep play (GDD 04 §4.6, sw-5x6.2). Carries opaque
## bytes between peers; knows nothing about orders or turns. Peer ids are small
## ints (the lockstep slot ids). Implementations: LoopbackTransport (tests,
## local), SteamTransport (GodotSteam lobbies + Sockets/SDR).

signal packet_received(from_peer: int, data: PackedByteArray)
signal peer_connected(peer: int)
signal peer_disconnected(peer: int)

## Channel for gameplay packets; reliable and ordered.
const RELIABLE := true


func local_peer() -> int:
	return -1


## Connected remote peers (not including the local peer).
func peers() -> PackedInt32Array:
	return PackedInt32Array()


func send(_to_peer: int, _data: PackedByteArray, _reliable: bool = RELIABLE) -> bool:
	return false


func broadcast(data: PackedByteArray, reliable: bool = RELIABLE) -> void:
	for p in peers():
		send(p, data, reliable)


## Drain incoming packets and connection events; call once per frame.
func poll() -> void:
	pass


func close() -> void:
	pass
