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
@export var exit_door_path: NodePath = ^"Goals/ExitDoor"

var _is_completed: bool = false
var _safe_frames: int = 5 # Prevents instant-death from spawn overlaps during load

@onready var _players: Node2D = get_node(players_path) as Node2D
@onready var _player_spawn: Marker2D = get_node(player_spawn_path) as Marker2D
@onready var _player_spawn_2: Marker2D = get_node_or_null(player_spawn_2_path) as Marker2D
@onready var _gem_manager: GemManager = get_node_or_null(collectibles_path) as GemManager
@onready var _hazards: Node2D = get_node_or_null(hazards_path) as Node2D
@onready var _hazard_zone: HazardZone = get_node_or_null(hazard_zone_path) as HazardZone
@onready var _exit_door: ExitDoor = get_node(exit_door_path) as ExitDoor

func _ready() -> void:
	if multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
		_connect_hazards()
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
	var node := get_node_or_null("/root/GameplayRpc")
	if node == null:
		node = get_node_or_null("/root/GameplayRPC")
	return node
