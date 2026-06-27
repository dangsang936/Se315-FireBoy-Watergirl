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

func attach_player(player: Node2D, spawn_idx: int = 1) -> void:
	var spawn_position: Vector2 = get_spawn_position() if spawn_idx == 1 else get_spawn_position_2()
	player.position = _players.to_local(spawn_position)
	_players.add_child(player)
	player.global_position = spawn_position
	
	if _gem_manager != null:
		var p_element: int = 0
		if player.has_method("get_element"):
			p_element = int(player.call("get_element"))
		elif player.has_meta("element"):
			p_element = player.get_meta("element")
		elif "element" in player:
			p_element = int(player.get("element"))
			
		_gem_manager.configure_for_element(p_element)
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
	var prototype_player := player as PrototypePlayer
	if prototype_player and prototype_player.is_local:
		if NetworkManager.is_connected_to_server():
			NetworkManager.send_player_failed()
		else:
			player_failed.emit(player)

func _on_exit_door_player_entered(player: Node2D) -> void:
	if NetworkManager.is_connected_to_server():
		var players_inside = _exit_door.get_overlapping_bodies().filter(func(body): return body.is_in_group("player"))
		if players_inside.size() == 2:
			if not are_all_level_gems_collected():
				exit_locked.emit(1, 0)
				return
			NetworkManager.send_level_completed()
	else:
		if _gem_manager != null and not _gem_manager.is_unlocked():
			exit_locked.emit(_gem_manager.get_remaining_count(), _gem_manager.get_active_gem_element())
			return
		level_completed.emit()

func are_all_level_gems_collected() -> bool:
	if _gem_manager == null:
		return true
	for child in _gem_manager.get_children():
		var gem = child as CollectibleGem
		if gem and not gem._is_collected:
			return false
	return true

func _on_gem_progress_changed(collected: int, required: int) -> void:
	gem_progress_changed.emit(collected, required)
