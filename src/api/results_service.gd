class_name ResultsService
extends RefCounted
## Ranked results service core (GDD 04 §4.6, sw-5x6.4). Transport-free: the
## serverless deployment wraps submit()/ingest() in HTTP handlers; tests call
## them directly. No rating model yet (R7Q10): results are only recorded.
##
## A result is accepted when every player named in it co-signed the same
## canonical bytes and every signer's Steam auth ticket verified. Verification
## is injected so Steam stays behind the transport layer:
##   ticket_verifier(peer_key, ticket: PackedByteArray) -> bool
##   sig_verifier(peer_key, payload: PackedByteArray, sig: PackedByteArray) -> bool
## Telemetry (opt-in, anonymous) is validated against an allowlist and stored
## separately; nothing in it identifies a player.

const TELEMETRY_KINDS := {
	"disconnect": ["cause", "turn"],
	"match_length": ["turns", "mode"],
	"crash": ["signature", "build"],
	"performance": ["avg_frame_msec", "p99_frame_msec", "build"],
}
const MAX_STRING := 64

var ticket_verifier: Callable
var sig_verifier: Callable
var results: Array = []  ## accepted result dictionaries (no rating)
var telemetry: Array = []
var rejects: Array = []  ## {id, reason}, for the auditor / moderation
var _seen: Dictionary = {}


func _init(tickets: Callable, sigs: Callable) -> void:
	ticket_verifier = tickets
	sig_verifier = sigs


## Canonical, order-independent bytes every peer signs. result keys:
## match_id, data_hash, seed, winner_side, turns, players: {peer_key: side}.
static func canonical(result: Dictionary) -> PackedByteArray:
	var players: Dictionary = result.get("players", {})
	var keys := players.keys()
	keys.sort()
	var parts: PackedStringArray = []
	for k in keys:
		parts.append("%s=%s" % [k, players[k]])
	var s := "v1|%s|%s|%s|%s|%d|%s" % [
		result.get("match_id", ""), result.get("data_hash", ""), result.get("seed", ""),
		result.get("winner_side", ""), int(result.get("turns", 0)), ",".join(parts)]
	return s.to_utf8_buffer()


## submission: {result, tickets: {peer_key: bytes}, sigs: {peer_key: bytes}}.
## Returns {ok: bool, reason: String}.
func submit(submission: Dictionary) -> Dictionary:
	var result: Dictionary = submission.get("result", {})
	var id := String(result.get("match_id", ""))
	if id == "" or result.get("players", {}).size() < 2:
		return _reject(id, "malformed")
	if _seen.has(id):
		return _reject(id, "duplicate")
	var payload := canonical(result)
	var tickets: Dictionary = submission.get("tickets", {})
	var sigs: Dictionary = submission.get("sigs", {})
	for peer in result["players"]:
		if not tickets.has(peer) or not ticket_verifier.call(peer, tickets[peer]):
			return _reject(id, "bad_ticket:%s" % peer)
		if not sigs.has(peer) or not sig_verifier.call(peer, payload, sigs[peer]):
			return _reject(id, "bad_signature:%s" % peer)
	_seen[id] = true
	results.append(result.duplicate(true))
	return {"ok": true, "reason": ""}


## Telemetry event: {kind, fields}. Only allowlisted kinds and fields are kept
## (no chat, names or ids); strings are capped.
func ingest(event: Dictionary) -> Dictionary:
	var kind := String(event.get("kind", ""))
	if not TELEMETRY_KINDS.has(kind):
		return {"ok": false, "reason": "unknown_kind"}
	var clean := {"kind": kind}
	var fields: Dictionary = event.get("fields", {})
	for f in TELEMETRY_KINDS[kind]:
		if fields.has(f):
			var v = fields[f]
			if v is String:
				v = v.left(MAX_STRING)
			elif not (v is int or v is float or v is bool):
				continue
			clean[f] = v
	telemetry.append(clean)
	return {"ok": true, "reason": ""}


func _reject(id: String, reason: String) -> Dictionary:
	rejects.append({"id": id, "reason": reason})
	return {"ok": false, "reason": reason}
