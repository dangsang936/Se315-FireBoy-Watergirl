class_name PushBlock
extends RigidBody2D

@export var max_push_force: float = 700.0
@export var push_ramp_time: float = 0.6
@export var two_player_boost_multiplier: float = 1.55
@export var max_linear_speed: float = 65.0
@export var max_angular_speed: float = 3.0
@export var idle_damping: float = 14.0
@export var moving_damping: float = 2.5
@export var push_detector_path: NodePath = ^"PushDetector"
@export var ground_detector_path: NodePath = ^"GroundDetector"

const PUSH_BLOCK_COLLISION_LAYER: int = 4
const PUSH_BLOCK_COLLISION_MASK: int = 3
const PUSH_DETECTOR_COLLISION_MASK: int = 2

const MIN_SIDE_PUSH_OFFSET: float = 0.5
const MAX_VERTICAL_PUSH_OFFSET: float = 22.0
const MAX_HORIZONTAL_PUSH_OFFSET: float = 30.0
const GROUND_DETECTOR_OFFSET: float = 7.0
const IDLE_LINEAR_THRESHOLD: float = 4.0
const IDLE_ANGULAR_THRESHOLD: float = 0.25
const AIR_DAMPING: float = 0.1
const LANDING_ROLL_SPEED: float = 4.0
const LANDING_ROLL_ANGULAR_BOOST: float = 0.45
const GROUND_ROLL_ACCEL: float = 1.2
const GROUND_ROLL_RATIO: float = 0.015
const PUSH_ROLL_TORQUE_RATIO: float = 0.025
const PUSH_ATTEMPT_TTL: float = 0.1
const SYNC_RATE: float = 0.05

var _push_attempts: Dictionary = {}
var _push_time: float = 0.0
var _is_grounded: bool = false
var _was_grounded: bool = false
var _sync_timer: float = 0.0

@onready var _push_detector: Area2D = get_node_or_null(push_detector_path) as Area2D
@onready var _ground_detector: RayCast2D = get_node_or_null(ground_detector_path) as RayCast2D

func _ready() -> void:
	add_to_group("push_block")
	collision_layer = PUSH_BLOCK_COLLISION_LAYER
	collision_mask = PUSH_BLOCK_COLLISION_MASK
	freeze = false
	freeze_mode = RigidBody2D.FREEZE_MODE_STATIC

	lock_rotation = false
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 8
	linear_damp = idle_damping
	angular_damp = idle_damping

	if _push_detector != null:
		_push_detector.collision_mask = PUSH_DETECTOR_COLLISION_MASK
		_push_detector.body_entered.connect(_on_push_detector_body_entered)

	if _ground_detector != null:
		_ground_detector.top_level = true
		_ground_detector.enabled = true

func register_push_attempt(body: Node2D, push_direction: float) -> void:
	if not body.is_in_group("player"):
		return
	if body.get("is_local") == false:
		return
	var direction: float = clampf(push_direction, -1.0, 1.0)
	if direction == 0.0:
		return
	sleeping = false
	_push_attempts[body.get_instance_id()] = Vector2(direction, PUSH_ATTEMPT_TTL)

func _physics_process(delta: float) -> void:
	if _ground_detector == null:
		_is_grounded = get_contact_count() > 0
	else:
		_ground_detector.global_position = global_position + Vector2(0.0, GROUND_DETECTOR_OFFSET)
		_ground_detector.global_rotation = 0.0
		_ground_detector.force_raycast_update()
		_is_grounded = _ground_detector.is_colliding()

	_sync_timer += delta
	if _sync_timer >= SYNC_RATE and not sleeping:
		_sync_timer = 0.0
		var network_manager := get_node_or_null("/root/NetworkManager")
		if network_manager != null and bool(network_manager.call("is_connected_to_server")):
			var level := _find_level_root()
			var block_path := str(level.get_path_to(self)) if level != null else str(get_path())
			network_manager.call("send_push_block_state", block_path, global_position, rotation, linear_velocity, angular_velocity)

func _find_level_root() -> Node:
	var node: Node = self
	while node != null:
		if node is PrototypeLevel:
			return node
		node = node.get_parent()
	return null

func apply_remote_state(pos: Vector2, rot: float, remote_linear_velocity: Vector2, remote_angular_velocity: float) -> void:
	global_position = pos
	rotation = rot
	linear_velocity = remote_linear_velocity
	angular_velocity = remote_angular_velocity

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	var right_pushers: int = _count_pushers_for_direction(1.0)
	var left_pushers: int = _count_pushers_for_direction(-1.0)
	var push_direction: float = 0.0
	var pusher_count: int = 0
	var velocity: Vector2 = state.linear_velocity

	if right_pushers > left_pushers:
		push_direction = 1.0
		pusher_count = right_pushers
	elif left_pushers > right_pushers:
		push_direction = -1.0
		pusher_count = left_pushers

	if push_direction != 0.0:
		_push_time = minf(_push_time + state.step, push_ramp_time)
		var ramp: float = _push_time / push_ramp_time
		var force_multiplier: float = 1.0 + maxf(float(pusher_count - 1), 0.0) * (two_player_boost_multiplier - 1.0)
		var push_acceleration: float = max_push_force * ramp * force_multiplier
		velocity.x = move_toward(velocity.x, push_direction * max_linear_speed, push_acceleration * state.step)
		state.apply_central_force(Vector2(push_direction * max_push_force * force_multiplier, 0.0))
		state.apply_torque(push_direction * max_push_force * ramp * force_multiplier * PUSH_ROLL_TORQUE_RATIO)
	else:
		_push_time = 0.0

	velocity.x = clampf(velocity.x, -max_linear_speed, max_linear_speed)

	if _is_grounded and push_direction == 0.0 and absf(velocity.x) < IDLE_LINEAR_THRESHOLD:
		velocity.x = 0.0

	state.linear_velocity = velocity

	if _is_grounded and not _was_grounded and absf(velocity.x) >= LANDING_ROLL_SPEED:
		state.angular_velocity += signf(velocity.x) * LANDING_ROLL_ANGULAR_BOOST
	if _is_grounded and push_direction == 0.0 and absf(velocity.x) >= LANDING_ROLL_SPEED:
		var roll_target: float = signf(velocity.x) * minf(max_angular_speed, absf(velocity.x) * GROUND_ROLL_RATIO)
		state.angular_velocity = move_toward(state.angular_velocity, roll_target, GROUND_ROLL_ACCEL * state.step)

	state.angular_velocity = clampf(state.angular_velocity, -max_angular_speed, max_angular_speed)
	if _is_grounded and push_direction == 0.0 and absf(state.angular_velocity) < IDLE_ANGULAR_THRESHOLD:
		state.angular_velocity = 0.0

	var idle_on_ground: bool = _is_grounded and push_direction == 0.0 and velocity.length() < IDLE_LINEAR_THRESHOLD
	if not _is_grounded:
		linear_damp = AIR_DAMPING
		angular_damp = AIR_DAMPING
	else:
		linear_damp = idle_damping if idle_on_ground else moving_damping
		angular_damp = idle_damping if idle_on_ground else moving_damping
	_was_grounded = _is_grounded
	_decay_push_attempts(state.step)

func _count_pushers_for_direction(direction: float) -> int:
	var count: int = 0
	for attempt_data: Variant in _push_attempts.values():
		var attempt := attempt_data as Vector2
		if signf(attempt.x) == direction:
			count += 1
	return count

func _decay_push_attempts(delta: float) -> void:
	for id: Variant in _push_attempts.keys():
		var attempt := _push_attempts[id] as Vector2
		attempt.y -= delta
		if attempt.y <= 0.0:
			_push_attempts.erase(id)
		else:
			_push_attempts[id] = attempt

func _on_push_detector_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	sleeping = false
