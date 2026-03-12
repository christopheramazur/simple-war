extends Control

## Scenario selection screen: lists available scenarios and starts battles.

@onready var scenario_list: ItemList = %ScenarioList
@onready var description_label: Label = %DescriptionLabel
@onready var attacker_label: Label = %AttackerLabel
@onready var defender_label: Label = %DefenderLabel
@onready var start_btn: Button = %StartButton
@onready var back_btn: Button = %BackButton
@onready var sim_btn: Button = %SimulateButton

var _scenario_ids: Array[String] = []


func _ready() -> void:
	_load_scenarios()
	scenario_list.item_selected.connect(_on_scenario_selected)
	start_btn.pressed.connect(_on_start)
	back_btn.pressed.connect(_on_back)
	sim_btn.pressed.connect(_on_simulate)
	start_btn.disabled = true
	sim_btn.disabled = true

	if scenario_list.item_count > 0:
		scenario_list.select(0)
		_on_scenario_selected(0)


func _load_scenarios() -> void:
	var raw := DataLoader.load_scenarios()
	if not raw.has("scenarios"):
		return
	for entry: Dictionary in raw["scenarios"]:
		var id: String = entry.get("id", "")
		var name: String = entry.get("display_name", id)
		scenario_list.add_item(name)
		_scenario_ids.append(id)


func _on_scenario_selected(index: int) -> void:
	start_btn.disabled = false
	sim_btn.disabled = false

	var raw := DataLoader.load_scenarios()
	var scenarios: Array = raw.get("scenarios", [])
	if index >= scenarios.size():
		return

	var scenario: Dictionary = scenarios[index]
	description_label.text = scenario.get("description", "")

	var atk_text := ""
	var def_text := ""
	for force: Dictionary in scenario.get("forces", []):
		var side: String = force.get("side", "")
		var units_text := ""
		for unit_entry: Dictionary in force.get("units", []):
			var unit_id: String = unit_entry.get("unit_id", "")
			var count: int = int(unit_entry.get("count", 1))
			if not units_text.is_empty():
				units_text += ", "
			units_text += "%dx %s" % [count, unit_id]
		if side == "attacker":
			atk_text = units_text
		else:
			def_text = units_text

	attacker_label.text = "Attacker: %s" % atk_text
	defender_label.text = "Defender: %s" % def_text


func _on_start() -> void:
	var selected := scenario_list.get_selected_items()
	if selected.is_empty():
		return
	GameData.selected_scenario_id = _scenario_ids[selected[0]]
	get_tree().change_scene_to_file("res://src/ui/battlefield.tscn")


func _on_simulate() -> void:
	var selected := scenario_list.get_selected_items()
	if selected.is_empty():
		return
	var scenario_id := _scenario_ids[selected[0]]
	var report := GameData.scenario_runner.run_scenario(scenario_id, 500)
	if report != null:
		description_label.text = report.to_string_report()


func _on_back() -> void:
	get_tree().change_scene_to_file("res://src/ui/main_menu.tscn")
