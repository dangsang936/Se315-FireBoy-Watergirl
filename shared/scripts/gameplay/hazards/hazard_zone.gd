class_name HazardZone
extends Area2D

enum PoolType { LAVA, WATER, POISON }

signal player_entered(player: Node2D)

@export var pool_type: PoolType = PoolType.WATER

const HAZARD_COLLISION_LAYER: int = 16
const HAZARD_COLLISION_MASK: int = 2

func _ready() -> void:
	collision_layer = HAZARD_COLLISION_LAYER
	collision_mask = HAZARD_COLLISION_MASK
	# Only the server detects hazard collisions and emits player_entered.
	if multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
		body_entered.connect(_on_body_entered)
		monitoring = true
		monitorable = true
	else:
		monitoring = false

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
		
	# Use duck-typing so server dummy bodies survive correctly
	if _can_survive(body):
		return
		
	player_entered.emit(body)

func _can_survive(body: Node2D) -> bool:
	# Client / Offline Full Player check
	if body.has_method("can_survive_pool"):
		return body.call("can_survive_pool", int(pool_type))

	# Server Dummy Body check
	var el: int = -1
	if body.has_meta("element"):
		el = int(body.get_meta("element"))
	elif body.has_method("get_element"):
		el = int(body.call("get_element"))
	elif "element" in body:
		el = int(body.get("element"))

	return el == int(pool_type)
