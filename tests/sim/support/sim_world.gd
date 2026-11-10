extends RefCounted
## A small deterministic world for sim-core tests: two battle contexts with
## moving, decaying squads, rng-driven spawns, and cross-context transfers.


class SquadTable extends SoaTable:
	var x := PackedInt64Array()
	var y := PackedInt64Array()
	var vx := PackedInt64Array()
	var vy := PackedInt64Array()
	var hp := PackedInt64Array()
	var team := PackedByteArray()

	func _init() -> void:
		super(&"squad")
		declare(&"x")
		declare(&"y")
		declare(&"vx")
		declare(&"vy")
		declare(&"hp", 100)
		declare(&"team")


class MoveSystem extends SimSystem:
	const BOUND: int = 100 * Fixed.ONE

	func system_name() -> StringName:
		return &"move"

	func run(ctx: SimContext) -> void:
		var t: SoaTable = ctx.table(&"squad")
		var x: PackedInt64Array = t.take_column(&"x")
		var y: PackedInt64Array = t.take_column(&"y")
		var vx: PackedInt64Array = t.take_column(&"vx")
		var vy: PackedInt64Array = t.take_column(&"vy")
		for row in x.size():
			x[row] += vx[row]
			y[row] += vy[row]
			if x[row] < 0 or x[row] > BOUND:
				vx[row] = -vx[row]
				x[row] = Fixed.clamp_fixed(x[row], 0, BOUND)
			if y[row] < 0 or y[row] > BOUND:
				vy[row] = -vy[row]
				y[row] = Fixed.clamp_fixed(y[row], 0, BOUND)
		t.put_column(&"x", x)
		t.put_column(&"y", y)
		t.put_column(&"vx", vx)
		t.put_column(&"vy", vy)


class DecaySystem extends SimSystem:
	func system_name() -> StringName:
		return &"decay"

	func run(ctx: SimContext) -> void:
		var t: SoaTable = ctx.table(&"squad")
		var hp: PackedInt64Array = t.take_column(&"hp")
		var vx: PackedInt64Array = t.vx
		var vy: PackedInt64Array = t.vy
		for row in hp.size():
			# Faster squads tire faster: hp -= 1 + |v| / 2 (in whole units).
			hp[row] -= 1 + Fixed.to_int_floor(Fixed.length(vx[row], vy[row]) >> 1)
			if hp[row] <= 0:
				ctx.commands.despawn(&"squad", t.id_at(row))
		t.put_column(&"hp", hp)


class SpawnSystem extends SimSystem:
	func system_name() -> StringName:
		return &"spawn"

	func run(ctx: SimContext) -> void:
		if ctx.tick % 5 != 0:
			return
		var angle := ctx.rng.next_below(Fixed.ANGLE_FULL)
		var speed := Fixed.from_ratio(ctx.rng.next_range(1, 8), 4)
		ctx.commands.spawn(&"squad", {
			"x": Fixed.from_int(ctx.rng.next_range(0, 100)),
			"y": Fixed.from_int(ctx.rng.next_range(0, 100)),
			"vx": Fixed.mul(speed, Fixed.fcos(angle)),
			"vy": Fixed.mul(speed, Fixed.fsin(angle)),
			"hp": ctx.rng.next_range(20, 120),
			"team": ctx.id,
		}, ctx.tick)


## Every 8 ticks, context 1 sends its first squad to context 2.
class SendSystem extends SimSystem:
	func system_name() -> StringName:
		return &"send"

	func run(ctx: SimContext) -> void:
		var t: SoaTable = ctx.table(&"squad")
		if ctx.id == 1 and ctx.tick % 8 == 0 and t.count() > 0:
			ctx.post(&"transfer_requested", {"kind": &"squad", "id": t.id_at(0), "to": 2, "set": {"team": 9}})


var bus := PulseBus.new()
var runner := SystemRunner.new()
var contexts: Array[SimContext] = []


func _init(seed_value: int, hash_ticks: bool = false) -> void:
	runner.hash_every_tick = hash_ticks
	runner.add_phase(&"spawn", [SpawnSystem.new()] as Array[SimSystem])
	runner.add_phase(&"update", [MoveSystem.new(), DecaySystem.new(), SendSystem.new()] as Array[SimSystem])
	TransferSystem.new().attach(bus)
	for cid in [1, 2]:
		var ctx := SimContext.new(cid, &"battle", seed_value * 31 + cid)
		ctx.add_table(SquadTable.new())
		bus.register_context(ctx)
		contexts.append(ctx)


## Runs `turns` turns of `ticks` ticks per context, flushing the bus after each.
func run(turns: int, ticks: int) -> void:
	for _t in turns:
		for ctx in contexts:
			ctx.begin_turn()
			runner.step_n(ctx, ticks)
		bus.flush(PulseClock.POINT_AFTER_EXECUTE)


func combined_hash() -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	for ctx in contexts:
		h.update(ctx.state_hash())
	h.update(PackedInt64Array([bus.history.size()]).to_byte_array())
	return h.finish().hex_encode()
