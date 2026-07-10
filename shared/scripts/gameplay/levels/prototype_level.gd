class_name PrototypeLevel
extends Node2D

signal level_completed
signal player_failed(player: Node2D)
signal exit_locked(remaining: int, gem_element: int)
signal gem_progress_changed(collected: int, required: int)

@export var players_path: NodePath = ^"Players"
@export var player_spawn_path: NodePath = ^"Players/PlayerSpawn"
@export var player_spawn_2_path: NodePath = ^"Players/PlayerSpawn2"
@export var collectibles_path: NodePath = ^"Collectibles"
@export var hazards_path: NodePath = ^"Hazards"
@export var hazard_zone_path: NodePath = ^"Hazards/HazardZone"
@export var fire_goal_door_path: NodePath = ^"Goals/FireDoor"
@export var water_goal_door_path: NodePath = ^"Goals/WaterDoor"

@onready var _players: Node2D = get_node(players_path) as Node2D
@onready var _player_spawn: Marker2D = get_node(player_spawn_path) as Marker2D
@onready var _player_spawn_2: Marker2D = get_node_or_null(player_spawn_2_path) as Marker2D
@onready var _gem_manager: GemManager = get_node_or_null(collectibles_path) as GemManager
@onready var _hazards: Node2D = get_node_or_null(hazards_path) as Node2D
@onready var _hazard_zone: HazardZone = get_node_or_null(hazard_zone_path) as HazardZone
@onready var _fire_goal_door: Node = get_node_or_null(fire_goal_door_path)
@onready var _water_goal_door: Node = get_node_or_null(water_goal_door_path)

var _fire_door_ready: bool = false
var _water_door_ready: bool = false
var _level_completed: bool = false

func _ready() -> void:
	_connect_hazards()
	_connect_collectibles()
	_connect_goal_doors()

func _connect_goal_doors() -> void:
	if _fire_goal_door != null:
		if _fire_goal_door.has_signal("occupancy_changed") and not _fire_goal_door.is_connected("occupancy_changed", Callable(self, "_on_goal_door_occupancy_changed")):
			_fire_goal_door.connect("occupancy_changed", Callable(self, "_on_goal_door_occupancy_changed"))
		if _fire_goal_door.has_signal("wrong_player_entered") and not _fire_goal_door.is_connected("wrong_player_entered", Callable(self, "_on_wrong_goal_door_entered")):
			_fire_goal_door.connect("wrong_player_entered", Callable(self, "_on_wrong_goal_door_entered"))
		if _fire_goal_door.has_method("refresh_occupancy"):
			_fire_goal_door.call_deferred("refresh_occupancy")
	if _water_goal_door != null:
		if _water_goal_door.has_signal("occupancy_changed") and not _water_goal_door.is_connected("occupancy_changed", Callable(self, "_on_goal_door_occupancy_changed")):
			_water_goal_door.connect("occupancy_changed", Callable(self, "_on_goal_door_occupancy_changed"))
		if _water_goal_door.has_signal("wrong_player_entered") and not _water_goal_door.is_connected("wrong_player_entered", Callable(self, "_on_wrong_goal_door_entered")):
			_water_goal_door.connect("wrong_player_entered", Callable(self, "_on_wrong_goal_door_entered"))
		if _water_goal_door.has_method("refresh_occupancy"):
			_water_goal_door.call_deferred("refresh_occupancy")

func _on_goal_door_occupancy_changed(required_element: int, is_occupied: bool, _player: Node2D) -> void:
	match required_element:
		int(PrototypePlayer.Element.FIRE):
			_fire_door_ready = is_occupied
		int(PrototypePlayer.Element.WATER):
			_water_door_ready = is_occupied
		_:
			push_warning("Unknown goal door element: %s" % required_element)
	_try_complete_level()

func _on_wrong_goal_door_entered(_required_element: int, _player_element: int, _player: Node2D) -> void:
	exit_locked.emit(_gem_manager.get_remaining_count() if _gem_manager != null else 0, _required_element)

func _try_complete_level() -> void:
	if _level_completed:
		return
	if not _fire_door_ready or not _water_door_ready:
		_refresh_goal_door_occupancy()
		if not _fire_door_ready or not _water_door_ready:
			return
	if _gem_manager != null and not _gem_manager.is_unlocked():
		exit_locked.emit(_gem_manager.get_remaining_count(), _gem_manager.get_active_gem_element())
		return
	_level_completed = true
	level_completed.emit()

func _refresh_goal_door_occupancy() -> void:
	if _fire_goal_door != null and _fire_goal_door.has_method("refresh_occupancy"):
		_fire_goal_door.call("refresh_occupancy")
	if _water_goal_door != null and _water_goal_door.has_method("refresh_occupancy"):
		_water_goal_door.call("refresh_occupancy")

func attach_player(player: Node2D, spawn_idx: int = 1) -> void:
	var spawn_position: Vector2 = get_spawn_position() if spawn_idx == 1 else get_spawn_position_2()
	player.position = _players.to_local(spawn_position)
	_players.add_child(player)
	player.global_position = spawn_position
	
	if _gem_manager != null and _gem_manager.has_method("configure_for_player"):
		_gem_manager.configure_for_player(player)

func get_spawn_position() -> Vector2:
	return _player_spawn.global_position

func get_spawn_position_2() -> Vector2:
	if _player_spawn_2:
		return _player_spawn_2.global_position
	return get_spawn_position()

func _connect_hazards() -> void:
	if _hazards == null:
		if _hazard_zone != null:
			_hazard_zone.player_entered.connect(_on_hazard_zone_player_entered)
		return

	for child: Node in _hazards.get_children():
		var hazard := child as HazardZone
		if hazard == null:
			continue
		hazard.player_entered.connect(_on_hazard_zone_player_entered)

func _connect_collectibles() -> void:
	if _gem_manager == null:
		return
	if not _gem_manager.gem_progress_changed.is_connected(_on_gem_progress_changed):
		_gem_manager.gem_progress_changed.connect(_on_gem_progress_changed)
	if _gem_manager.has_method("configure_all"):
		_gem_manager.configure_all()

func _on_hazard_zone_player_entered(player: Node2D) -> void:
	if player.get("is_local") == false:
		return
	player_failed.emit(player)


func _on_gem_progress_changed(collected: int, required: int) -> void:
	gem_progress_changed.emit(collected, required)
	_try_complete_level()
