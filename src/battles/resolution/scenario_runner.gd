class_name ScenarioRunner
extends RefCounted

## Loads scenarios from JSON, constructs Unit archetype Entity instances
## for each side, runs the Combat System N times, and reports statistics.
## Primary iteration tool for balancing the Combat System pipeline.

var _attack_factory := AttackFactory.new()
var _item_factory := ItemFactory.new()
var _unit_factory := UnitFactory.new()
var _orchestrator := CombatOrchestrator.new()
var _scenarios: Dictionary = {}  # id -> raw dict


func initialize() -> void:
	_attack_factory.load_all()
	_item_factory.load_all(_attack_factory)
	_unit_factory.load_all(_item_factory)

	var raw := DataLoader.load_scenarios()
	if raw.has("scenarios"):
		for entry: Dictionary in raw["scenarios"]:
			_scenarios[entry["id"]] = entry


func get_scenario_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_scenarios.keys())
	return ids


func get_scenario_display_name(scenario_id: String) -> String:
	if _scenarios.has(scenario_id):
		return _scenarios[scenario_id].get("display_name", scenario_id)
	return scenario_id


func run_scenario(scenario_id: String, iterations: int = 100) -> ScenarioReport:
	if not _scenarios.has(scenario_id):
		push_error("ScenarioRunner: unknown scenario '%s'" % scenario_id)
		return null

	var def: Dictionary = _scenarios[scenario_id]
	var report := ScenarioReport.new()
	report.scenario_id = scenario_id
	report.scenario_name = def.get("display_name", scenario_id)
	report.iterations = iterations

	for _i in range(iterations):
		var attacker_units := _build_force(def, "attacker")
		var defender_units := _build_force(def, "defender")
		var result := _orchestrator.resolve_battle(attacker_units, defender_units)

		report.add_result(result)

	return report


func run_single(scenario_id: String) -> CombatResult:
	if not _scenarios.has(scenario_id):
		push_error("ScenarioRunner: unknown scenario '%s'" % scenario_id)
		return null

	var def: Dictionary = _scenarios[scenario_id]
	var attacker_units := _build_force(def, "attacker")
	var defender_units := _build_force(def, "defender")
	return _orchestrator.resolve_battle(attacker_units, defender_units)


func _build_force(scenario_def: Dictionary, side: String) -> Array[UnitData]:
	var units: Array[UnitData] = []
	var forces: Array = scenario_def.get("forces", [])
	for force: Dictionary in forces:
		if force.get("side", "") != side:
			continue
		var force_units: Array = force.get("units", [])
		for entry: Dictionary in force_units:
			var unit_id: String = entry.get("unit_id", "")
			var count: int = int(entry.get("count", 1))
			for _j in range(count):
				var unit := _unit_factory.create_unit(unit_id)
				if unit != null:
					if side == "attacker":
						unit.position = Vector2(100.0, 80.0 + units.size() * 5.0)
					else:
						unit.position = Vector2(100.0, 20.0 + units.size() * 5.0)
					units.append(unit)
	return units


## Aggregated statistics from running a scenario multiple times.
class ScenarioReport:
	extends RefCounted

	var scenario_id: String = ""
	var scenario_name: String = ""
	var iterations: int = 0

	var attacker_wins: int = 0
	var defender_wins: int = 0
	var draws: int = 0

	var total_attacker_models_lost: int = 0
	var total_defender_models_lost: int = 0
	var total_turns: int = 0
	var total_damage_dealt: int = 0

	func add_result(result: CombatResult) -> void:
		var winner := result.get_winner()
		match winner:
			"attacker":
				attacker_wins += 1
			"defender":
				defender_wins += 1
			_:
				draws += 1

		total_attacker_models_lost += result.attacker_models_lost
		total_defender_models_lost += result.defender_models_lost
		total_turns += result.turns_elapsed
		total_damage_dealt += result.total_damage_dealt

	func get_attacker_win_rate() -> float:
		if iterations == 0:
			return 0.0
		return float(attacker_wins) / float(iterations)

	func get_defender_win_rate() -> float:
		if iterations == 0:
			return 0.0
		return float(defender_wins) / float(iterations)

	func get_avg_turns() -> float:
		if iterations == 0:
			return 0.0
		return float(total_turns) / float(iterations)

	func get_avg_attacker_losses() -> float:
		if iterations == 0:
			return 0.0
		return float(total_attacker_models_lost) / float(iterations)

	func get_avg_defender_losses() -> float:
		if iterations == 0:
			return 0.0
		return float(total_defender_models_lost) / float(iterations)

	func to_string_report() -> String:
		var lines: PackedStringArray = []
		lines.append("=== %s ===" % scenario_name)
		lines.append("Iterations: %d" % iterations)
		lines.append("Attacker wins: %d (%.1f%%)" % [attacker_wins, get_attacker_win_rate() * 100.0])
		lines.append("Defender wins: %d (%.1f%%)" % [defender_wins, get_defender_win_rate() * 100.0])
		lines.append("Draws: %d" % draws)
		lines.append("Avg turns: %.1f" % get_avg_turns())
		lines.append("Avg attacker losses: %.1f models" % get_avg_attacker_losses())
		lines.append("Avg defender losses: %.1f models" % get_avg_defender_losses())
		return "\n".join(lines)
