class_name PrototypePlayer
extends CharacterBody2D

const LADDER_DETECTOR_SCRIPT: Script = preload("res://scripts/player/interaction/ladder_detector.gd")
const CLIMB_STATE_SCRIPT: Script = preload("res://scripts/player/states/climb_state.gd")
const PLAYER_COLLISION_LAYER: int = 2
const PLAYER_COLLISION_MASK: int = 5

enum PlayerState { IDLE, RUNNING, AIRBORNE, PUSHING, CLIMBING, DISABLED }
enum Element { FIRE, WATER }

@export var speed: float = 110.0
@export var jump_velocity: float = -236.0
@export var acceleration: float = 1500.0
@export var deceleration: float = 1250.0
@export var air_acceleration: float = 1000.0
@export var air_deceleration: float = 420.0
@export var turn_acceleration: float = 1850.0
@export var air_brake_multiplier: float = 1.0
@export var run_jump_height_multiplier: float = 1.0
@export var gravity_scale: float = 0.46
@export var coyote_time: float = 0.10
@export var jump_buffer_time: float = 0.05
@export var jump_hold_time: float = 0.18
@export var jump_cutoff_multiplier: float = 0.4
@export var max_fall_speed: float = 330.0
@export var rise_gravity_multiplier: float = 0.82
@export var apex_gravity_multiplier: float = 0.82
@export var apex_velocity_threshold: float = 18.0
@export var fall_gravity_multiplier: float = 1.35
@export var jump_cut_gravity_multiplier: float = 1.9
@export var fast_fall_gravity_multiplier: float = 1.15
@export var edge_correction_enabled: bool = true
@export var edge_correction_distance: float = 3.0
@export var edge_correction_step: float = 1.0
@export var edge_correction_min_rise_speed: float = 30.0
@export_multiline var edge_correction_collision_documentation: String = "Edge correction reuses the player World and PushBlock collision mask, only while rising into resolvable corners."
@export var animation_move_threshold: float = 5.0
@export var animated_sprite_path: NodePath = ^"AnimatedSprite2D"
@export var camera_path: NodePath = ^"Camera2D"
@export var collision_shape_path: NodePath = ^"CollisionShape2D"
@export var input_reader_path: NodePath = ^"PlayerInputReader"
@export var motor_path: NodePath = ^"PlayerMotor"
@export var animation_controller_path: NodePath = ^"PlayerAnimationController"
@export var push_interactor_path: NodePath = ^"PushInteractor"
@export var ladder_detector_path: NodePath = ^"LadderDetector"
@export var state_machine_path: NodePath = ^"PlayerStateMachine"
@export var push_probe_distance: float = 1.0
@export var push_probe_vertical_padding: float = 2.0
@export var ladder_climb_speed: float = 75.0
@export var element: Element = Element.FIRE

var player_state: PlayerState = PlayerState.IDLE

var _control_enabled: bool = true
var _input_reader: PlayerInputReader
var _player_motor: PlayerMotor
var _animation_controller: PlayerAnimationController
var _push_interactor: PushInteractor
var _ladder_detector: Node
var _state_machine: PlayerStateMachine

@onready var _animated_sprite: AnimatedSprite2D = get_node_or_null(animated_sprite_path) as AnimatedSprite2D
@onready var _camera: Camera2D = get_node_or_null(camera_path) as Camera2D
@onready var _collision_shape: CollisionShape2D = get_node_or_null(collision_shape_path) as CollisionShape2D

func _ready() -> void:
	collision_layer = PLAYER_COLLISION_LAYER
	collision_mask = PLAYER_COLLISION_MASK
	_ensure_wasd_input()
	add_to_group("player")
	_resolve_components()
	_configure_components()
	_state_machine.start()
	call_deferred("_refresh_camera")

func _physics_process(delta: float) -> void:
	if _state_machine == null or _input_reader == null:
		return

	_input_reader.update_from_input(_control_enabled)
	_state_machine.transition_from_player_context()
	_state_machine.physics_update(delta)
	move_and_slide()
	_register_push_block_contacts()
	_state_machine.transition_from_player_context()

func reset_to_spawn(spawn_position: Vector2) -> void:
	global_position = spawn_position
	_control_enabled = true
	velocity = Vector2.ZERO
	_clear_transient_state()
	if _state_machine != null:
		_state_machine.reset_to_initial()
	else:
		_set_player_state(PlayerState.IDLE)
	call_deferred("_refresh_camera")

func set_control_enabled(is_enabled: bool) -> void:
	_control_enabled = is_enabled
	if not is_enabled:
		_clear_transient_state()
		if _state_machine != null:
			_state_machine.force_disabled()
		else:
			_set_player_state(PlayerState.DISABLED)
		return

	if _state_machine != null:
		_state_machine.transition_from_player_context()

func get_player_state() -> PlayerState:
	return player_state

func get_player_state_name() -> StringName:
	if _state_machine == null:
		return _state_name_for_enum(player_state)
	return _state_machine.get_current_state_name()

func get_previous_player_state_name() -> StringName:
	if _state_machine == null:
		return &""
	return _state_machine.get_previous_state_name()

func get_registered_player_state_names() -> Array[StringName]:
	if _state_machine == null:
		return []
	return _state_machine.get_registered_state_names()

func get_element() -> Element:
	return element

func get_push_direction() -> float:
	return _get_input_direction()

func can_survive_pool(pool_type: int) -> bool:
	return int(element) == pool_type

func is_control_enabled() -> bool:
	return _control_enabled

func has_move_intent() -> bool:
	return _get_input_direction() != 0.0

func is_horizontally_moving() -> bool:
	return absf(velocity.x) > animation_move_threshold

func has_push_contact() -> bool:
	return _push_interactor != null and _push_interactor.last_push_contact

func is_ladder_available() -> bool:
	return _ladder_detector != null and bool(_ladder_detector.call("is_on_ladder"))

func has_ladder_climb_input() -> bool:
	return _input_reader != null and _input_reader.has_climb_input()

func get_ladder_climb_direction() -> float:
	if _input_reader == null:
		return 0.0
	return _input_reader.climb_direction

func apply_player_movement(delta: float) -> void:
	if _player_motor != null:
		_player_motor.apply_movement(delta)
	if _animation_controller != null:
		_animation_controller.face_direction(_get_input_direction())

func apply_ladder_movement(delta: float) -> void:
	var direction: float = _get_input_direction()
	var current_acceleration: float = acceleration if is_on_floor() else air_acceleration
	var current_deceleration: float = deceleration if is_on_floor() else air_deceleration
	if direction != 0.0:
		velocity.x = move_toward(velocity.x, direction * speed, current_acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, current_deceleration * delta)
	velocity.y = get_ladder_climb_direction() * _get_active_ladder_climb_speed()
	if _animation_controller != null:
		_animation_controller.face_direction(direction)

func clear_ladder_vertical_motion() -> void:
	velocity.y = 0.0

func clear_player_motion() -> void:
	_clear_transient_state()

func clear_precision_timers() -> void:
	if _player_motor != null:
		_player_motor.clear_transient_buffers()

func play_idle_animation() -> void:
	if _animation_controller != null:
		_animation_controller.play_idle()

func play_running_animation() -> void:
	if _animation_controller != null:
		_animation_controller.play_running()

func play_motion_animation() -> void:
	if _animation_controller != null:
		_animation_controller.play_for_motion(has_move_intent(), velocity.x)

func set_player_state_from_state_name(state_name: StringName) -> void:
	_set_player_state(_enum_for_state_name(state_name))

func _resolve_components() -> void:
	_input_reader = get_node_or_null(input_reader_path) as PlayerInputReader
	_player_motor = get_node_or_null(motor_path) as PlayerMotor
	_animation_controller = get_node_or_null(animation_controller_path) as PlayerAnimationController
	_push_interactor = get_node_or_null(push_interactor_path) as PushInteractor
	_ladder_detector = get_node_or_null(ladder_detector_path)
	_state_machine = get_node_or_null(state_machine_path) as PlayerStateMachine

	if _input_reader == null:
		_input_reader = PlayerInputReader.new()
		_input_reader.name = "PlayerInputReader"
		add_child(_input_reader)
	if _player_motor == null:
		_player_motor = PlayerMotor.new()
		_player_motor.name = "PlayerMotor"
		add_child(_player_motor)
	if _animation_controller == null:
		_animation_controller = PlayerAnimationController.new()
		_animation_controller.name = "PlayerAnimationController"
		add_child(_animation_controller)
	if _push_interactor == null:
		_push_interactor = PushInteractor.new()
		_push_interactor.name = "PushInteractor"
		add_child(_push_interactor)
	if _ladder_detector == null:
		_ladder_detector = LADDER_DETECTOR_SCRIPT.new() as Node
		_ladder_detector.name = "LadderDetector"
		add_child(_ladder_detector)
	if _state_machine == null:
		_state_machine = _create_default_state_machine()

func _create_default_state_machine() -> PlayerStateMachine:
	var machine := PlayerStateMachine.new()
	machine.name = "PlayerStateMachine"
	add_child(machine)

	var state_nodes: Array[PlayerStateNode] = [
		IdleState.new(),
		RunState.new(),
		AirborneState.new(),
		PushState.new(),
		CLIMB_STATE_SCRIPT.new() as PlayerStateNode,
		DisabledState.new(),
	]
	for state_node: PlayerStateNode in state_nodes:
		machine.add_child(state_node)

	return machine

func _configure_components() -> void:
	_player_motor.setup(self, _input_reader)
	_animation_controller.setup(_animated_sprite, animation_move_threshold)
	_push_interactor.setup(self, _collision_shape)
	if _ladder_detector.has_method("setup"):
		_ladder_detector.call("setup", self)
	_state_machine.setup(self)

func _clear_transient_state() -> void:
	velocity = Vector2.ZERO
	if _input_reader != null:
		_input_reader.clear_transient_input()
	if _player_motor != null:
		_player_motor.clear_motion()
	if _push_interactor != null:
		_push_interactor.clear_contact()
	if _ladder_detector != null:
		_ladder_detector.call("clear_ladders")

func _update_player_state(refresh_input: bool = true) -> void:
	if refresh_input and _input_reader != null:
		_input_reader.update_from_input(_control_enabled)
	if _state_machine != null:
		_state_machine.transition_from_player_context()
		return
	var next_state: PlayerState = PlayerState.RUNNING if has_move_intent() or is_horizontally_moving() else PlayerState.IDLE
	_set_player_state(next_state)

func _register_push_block_contacts() -> void:
	if _push_interactor == null:
		return
	if not _control_enabled:
		_push_interactor.clear_contact()
		return
	_push_interactor.register_contacts(get_push_direction())

func _register_push_block_probe(push_direction: float) -> void:
	if _push_interactor != null:
		_push_interactor.call("_register_push_block_probe", push_direction)

func _set_player_state(next_state: PlayerState) -> void:
	player_state = next_state

func _enum_for_state_name(state_name: StringName) -> PlayerState:
	match state_name:
		&"run":
			return PlayerState.RUNNING
		&"airborne":
			return PlayerState.AIRBORNE
		&"push":
			return PlayerState.PUSHING
		&"climb":
			return PlayerState.CLIMBING
		&"disabled":
			return PlayerState.DISABLED
		_:
			return PlayerState.IDLE

func _state_name_for_enum(state: PlayerState) -> StringName:
	match state:
		PlayerState.RUNNING:
			return &"run"
		PlayerState.AIRBORNE:
			return &"airborne"
		PlayerState.PUSHING:
			return &"push"
		PlayerState.CLIMBING:
			return &"climb"
		PlayerState.DISABLED:
			return &"disabled"
		_:
			return &"idle"

func _get_run_jump_velocity() -> float:
	if _player_motor != null:
		return _player_motor.get_run_jump_velocity()
	var run_factor: float = clampf(absf(velocity.x) / speed, 0.0, 1.0)
	return jump_velocity * lerpf(1.0, run_jump_height_multiplier, run_factor)

func _get_input_direction() -> float:
	if _input_reader != null:
		return _input_reader.horizontal_direction
	var direction: float = Input.get_axis("move_left", "move_right")
	if Input.is_physical_key_pressed(KEY_A):
		direction -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		direction += 1.0
	return clampf(direction, -1.0, 1.0)

func _get_active_ladder_climb_speed() -> float:
	if _ladder_detector == null:
		return ladder_climb_speed
	return float(_ladder_detector.call("get_current_climb_speed", ladder_climb_speed))

func _ensure_wasd_input() -> void:
	_ensure_key_action(&"move_left", KEY_A)
	_ensure_key_action(&"move_right", KEY_D)
	_ensure_key_action(&"jump", KEY_W)
	_ensure_key_action(&"move_down", KEY_S)

func _ensure_key_action(action: StringName, physical_key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)

	for event: InputEvent in InputMap.action_get_events(action):
		var existing_key_event: InputEventKey = event as InputEventKey
		if existing_key_event != null and existing_key_event.physical_keycode == physical_key:
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
