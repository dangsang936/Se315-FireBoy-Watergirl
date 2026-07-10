class_name GoalDoor
extends Area2D

signal occupancy_changed(required_element: int, is_occupied: bool, player: Node2D)
signal wrong_player_entered(required_element: int, player_element: int, player: Node2D)

const EXIT_COLLISION_LAYER: int = 64
const EXIT_COLLISION_MASK: int = 2

@export_enum("Fire", "Water") var required_element: int = PrototypePlayer.Element.FIRE

var _occupying_player: PrototypePlayer

func _ready() -> void:
	collision_layer = EXIT_COLLISION_LAYER
	collision_mask = EXIT_COLLISION_MASK
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)
	call_deferred("refresh_occupancy")

func is_occupied_by_required_player() -> bool:
	return is_instance_valid(_occupying_player)

func refresh_occupancy() -> void:
	if is_instance_valid(_occupying_player) and get_overlapping_bodies().has(_occupying_player):
		return
	var previous_player := _occupying_player
	_occupying_player = null
	for body in get_overlapping_bodies():
		_on_body_entered(body)
		if is_instance_valid(_occupying_player):
			return
	if is_instance_valid(previous_player):
		occupancy_changed.emit(required_element, false, previous_player)

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	var player := body as PrototypePlayer
	if player == null:
		return
	if int(player.element) != required_element:
		wrong_player_entered.emit(required_element, int(player.element), player)
		return
	if _occupying_player == player:
		return
	_occupying_player = player
	occupancy_changed.emit(required_element, true, player)

func _on_body_exited(body: Node2D) -> void:
	if _occupying_player == null:
		return
	if body != _occupying_player:
		return
	var player := _occupying_player
	_occupying_player = null
	occupancy_changed.emit(required_element, false, player)
