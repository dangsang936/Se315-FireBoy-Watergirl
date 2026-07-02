class_name ExitDoor
extends Area2D

signal player_entered(player: Node2D)
signal both_players_entered()

var _players_inside: Array[Node2D] = []

const EXIT_COLLISION_LAYER: int = 64
const EXIT_COLLISION_MASK: int = 2

func _ready() -> void:
	collision_layer = EXIT_COLLISION_LAYER
	collision_mask = EXIT_COLLISION_MASK
	# Only the server detects door collisions and emits signals.
	# Clients have monitoring disabled so they never self-trigger level complete.
	if multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
		body_entered.connect(_on_body_entered)
		body_exited.connect(_on_body_exited)
		monitoring = true
		monitorable = true
	else:
		monitoring = false

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if not _players_inside.has(body):
		_players_inside.append(body)
		player_entered.emit(body)

		if _players_inside.size() >= 2:
			both_players_entered.emit()

func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_players_inside.erase(body)
