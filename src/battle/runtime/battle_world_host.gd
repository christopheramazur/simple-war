extends Node
class_name BattleWorldHost
## Owns a GECS [World] for battle data **without** replacing [member ECS.world] (campaign stays on the singleton).
## Drives [method World.process] each frame so battle systems can be added later alongside [BattlefieldSimulation].

const C_BATTLE_SCOPE := preload("res://src/battle/components/c_battle_scope.gd")

var world: World

func _ready() -> void:
	_setup_world()
	_spawn_scope_entity()

func _setup_world() -> void:
	world = World.new()
	world.name = "BattleWorld"
	var entities := Node.new()
	entities.name = "Entities"
	var systems := Node.new()
	systems.name = "Systems"
	world.add_child(entities)
	world.add_child(systems)
	world.entity_nodes_root = world.get_path_to(entities)
	world.system_nodes_root = world.get_path_to(systems)
	add_child(world)

func _spawn_scope_entity() -> void:
	var e := Entity.new()
	e.name = "BattleScope"
	e.id = "battle_scope"
	e.add_component(C_BATTLE_SCOPE.new())
	world.add_entity(e)

func _process(delta: float) -> void:
	if world != null:
		world.process(delta)
