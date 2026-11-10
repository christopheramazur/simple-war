extends GutTest
## SoA store, command buffer, rng, runner. Tasks sw-qio.2, sw-qio.4.

const W := preload("res://tests/sim/support/sim_world.gd")


func test_spawn_defaults_and_values() -> void:
	var t := W.SquadTable.new()
	var a := t.spawn({"x": 5})
	var b := t.spawn({&"hp": 7})
	assert_ne(a, b)
	assert_eq(t.count(), 2)
	assert_eq(t.get_value(a, &"x"), 5)
	assert_eq(t.get_value(a, &"hp"), 100, "default")
	assert_eq(t.get_value(b, &"hp"), 7)


func test_despawn_swap_remove_keeps_other_rows() -> void:
	var t := W.SquadTable.new()
	var ids: Array[int] = []
	for i in 5:
		ids.append(t.spawn({"x": i * 10}))
	assert_true(t.despawn(ids[1]))
	assert_eq(t.count(), 4)
	assert_false(t.is_alive(ids[1]))
	for i in [0, 2, 3, 4]:
		assert_eq(t.get_value(ids[i], &"x"), i * 10, "row for id %d" % i)
	assert_eq(t.row_of(ids[4]), 1, "last row moved into the hole")
	assert_false(t.despawn(ids[1]), "double despawn is a no-op")


func test_stale_id_never_matches_reused_slot() -> void:
	var t := W.SquadTable.new()
	var a := t.spawn()
	t.despawn(a)
	var b := t.spawn()
	assert_eq(SoaTable.slot_of(a), SoaTable.slot_of(b), "slot reused")
	assert_ne(a, b)
	assert_false(t.is_alive(a))
	assert_true(t.is_alive(b))
	assert_eq(t.row_of(a), -1)


func test_take_put_writes_in_place() -> void:
	var t := W.SquadTable.new()
	var a := t.spawn()
	var hp: PackedInt64Array = t.take_column(&"hp")
	hp[0] = 42
	t.put_column(&"hp", hp)
	assert_eq(t.get_value(a, &"hp"), 42)
	t.set_value(a, &"hp", 43)
	assert_eq(t.hp[0], 43)


func test_export_row_and_ids() -> void:
	var t := W.SquadTable.new()
	var a := t.spawn({"x": 1, "y": 2})
	var row := t.export_row(a)
	assert_eq(row[&"x"], 1)
	assert_eq(row[&"y"], 2)
	assert_eq(t.ids(), PackedInt64Array([a]))


func test_hash_tracks_state() -> void:
	var c1 := SimContext.new(1, &"battle", 5)
	var c2 := SimContext.new(1, &"battle", 5)
	c1.add_table(W.SquadTable.new())
	c2.add_table(W.SquadTable.new())
	c1.table(&"squad").spawn({"x": 3})
	c2.table(&"squad").spawn({"x": 3})
	assert_eq(c1.state_hash_hex(), c2.state_hash_hex())
	c2.table(&"squad").set_value(c2.table(&"squad").id_at(0), &"x", 4)
	assert_ne(c1.state_hash_hex(), c2.state_hash_hex())


func test_command_buffer_defers_and_reports() -> void:
	var ctx := SimContext.new(1, &"battle")
	ctx.add_table(W.SquadTable.new())
	ctx.commands.spawn(&"squad", {"x": 9}, 77)
	assert_eq(ctx.table(&"squad").count(), 0, "deferred")
	ctx.commands.apply(ctx)
	assert_eq(ctx.table(&"squad").count(), 1)
	var spawned := ctx.events.of_type(&"entity_spawned")
	assert_eq(spawned.size(), 1)
	assert_eq(spawned[0].data["tag"], 77)
	var id: int = spawned[0].data["id"]
	ctx.commands.despawn(&"squad", id)
	ctx.commands.despawn(&"squad", id)
	ctx.commands.apply(ctx)
	assert_eq(ctx.events.of_type(&"entity_despawned").size(), 1, "second despawn ignored")


class ProbeSystem extends SimSystem:
	var seen: int = -1

	func system_name() -> StringName:
		return &"probe"

	func run(ctx: SimContext) -> void:
		seen = ctx.table(&"squad").count()


func test_runner_applies_commands_between_phases() -> void:
	var ctx := SimContext.new(1, &"battle", 3)
	ctx.add_table(W.SquadTable.new())
	var probe := ProbeSystem.new()
	var runner := SystemRunner.new()
	runner.add_phase(&"spawn", [W.SpawnSystem.new()] as Array[SimSystem])
	runner.add_phase(&"read", [probe] as Array[SimSystem])
	runner.step(ctx)
	assert_eq(probe.seen, 1, "phase 2 sees phase 1's spawn")
	assert_eq(ctx.tick, 1)
	assert_eq(ctx.turn_log.size(), 1, "spawn event logged")
	assert_eq(runner.order(), PackedStringArray(["spawn/spawn", "read/probe"]))


func test_rng_deterministic() -> void:
	var a := SimRng.new(12345)
	var b := SimRng.new(12345)
	var c := SimRng.new(12346)
	var same := true
	var differs := false
	for _i in 100:
		var va := a.next_u32()
		same = same and va == b.next_u32()
		differs = differs or va != c.next_u32()
		assert_true(va >= 0 and va <= SimRng.M32)
	assert_true(same)
	assert_true(differs)


func test_rng_state_round_trip_and_range() -> void:
	var a := SimRng.new(7)
	a.next_u32()
	var state := a.get_state()
	var first := a.next_u32()
	a.set_state(state)
	assert_eq(a.next_u32(), first)
	for _i in 200:
		var v := a.next_range(-3, 3)
		assert_true(v >= -3 and v <= 3)
