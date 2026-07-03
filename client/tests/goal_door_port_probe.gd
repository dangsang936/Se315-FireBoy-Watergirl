extends SceneTree

const GAME_SCENE: PackedScene = preload("res://scenes/bootstrap/game.tscn")
const FIREBOY_SCENE: PackedScene = preload("res://scenes/players/fireboy.tscn")
const WATERGIRL_SCENE: PackedScene = preload("res://scenes/players/watergirl.tscn")
const LEVEL_ONE_SCENE: PackedScene = preload("res://scenes/levels/real_level_blank.tscn")
const LEVEL_TWO_SCENE: PackedScene = preload("res://scenes/levels/real_level_blank_2.tscn")

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	await _verify_goal_door_level_flow()
	await _verify_game_manager_next_level_flow()
	await _verify_multiplayer_next_level_hooks()

	if _failures.is_empty():
		print("Goal door port probe passed.")
		quit(0)
		return

	for failure: String in _failures:
		printerr(failure)
	quit(1)

func _verify_goal_door_level_flow() -> void:
	var level: PrototypeLevel = LEVEL_ONE_SCENE.instantiate() as PrototypeLevel
	root.add_child(level)
	await process_frame

	_require(level.get("fire_goal_door_path") == NodePath("tilemap/Goals/FireDoor"), "Level 1 should wire fire_goal_door_path.")
	_require(level.get("water_goal_door_path") == NodePath("tilemap/Goals/WaterDoor"), "Level 1 should wire water_goal_door_path.")

	var fire_door: Node = level.get_node_or_null("tilemap/Goals/FireDoor")
	var water_door: Node = level.get_node_or_null("tilemap/Goals/WaterDoor")
	_require(fire_door != null, "Level 1 should contain FireDoor.")
	_require(water_door != null, "Level 1 should contain WaterDoor.")
	if fire_door == null or water_door == null:
		level.queue_free()
		await process_frame
		return

	var fireboy: PrototypePlayer = FIREBOY_SCENE.instantiate() as PrototypePlayer
	var watergirl: PrototypePlayer = WATERGIRL_SCENE.instantiate() as PrototypePlayer
	level.attach_player(fireboy, 1)
	level.attach_player(watergirl, 2)
	await process_frame

	var manager: Node = level.get_node_or_null("Collectibles")
	_require(manager != null, "Level 1 should keep a Collectibles manager.")
	if manager == null:
		level.queue_free()
		await process_frame
		return

	var completed: Array[bool] = [false]
	var locked: Array[bool] = [false]
	level.level_completed.connect(func() -> void:
		completed[0] = true
	)
	level.exit_locked.connect(func(_remaining: int, _gem_element: int) -> void:
		locked[0] = true
	)

	water_door.call("_on_body_entered", fireboy)
	await process_frame
	_require(locked[0], "Wrong player on WaterDoor should emit exit_locked.")
	_require(not completed[0], "Wrong player on WaterDoor should not complete the level.")

	for child: Node in manager.get_children():
		if child.has_method("_on_body_entered") and child.get("gem_element") == 0:
			child.call("_on_body_entered", fireboy)
		elif child.has_method("_on_body_entered") and child.get("gem_element") == 1:
			child.call("_on_body_entered", watergirl)

	fire_door.call("_on_body_entered", fireboy)
	water_door.call("_on_body_entered", watergirl)
	await process_frame
	_require(completed[0], "Both matching players on goal doors after collecting matching gems should complete the level.")

	level.queue_free()
	await process_frame

func _verify_game_manager_next_level_flow() -> void:
	var game: GameManager = GAME_SCENE.instantiate() as GameManager
	game.set("level_scene", LEVEL_ONE_SCENE)
	game.set("level_scenes", [LEVEL_ONE_SCENE, LEVEL_TWO_SCENE])
	root.add_child(game)
	await process_frame
	await process_frame
	for _frame in 10:
		await physics_frame

	var hud: PrototypeHUD = game.get_node("HUD") as PrototypeHUD
	_require(hud.has_signal("next_level_requested"), "HUD should expose next_level_requested.")
	_require(hud.has_method("show_level_complete"), "HUD should expose show_level_complete().")
	_require(hud.has_method("hide_level_complete"), "HUD should expose hide_level_complete().")

	game.set("_state", GameManager.ManagerState.WON)
	hud.emit_signal("next_level_requested")
	await process_frame
	await process_frame
	for _frame in 5:
		await physics_frame

	var current_level: Node = game.get("_current_level") as Node
	_require(current_level != null, "GameManager should still have a current level after next-level flow.")
	if current_level != null:
		_require(current_level.scene_file_path.ends_with("real_level_blank_2.tscn"), "GameManager should advance to level 2 after next_level_requested.")

	game.queue_free()
	await process_frame

func _verify_multiplayer_next_level_hooks() -> void:
	var network_manager: Node = root.get_node_or_null("NetworkManager")
	_require(network_manager != null, "Client project should autoload NetworkManager.")
	if network_manager == null:
		return
	_require(network_manager.has_signal("next_level_received"), "NetworkManager should expose next_level_received.")
	_require(network_manager.has_method("send_next_level"), "NetworkManager should expose send_next_level().")
	_require(network_manager.has_method("sync_next_level"), "NetworkManager should expose sync_next_level().")

	var gameplay_rpc: Node = root.get_node_or_null("GameplayRpc")
	_require(gameplay_rpc != null, "Client project should autoload GameplayRpc.")
	if gameplay_rpc == null:
		return
	_require(gameplay_rpc.has_method("sync_next_level"), "GameplayRpc should expose sync_next_level().")

func _require(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
