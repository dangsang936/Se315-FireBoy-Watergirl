class_name GameManager
extends Node2D

enum GameState { BOOT, LOADING_LEVEL, PLAYING, PAUSED, WON, LOST, RESTARTING, DISCONNECTED }

@export var fireboy_scene: PackedScene
@export var watergirl_scene: PackedScene
@export var level_root_path: NodePath = ^"LevelRoot"
@export var hud_path: NodePath = ^"HUD"

var _state: GameState = GameState.BOOT
var _current_level: PrototypeLevel
var _player: CharacterBody2D
var _remote_player: CharacterBody2D
var _is_reloading: bool = false

@onready var _level_root: Node2D = get_node(level_root_path) as Node2D
@onready var _hud: PrototypeHUD = get_node(hud_path) as PrototypeHUD

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_hud.restart_requested.connect(_restart_level)
	_hud.resume_requested.connect(_resume_game)

	# Listen to network manager
	NetworkManager.peer_disconnected.connect(_on_peer_disconnected)
	NetworkManager.disconnected_from_server.connect(_on_disconnected_from_server)
	NetworkManager.remote_player_position_received.connect(_on_remote_position_received)
	NetworkManager.remote_player_state_received.connect(_on_remote_state_received)

	_load_level()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("restart"):
		_restart_level()
		get_viewport().set_input_as_handled()

func _load_level() -> void:
	if not level_scene or not fireboy_scene or not watergirl_scene:
		push_error("GameManager needs level_scene, fireboy_scene, and watergirl_scene.")
		return
	if _is_reloading:
		return

	_is_reloading = true
	get_tree().paused = false
	_set_state(GameState.LOADING_LEVEL)
	for child in _level_root.get_children():
		child.queue_free()

	await get_tree().process_frame

	_current_level = level_scene.instantiate() as PrototypeLevel
	_level_root.add_child(_current_level)
	_current_level.level_completed.connect(_on_level_completed)
	_current_level.player_failed.connect(_on_player_failed)
	_current_level.exit_locked.connect(_on_exit_locked)
	_current_level.gem_progress_changed.connect(_on_gem_progress_changed)
	_spawn_players()
	_is_reloading = false
	_set_state(GameState.PLAYING)

func _spawn_players() -> void:
	var my_role = NetworkManager.my_role
	if my_role == -1: my_role = 0 # Default if offline testing

	var is_fireboy = (my_role == 0)
	var local_scene = fireboy_scene if is_fireboy else watergirl_scene
	var remote_scene = watergirl_scene if is_fireboy else fireboy_scene
	
	# Spawn Local Player
	_player = local_scene.instantiate() as CharacterBody2D
	_current_level.attach_player(_player, 1 if is_fireboy else 2)
	if _player.has_method("reset_to_spawn"):
		_player.call("reset_to_spawn", _current_level.get_spawn_position() if is_fireboy else _current_level.get_spawn_position_2())
	
	# Spawn Remote Player if online
	if NetworkManager.is_connected_to_server():
		_remote_player = remote_scene.instantiate() as CharacterBody2D
		if _remote_player.get("is_local") != null:
			_remote_player.set("is_local", false)
		
		# Attach RemotePlayer logic component
		var remote_comp = RemotePlayer.new()
		remote_comp.name = "RemotePlayer"
		_remote_player.add_child(remote_comp)
		
		_current_level.attach_player(_remote_player, 2 if is_fireboy else 1)
		
		var spawn_pos = _current_level.get_spawn_position_2() if is_fireboy else _current_level.get_spawn_position()
		_remote_player.global_position = spawn_pos
		remote_comp.target_position = spawn_pos

func _toggle_pause() -> void:
	if _state == GameState.PLAYING:
		_set_state(GameState.PAUSED)
	elif _state == GameState.PAUSED:
		_set_state(GameState.PLAYING)

func _resume_game() -> void:
	if _state == GameState.PAUSED:
		_set_state(GameState.PLAYING)

func _restart_level() -> void:
	if _state == GameState.LOADING_LEVEL or _is_reloading:
		return
	get_tree().paused = false
	_set_player_control_enabled(false)
	_set_state(GameState.RESTARTING)
	call_deferred("_load_level")

func _on_level_completed() -> void:
	if _state != GameState.PLAYING:
		return
	_set_player_control_enabled(false)
	_set_state(GameState.WON)

func _on_player_failed(_player_node: Node2D) -> void:
	if _state != GameState.PLAYING:
		return
	_set_player_control_enabled(false)
	_set_state(GameState.LOST)

func _on_exit_locked(remaining: int, _gem_element: int) -> void:
	if _state != GameState.PLAYING:
		return
	_hud.show_status("Gate locked. Gems remaining: %s" % remaining, false)

func _on_gem_progress_changed(collected: int, required: int) -> void:
	_hud.set_gem_progress(collected, required)

func _on_peer_disconnected(peer_id: int) -> void:
	if _state == GameState.PLAYING:
		_set_state(GameState.DISCONNECTED)

func _on_disconnected_from_server() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/lobby.tscn")

func _on_remote_position_received(player_id: int, pos: Vector2) -> void:
	if _remote_player and _remote_player.has_node("RemotePlayer"):
		var rp = _remote_player.get_node("RemotePlayer")
		if rp.has_method("update_position"):
			rp.update_position(pos)

func _on_remote_state_received(player_id: int, state: Dictionary) -> void:
	if _remote_player and _remote_player.has_node("RemotePlayer"):
		var rp = _remote_player.get_node("RemotePlayer")
		if rp.has_method("update_state"):
			rp.update_state(state)

func _set_player_control_enabled(is_enabled: bool) -> void:
	if is_instance_valid(_player):
		if _player.has_method("set_control_enabled"):
			_player.call("set_control_enabled", is_enabled)
		else:
			_player.set_physics_process(is_enabled)

func _set_state(next_state: GameState) -> void:
	_state = next_state
	match _state:
		GameState.LOADING_LEVEL:
			get_tree().paused = false
			_set_player_control_enabled(false)
			_hud.set_paused(false)
			_hud.set_gem_progress(0, 0)
			_hud.show_status("Loading prototype...", false)
		GameState.PLAYING:
			get_tree().paused = false
			_set_player_control_enabled(true)
			_hud.set_paused(false)
			_hud.show_status("Reach the exit. Collect matching gems.", false)
		GameState.PAUSED:
			_hud.show_status("Paused", false)
			_hud.set_paused(true)
			get_tree().paused = true
		GameState.WON:
			get_tree().paused = false
			_set_player_control_enabled(false)
			_hud.set_paused(false)
			_hud.show_status("Level complete! Press R to restart.", true)
		GameState.LOST:
			get_tree().paused = false
			_set_player_control_enabled(false)
			_hud.set_paused(false)
			_hud.show_status("You fell into danger. Press R to restart.", true)
		GameState.RESTARTING:
			get_tree().paused = false
			_set_player_control_enabled(false)
			_hud.set_paused(false)
			_hud.show_status("Restarting...", false)
		GameState.DISCONNECTED:
			get_tree().paused = true
			_set_player_control_enabled(false)
			_hud.set_paused(false)
			_hud.show_status("Peer disconnected. Waiting to reconnect...", true)
		_:
			pass
