class_name PrototypePlayer
extends CharacterBody2D

enum PlayerState { IDLE, RUNNING }
enum Element { FIRE, WATER }

@export var speed: float = 105.0
@export var jump_velocity: float = -220.0
@export var acceleration: float = 1700.0
@export var deceleration: float = 1100.0
@export var air_acceleration: float = 1200.0
@export var air_deceleration: float = 480.0
@export var run_jump_height_multiplier: float = 1.05
@export var gravity_scale: float = 0.46
@export var coyote_time: float = 0.08
@export var jump_buffer_time: float = 0.10
@export var max_fall_speed: float = 330.0
@export var fast_fall_gravity_multiplier: float = 1.25
@export var animation_move_threshold: float = 5.0
@export var animated_sprite_path: NodePath = ^"AnimatedSprite2D"
@export var camera_path: NodePath = ^"Camera2D"
@export var collision_shape_path: NodePath = ^"CollisionShape2D"
@export var push_probe_distance: float = 1.0
@export var push_probe_vertical_padding: float = 2.0
@export var element: Element = Element.FIRE

var player_state: PlayerState = PlayerState.IDLE
var _gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var _control_enabled: bool = true
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _jump_key_was_pressed: bool = false

@onready var _animated_sprite: AnimatedSprite2D = get_node_or_null(animated_sprite_path) as AnimatedSprite2D
@onready var _camera: Camera2D = get_node_or_null(camera_path) as Camera2D
@onready var _collision_shape: CollisionShape2D = get_node_or_null(collision_shape_path) as CollisionShape2D

func _ready() -> void:
	_ensure_wasd_input()
	add_to_group("player")
	_set_player_state(PlayerState.IDLE)
	call_deferred("_refresh_camera")

func _physics_process(delta: float) -> void:
	_update_jump_buffer(delta)
	_update_vertical_velocity(delta)
	_update_horizontal_velocity(delta)
	move_and_slide()
	_register_push_block_contacts()
	_update_player_state()

func reset_to_spawn(spawn_position: Vector2) -> void:
	global_position = spawn_position
	velocity = Vector2.ZERO
	_coyote_timer = 0.0
	_jump_buffer_timer = 0.0
	_jump_key_was_pressed = false
	set_control_enabled(true)
	_set_player_state(PlayerState.IDLE)
	call_deferred("_refresh_camera")

func set_control_enabled(is_enabled: bool) -> void:
	_control_enabled = is_enabled
	set_physics_process(is_enabled)
	if not is_enabled:
		velocity = Vector2.ZERO
		_coyote_timer = 0.0
		_jump_buffer_timer = 0.0
		_jump_key_was_pressed = false
		_set_player_state(PlayerState.IDLE)

func get_player_state() -> PlayerState:
	return player_state

func get_element() -> Element:
	return element

func get_push_direction() -> float:
	return _get_input_direction()

func can_survive_pool(pool_type: int) -> bool:
	return int(element) == pool_type

func _update_jump_buffer(delta: float) -> void:
	if _is_jump_just_pressed():
		_jump_buffer_timer = jump_buffer_time
	else:
		_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)

func _update_vertical_velocity(delta: float) -> void:
	if is_on_floor():
		_coyote_timer = coyote_time
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)
		var gravity_multiplier: float = fast_fall_gravity_multiplier if _is_move_down_pressed() and velocity.y > 0.0 else 1.0
		velocity.y = minf(velocity.y + _gravity * gravity_scale * gravity_multiplier * delta, max_fall_speed)

	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = _get_run_jump_velocity()
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0

func _update_horizontal_velocity(delta: float) -> void:
	var direction: float = _get_input_direction()
	var current_acceleration: float = acceleration if is_on_floor() else air_acceleration
	var current_deceleration: float = deceleration if is_on_floor() else air_deceleration

	if direction != 0.0:
		velocity.x = move_toward(velocity.x, direction * speed, current_acceleration * delta)
		if _animated_sprite != null:
			_animated_sprite.flip_h = direction < 0.0
	else:
		velocity.x = move_toward(velocity.x, 0.0, current_deceleration * delta)

func _update_player_state() -> void:
	var has_move_intent: bool = _get_input_direction() != 0.0
	var is_moving: bool = absf(velocity.x) > animation_move_threshold
	var next_state: PlayerState = PlayerState.RUNNING if has_move_intent or is_moving else PlayerState.IDLE
	_set_player_state(next_state)

func _register_push_block_contacts() -> void:
	var push_direction: float = get_push_direction()
	if push_direction == 0.0:
		return

	_register_push_block_probe(push_direction)

	for index: int in get_slide_collision_count():
		var collision := get_slide_collision(index)
		var collider := collision.get_collider()
		var collider_node := collider as Node2D
		if collider_node == null or not collider_node.has_method("register_push_attempt"):
			continue
		if absf(collision.get_normal().x) < 0.35:
			continue
		if signf(push_direction) != -signf(collision.get_normal().x):
			continue
		collider_node.call("register_push_attempt", self, push_direction)

func _register_push_block_probe(push_direction: float) -> void:
	if _collision_shape == null or _collision_shape.shape == null:
		return

	var rectangle := _collision_shape.shape as RectangleShape2D
	if rectangle == null:
		return

	var half_size: Vector2 = rectangle.size * 0.5
	var center: Vector2 = _collision_shape.global_position
	var probe_height: float = maxf(rectangle.size.y - push_probe_vertical_padding * 2.0, 2.0)
	var probe_shape := RectangleShape2D.new()
	probe_shape.size = Vector2(push_probe_distance, probe_height)
	var probe_center := Vector2(center.x + signf(push_direction) * (half_size.x + push_probe_distance * 0.5), center.y)
	var shape_query := PhysicsShapeQueryParameters2D.new()
	shape_query.shape = probe_shape
	shape_query.transform = Transform2D(0.0, probe_center)
	shape_query.exclude = [get_rid()]
	shape_query.collision_mask = collision_mask
	var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	for hit: Dictionary in space_state.intersect_shape(shape_query, 8):
		var shape_collider := hit.get("collider") as Node2D
		if shape_collider == null or not shape_collider.has_method("register_push_attempt"):
			continue
		shape_collider.call("register_push_attempt", self, push_direction)
		return

	var side_x: float = center.x + signf(push_direction) * half_size.x
	var probe_start_x: float = side_x + signf(push_direction) * 0.05
	var probe_end_x: float = side_x + signf(push_direction) * push_probe_distance
	var vertical_span: float = maxf(half_size.y - push_probe_vertical_padding, 0.0)
	var sample_offsets: Array[float] = [-vertical_span, 0.0, vertical_span]

	for y_offset: float in sample_offsets:
		var from: Vector2 = Vector2(probe_start_x, center.y + y_offset)
		var to: Vector2 = Vector2(probe_end_x, center.y + y_offset)
		var query := PhysicsRayQueryParameters2D.create(from, to)
		query.exclude = [get_rid()]
		query.collision_mask = collision_mask
		var hit: Dictionary = space_state.intersect_ray(query)
		if hit.is_empty():
			continue

		var collider_node := hit.get("collider") as Node2D
		if collider_node == null or not collider_node.has_method("register_push_attempt"):
			continue

		collider_node.call("register_push_attempt", self, push_direction)
		return

func _set_player_state(next_state: PlayerState) -> void:
	player_state = next_state
	match player_state:
		PlayerState.RUNNING:
			_play_animation(&"running")
		PlayerState.IDLE:
			_play_animation(&"idle")

func _get_run_jump_velocity() -> float:
	var run_factor: float = clampf(absf(velocity.x) / speed, 0.0, 1.0)
	return jump_velocity * lerpf(1.0, run_jump_height_multiplier, run_factor)

func _get_input_direction() -> float:
	var direction: float = Input.get_axis("move_left", "move_right")
	if Input.is_physical_key_pressed(KEY_A):
		direction -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		direction += 1.0
	return clampf(direction, -1.0, 1.0)

func _is_jump_just_pressed() -> bool:
	var jump_key_pressed: bool = Input.is_physical_key_pressed(KEY_W)
	var jump_just_pressed: bool = Input.is_action_just_pressed("jump") or (jump_key_pressed and not _jump_key_was_pressed)
	_jump_key_was_pressed = jump_key_pressed
	return jump_just_pressed

func _is_move_down_pressed() -> bool:
	return Input.is_action_pressed("move_down") or Input.is_physical_key_pressed(KEY_S)

func _ensure_wasd_input() -> void:
	_ensure_key_action(&"move_left", KEY_A)
	_ensure_key_action(&"move_right", KEY_D)
	_ensure_key_action(&"jump", KEY_W)
	_ensure_key_action(&"move_down", KEY_S)

func _ensure_key_action(action: StringName, physical_key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)

	for event: InputEvent in InputMap.action_get_events(action):
		var key_event: InputEventKey = event as InputEventKey
		if key_event != null and key_event.physical_keycode == physical_key:
			return

	var key_event := InputEventKey.new()
	key_event.keycode = physical_key
	key_event.physical_keycode = physical_key
	InputMap.action_add_event(action, key_event)

func _refresh_camera() -> void:
	if _camera == null:
		return
	_camera.make_current()
	if _camera.position_smoothing_enabled:
		_camera.reset_smoothing()

func _play_animation(animation_name: StringName) -> void:
	if _animated_sprite == null or _animated_sprite.sprite_frames == null:
		return
	if not _animated_sprite.sprite_frames.has_animation(animation_name):
		return
	if _animated_sprite.animation != animation_name or not _animated_sprite.is_playing():
		_animated_sprite.play(animation_name)
