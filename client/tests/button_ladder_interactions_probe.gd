extends SceneTree

const PLAYER_SCENE: PackedScene = preload("res://scenes/players/fireboy.tscn")
const WATERGIRL_SCENE: PackedScene = preload("res://scenes/players/watergirl.tscn")
const PRESSURE_BUTTON_SCENE: PackedScene = preload("res://scenes/gameplay/objects/pressure_button.tscn")
const BRIDGE_SCENE: PackedScene = preload("res://scenes/gameplay/objects/bridge_platform.tscn")
const LADDER_SCENE: PackedScene = preload("res://scenes/gameplay/objects/ladder.tscn")
const GEM_SCENE: PackedScene = preload("res://scenes/gameplay/collectibles/fire_gem.tscn")
const HAZARD_SCRIPT: Script = preload("res://shared/scripts/gameplay/hazards/hazard_zone.gd")
const EXIT_SCRIPT: Script = preload("res://shared/scripts/gameplay/doors/exit_door.gd")

class MockBridge:
	extends Node

	var active: bool = false

	func set_active(is_active: bool) -> void:
		active = is_active

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	await _verify_pressure_button_artwork_states()
	await _verify_pressure_button_supports_standing()
	await _verify_bridge_collision_activates_with_button_state()
	await _verify_ladder_climb_motion()
	await _verify_ladder_boundaries_and_regressions()

	if _failures.is_empty():
		print("Button and ladder interactions probe passed.")
		quit(0)
		return

	for failure in _failures:
		printerr(failure)
	quit(1)

func _verify_pressure_button_artwork_states() -> void:
	var button := PRESSURE_BUTTON_SCENE.instantiate() as PressureButton
	button.position = Vector2(0.0, 0.0)
	root.add_child(button)
	var bridge := MockBridge.new()
	root.add_child(bridge)
	button.bridge_path = button.get_path_to(bridge)
	await process_frame

	var sprite := button.get_node("AnimatedSprite2D") as AnimatedSprite2D
	button.call("_sync_visual_state")
	_require(sprite.frame == 0, "Pressure button should start on released frame 0, got %s." % sprite.frame)

	var player := PLAYER_SCENE.instantiate() as PrototypePlayer
	player.global_position = Vector2(0.0, -36.0)
	root.add_child(player)
	await _settle_frames(24)
	_require(button.is_pressed(), "Valid Fireboy should press the pressure button.")
	_require(sprite.frame == 1, "Pressed pressure button should show frame 1.")
	_require(bridge.active, "Pressed pressure button should activate linked bridge target.")

	player.global_position = Vector2(96.0, -36.0)
	await _settle_frames(12)
	_require(not button.is_pressed(), "Pressure button should release after player exits.")
	_require(sprite.frame == 0, "Released pressure button should return to frame 0.")
	_require(not bridge.active, "Released pressure button should deactivate linked bridge target.")

	button.required_element = PressureButton.ElementRequirement.WATER
	player.global_position = Vector2(0.0, -36.0)
	await _settle_frames(24)
	_require(not button.is_pressed(), "Wrong element should not press the pressure button.")
	_require(sprite.frame == 0, "Wrong element touch should keep released frame 0.")

	player.queue_free()
	button.queue_free()
	bridge.queue_free()
	await process_frame

func _verify_pressure_button_supports_standing() -> void:
	var button := PRESSURE_BUTTON_SCENE.instantiate() as PressureButton
	button.position = Vector2(0.0, 0.0)
	button.require_player_on_floor = false
	root.add_child(button)

	var player := PLAYER_SCENE.instantiate() as PrototypePlayer
	player.global_position = Vector2(0.0, -36.0)
	root.add_child(player)
	await _settle_frames(24)

	_require(player.is_on_floor(), "Player should be able to stand on pressure plate body.")
	_require(player.global_position.y < button.global_position.y, "Player should settle on top of pressure plate, not pass through it.")

	player.queue_free()
	button.queue_free()
	await process_frame

func _verify_bridge_collision_activates_with_button_state() -> void:
	var bridge := BRIDGE_SCENE.instantiate() as BridgePlatform
	bridge.start_active = false
	bridge.reveal_duration = 1.0
	bridge.tile_stagger = 0.5
	root.add_child(bridge)
	await process_frame

	var collision_shape := bridge.get_node("CollisionShape2D") as CollisionShape2D
	_require(collision_shape.disabled, "Inactive bridge should start with its collision disabled.")

	bridge.set_active(true)
	await physics_frame
	_require(not collision_shape.disabled, "Activating a bridge should enable collision before the reveal animation finishes.")

	bridge.queue_free()
	await process_frame

func _verify_ladder_climb_motion() -> void:
	var floor := _make_floor()
	root.add_child(floor)
	var ladder := LADDER_SCENE.instantiate() as Area2D
	ladder.global_position = Vector2(6.0, -42.0)
	root.add_child(ladder)
	var player := PLAYER_SCENE.instantiate() as PrototypePlayer
	player.global_position = Vector2(0.0, 0.0)
	root.add_child(player)
	await _settle_frames(6)

	var start_y: float = player.global_position.y
	_press_key(KEY_W)
	await _settle_frames(10)
	_release_key(KEY_W)
	_require(player.get_player_state() == PrototypePlayer.PlayerState.CLIMBING, "Holding W on ladder should enter CLIMBING enum state.")
	_require(player.get_player_state_name() == &"climb", "Holding W on ladder should enter readable climb state.")
	_require(player.global_position.y < start_y - 1.0, "Holding W on ladder should move player upward.")
	var hold_y: float = player.global_position.y
	await _settle_frames(8)
	_require(absf(player.global_position.y - hold_y) < 1.5, "Releasing vertical input should hold player stable on ladder. start=%s now=%s" % [hold_y, player.global_position.y])

	_press_key(KEY_S)
	await _settle_frames(10)
	_release_key(KEY_S)
	_require(player.global_position.y > hold_y + 1.0, "Holding S on ladder should move player downward.")

	var both_start_y: float = player.global_position.y
	_press_key(KEY_W)
	_press_key(KEY_S)
	await _settle_frames(8)
	_release_key(KEY_W)
	_release_key(KEY_S)
	_require(absf(player.global_position.y - both_start_y) < 1.5, "Holding W and S together should produce stable ladder hold. start=%s now=%s" % [both_start_y, player.global_position.y])

	player.global_position = Vector2(160.0, 0.0)
	await _settle_frames(4)
	_require(player.get_player_state_name() != &"climb", "Leaving ladder area should exit climb state.")

	player.queue_free()
	ladder.queue_free()
	floor.queue_free()
	await process_frame

func _verify_ladder_boundaries_and_regressions() -> void:
	var floor := _make_floor()
	root.add_child(floor)
	var ladder := LADDER_SCENE.instantiate() as Area2D
	ladder.global_position = Vector2(6.0, -42.0)
	root.add_child(ladder)
	var player := PLAYER_SCENE.instantiate() as PrototypePlayer
	player.global_position = Vector2(0.0, 0.0)
	root.add_child(player)
	await _settle_frames(6)

	_press_key(KEY_W)
	await _settle_frames(6)
	_release_key(KEY_W)
	player.set_control_enabled(false)
	await physics_frame
	_require(player.get_player_state_name() == &"disabled", "Control disable on ladder should enter disabled state.")
	_require(player.velocity == Vector2.ZERO, "Control disable on ladder should clear climb velocity.")
	player.reset_to_spawn(Vector2(120.0, 0.0))
	await _settle_frames(4)
	_require(player.get_player_state_name() != &"climb", "Reset away from ladder should clear climb attachment.")

	var sprite := player.get_node("AnimatedSprite2D") as AnimatedSprite2D
	player.global_position = Vector2(0.0, 0.0)
	await _settle_frames(6)
	_press_key(KEY_W)
	await _settle_frames(4)
	_release_key(KEY_W)
	_require(sprite.animation == &"idle", "Temporary climb visual should use idle animation.")

	_require(player.can_survive_pool(0), "Fireboy should still survive lava while ladder feature exists.")
	_require(not player.can_survive_pool(1), "Fireboy should still fail water while ladder feature exists.")
	_require(not player.can_survive_pool(2), "Fireboy should still fail poison while ladder feature exists.")

	var watergirl := WATERGIRL_SCENE.instantiate() as PrototypePlayer
	root.add_child(watergirl)
	await process_frame
	_require(watergirl.can_survive_pool(1), "Watergirl should still survive water while ladder feature exists.")
	_require(not watergirl.can_survive_pool(0), "Watergirl should still fail lava while ladder feature exists.")

	var gem := GEM_SCENE.instantiate() as CollectibleGem
	root.add_child(gem)
	await process_frame
	_require(gem.can_collect(player), "Fire gem should remain collectible by Fireboy near ladders.")
	_require(not gem.can_collect(watergirl), "Fire gem should remain nonmatching for Watergirl near ladders.")

	var hazard := HAZARD_SCRIPT.new() as HazardZone
	hazard.pool_type = HazardZone.PoolType.LAVA
	var hazard_seen: Array[bool] = [false]
	hazard.player_entered.connect(func(_player: Node2D) -> void: hazard_seen[0] = true)
	root.add_child(hazard)
	await process_frame
	hazard.call("_on_body_entered", watergirl)
	_require(hazard_seen[0], "Hazard should still emit failure for non-surviving player near ladders.")

	var exit := EXIT_SCRIPT.new() as ExitDoor
	var exit_seen: Array[bool] = [false]
	exit.player_entered.connect(func(_player: Node2D) -> void: exit_seen[0] = true)
	root.add_child(exit)
	await process_frame
	exit.call("_on_body_entered", player)
	_require(exit_seen[0], "Exit door should still emit player entry near ladders.")

	player.queue_free()
	watergirl.queue_free()
	gem.queue_free()
	hazard.queue_free()
	exit.queue_free()
	ladder.queue_free()
	floor.queue_free()
	await process_frame

func _settle_frames(count: int) -> void:
	for frame in count:
		await physics_frame

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
