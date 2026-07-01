class_name PlayerMovementSimulator
extends RefCounted

static func step(state: PlayerMovementState, packet: Dictionary, config: PlayerMovementConfig, delta: float) -> PlayerMovementState:
	var next_state := state.duplicate_state()
	var input_dir: float = clampf(float(packet.get("x", 0.0)), -1.0, 1.0)
	var jump_pressed: bool = bool(packet.get("j", false))
	var down_pressed: bool = bool(packet.get("d", false))

	if absf(input_dir) > 0.0:
		next_state.velocity.x = move_toward(next_state.velocity.x, input_dir * config.max_speed, config.acceleration * delta)
	else:
		next_state.velocity.x = move_toward(next_state.velocity.x, 0.0, config.deceleration * delta)

	if not next_state.on_floor:
		next_state.velocity.y += config.gravity * delta
	elif jump_pressed:
		next_state.velocity.y = config.jump_velocity
		next_state.on_floor = false

	if down_pressed and not next_state.on_floor:
		next_state.velocity.y += config.gravity * delta * 0.5

	next_state.position += next_state.velocity * delta
	if next_state.position.y >= 0.0:
		next_state.position.y = 0.0
		if next_state.velocity.y >= 0.0:
			next_state.velocity.y = 0.0
		next_state.on_floor = true
	else:
		next_state.on_floor = false

	return next_state
