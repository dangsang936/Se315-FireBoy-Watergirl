class_name GameManager
extends Node2D

enum ManagerState { BOOT, LOADING_LEVEL, PLAYING, PAUSED, WON, LOST, RESTARTING, DISCONNECTED }

@export var level_scene: PackedScene
@export var fireboy_scene: PackedScene
@export var watergirl_scene: PackedScene
@export var level_root_path: NodePath = ^"LevelRoot"
@export var hud_path: NodePath = ^"HUD"

var _state: ManagerState = ManagerState.BOOT
var _current_level: PrototypeLevel
var _player: CharacterBody2D
var _remote_player: CharacterBody2D
var _is_reloading: bool = false

@onready var _level_root: Node2D = get_node(level_root_path) as Node2D
@onready var _hud: PrototypeHUD = get_node(hud_path) as PrototypeHUD

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_hud.restart_requested.connect(_request_restart) # Changed this line
	_hud.resume_requested.connect(_resume_game)

	# Listen to network manager
	NetworkManager.peer_disconnected.connect(_on_peer_disconnected)
	NetworkManager.disconnected_from_server.connect(_on_disconnected_from_server)
	NetworkManager.remote_player_position_received.connect(_on_remote_position_received)
	NetworkManager.remote_player_state_received.connect(_on_remote_state_received)
	NetworkManager.player_sync_received.connect(_on_player_sync_received)

	NetworkManager.role_assigned.connect(_on_role_assigned)
	NetworkManager.player_list_updated.connect(_on_player_list_updated)
	NetworkManager.level_restart_requested.connect(_on_network_restart) # Added this line
	
	_show_connect_ui()

var _connect_ui_layer: CanvasLayer

func _show_connect_ui() -> void:
	_connect_ui_layer = CanvasLayer.new()
	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.7)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	bg.add_child(vbox)
	
	var lbl = Label.new()
	lbl.name = "StatusLabel"
	lbl.text = "Waiting for players..."
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lbl)
	
	var btn = Button.new()
	btn.name = "ConnectBtn"
	btn.text = "Connect to Server"
	btn.pressed.connect(_on_connect_button_pressed)
	vbox.add_child(btn)
	
	_connect_ui_layer.add_child(bg)
	add_child(_connect_ui_layer)

func _on_connect_button_pressed() -> void:
	if _connect_ui_layer.has_node("ColorRect/VBoxContainer/ConnectBtn"):
		var btn = _connect_ui_layer.get_node("ColorRect/VBoxContainer/ConnectBtn") as Button
		btn.disabled = true
	if _connect_ui_layer.has_node("ColorRect/VBoxContainer/StatusLabel"):
		var lbl = _connect_ui_layer.get_node("ColorRect/VBoxContainer/StatusLabel") as Label
		lbl.text = "Connecting..."
	NetworkManager.connect_to_server()

func _on_role_assigned(role: int) -> void:
	if is_instance_valid(_connect_ui_layer):
		_connect_ui_layer.queue_free()
	_load_level()

func _on_player_list_updated(players: Array) -> void:
	if _state == ManagerState.PLAYING and players.size() > 1 and not is_instance_valid(_remote_player):
		_spawn_remote_player()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("restart"):
		_request_restart() # Changed this line
		get_viewport().set_input_as_handled()

func _load_level() -> void:
	if not level_scene or not fireboy_scene or not watergirl_scene:
		push_error("GameManager needs level_scene, fireboy_scene, and watergirl_scene.")
		return
	if _is_reloading:
		return

	_is_reloading = true
	get_tree().paused = false
	_set_state(ManagerState.LOADING_LEVEL)
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
	_set_state(ManagerState.PLAYING)

func _spawn_players() -> void:
	var my_role = NetworkManager.my_role
	if my_role == -1: my_role = 0 # Default if offline testing

	var is_fireboy = (my_role == 0)
	var local_scene = fireboy_scene if is_fireboy else watergirl_scene
	var remote_scene = watergirl_scene if is_fireboy else fireboy_scene
	
	# Spawn Local Player (chỉ spawn 1 lần)
	if not is_instance_valid(_player):
		_player = local_scene.instantiate() as CharacterBody2D
		_current_level.attach_player(_player, 1 if is_fireboy else 2)
		if _player.has_method("reset_to_spawn"):
			_player.call("reset_to_spawn", _current_level.get_spawn_position() if is_fireboy else _current_level.get_spawn_position_2())
		if _player.get("is_local") != null:
			_player.set("is_local", true)
	
	_spawn_remote_player()

func _spawn_remote_player() -> void:
	if not NetworkManager.is_connected_to_server() or is_instance_valid(_remote_player):
		return
	if NetworkManager.connected_players.size() < 2:
		return
		
	var my_role = NetworkManager.my_role
	var is_fireboy = (my_role == 0)
	var remote_scene = watergirl_scene if is_fireboy else fireboy_scene
	
	_remote_player = remote_scene.instantiate() as CharacterBody2D
	if _remote_player.get("is_local") != null:
		_remote_player.set("is_local", false)
	if _remote_player.has_method("configure_remote_visual"):
		_remote_player.call("configure_remote_visual")

	# Attach RemotePlayer logic component
	var remote_comp = RemotePlayer.new()
	remote_comp.name = "RemotePlayer"
	_remote_player.add_child(remote_comp)
	
	_current_level.attach_player(_remote_player, 2 if is_fireboy else 1)
	
	var spawn_pos = _current_level.get_spawn_position_2() if is_fireboy else _current_level.get_spawn_position()
	_remote_player.global_position = spawn_pos
	remote_comp.target_position = spawn_pos

func _toggle_pause() -> void:
	if _state == ManagerState.PLAYING:
		_set_state(ManagerState.PAUSED)
	elif _state == ManagerState.PAUSED:
		_set_state(ManagerState.PLAYING)

func _resume_game() -> void:
	if _state == ManagerState.PAUSED:
		_set_state(ManagerState.PLAYING)

func _request_restart() -> void:
	NetworkManager.request_level_restart()

func _on_network_restart() -> void:
	_restart_level()


func _restart_level() -> void:
	if _state == ManagerState.LOADING_LEVEL or _is_reloading:
		return
	get_tree().paused = false
	_set_player_control_enabled(false)
	_set_state(ManagerState.RESTARTING)
	call_deferred("_load_level")


func _on_level_completed() -> void:
	if _state != ManagerState.PLAYING:
		return
	_set_player_control_enabled(false)
	_set_state(ManagerState.WON)

func _on_player_failed(_player_node: Node2D) -> void:
	if _state != ManagerState.PLAYING:
		return
	_set_player_control_enabled(false)
	_set_state(ManagerState.LOST)

func _on_exit_locked(remaining: int, _gem_element: int) -> void:
	if _state != ManagerState.PLAYING:
		return
	_hud.show_status("Gate locked. Gems remaining: %s" % remaining, false)

func _on_gem_progress_changed(collected: int, required: int) -> void:
	_hud.set_gem_progress(collected, required)

func _on_peer_disconnected(peer_id: int) -> void:
	if _state == ManagerState.PLAYING:
		_set_state(ManagerState.DISCONNECTED)

func _on_disconnected_from_server() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/lobby.tscn")

func _on_player_sync_received(packet: Dictionary) -> void:
	var sync_player_id := int(packet.get("id", 0))
	if sync_player_id == multiplayer.get_unique_id():
		if is_instance_valid(_player) and _player.has_method("apply_authoritative_sync"):
			_player.call("apply_authoritative_sync", packet)
		return

	var position: Vector2 = packet.get("p", Vector2.ZERO)
	var velocity: Vector2 = packet.get("v", Vector2.ZERO)
	var state := {
		"anim": str(packet.get("a", "idle")),
		"flip_h": velocity.x < 0.0
	}
	_on_remote_position_received(sync_player_id, position)
	_on_remote_state_received(sync_player_id, state)

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

func _set_state(next_state: ManagerState) -> void:
	_state = next_state
	match _state:
		ManagerState.LOADING_LEVEL:
			get_tree().paused = false
			_set_player_control_enabled(false)
			_hud.set_paused(false)
			_hud.set_gem_progress(0, 0)
			_hud.show_status("Loading prototype...", false)
		ManagerState.PLAYING:
			get_tree().paused = false
			_set_player_control_enabled(true)
			_hud.set_paused(false)
			_hud.show_status("Reach the exit. Collect matching gems.", false)
		ManagerState.PAUSED:
			_hud.show_status("Paused", false)
			_hud.set_paused(true)
			get_tree().paused = true
		ManagerState.WON:
			get_tree().paused = false
			_set_player_control_enabled(false)
			_hud.set_paused(false)
			_hud.show_status("Level complete! Press R to restart.", true)
		ManagerState.LOST:
			get_tree().paused = false
			_set_player_control_enabled(false)
			_hud.set_paused(false)
			_hud.show_status("You fell into danger. Press R to restart.", true)
		ManagerState.RESTARTING:
			get_tree().paused = false
			_set_player_control_enabled(false)
			_hud.set_paused(false)
			_hud.show_status("Restarting...", false)
		ManagerState.DISCONNECTED:
			get_tree().paused = true
			_set_player_control_enabled(false)
			_hud.set_paused(false)
			_hud.show_status("Peer disconnected. Waiting to reconnect...", true)
		_:
			pass
