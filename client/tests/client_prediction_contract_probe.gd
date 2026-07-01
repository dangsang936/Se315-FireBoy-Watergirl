extends SceneTree

func _init() -> void:
	var config := PlayerMovementConfig.create_default()
	var state := PlayerMovementState.new()
	state.on_floor = true

	var right_input := InputPacket.create(1, 1.0, false)
	var moved := PlayerMovementSimulator.step(state, right_input, config, 1.0 / 60.0)
	assert(moved.position.x > state.position.x)

	var jump_input := InputPacket.create(2, 0.0, true)
	var jumped := PlayerMovementSimulator.step(moved, jump_input, config, 1.0 / 60.0)
	assert(jumped.velocity.y < 0.0)
	assert(not jumped.on_floor)

	var controller := ClientPredictionController.new()
	controller.reset(Vector2.ZERO, Vector2.ZERO, true)
	controller.predict(InputPacket.create(1, 1.0, false), 1.0 / 60.0)
	controller.predict(InputPacket.create(2, 1.0, false), 1.0 / 60.0)

	var correction := {
		"ack_tick": 1,
		"pos": Vector2.ZERO,
		"vel": Vector2.ZERO,
		"on_floor": true,
	}
	controller.reconcile(correction, 1.0 / 60.0)
	assert(controller.last_ack_tick == 1)
	assert(controller.pending_inputs.size() == 1)

	print("Client prediction contract probe passed.")
	quit(0)
