extends Node

## GameData autoload: loads all JSON data at startup and provides
## factory access for constructing ECS archetype Entity instances.
## Load order respects Component dependencies:
##   AttackFactory (AttackProfileComponents) →
##   ItemFactory (Item Entities) →
##   UnitFactory (Unit + Model Entities).

var attack_factory := AttackFactory.new()
var item_factory := ItemFactory.new()
var unit_factory := UnitFactory.new()
var scenario_runner := ScenarioRunner.new()

var selected_scenario_id: String = ""

var _loaded := false


func _ready() -> void:
	load_all()


func load_all() -> void:
	if _loaded:
		return
	attack_factory.load_all()
	item_factory.load_all(attack_factory)
	unit_factory.load_all(item_factory)
	scenario_runner.initialize()
	_loaded = true
