class_name Centroids
extends SimSystem
## Recomputes each squad's centroid and living-unit count from its units, and
## groups unit rows by squad row for the systems after it this tick.

func system_name() -> StringName:
	return &"centroids"


func run(ctx: SimContext) -> void:
	update(ctx as BattleState)


static func update(state: BattleState) -> void:
	var sq := state.squads
	var u := state.units
	var n := sq.count()
	var sum_x := PackedInt64Array()
	var sum_y := PackedInt64Array()
	var cnt := PackedInt64Array()
	sum_x.resize(n)
	sum_y.resize(n)
	cnt.resize(n)
	var by_squad := {}
	for row in u.count():
		var srow := sq.row_of(u.squad[row])
		if srow < 0:
			continue
		sum_x[srow] += u.x[row]
		sum_y[srow] += u.y[row]
		cnt[srow] += 1
		if not by_squad.has(srow):
			by_squad[srow] = PackedInt64Array()
		var rows: PackedInt64Array = by_squad[srow]
		rows.append(row)
		by_squad[srow] = rows
	var cx: PackedInt64Array = sq.take_column(&"cx")
	var cy: PackedInt64Array = sq.take_column(&"cy")
	var alive: PackedInt64Array = sq.take_column(&"alive")
	for srow in n:
		alive[srow] = cnt[srow]
		if cnt[srow] > 0:
			cx[srow] = Fixed.round_div(sum_x[srow], cnt[srow])
			cy[srow] = Fixed.round_div(sum_y[srow], cnt[srow])
	sq.put_column(&"cx", cx)
	sq.put_column(&"cy", cy)
	sq.put_column(&"alive", alive)
	state.squad_units = by_squad


static func units_of(state: BattleState, srow: int) -> PackedInt64Array:
	return state.squad_units.get(srow, PackedInt64Array())
