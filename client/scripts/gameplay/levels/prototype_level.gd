class_name PrototypeLevel
extends Node2D

signal level_completed
signal player_failed(player: Node2D)

@export var players_path: NodePath = ^"Players"
@export var player_spawn_path: NodePath = ^"Players/PlayerSpawn"
@export var hazards_path: NodePath = ^"Hazards"
@export var hazard_zone_path: NodePath = ^"Hazards/HazardZone"
@export var exit_door_path: NodePath = ^"Goals/ExitDoor"

@onready var _players: Node2D = get_node(players_path) as Node2D
@onready var _player_spawn: Marker2D = get_node(player_spawn_path) as Marker2D
@onready var _hazards: Node2D = get_node_or_null(hazards_path) as Node2D
@onready var _hazard_zone: HazardZone = get_node_or_null(hazard_zone_path) as HazardZone
@onready var _exit_door: ExitDoor = get_node(exit_door_path) as ExitDoor


func _ready() -> void:
	_connect_hazards()
	_exit_door.player_entered.connect(_on_exit_door_player_entered)


func attach_player(player: Node2D) -> void:
	var spawn_position: Vector2 = get_spawn_position()
	player.position = _players.to_local(spawn_position)
	_players.add_child(player)
	player.global_position = spawn_position


func get_spawn_position() -> Vector2:
	return _player_spawn.global_position


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


func _on_hazard_zone_player_entered(player: Node2D) -> void:
	player_failed.emit(player)


func _on_exit_door_player_entered(_player: Node2D) -> void:
	level_completed.emit()
