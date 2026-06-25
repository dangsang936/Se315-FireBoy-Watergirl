class_name PlayerMotor
extends Node

const EDGE_CORRECTION_SCRIPT: Script = preload("res://scripts/player/motor/edge_correction.gd")

var owner_player: PrototypePlayer
var input_reader: PlayerInputReader

var _gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _jump_hold_timer: float = 0.0
var _jump_started_this_frame: bool = false
var _jump_cut_active: bool = false
var _was_on_floor: bool = false
var _edge_correction: EdgeCorrection
var _edge_correction_applied_this_frame: bool = false

func setup(player: PrototypePlayer, reader: PlayerInputReader) -> void:
	owner_player = player
	input_reader = reader
	_was_on_floor = player.is_on_floor()
	_ensure_edge_correction()

func apply_movement(delta: float) -> void:
	if owner_player == null or input_reader == null:
		return
	_ensure_edge_correction()
	_jump_started_this_frame = false
	_edge_correction_applied_this_frame = false
	_update_jump_buffer(delta)
	_update_coyote_timer(delta)
	_consume_requested_jump()
	_update_jump_cut_state(delta)
	_update_vertical_velocity(delta)
	_update_horizontal_velocity(delta)
	_edge_correction_applied_this_frame = _try_apply_edge_correction(delta)

func clear_motion() -> void:
	_coyote_timer = 0.0
	_jump_buffer_timer = 0.0
	_jump_hold_timer = 0.0
	_jump_started_this_frame = false
	_jump_cut_active = false
	_was_on_floor = false
	_edge_correction_applied_this_frame = false
	if _edge_correction != null:
		_edge_correction.clear_state()
	if owner_player != null:
		owner_player.velocity = Vector2.ZERO

func clear_transient_buffers() -> void:
	_coyote_timer = 0.0
	_jump_buffer_timer = 0.0
	_jump_hold_timer = 0.0
	_jump_started_this_frame = false
	_jump_cut_active = false
	_edge_correction_applied_this_frame = false
	if _edge_correction != null:
		_edge_correction.clear_state()

func get_run_jump_velocity() -> float:
	if owner_player == null:
		return 0.0
	var run_factor: float = clampf(absf(owner_player.velocity.x) / owner_player.speed, 0.0, 1.0)
	return owner_player.jump_velocity * lerpf(1.0, owner_player.run_jump_height_multiplier, run_factor)

func jump_started_this_frame() -> bool:
	return _jump_started_this_frame

func get_coyote_timer() -> float:
	return _coyote_timer

func get_jump_buffer_timer() -> float:
	return _jump_buffer_timer

func get_jump_hold_timer() -> float:
	return _jump_hold_timer

func was_edge_correction_applied_this_frame() -> bool:
	return _edge_correction_applied_this_frame

func _ensure_edge_correction() -> void:
	if _edge_correction != null:
		return
	_edge_correction = get_node_or_null(^"EdgeCorrection") as EdgeCorrection
	if _edge_correction == null:
		_edge_correction = EDGE_CORRECTION_SCRIPT.new() as EdgeCorrection
		_edge_correction.name = "EdgeCorrection"
		add_child(_edge_correction)
	if _edge_correction != null and owner_player != null:
		_edge_correction.setup(owner_player)

func _update_jump_buffer(delta: float) -> void:
	if _should_start_jump_buffer():
		_jump_buffer_timer = owner_player.jump_buffer_time
	else:
		_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)

func _should_start_jump_buffer() -> bool:
	return not owner_player.is_on_floor() and owner_player.velocity.y > 0.0 and input_reader.jump_just_pressed and _jump_buffer_timer <= 0.0

func _update_coyote_timer(delta: float) -> void:
	var is_grounded: bool = owner_player.is_on_floor()
	if is_grounded:
		_coyote_timer = owner_player.coyote_time
	elif _was_on_floor and owner_player.velocity.y >= 0.0:
		_coyote_timer = owner_player.coyote_time
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)
	_was_on_floor = is_grounded

func _consume_requested_jump() -> void:
	var request_jump: bool = input_reader.jump_just_pressed or _jump_buffer_timer > 0.0
	var can_jump: bool = owner_player.is_on_floor() or _coyote_timer > 0.0
	if not request_jump or not can_jump:
		return
	owner_player.velocity.y = get_run_jump_velocity()
	_jump_buffer_timer = 0.0
	_coyote_timer = 0.0
	_jump_hold_timer = owner_player.jump_hold_time
	_jump_cut_active = false
	_jump_started_this_frame = true

func _update_jump_cut_state(delta: float) -> void:
	if _jump_started_this_frame:
		return
	if owner_player.velocity.y >= 0.0:
		_jump_hold_timer = 0.0
		_jump_cut_active = false
		return
	if _jump_hold_timer > 0.0:
		_jump_hold_timer = maxf(_jump_hold_timer - delta, 0.0)
	if input_reader.jump_just_released and _jump_hold_timer > 0.0:
		owner_player.velocity.y *= owner_player.jump_cutoff_multiplier
		_jump_hold_timer = 0.0
		_jump_cut_active = true
		return
	if not input_reader.jump_pressed:
		_jump_cut_active = true

func _update_vertical_velocity(delta: float) -> void:
	if _jump_started_this_frame:
		return
	if owner_player.is_on_floor():
		if owner_player.velocity.y > 0.0:
			owner_player.velocity.y = 0.0
		return

	var gravity_multiplier: float = _get_gravity_multiplier()
	if input_reader.move_down_pressed and owner_player.velocity.y > 0.0:
		gravity_multiplier *= owner_player.fast_fall_gravity_multiplier
	owner_player.velocity.y = minf(owner_player.velocity.y + _gravity * owner_player.gravity_scale * gravity_multiplier * delta, owner_player.max_fall_speed)

func _get_gravity_multiplier() -> float:
	if owner_player.velocity.y < 0.0:
		if _jump_cut_active:
			return owner_player.jump_cut_gravity_multiplier
		if absf(owner_player.velocity.y) <= owner_player.apex_velocity_threshold:
			return owner_player.apex_gravity_multiplier
		return owner_player.rise_gravity_multiplier
	if owner_player.velocity.y > 0.0:
		return owner_player.fall_gravity_multiplier
	return owner_player.apex_gravity_multiplier

func _update_horizontal_velocity(delta: float) -> void:
	var direction: float = input_reader.horizontal_direction
	var is_grounded: bool = owner_player.is_on_floor()
	var current_acceleration: float = owner_player.acceleration if is_grounded else owner_player.air_acceleration
	var current_deceleration: float = owner_player.deceleration if is_grounded else owner_player.air_deceleration * owner_player.air_brake_multiplier

	if direction != 0.0:
		var target_speed: float = direction * owner_player.speed
		var applied_acceleration: float = current_acceleration
		if is_grounded and signf(owner_player.velocity.x) != 0.0 and signf(owner_player.velocity.x) != signf(direction):
			applied_acceleration = owner_player.turn_acceleration
		owner_player.velocity.x = move_toward(owner_player.velocity.x, target_speed, applied_acceleration * delta)
		return

	owner_player.velocity.x = move_toward(owner_player.velocity.x, 0.0, current_deceleration * delta)

func _try_apply_edge_correction(delta: float) -> bool:
	if _edge_correction == null or input_reader == null:
		return false
	return _edge_correction.try_apply(delta, input_reader.horizontal_direction)
