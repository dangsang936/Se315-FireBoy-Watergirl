class_name Ladder
extends Area2D

const LADDER_COLLISION_LAYER: int = 8
const LADDER_COLLISION_MASK: int = 0

@export var climb_speed: float = 75.0:
	set(value):
		climb_speed = maxf(value, 1.0)
@export_multiline var collision_layers_documentation: String = "Default layer/mask: LadderDetector overlaps this Area2D; the ladder does not block player movement."

func _ready() -> void:
	collision_layer = LADDER_COLLISION_LAYER
	collision_mask = LADDER_COLLISION_MASK
	add_to_group("ladder")
	monitoring = true
	monitorable = true

func get_climb_speed() -> float:
	return climb_speed
