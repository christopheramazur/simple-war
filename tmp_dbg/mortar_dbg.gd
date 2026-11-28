extends SceneTree
func _initialize() -> void:
	var sc := WorkshopScenario.find("fire_range_mortar_rifle")
	for vn in ["base", "focus"]:
		var run := WorkshopRun.execute(sc, vn)
		var s := run.state
		var u := s.units
		print("== ", vn, " errors ", run.errors)
		for row in u.count():
			print("unit id=%d sq=%d x=%.1f y=%.1f hp=%d" % [u.id_at(row), u.squad[row], float(u.x[row]) / Fixed.ONE, float(u.y[row]) / Fixed.ONE, u.hp[row] / Fixed.ONE])
		var tr := s.shot_trace
		var i := 0
		while i < tr.size() and i < 4 * 40:
			print("tick %d shooter %d victim %d hit %d" % [tr[i], tr[i+1], tr[i+2], tr[i+3]])
			i += 4
	quit(0)
