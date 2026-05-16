extends SceneTree

const GAME_SCENE: PackedScene = preload("res://scenes/bootstrap/game.tscn")
const REAL_GAME_SCENE: PackedScene = preload("res://scenes/bootstrap/game_real.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/players/fireboy.tscn")
const WATERGIRL_SCENE: PackedScene = preload("res://scenes/players/watergirl.tscn")
const PUSH_BLOCK_SCENE: PackedScene = preload("res://scenes/gameplay/objects/push_block.tscn")
const GEM_SCENE: PackedScene = preload("res://scenes/gameplay/collectibles/collectible_gem.tscn")
const HAZARD_SCRIPT: Script = preload("res://scripts/gameplay/hazards/hazard_zone.gd")

class PushProbePlayer:
	extends CharacterBody2D

	var push_direction: float = 0.0

	func get_push_direction() -> float:
		return push_direction

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	await _verify_game_start_allows_movement()
	await _verify_real_blank_game_starts()
	await _verify_level_connects_all_hazards()
	await _verify_player_can_jump_over_hazard()
	await _verify_jump_is_lower_and_floaty()
	await _verify_elemental_pool_rules()
	await _verify_gem_manager_gates_exit_for_fireboy()
	await _verify_wrong_element_gem_stays_available()
	await _verify_level_without_collectibles_keeps_exit_unlocked()
	await _verify_player_motion_and_animation()
	await _verify_player_animation_uses_move_intent_when_blocked()
	await _verify_real_player_pushes_block_from_side()
	await _verify_nearby_player_does_not_push_before_contact()
	await _verify_real_player_does_not_push_before_contact()
	await _verify_real_player_tiny_gap_does_not_register_push()
	await _verify_player_border_probe_pushes_block_before_slide_collision()
	await _verify_direction_push_ignores_player_origin_offset()
	await _verify_real_player_pushes_block_when_detector_misses()
	await _verify_real_player_pushes_level_block_from_side()
	await _verify_push_block_accelerates_and_stops()
	await _verify_two_pushers_boost_push_block()
	await _verify_push_block_rolls_after_drop()
	await _verify_restart_keeps_runtime_live()

	if _failures.is_empty():
		print("Prototype runtime probe passed.")
		quit(0)
		return

	for failure in _failures:
		printerr(failure)
	quit(1)

func _verify_player_motion_and_animation() -> void:
	var floor := _make_floor()
	root.add_child(floor)
	var player := PLAYER_SCENE.instantiate() as PrototypePlayer
	root.add_child(player)
	await process_frame
	for frame in 3:
		await physics_frame

	var sprite := player.get_node("AnimatedSprite2D") as AnimatedSprite2D
	_require(sprite.is_playing(), "Player idle animation should play after spawn.")

	var start_x := player.global_position.x
	_press_key(KEY_D)
	for frame in 20:
		await physics_frame
	_release_key(KEY_D)

	_require(player.global_position.x > start_x + 1.0, "Player should move right when move_right is pressed.")
	_require(player.get_player_state() == PrototypePlayer.PlayerState.RUNNING, "Player state should be running while moving.")
	_require(sprite.animation == &"running", "Player should switch to running animation while moving.")
	_require(sprite.is_playing(), "Running animation should keep playing while moving.")

	for frame in 20:
		await physics_frame
	_require(player.get_player_state() == PrototypePlayer.PlayerState.IDLE, "Player state should return to idle after releasing movement.")
	_require(sprite.animation == &"idle", "Player should switch back to idle after releasing movement.")

	var before_jump_y := player.global_position.y
	_press_key(KEY_W)
	for frame in 10:
		await physics_frame
	_release_key(KEY_W)

	_require(player.global_position.y < before_jump_y, "Player should jump when W is pressed.")

	player.queue_free()
	floor.queue_free()
	await process_frame

func _verify_player_animation_uses_move_intent_when_blocked() -> void:
	var floor := _make_floor()
	root.add_child(floor)
	var player := PLAYER_SCENE.instantiate() as PrototypePlayer
	root.add_child(player)
	await process_frame
	for frame in 3:
		await physics_frame

	var sprite := player.get_node("AnimatedSprite2D") as AnimatedSprite2D
	player.velocity = Vector2.ZERO
	Input.action_press(&"move_right")
	player.call("_update_player_state")
	Input.action_release(&"move_right")

	_require(player.get_player_state() == PrototypePlayer.PlayerState.RUNNING, "Player state should stay running while move input is held against a blocking body.")
	_require(sprite.animation == &"running", "Player running animation should not flicker to idle while pushing or blocked.")

	player.queue_free()
	floor.queue_free()
	await process_frame

func _verify_push_block_accelerates_and_stops() -> void:
	var floor := _make_floor()
	root.add_child(floor)

	var block := PUSH_BLOCK_SCENE.instantiate() as RigidBody2D
	block.global_position = Vector2(20.0, -8.0)
	root.add_child(block)

	var pusher := _make_push_probe_player(Vector2(5.0, -8.0), 1.0)
	root.add_child(pusher)

	await process_frame
	for frame in 5:
		await physics_frame

	var start_x := block.global_position.x
	var early_speed := 0.0
	for frame in 10:
		block.call("register_push_attempt", pusher, pusher.push_direction)
		await physics_frame
		if frame == 4:
			early_speed = block.linear_velocity.x

	for frame in 45:
		block.call("register_push_attempt", pusher, pusher.push_direction)
		await physics_frame

	var pushed_speed := block.linear_velocity.x
	var max_linear_speed: float = float(block.get("max_linear_speed"))
	_require(max_linear_speed <= 70.0, "Push block max speed should stay low enough to avoid slippery movement.")
	_require(block.global_position.x > start_x + 1.0, "Push block should move right when a player pushes from the left.")
	_require(pushed_speed > early_speed + 3.0, "Push block should accelerate over sustained pushing.")
	_require(pushed_speed <= max_linear_speed + 1.0, "Push block should clamp horizontal speed.")

	pusher.push_direction = 0.0
	for frame in 90:
		await physics_frame

	_require(absf(block.linear_velocity.x) < absf(pushed_speed), "Push block should slow after the player stops pushing.")
	_require(absf(block.linear_velocity.x) < 2.0, "Push block should nearly stop after release instead of sliding.")

	pusher.queue_free()
	block.queue_free()
	floor.queue_free()
	await process_frame

func _verify_real_player_pushes_block_from_side() -> void:
	var floor := _make_floor()
	root.add_child(floor)

	var block := PUSH_BLOCK_SCENE.instantiate() as RigidBody2D
	block.global_position = Vector2(28.0, -8.0)
	var detector := block.get_node("PushDetector") as Area2D
	detector.monitoring = false
	detector.monitorable = false
	root.add_child(block)

	var player := PLAYER_SCENE.instantiate() as PrototypePlayer
	player.global_position = Vector2(0.0, 0.0)
	root.add_child(player)

	await process_frame
	for frame in 10:
		await physics_frame

	block.sleeping = true
	var start_x := block.global_position.x
	_press_key(KEY_D)
	for frame in 45:
		await physics_frame
	_release_key(KEY_D)

	_require(block.global_position.x > start_x + 4.0, "A real PrototypePlayer should visibly push the block from the side within 45 physics frames.")

	player.queue_free()
	block.queue_free()
	floor.queue_free()
	await process_frame

func _verify_real_player_pushes_level_block_from_side() -> void:
	var level := preload("res://scenes/levels/prototype_level.tscn").instantiate() as PrototypeLevel
	root.add_child(level)
	await process_frame
	for frame in 20:
		await physics_frame

	var block := level.get_node("Objects/PushBlock") as RigidBody2D
	var player := PLAYER_SCENE.instantiate() as PrototypePlayer
	player.global_position = Vector2(block.global_position.x - 24.0, block.global_position.y + 8.0)
	root.add_child(player)

	await process_frame
	for frame in 20:
		await physics_frame

	var start_x := block.global_position.x
	_press_key(KEY_D)
	for frame in 45:
		await physics_frame
	_release_key(KEY_D)

	_require(block.global_position.x > start_x + 4.0, "A real PrototypePlayer should visibly push the prototype level block from the side within 45 physics frames.")

	player.queue_free()
	level.queue_free()
	await process_frame

func _verify_nearby_player_does_not_push_before_contact() -> void:
	var floor := _make_floor()
	root.add_child(floor)

	var block := PUSH_BLOCK_SCENE.instantiate() as RigidBody2D
	block.global_position = Vector2(28.0, -8.0)
	root.add_child(block)

	var pusher := _make_push_probe_player(Vector2(6.0, -8.0), 1.0)
	root.add_child(pusher)

	await process_frame
	for frame in 40:
		await physics_frame

	_require(absf(block.global_position.x - 28.0) < 1.0, "Push block should not drift before physical side contact.")

	pusher.queue_free()
	block.queue_free()
	floor.queue_free()
	await process_frame

func _verify_real_player_does_not_push_before_contact() -> void:
	var floor := _make_floor()
	root.add_child(floor)

	var block := PUSH_BLOCK_SCENE.instantiate() as RigidBody2D
	block.global_position = Vector2(28.0, -8.0)
	root.add_child(block)

	var player := PLAYER_SCENE.instantiate() as PrototypePlayer
	player.global_position = Vector2(6.0, 0.0)
	root.add_child(player)

	await process_frame
	for frame in 5:
		await physics_frame

	var start_x := block.global_position.x
	_press_key(KEY_D)
	for frame in 5:
		await physics_frame
	_release_key(KEY_D)

	_require(absf(block.global_position.x - start_x) < 0.5, "A real player should not push the block before touching its side.")

	player.queue_free()
	block.queue_free()
	floor.queue_free()
	await process_frame

func _verify_real_player_tiny_gap_does_not_register_push() -> void:
	var floor := _make_floor()
	root.add_child(floor)

	var block := PUSH_BLOCK_SCENE.instantiate() as RigidBody2D
	block.global_position = Vector2(28.0, -8.0)
	root.add_child(block)

	var player := PLAYER_SCENE.instantiate() as PrototypePlayer
	var player_shape := player.get_node("CollisionShape2D") as CollisionShape2D
	var player_rectangle := player_shape.shape as RectangleShape2D
	var block_half_width := 8.0
	var player_half_width := player_rectangle.size.x * 0.5
	var visible_gap := 1.25
	player.global_position = Vector2(block.global_position.x - block_half_width - player_half_width - visible_gap, -9.0)
	root.add_child(player)

	await process_frame
	for frame in 5:
		await physics_frame

	block.set("_push_attempts", {})
	_press_key(KEY_D)
	await physics_frame
	_release_key(KEY_D)

	var attempts: Dictionary = block.get("_push_attempts") as Dictionary
	_require(attempts.is_empty(), "A real player should not register a push while a visible side gap remains.")

	player.queue_free()
	block.queue_free()
	floor.queue_free()
	await process_frame

func _verify_player_border_probe_pushes_block_before_slide_collision() -> void:
	var floor := _make_floor()
	root.add_child(floor)

	var block := PUSH_BLOCK_SCENE.instantiate() as RigidBody2D
	block.global_position = Vector2(22.0, -8.0)
	var detector := block.get_node("PushDetector") as Area2D
	detector.monitoring = false
	detector.monitorable = false
	root.add_child(block)

	var player := PLAYER_SCENE.instantiate() as PrototypePlayer
	player.global_position = Vector2(0.0, 0.0)
	root.add_child(player)

	await process_frame
	for frame in 5:
		await physics_frame

	var start_x := block.global_position.x
	_press_key(KEY_D)
	for frame in 35:
		await physics_frame
	_release_key(KEY_D)

	_require(block.global_position.x > start_x + 2.0, "Player border probe should push a nearby side block before slide collision is reliable.")

	player.queue_free()
	block.queue_free()
	floor.queue_free()
	await process_frame

func _verify_direction_push_ignores_player_origin_offset() -> void:
	var floor := _make_floor()
	root.add_child(floor)

	var block := PUSH_BLOCK_SCENE.instantiate() as RigidBody2D
	block.global_position = Vector2(20.0, -8.0)
	root.add_child(block)

	var pusher := _make_push_probe_player(Vector2(-90.0, 40.0), 1.0)
	root.add_child(pusher)

	await process_frame
	for frame in 5:
		await physics_frame

	var start_x := block.global_position.x
	for frame in 30:
		block.call("register_push_attempt", pusher, 1.0)
		await physics_frame

	_require(block.global_position.x > start_x + 1.0, "Push block should trust a side-contact push direction instead of rechecking player origin offset. delta=%s" % [block.global_position.x - start_x])

	pusher.queue_free()
	block.queue_free()
	floor.queue_free()
	await process_frame

func _verify_real_player_pushes_block_when_detector_misses() -> void:
	var floor := _make_floor()
	root.add_child(floor)

	var block := PUSH_BLOCK_SCENE.instantiate() as RigidBody2D
	block.global_position = Vector2(28.0, -8.0)
	root.add_child(block)

	var player := PLAYER_SCENE.instantiate() as PrototypePlayer
	player.global_position = Vector2(0.0, 0.0)
	root.add_child(player)

	await process_frame
	for frame in 10:
		await physics_frame

	var start_x := block.global_position.x
	_press_key(KEY_D)
	for frame in 60:
		await physics_frame
	_release_key(KEY_D)

	_require(block.global_position.x > start_x + 4.0, "Player side collision should push the block even if PushDetector misses.")

	player.queue_free()
	block.queue_free()
	floor.queue_free()
	await process_frame

func _verify_two_pushers_boost_push_block() -> void:
	var single_speed: float = await _measure_push_block_speed(1)
	var boosted_speed: float = await _measure_push_block_speed(2)
	_require(boosted_speed > single_speed * 1.2, "Two pushers should move a push block faster than one pusher.")

func _measure_push_block_speed(pusher_count: int) -> float:
	var floor := _make_floor()
	root.add_child(floor)

	var block := PUSH_BLOCK_SCENE.instantiate() as RigidBody2D
	block.global_position = Vector2(20.0, -8.0)
	root.add_child(block)

	var pushers: Array[PushProbePlayer] = []
	for index in pusher_count:
		var pusher := _make_push_probe_player(Vector2(5.0, -8.0 + float(index * 6)), 1.0)
		pushers.append(pusher)
		root.add_child(pusher)

	await process_frame
	for frame in 30:
		for pusher in pushers:
			block.call("register_push_attempt", pusher, pusher.push_direction)
		await physics_frame

	var speed := block.linear_velocity.x

	for pusher in pushers:
		pusher.queue_free()
	block.queue_free()
	floor.queue_free()
	await process_frame

	return speed

func _verify_push_block_rolls_after_drop() -> void:
	var floor := _make_floor()
	root.add_child(floor)

	var block := PUSH_BLOCK_SCENE.instantiate() as RigidBody2D
	block.global_position = Vector2(-80.0, -96.0)
	block.linear_velocity = Vector2(60.0, 0.0)
	root.add_child(block)

	var largest_angular_speed := 0.0
	var grounded_frames := 0
	var largest_ground_speed := 0.0
	for frame in 150:
		await physics_frame
		largest_angular_speed = maxf(largest_angular_speed, absf(block.angular_velocity))
		if bool(block.get("_is_grounded")):
			grounded_frames += 1
			largest_ground_speed = maxf(largest_ground_speed, absf(block.linear_velocity.x))

	var max_angular_speed: float = float(block.get("max_angular_speed"))
	_require(block.global_position.x > -65.0, "Dropped push block should keep limited forward momentum. x=%s" % block.global_position.x)
	_require(largest_angular_speed > 0.05, "Dropped push block should roll lightly after landing. rotation=%s largest_angular_speed=%s grounded_frames=%s largest_ground_speed=%s" % [block.rotation, largest_angular_speed, grounded_frames, largest_ground_speed])
	_require(largest_angular_speed <= max_angular_speed + 0.1, "Push block angular speed should stay clamped.")

	block.queue_free()
	floor.queue_free()
	await process_frame

func _verify_game_start_allows_movement() -> void:
	var game := GAME_SCENE.instantiate() as GameManager
	root.add_child(game)
	await process_frame
	await process_frame
	for frame in 10:
		await physics_frame

	var level := game.get("_current_level") as PrototypeLevel
	var state: GameManager.GameState = game.get("_state") as GameManager.GameState
	var state_name: String = GameManager.GameState.keys()[state]

	var player := game.get("_player") as PrototypePlayer
	_require(player != null, "Game should spawn a PrototypePlayer.")
	if player != null and level != null:
		var hazard := level.get_node("Hazards/HazardZone") as HazardZone
		_require(
			state == GameManager.GameState.PLAYING,
			"Game should stay playable after spawning the player. state=%s player=%s hazard=%s" % [state_name, player.global_position, hazard.global_position]
		)
	else:
		_require(state == GameManager.GameState.PLAYING, "Game should stay playable after spawning the player. state=%s" % state_name)
	if player != null:
		var start_x := player.global_position.x
		_press_key(KEY_D)
		for frame in 20:
			await physics_frame
		_release_key(KEY_D)
		_require(player.global_position.x > start_x + 1.0, "Player should move right in the real game scene.")

	game.queue_free()
	await process_frame

func _verify_real_blank_game_starts() -> void:
	var game := REAL_GAME_SCENE.instantiate() as GameManager
	root.add_child(game)
	await process_frame
	await process_frame
	for frame in 10:
		await physics_frame

	var level := game.get("_current_level") as PrototypeLevel
	var player := game.get("_player") as PrototypePlayer
	_require(level != null, "Real game bootstrap should load the blank level.")
	_require(player != null, "Real game bootstrap should spawn a player.")
	if level != null:
		_require(level.get_node_or_null("Hazards/HazardZone") != null, "Real blank level should keep a HazardZone node.")
		_require(level.get_node_or_null("Goals/ExitDoor") != null, "Real blank level should keep an ExitDoor node.")
		_require(level.get_node_or_null("Players/PlayerSpawn") != null, "Real blank level should keep a PlayerSpawn node.")

	game.queue_free()
	await process_frame

func _verify_player_can_jump_over_hazard() -> void:
	var game := GAME_SCENE.instantiate() as GameManager
	root.add_child(game)
	await process_frame
	await process_frame
	for frame in 10:
		await physics_frame

	var level := game.get("_current_level") as PrototypeLevel
	var player := game.get("_player") as PrototypePlayer
	_require(level != null, "Game should load a level for hazard-jump testing.")
	_require(player != null, "Game should spawn a player for hazard-jump testing.")
	if level == null or player == null:
		game.queue_free()
		await process_frame
		return

	var hazard := level.get_node("Hazards/HazardZone") as HazardZone
	var block := level.get_node_or_null("Objects/PushBlock") as Node2D
	if block != null:
		block.global_position = Vector2(-1000.0, -1000.0)
	var hazard_shape_node := hazard.get_node("CollisionShape2D") as CollisionShape2D
	var hazard_shape := hazard_shape_node.shape as RectangleShape2D
	_require(hazard_shape.size.x >= 32.0 and hazard_shape.size.x <= 48.0, "Hazard width should be between 32px and 48px.")

	var jump_started := false
	_press_key(KEY_D)
	for frame in 180:
		if not jump_started and player.global_position.x > hazard.global_position.x - 80.0:
			_press_key(KEY_W)
			jump_started = true
		if jump_started and frame % 6 == 0:
			_release_key(KEY_W)
		await physics_frame
		var state: GameManager.GameState = game.get("_state") as GameManager.GameState
		if state != GameManager.GameState.PLAYING:
			break
		if player.global_position.x > hazard.global_position.x + 55.0:
			break
	_release_key(KEY_W)
	_release_key(KEY_D)

	var final_state: GameManager.GameState = game.get("_state") as GameManager.GameState
	_require(final_state == GameManager.GameState.PLAYING, "Player should be able to jump over the hazard without losing.")
	_require(player.global_position.x > hazard.global_position.x + 35.0, "Player should land past the hazard after a running jump.")

	game.queue_free()
	await process_frame

func _verify_jump_is_lower_and_floaty() -> void:
	var floor := _make_floor()
	root.add_child(floor)
	var player := PLAYER_SCENE.instantiate() as PrototypePlayer
	root.add_child(player)
	await process_frame
	for frame in 3:
		await physics_frame

	var start_y := player.global_position.y
	var peak_y := start_y
	var fastest_fall := 0.0
	_press_key(KEY_W)
	for frame in 90:
		await physics_frame
		if frame == 8:
			_release_key(KEY_W)
		peak_y = minf(peak_y, player.global_position.y)
		fastest_fall = maxf(fastest_fall, player.velocity.y)
	_release_key(KEY_W)

	var jump_height := start_y - peak_y
	_require(jump_height >= 38.0 and jump_height <= 62.0, "Jump should be lower but still useful. height=%s" % jump_height)
	_require(fastest_fall <= 380.0, "Player should fall slowly like feather falling. fastest_fall=%s" % fastest_fall)

	player.queue_free()
	floor.queue_free()
	await process_frame

func _verify_elemental_pool_rules() -> void:
	await _verify_pool_rule(PLAYER_SCENE, 0, false, "Fireboy should survive lava.")
	await _verify_pool_rule(PLAYER_SCENE, 1, true, "Fireboy should fail in water.")
	await _verify_pool_rule(PLAYER_SCENE, 2, true, "Fireboy should fail in poison.")
	await _verify_pool_rule(WATERGIRL_SCENE, 0, true, "Watergirl should fail in lava.")
	await _verify_pool_rule(WATERGIRL_SCENE, 1, false, "Watergirl should survive water.")
	await _verify_pool_rule(WATERGIRL_SCENE, 2, true, "Watergirl should fail in poison.")

func _verify_gem_manager_gates_exit_for_fireboy() -> void:
	var level := preload("res://scenes/levels/prototype_level.tscn").instantiate() as PrototypeLevel
	root.add_child(level)
	await process_frame

	var player := PLAYER_SCENE.instantiate() as PrototypePlayer
	level.attach_player(player)
	await process_frame

	var manager := level.get_node("Collectibles") as GemManager
	_require(manager.get_remaining_count() > 0, "Prototype level should require matching fire gems for Fireboy.")
	_require(not manager.is_unlocked(), "Gem manager should keep exit locked before required gems are collected.")

	var completed: Array[bool] = [false]
	var locked: Array[bool] = [false]
	level.level_completed.connect(func() -> void:
		completed[0] = true
	)
	level.exit_locked.connect(func(_remaining: int, _gem_element: int) -> void:
		locked[0] = true
	)

	level.call("_on_exit_door_player_entered", player)
	_require(locked[0], "Level should emit exit_locked when Fireboy reaches the door before collecting required gems.")
	_require(not completed[0], "Level should not complete before required gems are collected.")

	for child: Node in manager.get_children():
		var gem := child as CollectibleGem
		if gem != null and gem.gem_element == CollectibleGem.GemElement.FIRE:
			gem.call("_on_body_entered", player)

	_require(manager.is_unlocked(), "Gem manager should unlock after all matching fire gems are collected.")
	level.call("_on_exit_door_player_entered", player)
	_require(completed[0], "Level should complete after Fireboy collects all matching gems.")

	level.queue_free()
	await process_frame

func _verify_wrong_element_gem_stays_available() -> void:
	var gem := GEM_SCENE.instantiate() as CollectibleGem
	gem.gem_element = CollectibleGem.GemElement.WATER
	root.add_child(gem)

	var player := PLAYER_SCENE.instantiate() as PrototypePlayer
	root.add_child(player)
	await process_frame

	var wrong_touch: Array[bool] = [false]
	var collected: Array[bool] = [false]
	gem.wrong_element_touched.connect(func(_gem: CollectibleGem, _player: PrototypePlayer) -> void:
		wrong_touch[0] = true
	)
	gem.collected.connect(func(_gem: CollectibleGem, _player: PrototypePlayer) -> void:
		collected[0] = true
	)
	gem.call("_on_body_entered", player)

	_require(wrong_touch[0], "Wrong element gem touch should emit wrong_element_touched.")
	_require(not collected[0], "Wrong element gem touch should not collect the gem.")
	_require(gem.monitoring, "Wrong element gem should remain available after touch.")

	player.queue_free()
	gem.queue_free()
	await process_frame

func _verify_level_without_collectibles_keeps_exit_unlocked() -> void:
	var level := preload("res://scenes/levels/real_level_blank.tscn").instantiate() as PrototypeLevel
	root.add_child(level)
	await process_frame

	var player := PLAYER_SCENE.instantiate() as PrototypePlayer
	level.attach_player(player)
	await process_frame

	var completed: Array[bool] = [false]
	level.level_completed.connect(func() -> void:
		completed[0] = true
	)
	level.call("_on_exit_door_player_entered", player)
	_require(completed[0], "Level without Collectibles should keep old immediate exit behavior.")

	level.queue_free()
	await process_frame

func _verify_level_connects_all_hazards() -> void:
	var level := preload("res://scenes/levels/prototype_level.tscn").instantiate() as PrototypeLevel
	root.add_child(level)
	await process_frame

	var failed: Array[bool] = [false]
	level.player_failed.connect(func(_player: Node2D) -> void:
		failed[0] = true
	)

	var player := WATERGIRL_SCENE.instantiate() as PrototypePlayer
	player.add_to_group("player")
	root.add_child(player)
	var lava_pool := level.get_node("Hazards/LavaPool") as HazardZone
	lava_pool.call("_on_body_entered", player)

	_require(failed[0], "Prototype level should fail player from any hazard under Hazards, including LavaPool.")

	player.queue_free()
	level.queue_free()
	await process_frame

func _verify_pool_rule(player_scene: PackedScene, pool_type: int, should_fail: bool, message: String) -> void:
	var pool := Area2D.new()
	pool.set_script(HAZARD_SCRIPT)
	pool.set("pool_type", pool_type)
	var pool_shape_node := CollisionShape2D.new()
	var pool_shape := RectangleShape2D.new()
	pool_shape.size = Vector2(40.0, 18.0)
	pool_shape_node.shape = pool_shape
	pool.add_child(pool_shape_node)
	root.add_child(pool)

	var failed: Array[bool] = [false]
	pool.player_entered.connect(func(_player: Node2D) -> void:
		failed[0] = true
	)

	var player := player_scene.instantiate() as PrototypePlayer
	root.add_child(player)
	player.add_to_group("player")
	player.global_position = Vector2.ZERO
	await process_frame
	for frame in 3:
		await physics_frame
	pool.call("_on_body_entered", player)

	_require(failed[0] == should_fail, message)

	player.queue_free()
	pool.queue_free()
	await process_frame

func _verify_restart_keeps_runtime_live() -> void:
	var game := GAME_SCENE.instantiate() as GameManager
	root.add_child(game)
	await process_frame
	await process_frame

	game.call("_restart_level")
	await _wait_until_playing(game)

	var level_root := game.get_node("LevelRoot") as Node2D
	_require(not paused, "Restart should not leave SceneTree paused.")
	_require(level_root.get_child_count() == 1, "Restart should leave exactly one loaded level.")
	_require(game.get_viewport().get_camera_2d() != null, "Restart should keep an active Camera2D.")

	game.call("_toggle_pause")
	await process_frame
	_require(paused, "Pause should pause SceneTree.")
	game.call("_restart_level")
	await _wait_until_playing(game)

	_require(not paused, "Restart from pause should unpause SceneTree.")
	_require(level_root.get_child_count() == 1, "Restart from pause should keep one loaded level.")
	_require(game.get_viewport().get_camera_2d() != null, "Restart from pause should keep an active Camera2D.")

	game.queue_free()
	await process_frame

func _wait_until_playing(game: GameManager) -> void:
	for frame in 30:
		if game.get("_state") == GameManager.GameState.PLAYING:
			return
		await process_frame
	_require(false, "GameManager should return to PLAYING after restart.")

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

func _make_push_probe_player(position: Vector2, push_direction: float) -> PushProbePlayer:
	var player := PushProbePlayer.new()
	player.name = "PushProbePlayer"
	player.global_position = position
	player.push_direction = push_direction
	player.add_to_group("player")

	var shape_node := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(6.0, 16.0)
	shape_node.shape = shape
	player.add_child(shape_node)

	return player

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
