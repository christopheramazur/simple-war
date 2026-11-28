extends SceneTree
func _initialize() -> void:
	var sc := WorkshopScenario.find("fire_range_mortar_rifle")
	var run := WorkshopRun.execute(sc, "focus")
	for e in run.events:
		var s := str(e)
		if s.contains("4294967299") or s.contains("damag"):
			for ev in e:
				print(str(ev).substr(0, 200))
	quit(0)
