class_name GameManager
extends Node2D

enum ManagerState { BOOT, LOADING_LEVEL, PLAYING, PAUSED, WON, LOST, RESTARTING, DISCONNECTED }

@export var level_scene: PackedScene
@export var level_scenes: Array[PackedScene] = []
@export var fireboy_scene: PackedScene
@export var watergirl_scene: PackedScene
@export var level_root_path: NodePath = ^"LevelRoot"
@export var hud_path: NodePath = ^"HUD"

const RemotePlayerScript: Script = preload("res://scripts/multiplayer/remote_player.gd")
const DEFAULT_LEVEL_SCENE: PackedScene = preload("res://scenes/levels/real_level_blank.tscn")
const DEFAULT_LEVEL_SCENE_2: PackedScene = preload("res://scenes/levels/real_level_blank_2.tscn")
const DEFAULT_FIREBOY_SCENE: PackedScene = preload("res://scenes/players/fireboy.tscn")
const DEFAULT_WATERGIRL_SCENE: PackedScene = preload("res://scenes/players/watergirl.tscn")

var _state: ManagerState = ManagerState.BOOT
var _current_level: Node2D
var _player: CharacterBody2D
var _remote_player: CharacterBody2D
var _is_reloading: bool = false
var _current_level_index: int = 0
var _pending_collected_gem_paths: Dictionary = {}
var player_nodes: Dictionary = {}

@onready var _level_root: Node2D = get_node(level_root_path) as Node2D
@onready var _hud: CanvasLayer = get_node(hud_path) as CanvasLayer

func _network_manager() -> Node:
	return get_node_or_null("/root/" + "Network" + "Manager")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if level_scenes.is_empty():
		level_scenes = [DEFAULT_LEVEL_SCENE, DEFAULT_LEVEL_SCENE_2]
	if level_scene == null:
		level_scene = level_scenes[_current_level_index]
	if fireboy_scene == null:
		fireboy_scene = DEFAULT_FIREBOY_SCENE
	if watergirl_scene == null:
		watergirl_scene = DEFAULT_WATERGIRL_SCENE
	_hud.restart_requested.connect(_on_restart_requested)
	_hud.resume_requested.connect(_resume_game)
	if _hud.has_signal("next_level_requested"):
		_hud.next_level_requested.connect(_on_next_level_requested)

	var network_manager := _network_manager()
	if network_manager != null:
		network_manager.peer_disconnected.connect(_on_peer_disconnected)
		network_manager.disconnected_from_server.connect(_on_disconnected_from_server)
		network_manager.remote_player_snapshot_received.connect(_on_remote_snapshot_received)

		network_manager.gem_collected_received.connect(_on_gem_collected_received)
		network_manager.player_failed_received.connect(_on_player_failed_received)
		network_manager.level_completed_received.connect(_on_level_completed_received)
		network_manager.restart_level_received.connect(_on_restart_level_received)
		network_manager.pressure_button_state_received.connect(_on_pressure_button_state_received)
		network_manager.push_block_state_received.connect(_on_push_block_state_received)

		network_manager.role_assigned.connect(_on_role_assigned)
		network_manager.player_list_updated.connect(_on_player_list_updated)
		network_manager.authoritative_player_snapshot_received.connect(_on_authoritative_player_snapshot_received)
		if network_manager.has_signal("next_level_received"):
			network_manager.next_level_received.connect(_on_next_level_received)
		# NetworkManager.authoritative_player_snapshot_received.connect(_on_authoritative_player_snapshot_received)

	if network_manager == null or not bool(network_manager.call("is_connected_to_server")) or int(network_manager.get("my_role")) == -1:
		call_deferred("_load_level")
	else:
		call_deferred("_load_level")

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
	var network_manager := _network_manager()
	if network_manager != null:
		network_manager.call("connect_to_server")

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
	var network_manager := _network_manager()
	if network_manager != null and bool(network_manager.call("is_connected_to_server")):
		network_manager.call("send_restart_level")
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
	_connect_pressure_buttons(_current_level)
	print("[GameManager] level_scene=%s instantiated=%s spawn=%s" % [
		level_scene.resource_path,
		_current_level.scene_file_path,
		_current_level.call("get_spawn_position") if _current_level.has_method("get_spawn_position") else Vector2.INF,
	])
	_spawn_players()
	await get_tree().process_frame
	_replay_pending_collected_gems()
	_is_reloading = false
	_set_state(ManagerState.PLAYING)

func _spawn_players() -> void:
	var network_manager := _network_manager()
	var my_role: int = int(network_manager.get("my_role")) if network_manager != null else -1
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
	var my_id = multiplayer.get_unique_id() if network_manager != null and bool(network_manager.call("is_connected_to_server")) else 1
	player_nodes[my_id] = _player
	
	_spawn_remote_player()

func _spawn_remote_player() -> void:
	var network_manager := _network_manager()
	if network_manager == null or not bool(network_manager.call("is_connected_to_server")) or is_instance_valid(_remote_player):
		return
	if int(network_manager.get("connected_players").size()) < 2:
		return
		
	var my_role: int = int(network_manager.get("my_role"))
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
	for pid in network_manager.get("connected_players"):
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

func _on_next_level_requested() -> void:
	if _state != ManagerState.WON:
		return
	_load_next_level(true)

func _load_next_level(should_relay: bool = false) -> void:
	if _current_level_index >= level_scenes.size() - 1:
		return
	_load_level_by_index(_current_level_index + 1, should_relay)

func _on_next_level_received(level_index: int) -> void:
	if _state == ManagerState.LOADING_LEVEL or _state == ManagerState.RESTARTING or _is_reloading:
		return
	_load_level_by_index(level_index, false)

func _load_level_by_index(level_index: int, should_relay: bool) -> void:
	if level_index < 0 or level_index >= level_scenes.size():
		push_warning("Invalid level index requested: %s" % level_index)
		return
	_current_level_index = level_index
	level_scene = level_scenes[level_index]
	var network_manager := _network_manager()
	if should_relay and network_manager != null and bool(network_manager.call("is_connected_to_server")):
		network_manager.call("send_next_level", level_index)
	get_tree().paused = false
	_set_player_control_enabled(false)
	_set_state(ManagerState.RESTARTING)
	call_deferred("_load_level")

func _has_next_level() -> bool:
	return _current_level_index < level_scenes.size() - 1

func _on_level_completed() -> void:
	if _state != ManagerState.PLAYING:
		return
	var network_manager := _network_manager()
	if network_manager != null and bool(network_manager.call("is_connected_to_server")):
		network_manager.call("send_level_completed")
	_set_player_control_enabled(false)
	_set_state(ManagerState.WON)

func _on_player_failed(_player_node: Node2D) -> void:
	if _state != ManagerState.PLAYING:
		return
	var network_manager := _network_manager()
	if network_manager != null:
		if bool(network_manager.call("is_connected_to_server")):
			network_manager.call("send_player_failed")
		network_manager.call("send_stop_movement")
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

func _on_remote_snapshot_received(player_id: int, snapshot: Dictionary, tick: int) -> void:
	if player_nodes.has(player_id):
		var p_node = player_nodes[player_id]
		if is_instance_valid(p_node) and p_node.has_node("RemotePlayer"):
			var rp = p_node.get_node("RemotePlayer")
			if rp.has_method("push_snapshot"):
				rp.push_snapshot(snapshot, tick)

func _on_authoritative_player_snapshot_received(player_id: int, snapshot: Dictionary) -> void:
	if not is_instance_valid(_player):
		return
	var network_manager := _network_manager()
	var my_id := multiplayer.get_unique_id() if network_manager != null and bool(network_manager.call("is_connected_to_server")) else 1
	if player_id != my_id:
		return
	if _player.has_method("apply_authoritative_snapshot"):
		_player.call("apply_authoritative_snapshot", snapshot)

# --- Reliable Gameplay Event RPC Listeners ---

func _on_gem_collected_received(gem_path: String) -> void:
	if gem_path == "":
		return
	if not is_instance_valid(_current_level):
		_pending_collected_gem_paths[gem_path] = true
		return
	_apply_collected_gem_path(gem_path)

func _apply_collected_gem_path(gem_path: String) -> void:
	var manager := _current_level.get_node_or_null("Collectibles") as GemManager
	if manager != null and manager.has_method("client_mark_collected_by_path"):
		manager.call("client_mark_collected_by_path", gem_path)
	var gem_node = _current_level.get_node_or_null(NodePath(gem_path))
	if gem_node and gem_node.has_method("collect_remotely"):
		gem_node.collect_remotely()

func _replay_pending_collected_gems() -> void:
	if not is_instance_valid(_current_level):
		return
	for gem_path in _pending_collected_gem_paths.keys():
		_apply_collected_gem_path(str(gem_path))
	_pending_collected_gem_paths.clear()

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

func _on_pressure_button_state_received(button_path: String, is_pressed: bool) -> void:
	if not is_instance_valid(_current_level):
		return
	var button := _current_level.get_node_or_null(NodePath(button_path)) as PressureButton
	if button == null or not button.has_method("apply_remote_pressed_state"):
		return
	button.call("apply_remote_pressed_state", is_pressed)

func _on_push_block_state_received(block_path: String, pos: Vector2, rot: float, linear_velocity: Vector2, angular_velocity: float) -> void:
	if not is_instance_valid(_current_level):
		return
	var block := _current_level.get_node_or_null(NodePath(block_path))
	if block == null or not block.has_method("apply_remote_state"):
		return
	block.call("apply_remote_state", pos, rot, linear_velocity, angular_velocity)

func _connect_pressure_buttons(root: Node) -> void:
	for child: Node in root.get_children():
		var button := child as PressureButton
		if button != null:
			button.pressed_state_changed.connect(_on_pressure_button_state_changed.bind(button))
		_connect_pressure_buttons(child)

func _on_pressure_button_state_changed(is_pressed: bool, button: PressureButton) -> void:
	var network_manager := _network_manager()
	if network_manager == null or not bool(network_manager.call("is_connected_to_server")):
		return
	if not is_instance_valid(_current_level) or not is_instance_valid(button):
		return
	var button_path := str(_current_level.get_path_to(button))
	network_manager.call("send_pressure_button_state", button_path, is_pressed)

func _set_player_control_enabled(is_enabled: bool) -> void:
	if is_instance_valid(_player):
		if _player.has_method("set_control_enabled"):
			_player.call("set_control_enabled", is_enabled)
		else:
			_player.set_physics_process(is_enabled)
			
	if not is_enabled:
		var network_manager := _network_manager()
		if network_manager != null:
			network_manager.call("send_stop_movement")

func _set_state(next_state: ManagerState) -> void:
	_state = next_state
	match _state:
		ManagerState.LOADING_LEVEL:
			get_tree().paused = false
			_set_player_control_enabled(false)
			_hud.set_paused(false)
			if _hud.has_method("hide_level_complete"):
				_hud.hide_level_complete()
			_hud.set_gem_progress(0, 0)
			_hud.show_status("Loading prototype...", false)
		ManagerState.PLAYING:
			get_tree().paused = false
			_set_player_control_enabled(true)
			_hud.set_paused(false)
			if _hud.has_method("hide_level_complete"):
				_hud.hide_level_complete()
			_hud.show_status("Reach the exit. Collect matching gems.", false)
		ManagerState.PAUSED:
			_hud.show_status("Paused", false)
			_hud.set_paused(true)
			get_tree().paused = true
		ManagerState.WON:
			get_tree().paused = false
			_set_player_control_enabled(false)
			_hud.set_paused(false)
			_hud.show_status("Level complete!", false)
			if _hud.has_method("show_level_complete"):
				_hud.show_level_complete(_has_next_level())
		ManagerState.LOST:
			get_tree().paused = false
			_set_player_control_enabled(false)
			_hud.set_paused(false)
			if _hud.has_method("hide_level_complete"):
				_hud.hide_level_complete()
			_hud.show_status("You fell into danger. Press R to restart.", true)
		ManagerState.RESTARTING:
			get_tree().paused = false
			_set_player_control_enabled(false)
			_hud.set_paused(false)
			if _hud.has_method("hide_level_complete"):
				_hud.hide_level_complete()
			_hud.show_status("Restarting...", false)
		ManagerState.DISCONNECTED:
			get_tree().paused = true
			_set_player_control_enabled(false)
			_hud.set_paused(false)
			if _hud.has_method("hide_level_complete"):
				_hud.hide_level_complete()
			_hud.show_status("Peer disconnected. Waiting to reconnect...", true)
		_:
			pass
