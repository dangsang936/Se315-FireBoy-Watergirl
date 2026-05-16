extends SceneTree

const GAME_SCENE: PackedScene = preload("res://scenes/bootstrap/game.tscn")

var _failures: Array[String] = []
var _diag_lines: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game := GAME_SCENE.instantiate() as GameManager
	root.add_child(game)
	await process_frame
	await process_frame
	for frame in 20:
		await physics_frame

	var level := game.get("_current_level") as PrototypeLevel
	var player := game.get("_player") as PrototypePlayer
	var block := level.get_node_or_null("Objects/PushBlock") as RigidBody2D if level != null else null
	_require(level != null, "Level missing")
	_require(player != null, "Player missing")
	_require(block != null, "PushBlock missing")
	if level == null or player == null or block == null:
		_finish(game)
		return

	_diag("initial player=%s block=%s block_sleeping=%s" % [player.global_position, block.global_position, block.sleeping])
	await _debug_push_from_side(player, block, -1.0, KEY_D, "left-side push right")
	await _debug_push_from_side(player, block, 1.0, KEY_A, "right-side push left")
	await _debug_direct_push(player, block)
	_finish(game)

func _debug_push_from_side(player: PrototypePlayer, block: RigidBody2D, side: float, key: Key, label: String) -> void:
	_release_key(KEY_A)
	_release_key(KEY_D)
	player.global_position = block.global_position + Vector2(side * 20.0, 8.0)
	player.velocity = Vector2.ZERO
	player.reset_physics_interpolation()
	block.linear_velocity = Vector2.ZERO
	block.angular_velocity = 0.0
	block.sleeping = false
	for frame in 8:
		await physics_frame

	var start_x: float = block.global_position.x
	var ray_hit := _get_player_probe_hit(player, signf(-side))
	_diag("%s start player=%s block=%s ray_hit=%s" % [label, player.global_position, block.global_position, ray_hit])
	_press_key(key)
	for frame in 90:
		await physics_frame
	_release_key(key)

	var delta_x: float = block.global_position.x - start_x
	_diag("%s end block=%s delta_x=%s velocity=%s sleeping=%s" % [label, block.global_position, delta_x, block.linear_velocity, block.sleeping])
	if key == KEY_D:
		_require(delta_x > 8.0, "%s should push block right. delta=%s" % [label, delta_x])
	else:
		_require(delta_x < -8.0, "%s should push block left. delta=%s" % [label, delta_x])

func _debug_direct_push(player: PrototypePlayer, block: RigidBody2D) -> void:
	_release_key(KEY_A)
	_release_key(KEY_D)
	block.global_position = Vector2(110.0, -70.0)
	block.linear_velocity = Vector2.ZERO
	block.angular_velocity = 0.0
	block.sleeping = false
	player.global_position = block.global_position + Vector2(-20.0, 8.0)
	player.velocity = Vector2.ZERO
	for frame in 8:
		await physics_frame

	var start_x: float = block.global_position.x
	for frame in 90:
		block.call("register_push_attempt", player, 1.0)
		await physics_frame

	var delta_x: float = block.global_position.x - start_x
	_diag("direct register end block=%s delta_x=%s velocity=%s push_time=%s" % [block.global_position, delta_x, block.linear_velocity, block.get("_push_time")])
	_require(delta_x > 8.0, "Direct register should move level block right. delta=%s" % delta_x)

func _get_player_probe_hit(player: PrototypePlayer, direction: float) -> String:
	var shape_node := player.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null:
		return "no CollisionShape2D"
	var rectangle := shape_node.shape as RectangleShape2D
	if rectangle == null:
		return "not RectangleShape2D"

	var half_size: Vector2 = rectangle.size * 0.5
	var center: Vector2 = shape_node.global_position
	var side_x: float = center.x + direction * half_size.x
	var from: Vector2 = Vector2(side_x + direction * 0.5, center.y)
	var to: Vector2 = Vector2(side_x + direction * 10.0, center.y)
	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.exclude = [player.get_rid()]
	query.collision_mask = player.collision_mask
	var hit: Dictionary = player.get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return "none from=%s to=%s" % [from, to]
	return "%s at %s" % [hit.get("collider"), hit.get("position")]

func _finish(game: GameManager) -> void:
	_release_key(KEY_A)
	_release_key(KEY_D)
	game.queue_free()
	_write_diag_file()
	if _failures.is_empty():
		_diag("Push block debug probe passed.")
		_write_diag_file()
		quit(0)
		return
	for failure in _failures:
		_diag(failure)
	_write_diag_file()
	quit(1)

func _require(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _diag(message: String) -> void:
	_diag_lines.append("[push-debug] %s" % message)
	printerr("[push-debug] %s" % message)

func _write_diag_file() -> void:
	var file := FileAccess.open("res://.godot/push_block_debug_output.txt", FileAccess.WRITE)
	if file == null:
		return
	for line: String in _diag_lines:
		file.store_line(line)

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
