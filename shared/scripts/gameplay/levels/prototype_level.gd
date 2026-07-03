class_name PrototypeLevel
extends Node2D

signal level_completed
signal player_failed(player: Node2D)
signal exit_locked(remaining: int, gem_element: int)
signal gem_progress_changed(collected: int, required: int)

const ELEMENT_FIRE: int = 0
const ELEMENT_WATER: int = 1

@export var players_path: NodePath = ^"Players"
@export var player_spawn_path: NodePath = ^"Players/PlayerSpawn"
@export var player_spawn_2_path: NodePath = ^"Players/PlayerSpawn2"
@export var collectibles_path: NodePath = ^"Collectibles"
@export var hazards_path: NodePath = ^"Hazards"
@export var hazard_zone_path: NodePath = ^"Hazards/HazardZone"
@export var exit_door_path: NodePath = ^"Goals/ExitDoor"
@export var fire_goal_door_path: NodePath = ^""
@export var water_goal_door_path: NodePath = ^""

var _is_completed: bool = false
var _safe_frames: int = 5 # Prevents instant-death from spawn overlaps during load
var _fire_door_ready: bool = false
var _water_door_ready: bool = false

@onready var _players: Node2D = get_node(players_path) as Node2D
@onready var _player_spawn: Marker2D = get_node(player_spawn_path) as Marker2D
@onready var _player_spawn_2: Marker2D = get_node_or_null(player_spawn_2_path) as Marker2D
@onready var _gem_manager: GemManager = get_node_or_null(collectibles_path) as GemManager
@onready var _hazards: Node2D = get_node_or_null(hazards_path) as Node2D
@onready var _hazard_zone: HazardZone = get_node_or_null(hazard_zone_path) as HazardZone
@onready var _exit_door: ExitDoor = get_node_or_null(exit_door_path) as ExitDoor
@onready var _fire_goal_door: Node = get_node_or_null(fire_goal_door_path)
@onready var _water_goal_door: Node = get_node_or_null(water_goal_door_path)

func _ready() -> void:
	if multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
		_connect_hazards()
		if _uses_goal_doors():
			_connect_goal_doors()
		elif _exit_door != null:
			_exit_door.player_entered.connect(_on_exit_door_player_entered)
			_exit_door.both_players_entered.connect(_on_exit_door_both_players_entered)
	_connect_collectibles()

func _physics_process(_delta: float) -> void:
	if _safe_frames > 0:
		_safe_frames -= 1

func _on_exit_door_player_entered(_player: Node2D) -> void:
	if _gem_manager != null and not _gem_manager.is_unlocked():
		exit_locked.emit(_gem_manager.get_remaining_count(), _gem_manager.get_active_gem_element())
		return
	if _get_required_exit_players() <= 1:
		_complete_level()

func _on_exit_door_both_players_entered() -> void:
	if _gem_manager != null and not _gem_manager.is_unlocked():
		return
	_complete_level()

func _connect_goal_doors() -> void:
	if _fire_goal_door != null and not _fire_goal_door.occupancy_changed.is_connected(_on_goal_door_occupancy_changed):
		_fire_goal_door.occupancy_changed.connect(_on_goal_door_occupancy_changed)
	if _water_goal_door != null and not _water_goal_door.occupancy_changed.is_connected(_on_goal_door_occupancy_changed):
		_water_goal_door.occupancy_changed.connect(_on_goal_door_occupancy_changed)
	if _fire_goal_door != null and not _fire_goal_door.wrong_player_entered.is_connected(_on_wrong_goal_door_entered):
		_fire_goal_door.wrong_player_entered.connect(_on_wrong_goal_door_entered)
	if _water_goal_door != null and not _water_goal_door.wrong_player_entered.is_connected(_on_wrong_goal_door_entered):
		_water_goal_door.wrong_player_entered.connect(_on_wrong_goal_door_entered)

func _on_goal_door_occupancy_changed(required_element: int, is_occupied: bool, _player: Node2D) -> void:
	match required_element:
		ELEMENT_FIRE:
			_fire_door_ready = is_occupied
		ELEMENT_WATER:
			_water_door_ready = is_occupied
		_:
			push_warning("Unknown goal door element: %s" % required_element)
			return
	_try_complete_goal_door_level()

func _on_wrong_goal_door_entered(required_element: int, _player_element: int, _player: Node2D) -> void:
	exit_locked.emit(_gem_manager.get_remaining_count() if _gem_manager != null else 0, required_element)

func _try_complete_goal_door_level() -> void:
	if _is_completed:
		return
	if not _uses_goal_doors():
		return
	if not _fire_door_ready or not _water_door_ready:
		return
	if _gem_manager != null and not _gem_manager.is_unlocked():
		exit_locked.emit(_gem_manager.get_remaining_count(), _gem_manager.get_active_gem_element())
		return
	_complete_level()

func attach_player(player: Node2D, spawn_idx: int = 1) -> void:
	var spawn_position: Vector2 = get_spawn_position() if spawn_idx == 1 else get_spawn_position_2()
	player.position = _players.to_local(spawn_position)
	_players.add_child(player)
	player.global_position = spawn_position

	if _gem_manager != null:
		_configure_gems_for_attached_players(player)

func get_spawn_position() -> Vector2:
	return _player_spawn.global_position

func get_spawn_position_2() -> Vector2:
	if _player_spawn_2:
		return _player_spawn_2.global_position
	return get_spawn_position() + Vector2(50, 0)

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

func _on_hazard_zone_player_entered(player: Node2D) -> void:
	# Ignore hazards for the first few frames to prevent boot-up death loops
	if _safe_frames > 0:
		return 
		
	var failed_id := _get_player_peer_id(player)
	_broadcast_player_failed(failed_id)
	player_failed.emit(player)

func _on_gem_progress_changed(collected: int, required: int) -> void:
	gem_progress_changed.emit(collected, required)
	_try_complete_goal_door_level()

func _configure_gems_for_attached_players(fallback_player: Node2D) -> void:
	if _gem_manager == null:
		return
	if _gem_manager.has_method("configure_for_players"):
		_gem_manager.configure_for_players(_players.get_children())
	elif _gem_manager.has_method("configure_for_player"):
		_gem_manager.configure_for_player(fallback_player)
	elif _gem_manager.has_method("configure_all"):
		_gem_manager.configure_all()

func _get_required_exit_players() -> int:
	return maxi(_players.get_child_count(), 1)

func _uses_goal_doors() -> bool:
	return _fire_goal_door != null or _water_goal_door != null

func _complete_level() -> void:
	if _is_completed:
		return
	_is_completed = true
	print("[Server] Exit condition satisfied. Level complete!")
	_broadcast_level_completed()
	level_completed.emit()

func _get_player_peer_id(player: Node2D) -> int:
	if player == null:
		return 0
	if player.has_meta("player_id"):
		return int(player.get_meta("player_id"))
	if "player_id" in player:
		return int(player.get("player_id"))
	return 0

func _broadcast_player_failed(failed_player_id: int) -> void:
	var rpc_node := _get_gameplay_rpc()
	if rpc_node and rpc_node.has_method("sync_player_failed"):
		rpc_node.rpc("sync_player_failed", failed_player_id)
	else:
		var nm := get_node_or_null("/root/NetworkManager")
		if nm and nm.has_method("_broadcast_player_failed_rpc"):
			nm.call("_broadcast_player_failed_rpc", failed_player_id)

func _broadcast_level_completed() -> void:
	var rpc_node := _get_gameplay_rpc()
	if rpc_node and rpc_node.has_method("sync_level_completed"):
		rpc_node.rpc("sync_level_completed")
	else:
		var nm := get_node_or_null("/root/NetworkManager")
		if nm and nm.has_method("_broadcast_level_completed_rpc"):
			nm.call("_broadcast_level_completed_rpc")

func _get_gameplay_rpc() -> Node:
	return get_node_or_null("/root/GameplayRpc")
