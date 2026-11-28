extends SceneTree
## sw-arse scratch: per-call cost of the LoS walk (plain vs the jump walk) on the
## duel_crossroads map, for random cell pairs 6-20 cells apart.
## Run: harness/bin/hx godot run docs/design/u1/scripts/fp/los_cost.gd

func _initialize() -> void:
	Fixed.warm()
	var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	var r := BattleRules.compile(l.templates, "duel_crossroads", l.data_hash)
	var n := 20000
	var seed := 7
	var pairs := PackedInt64Array()
	for i in n:
		seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
		var x0 := seed % r.width
		seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
		var y0 := seed % r.height
		seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
		var d := 6 + seed % 15
		var ang := float(seed % 628) / 100.0
		var x1 := clampi(x0 + int(round(d * cos(ang))), 0, r.width - 1)
		var y1 := clampi(y0 + int(round(d * sin(ang))), 0, r.height - 1)
		pairs.append_array([x0, y0, x1, y1])
	r.los_ready()
	var t0 := Time.get_ticks_usec()
	var a := 0
	for i in n:
		if r._walk_los(pairs[4 * i], pairs[4 * i + 1], pairs[4 * i + 2], pairs[4 * i + 3]):
			a += 1
	var t1 := Time.get_ticks_usec()
	var b := 0
	for i in n:
		if r._jump_los(pairs[4 * i], pairs[4 * i + 1], pairs[4 * i + 2], pairs[4 * i + 3]):
			b += 1
	var t2 := Time.get_ticks_usec()
	var c := 0
	for i in n:
		c += pairs[4 * i]
	var t3 := Time.get_ticks_usec()
	print("walk %.2f us/call  jump walk %.2f us/call  loop overhead %.2f us/call  agree %s (%d clear)" % [
		(t1 - t0) / float(n), (t2 - t1) / float(n), (t3 - t2) / float(n), a == b, a])
	quit(0)
