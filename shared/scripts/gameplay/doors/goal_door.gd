class_name GoalDoor
extends Area2D

signal occupancy_changed(required_element: int, is_occupied: bool, player: Node2D)
signal wrong_player_entered(required_element: int, player_element: int, player: Node2D)

const EXIT_COLLISION_LAYER: int = 64
const EXIT_COLLISION_MASK: int = 2
const ELEMENT_FIRE: int = 0
const ELEMENT_WATER: int = 1

@export_enum("Fire", "Water") var required_element: int = ELEMENT_FIRE

var _occupying_player: Node2D

func _ready() -> void:
	collision_layer = EXIT_COLLISION_LAYER
	collision_mask = EXIT_COLLISION_MASK
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)

func is_occupied_by_required_player() -> bool:
	return is_instance_valid(_occupying_player)

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	var player_element := _get_player_element(body)
	if player_element < 0:
		return
	if player_element != required_element:
		wrong_player_entered.emit(required_element, player_element, body)
		return
	if _occupying_player == body:
		return
	_occupying_player = body
	occupancy_changed.emit(required_element, true, body)

func _on_body_exited(body: Node2D) -> void:
	if _occupying_player == null:
		return
	if body != _occupying_player:
		return
	var player := _occupying_player
	_occupying_player = null
	occupancy_changed.emit(required_element, false, player)

func _get_player_element(player: Node2D) -> int:
	if player == null:
		return -1
	if player.has_meta("element"):
		return int(player.get_meta("element"))
	if player.has_method("get_element"):
		return int(player.call("get_element"))
	if "element" in player:
		return int(player.get("element"))
	return -1
