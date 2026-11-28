extends SceneTree
## Times CombatSystem.run on identical states under nearest and focus: the
## fire_duel_rifle_mirror opening (8 v 8 rifles, both firing) and the mortar
## range (3 mortars, area plan). Each iteration restores the same snapshot.
const N := 400

func _bench(sid: String, variant: String, label: String) -> void:
	var sc := WorkshopScenario.find(sid)
	var run := WorkshopRun.execute(sc, variant, false)
	var s := run.state
	var sys := CombatSystem.new()
	# Arm the opening: engage and ready every shooter.
	var snap := s.snapshot()
	var t0 := Time.get_ticks_usec()
	for i in N:
		s.restore(snap)
		sys.run(s)
	var dt := Time.get_ticks_usec() - t0
	print("%s %s: %.1f usec per combat tick" % [sid, label, float(dt) / N])

func _initialize() -> void:
	for rep in 2:
		_bench("fire_duel_rifle_mirror", "base", "nearest/nearest")
		_bench("fire_duel_rifle_mirror", "focus_a", "focus/nearest")
		_bench("fire_range_mortar_rifle", "base", "nearest")
		_bench("fire_range_mortar_rifle", "focus", "focus")
		_bench("fire_range_hwt_rifle", "base", "nearest")
		_bench("fire_range_hwt_rifle", "focus", "focus")
	quit(0)
