class_name PlayerMovementSimulator
extends RefCounted

static func step(state: PlayerMovementState, packet: Dictionary, config: PlayerMovementConfig, delta: float) -> PlayerMovementState:
	var next_state := state.duplicate_state()
	_apply_velocity_step(next_state, packet, config, delta)

	next_state.position += next_state.velocity * delta
	if next_state.position.y >= 0.0:
		next_state.position.y = 0.0
		if next_state.velocity.y >= 0.0:
			next_state.velocity.y = 0.0
		next_state.on_floor = true
	else:
		next_state.on_floor = false

	return next_state

static func step_body(body: CharacterBody2D, state: PlayerMovementState, packet: Dictionary, config: PlayerMovementConfig, delta: float) -> PlayerMovementState:
	var next_state := state.duplicate_state()
	next_state.position = body.global_position
	next_state.velocity = body.velocity
	next_state.on_floor = body.is_on_floor()

	_apply_velocity_step(next_state, packet, config, delta)
	body.velocity = next_state.velocity
	body.move_and_slide()

	next_state.position = body.global_position
	next_state.velocity = body.velocity
	next_state.on_floor = body.is_on_floor()
	_update_anim(next_state, float(packet.get("x", 0.0)), config)
	return next_state

static func _apply_velocity_step(state: PlayerMovementState, packet: Dictionary, config: PlayerMovementConfig, delta: float) -> void:
	var input_dir: float = clampf(float(packet.get("x", 0.0)), -1.0, 1.0)
	var jump_pressed: bool = bool(packet.get("j", false))
	var down_pressed: bool = bool(packet.get("d", false))

	if jump_pressed:
		state.jump_buffer_timer = config.jump_buffer_time
	else:
		state.jump_buffer_timer = maxf(state.jump_buffer_timer - delta, 0.0)

	if state.on_floor:
		state.coyote_timer = config.coyote_time
	else:
		state.coyote_timer = maxf(state.coyote_timer - delta, 0.0)
		var gravity_multiplier: float = config.fast_fall_gravity_multiplier if down_pressed and state.velocity.y > 0.0 else 1.0
		state.velocity.y = minf(state.velocity.y + config.gravity * gravity_multiplier * delta, config.max_fall_speed)

	if state.jump_buffer_timer > 0.0 and state.coyote_timer > 0.0:
		var run_factor: float = clampf(absf(state.velocity.x) / config.max_speed, 0.0, 1.0)
		state.velocity.y = config.jump_velocity * lerpf(1.0, config.run_jump_height_multiplier, run_factor)
		state.jump_buffer_timer = 0.0
		state.coyote_timer = 0.0
		state.on_floor = false

	var current_acceleration: float = config.acceleration if state.on_floor else config.air_acceleration
	var current_deceleration: float = config.deceleration if state.on_floor else config.air_deceleration
	if input_dir != 0.0:
		state.velocity.x = move_toward(state.velocity.x, input_dir * config.max_speed, current_acceleration * delta)
	else:
		state.velocity.x = move_toward(state.velocity.x, 0.0, current_deceleration * delta)

	_update_anim(state, input_dir, config)

static func _update_anim(state: PlayerMovementState, input_dir: float, config: PlayerMovementConfig) -> void:
	state.anim = "running" if input_dir != 0.0 or absf(state.velocity.x) > config.animation_move_threshold else "idle"
	if state.velocity.x != 0.0:
		state.flip_h = state.velocity.x < 0.0
