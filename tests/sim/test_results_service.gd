extends GutTest
## Results service + telemetry (sw-5x6.4).

const KEY := "k"


func _sign(peer: String, payload: PackedByteArray) -> PackedByteArray:
	var c := Crypto.new()
	return c.hmac_digest(HashingContext.HASH_SHA256, KEY.to_utf8_buffer(), payload + peer.to_utf8_buffer())


func _svc() -> ResultsService:
	return ResultsService.new(
		func(_p, t): return t.size() > 0,
		func(p, payload, sig): return _sign(p, payload) == sig)


func _result() -> Dictionary:
	return {"match_id": "m1", "data_hash": "h", "seed": 7, "winner_side": "a", "turns": 12,
		"players": {"p2": "b", "p1": "a"}}


func _sub(r: Dictionary) -> Dictionary:
	var tickets := {}
	var sigs := {}
	var payload := ResultsService.canonical(r)
	for p in r["players"]:
		tickets[p] = PackedByteArray([1])
		sigs[p] = _sign(p, payload)
	return {"result": r, "tickets": tickets, "sigs": sigs}


func test_accepts_cosigned_result_without_rating() -> void:
	var s := _svc()
	assert_true(s.submit(_sub(_result()))["ok"])
	assert_eq(s.results.size(), 1)
	assert_false(s.results[0].has("rating"))


func test_canonical_ignores_player_order() -> void:
	var a := _result()
	var b := _result()
	b["players"] = {"p1": "a", "p2": "b"}
	assert_eq(ResultsService.canonical(a), ResultsService.canonical(b))


func test_rejects_missing_signature_tampering_and_duplicate() -> void:
	var s := _svc()
	var sub := _sub(_result())
	sub["sigs"].erase("p2")
	assert_eq(s.submit(sub)["reason"], "bad_signature:p2")
	var t := _sub(_result())
	t["result"]["winner_side"] = "b"
	assert_false(s.submit(t)["ok"])
	assert_true(s.submit(_sub(_result()))["ok"])
	assert_eq(s.submit(_sub(_result()))["reason"], "duplicate")


func test_rejects_bad_ticket_and_malformed() -> void:
	var s := _svc()
	var sub := _sub(_result())
	sub["tickets"]["p1"] = PackedByteArray()
	assert_eq(s.submit(sub)["reason"], "bad_ticket:p1")
	assert_eq(s.submit({"result": {}})["reason"], "malformed")


func test_service_telemetry_allowlist() -> void:
	var s := _svc()
	assert_false(s.ingest({"kind": "chat", "fields": {}})["ok"])
	s.ingest({"kind": "disconnect", "fields": {"cause": "x".repeat(100), "turn": 3, "name": "bob", "obj": {}}})
	assert_eq(s.telemetry[0].keys().size(), 3)
	assert_eq(s.telemetry[0]["cause"].length(), 64)


func test_client_opt_in_and_flush() -> void:
	var sent := []
	var ok := [false]
	var c := TelemetryClient.new(func(ev): sent.append_array(ev); return ok[0])
	assert_false(c.record("crash", {"signature": "a"}))
	c.set_opt_in(true)
	assert_true(c.record("crash", {"signature": "a", "user": "me"}))
	assert_false(c.record("chat", {}))
	assert_eq(c.queue[0]["fields"].keys(), ["signature"])
	assert_eq(c.flush(), 0)
	assert_eq(c.queue.size(), 1)
	ok[0] = true
	assert_eq(c.flush(), 1)
	assert_true(c.queue.is_empty())
	c.record("crash", {})
	c.set_opt_in(false)
	assert_true(c.queue.is_empty())
