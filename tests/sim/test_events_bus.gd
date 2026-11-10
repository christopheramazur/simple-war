extends GutTest
## Event queues, pulse bus and transfers. GDD 04 §4.3, R7Q12, R7Q13. Task sw-qio.5.

const W := preload("res://tests/sim/support/sim_world.gd")

var _seen: Array = []


func _make() -> Array:
	var bus := PulseBus.new()
	var c1 := SimContext.new(1, &"battle")
	var c2 := SimContext.new(2, &"battle")
	c1.add_table(W.SquadTable.new())
	c2.add_table(W.SquadTable.new())
	# Register out of order on purpose: delivery must still be by context ID.
	bus.register_context(c2)
	bus.register_context(c1)
	return [bus, c1, c2]


func test_delivery_is_canonical_and_only_at_flush() -> void:
	var m := _make()
	var bus: PulseBus = m[0]
	var c1: SimContext = m[1]
	var c2: SimContext = m[2]
	c2.post(&"ping", {"n": 1})
	c1.post(&"ping", {"n": 2})
	c1.post(&"ping", {"n": 3})
	var order: Array[int] = []
	bus.register_handler(&"ping", func(_b: PulseBus, e: SimEvent) -> void: order.append(e.data["n"]))
	assert_eq(order.size(), 0, "nothing delivered before flush")
	bus.flush(&"after_execute")
	assert_eq(order, [2, 3, 1] as Array[int])


func test_handler_posts_join_same_flush_in_order() -> void:
	var m := _make()
	var bus: PulseBus = m[0]
	var c1: SimContext = m[1]
	var order: Array[String] = []
	bus.register_handler(&"a", func(b: PulseBus, _e: SimEvent) -> void:
		order.append("a")
		b.post(&"b", {}))
	bus.register_handler(&"b", func(_b: PulseBus, _e: SimEvent) -> void: order.append("b"))
	c1.post(&"a", {})
	c1.post(&"a", {})
	var delivered := bus.flush(&"turn_start")
	assert_eq(order, ["a", "a", "b", "b"] as Array[String])
	assert_eq(delivered.size(), 4)


func _on_published(e: SimEvent, point: StringName) -> void:
	_seen.append([e.type, point])


func test_presentation_hears_after_sim() -> void:
	var m := _make()
	var bus: PulseBus = m[0]
	var c1: SimContext = m[1]
	_seen = []
	bus.published.connect(_on_published)
	c1.post(&"battle_ended", {})
	bus.flush(&"after_execute")
	assert_eq(_seen, [[&"battle_ended", &"after_execute"]])


func test_transfer_moves_entity_between_contexts() -> void:
	var m := _make()
	var bus: PulseBus = m[0]
	var c1: SimContext = m[1]
	var c2: SimContext = m[2]
	TransferSystem.new().attach(bus)
	var id := c1.table(&"squad").spawn({"x": 7, "hp": 55, "team": 1})
	c1.post(&"transfer_requested", {"kind": &"squad", "id": id, "to": 2, "set": {"team": 2}})
	assert_eq(c2.table(&"squad").count(), 0, "not mid-tick")
	var delivered := bus.flush(&"after_execute")
	assert_false(c1.table(&"squad").is_alive(id))
	assert_eq(c2.table(&"squad").count(), 1)
	var applied := delivered.filter(func(e: SimEvent) -> bool: return e.type == &"transfer_applied")
	assert_eq(applied.size(), 1)
	var new_id: int = applied[0].data["new_id"]
	assert_eq(c2.table(&"squad").get_value(new_id, &"x"), 7)
	assert_eq(c2.table(&"squad").get_value(new_id, &"hp"), 55)
	assert_eq(c2.table(&"squad").get_value(new_id, &"team"), 2, "override applied")


func test_transfer_of_dead_entity_fails_cleanly() -> void:
	var m := _make()
	var bus: PulseBus = m[0]
	var c1: SimContext = m[1]
	TransferSystem.new().attach(bus)
	var id := c1.table(&"squad").spawn()
	c1.table(&"squad").despawn(id)
	c1.post(&"transfer_requested", {"kind": &"squad", "id": id, "to": 2})
	var delivered := bus.flush(&"after_execute")
	var failed := delivered.filter(func(e: SimEvent) -> bool: return e.type == &"transfer_failed")
	assert_eq(failed.size(), 1)
	assert_eq(failed[0].data["reason"], "entity not alive")
