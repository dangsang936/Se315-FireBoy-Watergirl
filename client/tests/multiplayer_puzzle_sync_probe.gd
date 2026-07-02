extends SceneTree

const LEVEL_SCENE: PackedScene = preload("res://scenes/levels/real_level_blank.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/players/fireboy.tscn")

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	await _verify_remote_player_visual_does_not_press_button()
	await _verify_remote_button_state_controls_bridge()

	if _failures.is_empty():
		print("Multiplayer puzzle sync probe passed.")
		quit(0)
		return

	for failure: String in _failures:
		printerr(failure)
	quit(1)

func _verify_remote_player_visual_does_not_press_button() -> void:
	var level := LEVEL_SCENE.instantiate() as PrototypeLevel
	root.add_child(level)
	await process_frame

	var button := level.get_node("tilemap/PressureButton") as PressureButton
	button.require_player_on_floor = false

	var remote_player := PLAYER_SCENE.instantiate() as PrototypePlayer
	remote_player.is_local = false
	level.attach_player(remote_player, 1)
	button.call("_on_body_entered", remote_player)
	await physics_frame

	_require(not button.is_pressed(), "Remote player visuals should not drive local pressure buttons.")

	level.queue_free()
	await process_frame

func _verify_remote_button_state_controls_bridge() -> void:
	var level := LEVEL_SCENE.instantiate() as PrototypeLevel
	root.add_child(level)
	await process_frame

	var button := level.get_node("tilemap/PressureButton") as PressureButton
	var bridge := level.get_node("Puzzles/LavaBridge") as BridgePlatform
	_require(button.has_method("apply_remote_pressed_state"), "PressureButton should expose a remote state apply method.")

	if button.has_method("apply_remote_pressed_state"):
		button.call("apply_remote_pressed_state", true)
		await physics_frame
		_require(button.is_pressed(), "Remote pressed state should update button state.")
		_require(bridge.is_active(), "Remote pressed state should activate the linked bridge.")

		button.call("apply_remote_pressed_state", false)
		await physics_frame
		_require(not button.is_pressed(), "Remote release state should update button state.")
		_require(not bridge.is_active(), "Remote release state should deactivate the linked bridge.")

	level.queue_free()
	await process_frame

func _require(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
