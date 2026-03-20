extends RefCounted
class_name UnitRuntime

var id: String
var display_name: String
var faction: String
var speed: float
var durability: int
var model_count: int
var position: Vector2
var destination: Vector2
var selected: bool = false
var has_order: bool = false
var alive: bool = true

func _init(
	p_id: String,
	p_name: String,
	p_faction: String,
	p_speed: float,
	p_durability: int,
	p_model_count: int,
	p_position: Vector2
) -> void:
	id = p_id
	display_name = p_name
	faction = p_faction
	speed = p_speed
	durability = p_durability
	model_count = p_model_count
	position = p_position
	destination = p_position
