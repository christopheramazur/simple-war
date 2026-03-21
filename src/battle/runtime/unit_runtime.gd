extends RefCounted
class_name UnitRuntime

var id: String
var display_name: String
var faction: String
var speed: float
var durability: int
var model_count: int
## World-space spacing for formation layout (miniatures).
var model_diameter_world: float = 1.0
## Formation grid: files (width) × ranks (depth). Used for draw offsets.
var formation_files: int = 5
var formation_ranks: int = 2
var position: Vector2
var destination: Vector2
var selected: bool = false
var has_order: bool = false
var alive: bool = true
var deployed: bool = false

func _init(
	p_id: String,
	p_name: String,
	p_faction: String,
	p_speed: float,
	p_durability: int,
	p_model_count: int,
	p_position: Vector2,
	p_model_diameter_world: float = 1.0,
	p_formation_files: int = 5,
	p_formation_ranks: int = 2
) -> void:
	id = p_id
	display_name = p_name
	faction = p_faction
	speed = p_speed
	durability = p_durability
	model_count = p_model_count
	model_diameter_world = p_model_diameter_world
	formation_files = p_formation_files
	formation_ranks = p_formation_ranks
	position = p_position
	destination = p_position
