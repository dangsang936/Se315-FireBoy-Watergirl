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

@onready var _players: Node2D = get_node(players_path) as Node2D
@onready var _player_spawn: Marker2D = get_node(player_spawn_path) as Marker2D
@onready var _player_spawn_2: Marker2D = get_node_or_null(player_spawn_2_path) as Marker2D
@onready var _gem_manager: GemManager = get_node_or_null(collectibles_path) as GemManager
@onready var _hazards: Node2D = get_node_or_null(hazards_path) as Node2D
@onready var _hazard_zone: HazardZone = get_node_or_null(hazard_zone_path) as HazardZone
@onready var _exit_door: ExitDoor = get_node(exit_door_path) as ExitDoor

func _ready() -> void:
	_connect_hazards()
	_connect_collectibles()
	_exit_door.player_entered.connect(_on_exit_door_player_entered)
	_exit_door.both_players_entered.connect(_on_exit_door_both_players_entered) # ADD THIS

func _on_exit_door_player_entered(_player: Node2D) -> void:
	# Warn player if gems missing
	if _gem_manager != null and not _gem_manager.is_unlocked():
		exit_locked.emit(_gem_manager.get_remaining_count(), _gem_manager.get_active_gem_element())
		return
	emit_signal("level_completed")

func _on_exit_door_both_players_entered() -> void:
	# Win level if gems done
	if _gem_manager != null and not _gem_manager.is_unlocked():
		return
		
	print("[Server] Both players at door. Level complete!")
	emit_signal("level_completed")
func attach_player(player: Node2D, spawn_idx: int = 1) -> void:
	var spawn_position: Vector2 = get_spawn_position() if spawn_idx == 1 else get_spawn_position_2()
	player.position = _players.to_local(spawn_position)
	_players.add_child(player)
	player.global_position = spawn_position
	
	if _gem_manager != null and _gem_manager.has_method("configure_for_player"):
		_gem_manager.configure_for_player(player)
		# NetworkManager.authoritative_player_snapshot_received.connect(_on_authoritative_player_snapshot_received)
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

func _on_hazard_zone_player_entered(player: Node2D) -> void:
	if player.get("is_local") == false:
		return
	player_failed.emit(player)


func _on_gem_progress_changed(collected: int, required: int) -> void:
	gem_progress_changed.emit(collected, required)
