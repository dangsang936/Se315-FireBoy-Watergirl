extends SceneTree

const LEVEL_SCENE: PackedScene = preload("res://scenes/levels/real_level_blank.tscn")
const WATERGIRL_SCENE: PackedScene = preload("res://scenes/players/watergirl.tscn")

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	await _verify_remote_player_visual_does_not_fail_local_level()
	await _verify_local_player_still_fails_hazard()

	if _failures.is_empty():
		print("Multiplayer hazard sync probe passed.")
		quit(0)
		return

	for failure: String in _failures:
		printerr(failure)
	quit(1)

func _verify_remote_player_visual_does_not_fail_local_level() -> void:
	var level := LEVEL_SCENE.instantiate() as PrototypeLevel
	root.add_child(level)
	await process_frame

	var failed: Array[bool] = [false]
	level.player_failed.connect(func(_player: Node2D) -> void:
		failed[0] = true
	)

	var remote_player := WATERGIRL_SCENE.instantiate() as PrototypePlayer
	remote_player.is_local = false
	level.attach_player(remote_player, 2)
	await process_frame

	var lava_pool := level.get_node("Hazards/LavaPool") as HazardZone
	lava_pool.call("_on_body_entered", remote_player)

	_require(not failed[0], "Remote player visuals should not trigger local hazard failure.")

	level.queue_free()
	await process_frame

func _verify_local_player_still_fails_hazard() -> void:
	var level := LEVEL_SCENE.instantiate() as PrototypeLevel
	root.add_child(level)
	await process_frame

	var failed: Array[bool] = [false]
	level.player_failed.connect(func(_player: Node2D) -> void:
		failed[0] = true
	)

	var local_player := WATERGIRL_SCENE.instantiate() as PrototypePlayer
	local_player.is_local = true
	level.attach_player(local_player, 2)
	await process_frame

	var lava_pool := level.get_node("Hazards/LavaPool") as HazardZone
	lava_pool.call("_on_body_entered", local_player)

	_require(failed[0], "Local player should still trigger hazard failure.")

	level.queue_free()
	await process_frame

func _require(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
