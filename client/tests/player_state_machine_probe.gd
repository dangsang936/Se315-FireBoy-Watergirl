extends SceneTree

const PLAYER_SCENE: PackedScene = preload("res://scenes/players/fireboy.tscn")
const PUSH_BLOCK_SCENE: PackedScene = preload("res://scenes/gameplay/objects/push_block.tscn")

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	await _verify_registered_state_names()
	await _verify_idle_run_airborne_disabled_reset()
	await _verify_push_state_from_side_contact()

	if _failures.is_empty():
		print("Player state machine probe passed.")
		quit(0)
		return

	for failure in _failures:
		printerr(failure)
	quit(1)

func _verify_registered_state_names() -> void:
	var player := PLAYER_SCENE.instantiate() as PrototypePlayer
	root.add_child(player)
	await process_frame
	for frame in 2:
		await physics_frame

	var names: Array[StringName] = player.get_registered_player_state_names()
	for state_name: StringName in [&"idle", &"run", &"airborne", &"push", &"climb", &"disabled"]:
		_require(names.has(state_name), "Player should register state: %s names=%s" % [state_name, names])

	player.queue_free()
	await process_frame

func _verify_idle_run_airborne_disabled_reset() -> void:
	var floor := _make_floor()
	root.add_child(floor)
	var player := PLAYER_SCENE.instantiate() as PrototypePlayer
	root.add_child(player)
	await process_frame
	for frame in 3:
		await physics_frame

	_require(player.get_player_state() == PrototypePlayer.PlayerState.IDLE, "Initial enum state should be IDLE.")
	_require(player.get_player_state_name() == &"idle", "Initial readable state should be idle.")

	_press_key(KEY_D)
	for frame in 12:
		await physics_frame
	_release_key(KEY_D)
	_require(player.get_player_state() == PrototypePlayer.PlayerState.RUNNING, "Move input should enter RUNNING enum state.")
	_require(player.get_player_state_name() == &"run", "Move input should enter readable run state.")
	_require(player.get_previous_player_state_name() == &"idle", "Run transition should expose previous idle state.")

	_press_key(KEY_W)
	for frame in 8:
		await physics_frame
	_release_key(KEY_W)
	_require(player.get_player_state() == PrototypePlayer.PlayerState.AIRBORNE, "Jump should enter AIRBORNE enum state.")
	_require(player.get_player_state_name() == &"airborne", "Jump should enter readable airborne state.")

	for frame in 180:
		await physics_frame
		if player.get_player_state_name() == &"idle":
			break
	_require(player.get_player_state_name() == &"idle", "Landing after jump should return to idle.")

	player.velocity = Vector2(45.0, -30.0)
	player.set_control_enabled(false)
	await physics_frame
	_require(player.get_player_state() == PrototypePlayer.PlayerState.DISABLED, "Control disable should enter DISABLED enum state.")
	_require(player.get_player_state_name() == &"disabled", "Control disable should enter readable disabled state.")
	_require(player.velocity == Vector2.ZERO, "Disabled state should clear velocity.")

	player.reset_to_spawn(Vector2.ZERO)
	await physics_frame
	_require(player.get_player_state() == PrototypePlayer.PlayerState.IDLE, "Reset should return to IDLE enum state.")
	_require(player.get_player_state_name() == &"idle", "Reset should return to readable idle state.")

	player.queue_free()
	floor.queue_free()
	await process_frame

func _verify_push_state_from_side_contact() -> void:
	var floor := _make_floor()
	root.add_child(floor)

	var block := PUSH_BLOCK_SCENE.instantiate() as RigidBody2D
	block.global_position = Vector2(22.0, -8.0)
	root.add_child(block)

	var player := PLAYER_SCENE.instantiate() as PrototypePlayer
	player.global_position = Vector2(0.0, 0.0)
	root.add_child(player)
	await process_frame
	for frame in 8:
		await physics_frame

	var saw_push_state := false
	var start_x: float = block.global_position.x
	_press_key(KEY_D)
	for frame in 70:
		await physics_frame
		saw_push_state = saw_push_state or player.get_player_state() == PrototypePlayer.PlayerState.PUSHING
		if block.global_position.x > start_x + 2.0 and saw_push_state:
			break
	_release_key(KEY_D)

	_require(saw_push_state, "Side contact should expose PUSHING enum state.")
	_require(player.get_registered_player_state_names().has(&"push"), "Push state should remain registered for QA.")
	_require(block.global_position.x > start_x + 1.0, "Push state probe should still move the push block.")

	player.queue_free()
	block.queue_free()
	floor.queue_free()
	await process_frame

func _require(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _make_floor() -> StaticBody2D:
	var floor := StaticBody2D.new()
	floor.name = "ProbeFloor"
	floor.position = Vector2(0.0, 10.0)
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(400.0, 20.0)
	shape.shape = rectangle
	floor.add_child(shape)
	return floor

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
