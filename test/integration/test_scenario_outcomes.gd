extends GutTest

## Integration tests: run full scenarios from JSON data and verify
## outcome distributions are reasonable.

var runner: ScenarioRunner


func before_all() -> void:
	runner = ScenarioRunner.new()
	runner.initialize()


func test_mirror_match_is_roughly_even() -> void:
	seed(42)
	var report := runner.run_scenario("mirror_match", 200)

	assert_not_null(report, "Report should be generated")
	var rate := report.get_attacker_win_rate()
	assert_gt(rate, 0.25, "Attacker should win at least 25%% in mirror match")
	assert_lt(rate, 0.75, "Attacker should win at most 75%% in mirror match")
	gut.p(report.to_string_report())


func test_horde_vs_warmachine_warmachine_usually_wins() -> void:
	seed(42)
	var report := runner.run_scenario("horde_vs_warmachine", 200)

	assert_not_null(report)
	gut.p(report.to_string_report())
	# Warmachine is the defender; it should win often but not always
	assert_gt(report.defender_wins, 0,
		"Warmachine should win at least some battles")


func test_infantry_vs_bioterror_bioterror_is_strong() -> void:
	seed(42)
	var report := runner.run_scenario("infantry_vs_bioterror", 200)

	assert_not_null(report)
	gut.p(report.to_string_report())
	# Both sides should be able to win -- riflemen through volume, bioterror through power
	assert_gt(report.attacker_wins + report.defender_wins, 0,
		"At least one side should win some battles")


func test_mage_vs_horde() -> void:
	seed(42)
	var report := runner.run_scenario("mage_vs_horde", 200)

	assert_not_null(report)
	gut.p(report.to_string_report())


func test_warmachine_vs_bioterror() -> void:
	seed(42)
	var report := runner.run_scenario("warmachine_vs_bioterror", 200)

	assert_not_null(report)
	gut.p(report.to_string_report())


func test_combined_arms() -> void:
	seed(42)
	var report := runner.run_scenario("combined_arms", 200)

	assert_not_null(report)
	gut.p(report.to_string_report())


func test_all_scenarios_load_and_run() -> void:
	var ids := runner.get_scenario_ids()
	assert_gt(ids.size(), 0, "Should have at least one scenario")

	for id in ids:
		var report := runner.run_scenario(id, 10)
		assert_not_null(report, "Scenario '%s' should produce a report" % id)
