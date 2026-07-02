class_name PressureButton
extends StaticBody2D

signal pressed_state_changed(is_pressed: bool)

enum ElementRequirement { FIRE, WATER, ANY }

const WORLD_COLLISION_LAYER: int = 1
const WORLD_COLLISION_MASK: int = 6
const PRESSURE_BUTTON_COLLISION_LAYER: int = 128
const PRESSURE_BUTTON_COLLISION_MASK: int = 2

@export var bridge_path: NodePath = ^""
@export var required_element: ElementRequirement = ElementRequirement.FIRE
@export var require_player_on_floor: bool = true
@export var trigger_size: Vector2 = Vector2(30.0, 18.0):
	set(value):
		trigger_size = Vector2(maxf(value.x, 14.0), maxf(value.y, 10.0))
@export var trigger_area_path: NodePath = ^"TriggerArea"
@export var visual_path: NodePath = ^"AnimatedSprite2D"
@export var released_frame: int = 0:
	set(value):
		released_frame = maxi(value, 0)
		_sync_visual_state()
@export var pressed_frame: int = 1:
	set(value):
		pressed_frame = maxi(value, 0)
		_sync_visual_state()
@export var collision_shape_path: NodePath = ^"TriggerArea/CollisionShape2D"

var _tracked_players: Array[PrototypePlayer] = []
var _is_pressed: bool = false

@onready var _trigger_area: Area2D = get_node_or_null(trigger_area_path) as Area2D
@onready var _collision_shape: CollisionShape2D = get_node_or_null(collision_shape_path) as CollisionShape2D
@onready var _visual: AnimatedSprite2D = get_node_or_null(visual_path) as AnimatedSprite2D

func _ready() -> void:
	collision_layer = WORLD_COLLISION_LAYER
	collision_mask = WORLD_COLLISION_MASK
	_ensure_trigger_area()
	_trigger_area.collision_layer = PRESSURE_BUTTON_COLLISION_LAYER
	_trigger_area.collision_mask = PRESSURE_BUTTON_COLLISION_MASK
	_ensure_collision_shape()
	_resolve_visual()
	_sync_visual_state()
	_trigger_area.body_entered.connect(_on_body_entered)
	_trigger_area.body_exited.connect(_on_body_exited)
	set_physics_process(true)

func is_pressed() -> bool:
	return _is_pressed

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return

	var should_press: bool = false
	for player_index: int in range(_tracked_players.size() - 1, -1, -1):
		var player: PrototypePlayer = _tracked_players[player_index]
		if not is_instance_valid(player):
			_tracked_players.remove_at(player_index)
			continue
		if _can_press_with_player(player):
			should_press = true

	_set_pressed_state(should_press)

func _ensure_trigger_area() -> void:
	if _trigger_area != null:
		return
	_trigger_area = Area2D.new()
	_trigger_area.name = "TriggerArea"
	_trigger_area.monitorable = false
	add_child(_trigger_area)

func _ensure_collision_shape() -> void:
	if _trigger_area == null:
		return
	if _collision_shape != null:
		return
	_collision_shape = CollisionShape2D.new()
	_collision_shape.name = "CollisionShape2D"
	_trigger_area.add_child(_collision_shape)

	var rectangle_shape := _collision_shape.shape as RectangleShape2D
	if rectangle_shape == null:
		rectangle_shape = RectangleShape2D.new()
		_collision_shape.shape = rectangle_shape

	rectangle_shape.size = trigger_size
	_collision_shape.position = Vector2(0.0, -trigger_size.y * 0.5)

func _resolve_visual() -> void:
	_visual = get_node_or_null(visual_path) as AnimatedSprite2D

func _sync_visual_state() -> void:
	if _visual == null:
		_resolve_visual()
	if _visual == null:
		return

	var next_frame: int = pressed_frame if _is_pressed else released_frame
	if _visual.sprite_frames != null and _visual.sprite_frames.has_animation(_visual.animation):
		var frame_count: int = _visual.sprite_frames.get_frame_count(_visual.animation)
		if frame_count > 0:
			next_frame = clampi(next_frame, 0, frame_count - 1)
	_visual.stop()
	_visual.frame = next_frame
	_visual.frame_progress = 0.0

func _on_body_entered(body: Node2D) -> void:
	var player := body as PrototypePlayer
	if player == null:
		return
	if not _tracked_players.has(player):
		_tracked_players.append(player)

func _on_body_exited(body: Node2D) -> void:
	var player := body as PrototypePlayer
	if player == null:
		return
	_tracked_players.erase(player)

func _can_press_with_player(player: PrototypePlayer) -> bool:
	if player.get("is_local") == false:
		return false
	if not _matches_required_element(player):
		return false
	if require_player_on_floor and not player.is_on_floor():
		return false
	return true

func _matches_required_element(player: PrototypePlayer) -> bool:
	if required_element == ElementRequirement.ANY:
		return true
	return int(player.get_element()) == int(required_element)

func apply_remote_pressed_state(next_pressed: bool) -> void:
	_set_pressed_state(next_pressed, false)

func _set_pressed_state(next_pressed: bool, should_emit_signal: bool = true) -> void:
	if _is_pressed == next_pressed:
		_sync_visual_state()
		return

	_is_pressed = next_pressed
	_sync_visual_state()
	_sync_bridge_target()
	if should_emit_signal:
		pressed_state_changed.emit(_is_pressed)

func _sync_bridge_target() -> void:
	if bridge_path.is_empty():
		return

	var bridge_target := get_node_or_null(bridge_path)
	if bridge_target == null:
		return

	if bridge_target.has_method("set_active"):
		bridge_target.call("set_active", _is_pressed)
	elif _is_pressed and bridge_target.has_method("activate"):
		bridge_target.call("activate")
	elif not _is_pressed and bridge_target.has_method("deactivate"):
		bridge_target.call("deactivate")
