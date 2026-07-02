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
	# Clients never fire this signal locally to avoid desyncs.
	if multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
		body_entered.connect(_on_body_entered)
		monitoring = true
		monitorable = true
	else:
		monitoring = false


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if body.has_method("can_survive_pool") and body.call("can_survive_pool", int(pool_type)):
		return
	player_entered.emit(body)
