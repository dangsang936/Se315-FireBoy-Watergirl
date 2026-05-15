class_name HazardZone
extends Area2D

enum PoolType { LAVA, WATER, POISON }

signal player_entered(player: Node2D)

@export var pool_type: PoolType = PoolType.WATER

func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if body.has_method("can_survive_pool") and body.call("can_survive_pool", int(pool_type)):
		return
	player_entered.emit(body)
