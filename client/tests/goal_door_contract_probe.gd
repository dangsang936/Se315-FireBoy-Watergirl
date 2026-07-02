extends SceneTree

const FIREBOY_SCENE: PackedScene = preload("res://scenes/players/fireboy.tscn")
const WATERGIRL_SCENE: PackedScene = preload("res://scenes/players/watergirl.tscn")
const LEVEL_SCENE: PackedScene = preload("res://scenes/levels/real_level_blank.tscn")

var _failures: Array[String] = []
var _completed_count: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	await _verify_goal_door_contract()
	if _failures.is_empty():
		print("Goal door contract probe passed.")
		quit(0)
		return
	for failure: String in _failures:
		printerr(failure)
	quit(1)

func _verify_goal_door_contract() -> void:
	var level := LEVEL_SCENE.instantiate() as PrototypeLevel
	root.add_child(level)
	level.level_completed.connect(func() -> void: _completed_count += 1)
	await process_frame

	var fireboy := FIREBOY_SCENE.instantiate() as PrototypePlayer
	var watergirl := WATERGIRL_SCENE.instantiate() as PrototypePlayer
	level.attach_player(fireboy, 1)
	level.attach_player(watergirl, 2)
	await process_frame
	_require(fireboy.global_position == watergirl.global_position, "Both players should spawn at the shared PlayerSpawn.")

	var fire_door := level.get_node("Goals/FireDoor")
	var water_door := level.get_node("Goals/WaterDoor")
	_require(fire_door != null, "Level must contain Goals/FireDoor.")
	_require(water_door != null, "Level must contain Goals/WaterDoor.")
	if fire_door == null or water_door == null:
		level.queue_free()
		await process_frame
		return

	fire_door._on_body_entered(watergirl)
	water_door._on_body_entered(fireboy)
	_require(not fire_door.is_occupied_by_required_player(), "Watergirl must not occupy FireDoor.")
	_require(not water_door.is_occupied_by_required_player(), "Fireboy must not occupy WaterDoor.")
	_require(_completed_count == 0, "Wrong doors must not complete the level.")

	fire_door._on_body_entered(fireboy)
	water_door._on_body_entered(watergirl)
	_require(fire_door.is_occupied_by_required_player(), "Fireboy must occupy FireDoor.")
	_require(water_door.is_occupied_by_required_player(), "Watergirl must occupy WaterDoor.")
	_require(_completed_count == 0, "Doors must stay locked while required gems remain.")

	var manager := level.get_node("Collectibles") as GemManager
	_require(manager != null, "Level must contain Collectibles GemManager.")
	if manager != null:
		for gem_node: Node in manager.get_children():
			var gem := gem_node as CollectibleGem
			if gem != null:
				gem.collect_remotely()
				var gem_path := str(level.get_path_to(gem))
				manager.client_mark_collected_by_path(gem_path)
		await process_frame
		_require(_completed_count == 1, "All gems plus both correct doors must complete once.")

	fire_door._on_body_exited(fireboy)
	water_door._on_body_exited(watergirl)
	_require(_completed_count == 1, "Completion must emit only once.")

	level.queue_free()
	await process_frame

func _require(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
