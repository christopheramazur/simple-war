extends Node
## Creates the default GECS [World], assigns [member ECS.world], and drives [method ECS.process] each frame.
## World is parented under the scene tree root when no node named "Root" exists (see addons/gecs/ecs/ecs.gd).

func _ready() -> void:
	call_deferred("_ensure_world")

func _ensure_world() -> void:
	if ECS.world != null:
		return
	var w := World.new()
	w.name = "GameWorld"
	var entities := Node.new()
	entities.name = "Entities"
	var systems := Node.new()
	systems.name = "Systems"
	w.add_child(entities)
	w.add_child(systems)
	w.entity_nodes_root = w.get_path_to(entities)
	w.system_nodes_root = w.get_path_to(systems)
	ECS.world = w

func _process(delta: float) -> void:
	if ECS.world != null:
		ECS.process(delta)
