extends SceneTree
func _initialize() -> void:
	var sc := WorkshopScenario.find("fire_range_mortar_rifle")
	var run := WorkshopRun.execute(sc, "focus", false)
	var u := run.state.units
	for row in u.count():
		print("unit %d x=%.2f y=%.2f hp=%d" % [u.id_at(row) - 4294967296, float(u.x[row]) / Fixed.ONE, float(u.y[row]) / Fixed.ONE, u.hp[row] / Fixed.ONE])
	quit(0)
