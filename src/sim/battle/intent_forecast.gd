class_name IntentForecast
extends RefCounted
## The planning forecast behind intent ghosts (GDD 02 §2.2, R4Q3, R6Q2):
## the coming turn run on a scratch copy with one player's drafted orders,
## as that player knows the battle. Enemy squads the player can't see now
## are taken out of the copy, so the forecast never reveals them; other
## players' drafts are secret, so their squads keep their current orders.
## Read-only: the real state is never touched.

## Ghost positions per squad over the turn (the last one is its end).
const SAMPLES: int = 5


## {"ghosts": own squad ID -> PackedInt64Array [x0, y0, x1, y1, ...] (fixed,
## SAMPLES points), "contacts": [{"squad" (own), "target", "tick",
## "reactions" (names the own squad could react with)}] in canonical order
## (tick, squad, target), "errors": the drafted orders' errors}.
static func run(state: BattleState, sim: BattleSim, player: int, orders: Array) -> Dictionary:
	Stats.warm(state.rules)
	Fixed.warm()
	return _forecast(_copy(state), sim, player, orders)


## The same forecast as a job for a worker thread (sw-j4u): the copy is
## taken now, on the caller's thread, and shared caches are filled; the
## returned Callable runs the turn on the copy with its own BattleSim and
## only reads what is shared (the compiled rules data), so it may run while
## the caller carries on. The caller must not run the real battle until it
## is done.
static func job(state: BattleState, player: int, orders: Array) -> Callable:
	Stats.warm(state.rules)
	Fixed.warm()
	var scratch := _copy(state)
	var o := orders.duplicate(true)
	return func() -> Dictionary: return _forecast(scratch, BattleSim.new(), player, o)


static func _copy(state: BattleState) -> BattleState:
	# Private route cache: the real battle's rules (and any other forecast
	# running at once) must never see this run's cache writes (sw-ll4.26.2).
	var scratch := BattleState.new(state.id, state.rules.forecast_copy())
	scratch.restore(state.snapshot())
	return scratch


static func _forecast(scratch: BattleState, sim: BattleSim, player: int, orders: Array) -> Dictionary:
	var sq := scratch.squads
	var me := BattleSquads.bit(player)
	var withdrawn: PackedByteArray = sq.take_column(&"withdrawn")
	for row in sq.count():
		if sq.player[row] != player and sq.seen_by[row] & me == 0:
			withdrawn[row] = 1
	sq.put_column(&"withdrawn", withdrawn)
	Centroids.update(scratch)
	var errors := BattleOrders.apply(scratch, player, orders)
	var ghosts := {}
	var contacts := []
	var seen := {}
	var n: int = scratch.rules.ticks_per_turn
	var every := maxi(n / SAMPLES, 1)
	scratch.begin_turn()
	for t in n:
		sim.runner.step(scratch)
		for e in scratch.turn_log:
			if e.type != &"engagement":
				continue
			for pair in [[e.data["squad"], e.data["target"]], [e.data["target"], e.data["squad"]]]:
				var row := sq.row_of(pair[0])
				var key := "%d,%d" % pair
				if row < 0 or sq.player[row] != player or seen.has(key):
					continue
				seen[key] = true
				contacts.append({"squad": pair[0], "target": pair[1], "tick": e.tick,
					"reactions": Reactions.available(scratch, row)})
		scratch.turn_log = []
		if (t + 1) % every == 0 or t == n - 1:
			for row in sq.count():
				if sq.player[row] != player or not sq.is_active(row):
					continue
				var id := sq.id_at(row)
				var pts: PackedInt64Array = ghosts.get(id, PackedInt64Array())
				if pts.size() < SAMPLES * 2:
					pts.append_array([sq.cx[row], sq.cy[row]])
				else:
					pts[pts.size() - 2] = sq.cx[row]
					pts[pts.size() - 1] = sq.cy[row]
				ghosts[id] = pts
	contacts.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if x["tick"] != y["tick"]:
			return x["tick"] < y["tick"]
		if x["squad"] != y["squad"]:
			return x["squad"] < y["squad"]
		return x["target"] < y["target"])
	return {"ghosts": ghosts, "contacts": contacts, "errors": errors}
