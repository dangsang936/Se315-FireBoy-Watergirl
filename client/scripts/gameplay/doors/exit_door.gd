class_name ExitDoor
extends Area2D

const EXIT_COLLISION_LAYER: int = 64
const EXIT_COLLISION_MASK: int = 2

signal player_entered(player: Node2D)


func _ready() -> void:
	collision_layer = EXIT_COLLISION_LAYER
	collision_mask = EXIT_COLLISION_MASK
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_entered.emit(body)
