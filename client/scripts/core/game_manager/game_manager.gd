class_name GameManager
extends Node2D

enum ManagerState { BOOT, LOADING_LEVEL, PLAYING, PAUSED, WON, LOST, RESTARTING, DISCONNECTED }

@export var level_scene: PackedScene
@export var fireboy_scene: PackedScene
@export var watergirl_scene: PackedScene
@export var level_root_path: NodePath = ^"LevelRoot"
@export var hud_path: NodePath = ^"HUD"

const RemotePlayerScript: Script = preload("res://scripts/multiplayer/remote_player.gd")

var _state: ManagerState = ManagerState.BOOT
var _current_level: Node2D
var _player: CharacterBody2D
var _remote_player: CharacterBody2D
var _is_reloading: bool = false
var player_nodes: Dictionary = {}

@onready var _level_root: Node2D = get_node(level_root_path) as Node2D
@onready var _hud: CanvasLayer = get_node(hud_path) as CanvasLayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_hud.restart_requested.connect(_on_restart_requested)
	_hud.resume_requested.connect(_resume_game)

	# Listen to network manager
	NetworkManager.peer_disconnected.connect(_on_peer_disconnected)
	NetworkManager.disconnected_from_server.connect(_on_disconnected_from_server)
	NetworkManager.remote_player_position_received.connect(_on_remote_position_received)
	NetworkManager.remote_player_state_received.connect(_on_remote_state_received)
	NetworkManager.remote_player_snapshot_received.connect(_on_remote_snapshot_received)

	# Listen to reliable gameplay RPC signals
	NetworkManager.gem_collected_received.connect(_on_gem_collected_received)
	NetworkManager.player_failed_received.connect(_on_player_failed_received)
	NetworkManager.level_completed_received.connect(_on_level_completed_received)
	NetworkManager.restart_level_received.connect(_on_restart_level_received)

	NetworkManager.role_assigned.connect(_on_role_assigned)
	NetworkManager.player_list_updated.connect(_on_player_list_updated)
	
	if NetworkManager.is_connected_to_server() and NetworkManager.my_role != -1:
		_load_level()
	else:
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
		_on_restart_requested()
		get_viewport().set_input_as_handled()

func _on_restart_requested() -> void:
	if NetworkManager.is_connected_to_server():
		NetworkManager.send_restart_level()
	else:
		_restart_level()

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

	player_nodes.clear()
	_player = null
	_remote_player = null

	_current_level = level_scene.instantiate() as Node2D
	_current_level.level_completed.connect(_on_level_completed)
	_current_level.player_failed.connect(_on_player_failed)
	_current_level.exit_locked.connect(_on_exit_locked)
	_current_level.gem_progress_changed.connect(_on_gem_progress_changed)
	_level_root.add_child(_current_level)
	_spawn_players()
	_is_reloading = false
	_set_state(ManagerState.PLAYING)

func _spawn_players() -> void:
	var my_role = NetworkManager.my_role
	if my_role == -1: my_role = 0 # Default if offline testing

	var is_fireboy = (my_role == 0)
	var local_scene = fireboy_scene if is_fireboy else watergirl_scene
	
	# Spawn Local Player (chỉ spawn 1 lần)
	if not is_instance_valid(_player):
		_player = local_scene.instantiate() as CharacterBody2D
		_current_level.attach_player(_player, 1 if is_fireboy else 2)
		if _player.has_method("reset_to_spawn"):
			_player.call("reset_to_spawn", _current_level.get_spawn_position() if is_fireboy else _current_level.get_spawn_position_2())
		
		if _player.get("is_local") != null:
			_player.set("is_local", true)
		var my_id = multiplayer.get_unique_id() if NetworkManager.is_connected_to_server() else 1
		player_nodes[my_id] = _player
	
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
	
	# Attach RemotePlayer logic component
	var remote_comp = RemotePlayerScript.new()
	remote_comp.name = "RemotePlayer"
	_remote_player.add_child(remote_comp)
	
	_current_level.attach_player(_remote_player, 2 if is_fireboy else 1)
	
	var spawn_pos = _current_level.get_spawn_position_2() if is_fireboy else _current_level.get_spawn_position()
	_remote_player.global_position = spawn_pos
	remote_comp.target_position = spawn_pos

	var remote_id = -1
	for pid in NetworkManager.connected_players:
		if pid != multiplayer.get_unique_id():
			remote_id = pid
			break
	if remote_id != -1:
		player_nodes[remote_id] = _remote_player

func _toggle_pause() -> void:
	if _state == ManagerState.PLAYING:
		_set_state(ManagerState.PAUSED)
	elif _state == ManagerState.PAUSED:
		_set_state(ManagerState.PLAYING)

func _resume_game() -> void:
	if _state == ManagerState.PAUSED:
		_set_state(ManagerState.PLAYING)

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
	NetworkManager.send_stop_movement() # NEW LINE
	_set_player_control_enabled(false)
	_set_state(ManagerState.LOST)

func _on_exit_locked(remaining: int, _gem_element: int) -> void:
	if _state != ManagerState.PLAYING:
		return
	_hud.show_status("Gate locked. Gems remaining: %s" % remaining, false)

func _on_gem_progress_changed(collected: int, required: int) -> void:
	_hud.set_gem_progress(collected, required)

func _on_peer_disconnected(peer_id: int) -> void:
	_clear_remote_player(peer_id)
	if _state == ManagerState.PLAYING:
		_set_state(ManagerState.DISCONNECTED)

func _on_disconnected_from_server() -> void:
	_clear_multiplayer_players()
	get_tree().change_scene_to_file("res://scenes/ui/lobby.tscn")

func _clear_remote_player(peer_id: int = -1) -> void:
	if peer_id != -1:
		player_nodes.erase(peer_id)
	if is_instance_valid(_remote_player):
		_remote_player.queue_free()
	_remote_player = null

func _clear_multiplayer_players() -> void:
	_clear_remote_player()
	player_nodes.clear()
	if is_instance_valid(_player):
		_player.queue_free()
	_player = null

func _on_remote_position_received(player_id: int, pos: Vector2, tick: int) -> void:
	if player_nodes.has(player_id):
		var p_node = player_nodes[player_id]
		if is_instance_valid(p_node) and p_node.has_node("RemotePlayer"):
			var rp = p_node.get_node("RemotePlayer")
			if rp.has_method("update_position"):
				rp.update_position(pos, tick)

func _on_remote_state_received(player_id: int, state: Dictionary, tick: int) -> void:
	if player_nodes.has(player_id):
		var p_node = player_nodes[player_id]
		if is_instance_valid(p_node) and p_node.has_node("RemotePlayer"):
			var rp = p_node.get_node("RemotePlayer")
			if rp.has_method("update_state"):
				rp.update_state(state, tick)

func _on_remote_snapshot_received(player_id: int, snapshot: Dictionary, tick: int) -> void:
	if player_nodes.has(player_id):
		var p_node = player_nodes[player_id]
		if is_instance_valid(p_node) and p_node.has_node("RemotePlayer"):
			var rp = p_node.get_node("RemotePlayer")
			if rp.has_method("push_snapshot"):
				rp.push_snapshot(snapshot, tick)

# --- Reliable Gameplay Event RPC Listeners ---

func _on_gem_collected_received(gem_path: String) -> void:
	var gem_node = get_node_or_null(gem_path)
	if gem_node and gem_node.has_method("collect_remotely"):
		gem_node.collect_remotely()

func _on_player_failed_received() -> void:
	if _state != ManagerState.PLAYING:
		return
	_set_player_control_enabled(false)
	_set_state(ManagerState.LOST)

func _on_level_completed_received() -> void:
	if _state != ManagerState.PLAYING:
		return
	_set_player_control_enabled(false)
	_set_state(ManagerState.WON)

func _on_restart_level_received() -> void:
	_restart_level()

func _set_player_control_enabled(is_enabled: bool) -> void:
	if is_instance_valid(_player):
		if _player.has_method("set_control_enabled"):
			_player.call("set_control_enabled", is_enabled)
		else:
			_player.set_physics_process(is_enabled)
			
	if not is_enabled:
		NetworkManager.send_stop_movement() # Make sure server stop

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
