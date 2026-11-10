extends GutTest
## Pulse clock and turn phases. GDD 02 §2.2. Task sw-qio.6.

var _phases: Array[String] = []
var _points: Array[String] = []


func _clock(cfg: ClockConfig = null) -> PulseClock:
	var c := PulseClock.new(cfg)
	c.add_player(1)
	c.add_player(2)
	_phases = []
	_points = []
	c.phase_changed.connect(func(p: PulseClock.Phase, t: int) -> void:
		_phases.append("%s@%d" % [PulseClock.Phase.keys()[p], t]))
	c.pulse_point.connect(func(point: StringName, t: int) -> void:
		_points.append("%s@%d" % [point, t]))
	return c


func test_parallel_bonus_curve() -> void:
	var cfg := ClockConfig.new()
	assert_eq(cfg.parallel_bonus_ms(0), 0)
	assert_eq(cfg.parallel_bonus_ms(1), 0)
	assert_eq(cfg.parallel_bonus_ms(2), 10000)
	assert_eq(cfg.parallel_bonus_ms(3), 19167)
	assert_eq(cfg.parallel_bonus_ms(10), 60000)
	assert_eq(cfg.parallel_bonus_ms(12), 62000)
	var prev_step := 1 << 40
	for n in range(2, 11):
		var step := cfg.parallel_bonus_ms(n) - cfg.parallel_bonus_ms(n - 1)
		assert_true(step <= prev_step and step > 0, "increments shrink at %d" % n)
		prev_step = step


func test_all_ready_ends_planning() -> void:
	var c := _clock()
	c.start()
	c.advance(5000)
	c.mark_ready(1)
	assert_eq(c.phase, PulseClock.Phase.PLANNING)
	c.mark_ready(2)
	assert_eq(c.phase, PulseClock.Phase.REACTION)
	assert_eq(_phases, ["PLANNING@1", "REVEAL@1", "REACTION@1"] as Array[String])
	assert_eq(_points, ["turn_start@1"] as Array[String])


func test_full_turn_with_timeouts_reserve_and_early_intermission() -> void:
	var c := _clock()
	c.start()
	c.advance(10000)
	c.mark_ready(1)
	c.advance(79999)
	assert_eq(c.phase, PulseClock.Phase.PLANNING, "player 2 still has reserve")
	c.advance(1)
	assert_eq(c.phase, PulseClock.Phase.REACTION, "planning 60 s + reserve 30 s")
	assert_eq(c.reserve_ms(1), 30000, "ready early: no reserve used")
	assert_eq(c.reserve_ms(2), 0, "timed out: reserve spent")
	c.advance(10000)
	assert_eq(c.phase, PulseClock.Phase.EXECUTE)
	c.advance(999999)
	assert_eq(c.phase, PulseClock.Phase.EXECUTE, "playback is not timed")
	c.execute_finished()
	assert_eq(c.phase, PulseClock.Phase.INTERMISSION)
	c.advance(1000)
	c.mark_ready(1)
	c.advance(2999)
	assert_eq(c.phase, PulseClock.Phase.INTERMISSION)
	c.advance(1)
	assert_eq(c.phase, PulseClock.Phase.PLANNING, "half ready: drops to 3 s")
	assert_eq(c.turn, 2)
	assert_eq(c.reserve_ms(1), 40000, "top-up")
	assert_eq(c.reserve_ms(2), 10000, "top-up")
	assert_eq(_points, ["turn_start@1", "after_execute@1", "turn_start@2"] as Array[String])


func test_parallel_bonus_extends_planning() -> void:
	var c := _clock()
	c.set_battles(1, 2)
	c.start()
	c.mark_ready(2)
	assert_eq(c.remaining_ms(1), 60000 + 10000 + 30000)
	c.advance(99999)
	assert_eq(c.phase, PulseClock.Phase.PLANNING)
	c.advance(1)
	assert_eq(c.phase, PulseClock.Phase.REACTION)


func test_reaction_disabled_and_ranked_intermission() -> void:
	var cfg := ClockConfig.new()
	cfg.reaction_enabled = false
	cfg.ranked = true
	var c := _clock(cfg)
	c.start()
	c.mark_ready(1)
	c.mark_ready(2)
	assert_eq(c.phase, PulseClock.Phase.EXECUTE)
	c.execute_finished()
	c.advance(9999)
	assert_eq(c.phase, PulseClock.Phase.INTERMISSION)
	c.advance(1)
	assert_eq(c.phase, PulseClock.Phase.PLANNING, "ranked cap 10 s")


func test_untimed_waits_for_everyone() -> void:
	var cfg := ClockConfig.new()
	cfg.untimed = true
	var c := _clock(cfg)
	c.start()
	c.advance(10000000)
	assert_eq(c.phase, PulseClock.Phase.PLANNING)
	assert_eq(c.remaining_ms(1), -1)
	c.mark_ready(1)
	c.mark_ready(2)
	assert_eq(c.phase, PulseClock.Phase.REACTION)
	assert_eq(c.reserve_ms(1), 30000, "untimed never draws reserve")
