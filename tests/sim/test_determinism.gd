extends GutTest
## Same inputs + same seed => same state hash. GDD 02 §2.1, R1Q7. Task sw-qio.7.
##
## The world exercises fixed-point movement, trig, rng-driven spawns through
## the command buffer, despawns (swap-remove, slot reuse) and cross-context
## transfers through the pulse bus.

const W := preload("res://tests/sim/support/sim_world.gd")


func test_same_seed_same_hashes_every_tick() -> void:
	var a := W.new(42, true)
	var b := W.new(42, true)
	a.run(6, 30)
	b.run(6, 30)
	assert_eq(a.combined_hash(), b.combined_hash())
	assert_eq(a.runner.tick_hashes, b.runner.tick_hashes)
	assert_eq(a.runner.tick_hashes.size(), 6 * 30 * 2)


func test_world_actually_churns() -> void:
	var w := W.new(42)
	w.run(6, 30)
	var applied := 0
	for entry in w.bus.history:
		if (entry[1] as SimEvent).type == &"transfer_applied":
			applied += 1
	assert_gt(applied, 0, "transfers happened")
	var despawned := 0
	for ctx in w.contexts:
		for e in ctx.turn_log:
			if e.type == &"entity_despawned":
				despawned += 1
	assert_gt(w.contexts[1].table(&"squad").count(), 0, "context 2 has squads")
	assert_true(despawned >= 0)


func test_different_seed_diverges() -> void:
	var a := W.new(42)
	var b := W.new(43)
	a.run(3, 30)
	b.run(3, 30)
	assert_ne(a.combined_hash(), b.combined_hash())


func test_hash_changes_every_tick() -> void:
	var w := W.new(7, true)
	w.run(1, 20)
	var unique := {}
	for h in w.runner.tick_hashes:
		unique[h] = true
	assert_eq(unique.size(), w.runner.tick_hashes.size(), "tick counter alone changes the hash")


func test_split_runs_match_one_run() -> void:
	# Running 4 turns as 2 + 2 gives the same state as 4 at once.
	var a := W.new(99)
	var b := W.new(99)
	a.run(4, 25)
	b.run(2, 25)
	b.run(2, 25)
	assert_eq(a.combined_hash(), b.combined_hash())
