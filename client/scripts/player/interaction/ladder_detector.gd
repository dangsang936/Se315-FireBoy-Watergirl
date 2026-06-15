class_name LadderDetector
extends Area2D

const LADDER_DETECTOR_LAYER: int = 0
const LADDER_DETECTOR_MASK: int = 8

@export var detector_size: Vector2 = Vector2(12.0, 24.0):
	set(value):
		detector_size = Vector2(maxf(value.x, 4.0), maxf(value.y, 4.0))
		_sync_collision_shape()
@export var detector_offset: Vector2 = Vector2(6.0, -9.0):
	set(value):
		detector_offset = value
		_sync_collision_shape()
@export_multiline var collision_layers_documentation: String = "Default layer/mask: detector monitors ladder Area2D objects and does not block movement."

var owner_player: PrototypePlayer

var _active_ladders: Array[Area2D] = []
var _collision_shape: CollisionShape2D

func _ready() -> void:
	collision_layer = LADDER_DETECTOR_LAYER
	collision_mask = LADDER_DETECTOR_MASK
	_collision_shape = get_node_or_null(^"CollisionShape2D") as CollisionShape2D
	_ensure_collision_shape()
	_sync_collision_shape()
	monitoring = true
	monitorable = false
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)

func setup(player: PrototypePlayer) -> void:
	owner_player = player

func is_on_ladder() -> bool:
	_prune_invalid_ladders()
	return not _active_ladders.is_empty()

func get_current_ladder() -> Area2D:
	_prune_invalid_ladders()
	if _active_ladders.is_empty():
		return null
	return _active_ladders.back()

func get_current_climb_speed(default_speed: float) -> float:
	var ladder := get_current_ladder()
	if ladder == null or not ladder.has_method("get_climb_speed"):
		return default_speed
	return float(ladder.call("get_climb_speed"))

func clear_ladders() -> void:
	_active_ladders.clear()

func _ensure_collision_shape() -> void:
	if _collision_shape != null:
		return
	_collision_shape = CollisionShape2D.new()
	_collision_shape.name = "CollisionShape2D"
	add_child(_collision_shape)

func _sync_collision_shape() -> void:
	if _collision_shape == null:
		return
	var rectangle_shape := _collision_shape.shape as RectangleShape2D
	if rectangle_shape == null:
		rectangle_shape = RectangleShape2D.new()
		_collision_shape.shape = rectangle_shape
	rectangle_shape.size = detector_size
	_collision_shape.position = detector_offset

func _on_area_entered(area: Area2D) -> void:
	if not area.is_in_group("ladder") and not area.has_method("get_climb_speed"):
		return
	if not _active_ladders.has(area):
		_active_ladders.append(area)

func _on_area_exited(area: Area2D) -> void:
	if not area.is_in_group("ladder") and not area.has_method("get_climb_speed"):
		return
	_active_ladders.erase(area)

func _prune_invalid_ladders() -> void:
	for index: int in range(_active_ladders.size() - 1, -1, -1):
		if not is_instance_valid(_active_ladders[index]):
			_active_ladders.remove_at(index)
