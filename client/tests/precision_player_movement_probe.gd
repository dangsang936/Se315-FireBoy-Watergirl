extends SceneTree

const PLAYER_SCENE: PackedScene = preload("res://scenes/players/fireboy.tscn")

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	await _verify_ground_acceleration_and_braking()
	await _verify_ground_reversal_and_air_control()
	await _verify_variable_jump_and_jump_cut()
	await _verify_coyote_jump()
	await _verify_jump_buffer()
	await _verify_edge_correction()

	if _failures.is_empty():
		print("Precision player movement probe passed.")
		quit(0)
		return

	for failure in _failures:
		printerr(failure)
	quit(1)

func _verify_ground_acceleration_and_braking() -> void:
	var floor := _make_floor(Vector2(400.0, 20.0), Vector2(0.0, 10.0))
	root.add_child(floor)
	var player := PLAYER_SCENE.instantiate() as PrototypePlayer
	root.add_child(player)
	await process_frame
	for frame in 4:
		await physics_frame

	_press_key(KEY_D)
	for frame in 10:
		await physics_frame
	_release_key(KEY_D)
	var run_speed: float = player.velocity.x
	for frame in 14:
		await physics_frame
	var stop_speed: float = absf(player.velocity.x)

	_require(run_speed > 50.0, "Ground acceleration should build speed quickly. run_speed=%s" % run_speed)
	_require(stop_speed < 5.0, "Ground braking should settle speed quickly after release. stop_speed=%s" % stop_speed)

	player.queue_free()
	floor.queue_free()
	await process_frame

func _verify_ground_reversal_and_air_control() -> void:
	var floor := _make_floor(Vector2(400.0, 20.0), Vector2(0.0, 10.0))
	root.add_child(floor)
	var player := PLAYER_SCENE.instantiate() as PrototypePlayer
	root.add_child(player)
	await process_frame
	for frame in 4:
		await physics_frame

	_press_key(KEY_D)
	for frame in 10:
		await physics_frame
	_release_key(KEY_D)
	_press_key(KEY_A)
	for frame in 12:
		await physics_frame
	_release_key(KEY_A)
	_require(player.velocity.x < -25.0, "Ground reversal should flip into leftward movement quickly. velocity=%s" % player.velocity.x)

	_press_key(KEY_D)
	for frame in 4:
		await physics_frame
	_press_key(KEY_W)
	for frame in 2:
		await physics_frame
	_release_key(KEY_W)
	for frame in 3:
		await physics_frame
	var air_right_speed: float = player.velocity.x
	_release_key(KEY_D)
	_press_key(KEY_A)
	for frame in 10:
		await physics_frame
	_release_key(KEY_A)
	var air_left_speed: float = player.velocity.x
	_require(air_left_speed < air_right_speed - 10.0, "Air steering should still redirect horizontal velocity. right=%s left=%s" % [air_right_speed, air_left_speed])

	player.queue_free()
	floor.queue_free()
	await process_frame

func _verify_variable_jump_and_jump_cut() -> void:
	var short_profile := await _measure_jump_profile(2)
	var medium_profile := await _measure_jump_profile(6)
	var full_profile := await _measure_jump_profile(12)
	_require(medium_profile.height > short_profile.height + 5.0, "Medium hold should rise higher than a tap jump. short=%s medium=%s" % [short_profile.height, medium_profile.height])
	_require(full_profile.height > medium_profile.height + 5.0, "Full hold should rise higher than a medium hold. medium=%s full=%s" % [medium_profile.height, full_profile.height])
	_require(short_profile.airborne_frames < medium_profile.airborne_frames, "Medium hold should stay airborne longer than a tap jump. short=%s medium=%s" % [short_profile.airborne_frames, medium_profile.airborne_frames])
	_require(medium_profile.airborne_frames <= full_profile.airborne_frames, "Full hold should not end sooner than a medium hold. medium=%s full=%s" % [medium_profile.airborne_frames, full_profile.airborne_frames])
	_require(full_profile.fastest_fall >= 180.0, "Precision jump should produce a sharper descent than the old floaty baseline. fastest_fall=%s" % full_profile.fastest_fall)

func _verify_coyote_jump() -> void:
	var floor := _make_floor(Vector2(80.0, 20.0), Vector2(0.0, 10.0))
	root.add_child(floor)
	var player := PLAYER_SCENE.instantiate() as PrototypePlayer
	player.global_position = Vector2(18.0, 0.0)
	root.add_child(player)
	await process_frame
	for frame in 4:
		await physics_frame

	_press_key(KEY_D)
	var left_floor := false
	for frame in 24:
		await physics_frame
		if not player.is_on_floor():
			left_floor = true
			break
	_release_key(KEY_D)
	_require(left_floor, "Coyote test should leave the floor before jump.")
	var edge_y := player.global_position.y
	_tap_key(KEY_W)
	for frame in 8:
		await physics_frame
	_require(player.global_position.y < edge_y - 4.0, "Coyote jump should still lift the player after leaving the ledge. edge_y=%s current=%s" % [edge_y, player.global_position.y])

	player.queue_free()
	floor.queue_free()
	await process_frame

func _verify_jump_buffer() -> void:
	var floor := _make_floor(Vector2(400.0, 20.0), Vector2(0.0, 10.0))
	root.add_child(floor)
	var player := PLAYER_SCENE.instantiate() as PrototypePlayer
	player.global_position = Vector2(0.0, -72.0)
	root.add_child(player)
	await process_frame
	for frame in 2:
		await physics_frame

	var pressed_buffer := false
	var jumped_from_buffer := false
	for frame in 60:
		if not pressed_buffer and player.global_position.y > -18.0:
			_tap_key(KEY_W)
			pressed_buffer = true
		await physics_frame
		if pressed_buffer and player.velocity.y < -40.0:
			jumped_from_buffer = true
			break
	_require(pressed_buffer, "Jump buffer test should press jump shortly before landing.")
	_require(jumped_from_buffer, "Buffered jump should trigger on landing. velocity=%s" % player.velocity.y)

	player.queue_free()
	floor.queue_free()
	await process_frame

func _verify_edge_correction() -> void:
	var floor := _make_floor(Vector2(400.0, 20.0), Vector2(0.0, 10.0))
	root.add_child(floor)
	var corner := _make_block(Vector2(32.0, -18.0), Vector2(16.0, 16.0), "ResolvableCorner")
	root.add_child(corner)
	var player := PLAYER_SCENE.instantiate() as PrototypePlayer
	player.global_position = Vector2(6.0, 0.0)
	root.add_child(player)
	await process_frame
	for frame in 4:
		await physics_frame

	var motor := player.get_node("PlayerMotor") as PlayerMotor
	var saw_correction := false
	_press_key(KEY_D)
	_press_key(KEY_W)
	for frame in 28:
		await physics_frame
		if frame == 3:
			_release_key(KEY_W)
		saw_correction = saw_correction or motor.was_edge_correction_applied_this_frame()
	_release_key(KEY_D)
	_release_key(KEY_W)
	_require(saw_correction, "Resolvable upward corner should trigger bounded edge correction.")
	_require(player.global_position.x > 18.0, "Edge correction path should allow the player to continue moving past the corner approach. x=%s" % player.global_position.x)

	player.queue_free()
	corner.queue_free()
	floor.queue_free()
	await process_frame

func _measure_jump_profile(release_frame: int) -> Dictionary:
	var floor := _make_floor(Vector2(400.0, 20.0), Vector2(0.0, 10.0))
	root.add_child(floor)
	var player := PLAYER_SCENE.instantiate() as PrototypePlayer
	root.add_child(player)
	await process_frame
	for frame in 3:
		await physics_frame

	var start_y := player.global_position.y
	var peak_y := start_y
	var fastest_fall := 0.0
	var airborne_frames := 0
	_press_key(KEY_W)
	for frame in 90:
		await physics_frame
		if frame == release_frame:
			_release_key(KEY_W)
		peak_y = minf(peak_y, player.global_position.y)
		fastest_fall = maxf(fastest_fall, player.velocity.y)
		if not player.is_on_floor() or frame < 2:
			airborne_frames += 1
		if frame > release_frame + 8 and player.is_on_floor() and player.velocity.y == 0.0:
			break
	_release_key(KEY_W)

	var jump_height := start_y - peak_y
	player.queue_free()
	floor.queue_free()
	await process_frame
	return {
		"height": jump_height,
		"fastest_fall": fastest_fall,
		"airborne_frames": airborne_frames,
	}

func _make_floor(size: Vector2, position: Vector2) -> StaticBody2D:
	var floor := StaticBody2D.new()
	floor.name = "PrecisionProbeFloor"
	floor.position = position
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	shape.shape = rectangle
	floor.add_child(shape)
	return floor

func _make_block(position: Vector2, size: Vector2, node_name: String) -> StaticBody2D:
	var block := StaticBody2D.new()
	block.name = node_name
	block.position = position
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	shape.shape = rectangle
	block.add_child(shape)
	return block

func _tap_key(key: Key) -> void:
	_press_key(key)
	call_deferred("_release_key", key)

func _require(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _press_key(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	Input.parse_input_event(event)

func _release_key(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = false
	Input.parse_input_event(event)
