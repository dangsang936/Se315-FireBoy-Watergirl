extends SceneTree

const GAME_SCENE: PackedScene = preload("res://scenes/bootstrap/game.tscn")
const TARGET_BLOCK_DELTA: float = 42.0
const MAX_ROUTE_FRAMES: int = 360
const MAX_PUSH_FRAMES: int = 240

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game := GAME_SCENE.instantiate() as GameManager
	root.add_child(game)
	await process_frame
	await process_frame
	for frame in 10:
		await physics_frame

	var level := game.get("_current_level") as PrototypeLevel
	var player := game.get("_player") as PrototypePlayer
	_require(level != null, "Gameplay probe needs loaded prototype level.")
	_require(player != null, "Gameplay probe needs spawned player.")
	if level == null or player == null:
		_finish(game)
		return

	var block := level.get_node_or_null("Objects/PushBlock") as RigidBody2D
	_require(block != null, "Gameplay probe needs Objects/PushBlock in the level.")
	if block == null:
		_finish(game)
		return
	_disable_level_hazards(level)
	_prepare_push_fixture(player, block)
	for frame in 8:
		await physics_frame

	await _run_to_block(player, block)
	await _push_block_to_target(player, block)
	_finish(game)

func _prepare_push_fixture(player: PrototypePlayer, block: RigidBody2D) -> void:
	player.global_position = Vector2(-120.0, -12.0)
	player.velocity = Vector2.ZERO
	block.global_position = Vector2(-78.0, -20.0)
	block.linear_velocity = Vector2.ZERO
	block.angular_velocity = 0.0
	block.sleeping = false

func _disable_level_hazards(level: PrototypeLevel) -> void:
	var hazards := level.get_node_or_null("Hazards")
	if hazards == null:
		return
	for child: Node in hazards.get_children():
		var hazard_area := child as Area2D
		if hazard_area == null:
			continue
		hazard_area.monitoring = false

func _run_to_block(player: PrototypePlayer, block: RigidBody2D) -> void:
	var start_distance: float = absf(block.global_position.x - player.global_position.x)
	var reached_block := false
	_press_key(KEY_D)
	for frame in MAX_ROUTE_FRAMES:
		if _should_jump_toward_block(player, block, frame):
			_tap_jump()
		await physics_frame
		var distance: float = absf(block.global_position.x - player.global_position.x)
		if distance < 24.0 and absf(block.global_position.y - player.global_position.y) < 44.0:
			reached_block = true
			break
		if distance > start_distance + 80.0:
			break
	_release_key(KEY_D)

	if reached_block:
		return

	_require(false, "Gameplay probe player should reach the block by movement input. player=%s block=%s" % [player.global_position, block.global_position])

func _push_block_to_target(player: PrototypePlayer, block: RigidBody2D) -> void:
	var block_start_x: float = block.global_position.x
	var player_start_x: float = player.global_position.x
	var target_x: float = block_start_x + TARGET_BLOCK_DELTA
	var reached_target := false
	var saw_push_state := false
	var saw_right_push_direction := false

	_press_key(KEY_D)
	for frame in MAX_PUSH_FRAMES:
		await physics_frame
		saw_push_state = saw_push_state or player.get_player_state() == PrototypePlayer.PlayerState.PUSHING
		saw_right_push_direction = saw_right_push_direction or player.get_push_direction() > 0.0
		if block.global_position.x >= target_x:
			reached_target = true
			break
	_release_key(KEY_D)

	_require(player.global_position.x > player_start_x + 4.0, "Gameplay probe player should move into the block before pushing.")
	_require(block.global_position.x > block_start_x + 8.0, "Gameplay probe block should move right after player pushes.")
	_require(saw_push_state, "Gameplay probe player should expose PUSHING state while side-pushing the block.")
	_require(saw_right_push_direction, "Gameplay probe player should report rightward push direction while pushing.")
	_require(reached_target, "Gameplay probe block should be pushed at least %s px toward the destination. actual_delta=%s" % [TARGET_BLOCK_DELTA, block.global_position.x - block_start_x])

func _should_jump_toward_block(player: PrototypePlayer, block: RigidBody2D, _frame: int) -> bool:
	if not player.is_on_floor():
		return false
	if player.global_position.y < -30.0:
		return false
	if player.global_position.x < -82.0:
		return false
	if player.global_position.x > block.global_position.x - 8.0:
		return false
	return true

func _tap_jump() -> void:
	_press_key(KEY_W)
	call_deferred("_release_key", KEY_W)

func _finish(game: GameManager) -> void:
	_release_key(KEY_A)
	_release_key(KEY_D)
	_release_key(KEY_W)
	game.queue_free()
	if _failures.is_empty():
		print("Push block gameplay probe passed.")
		quit(0)
		return
	for failure in _failures:
		printerr(failure)
	quit(1)

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
