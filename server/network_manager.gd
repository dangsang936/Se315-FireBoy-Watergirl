# server/network_manager.gd
# Dedicated server using Godot's built-in ENetMultiplayerPeer
extends Node

const DEFAULT_PORT: int = 9999
const DEFAULT_MAX_PLAYERS: int = 2
const DEFAULT_MAP_SCENE_PATH: String = "res://shared/scenes/levels/prototype_level_physics.tscn"
const SERVER_PLAYER_COLLISION_LAYER: int = 2
const SERVER_PLAYER_COLLISION_MASK: int = 5
const SERVER_PLAYER_COLLISION_SIZE: Vector2 = Vector2(6, 18)
const SERVER_PLAYER_COLLISION_OFFSET: Vector2 = Vector2(6, -9)
const PlayerMovementConfigScript = preload("res://shared/scripts/multiplayer/movement/player_movement_config.gd")
const PlayerMovementStateScript = preload("res://shared/scripts/multiplayer/movement/player_movement_state.gd")
const PlayerMovementSimulator = preload("res://shared/scripts/multiplayer/movement/player_movement_simulator.gd")

var peer: ENetMultiplayerPeer = null
var connected_players: Array[int] = []
var player_roles: Dictionary = {}
var _authoritative_states: Dictionary = {}
var _movement_config: PlayerMovementConfig = PlayerMovementConfigScript.create_default()
var _server_tick_delta: float = 1.0 / 60.0
var port: int = DEFAULT_PORT
var max_players: int = DEFAULT_MAX_PLAYERS
var map_scene_path: String = DEFAULT_MAP_SCENE_PATH
var _loaded_map: Node2D = null
var _server_players: Dictionary = {}
var _pending_inputs: Dictionary = {}

func _ready() -> void:
	_parse_args()
	_load_authoritative_map()
	_start_server()

func _parse_args() -> void:
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--port="):
			var parsed_port := arg.get_slice("=", 1).to_int()
			if parsed_port > 0:
				port = parsed_port
		elif arg.begins_with("--max-players="):
			var parsed_max_players := arg.get_slice("=", 1).to_int()
			if parsed_max_players > 0:
				max_players = parsed_max_players
		elif arg.begins_with("--map="):
			var parsed_map := arg.get_slice("=", 1)
			if not parsed_map.is_empty():
				map_scene_path = parsed_map
		elif arg.begins_with("--tick-rate="):
			var parsed_tick_rate := arg.get_slice("=", 1).to_int()
			if parsed_tick_rate > 0:
				Engine.physics_ticks_per_second = parsed_tick_rate
				_server_tick_delta = 1.0 / float(parsed_tick_rate)

func _load_authoritative_map() -> void:
	var packed_scene := load(map_scene_path) as PackedScene
	if packed_scene == null:
		printerr("[Server] Failed to load map scene: %s" % map_scene_path)
		return

	_loaded_map = packed_scene.instantiate() as Node2D
	if _loaded_map == null:
		printerr("[Server] Map root is not Node2D: %s" % map_scene_path)
		return

	_loaded_map.name = "AuthoritativeMap"
	add_child(_loaded_map)
	print("[Server] Loaded authoritative map: %s" % map_scene_path)

func _start_server() -> void:
	peer = ENetMultiplayerPeer.new()
	peer.set_bind_ip("0.0.0.0")
	var error := peer.create_server(port, max_players)
	if error != OK:
		printerr("[Server] Failed to create server on port %d: %s" % [port, error_string(error)])
		return

	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	print("[Server] Server started on port %d (max %d players)" % [port, max_players])

func _on_peer_connected(id: int) -> void:
	connected_players.append(id)
	print("[Server] Player connected: %d (total: %d)" % [id, connected_players.size()])

	var role: int = 0 # Default to Fireboy
	if player_roles.values().has(0):
		role = 1 # Watergirl

	_assign_role(id, role)

	if connected_players.size() == max_players:
		print("[Server] Lobby full, waiting for host to start game")

func _on_peer_disconnected(id: int) -> void:
	connected_players.erase(id)
	player_roles.erase(id)
	_authoritative_states.erase(id)
	_pending_inputs.erase(id)
	var server_player := _server_players.get(id) as Node
	if server_player != null:
		server_player.queue_free()
	_server_players.erase(id)
	print("[Server] Player disconnected: %d (remaining: %d)" % [id, connected_players.size()])

	for pid in connected_players:
		rpc_id(pid, "notify_peer_disconnected", id)

	_broadcast_player_list()

func _broadcast_player_list() -> void:
	for pid in connected_players:
		rpc_id(pid, "receive_player_list", connected_players)
		rpc_id(pid, "receive_all_roles", player_roles)

func _broadcast_game_start() -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	print("[Server] Host started game; request_sender=%d connected_players=%s" % [sender_id, str(connected_players)])
	for pid in connected_players:
		print("[Server] notify_game_start -> peer %d" % pid)
		rpc_id(pid, "notify_game_start")

func _assign_role(peer_id: int, role: int) -> bool:
	if not connected_players.has(peer_id):
		return false
	if role < 0 or role > 1:
		return false
	if not _is_role_available_for_peer(role, peer_id):
		rpc_id(peer_id, "receive_role_assignment", player_roles.get(peer_id, -1))
		return false

	player_roles[peer_id] = role
	rpc_id(peer_id, "receive_role_assignment", role)
	print("[Server] Assigned role %d to player %d" % [role, peer_id])
	_broadcast_player_list()
	return true

func _is_role_available_for_peer(role: int, peer_id: int) -> bool:
	for existing_peer_id in player_roles:
		if existing_peer_id != peer_id and player_roles[existing_peer_id] == role:
			return false
	return true

# ------------------------------------------------------------------
# RPCs called ON clients (defined here so the server script compiles,
# but the real implementation lives in the client's network_manager).
# ------------------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func receive_role_assignment(_role: int) -> void:
	pass  # Implemented on clients

@rpc("authority", "call_remote", "reliable")
func receive_player_list(_players: Array) -> void:
	pass  # Implemented on clients

@rpc("authority", "call_remote", "reliable")
func receive_all_roles(_roles: Dictionary) -> void:
	pass

@rpc("authority", "call_remote", "reliable")
func notify_game_start() -> void:
	pass

@rpc("authority", "call_remote", "reliable")
func notify_peer_disconnected(_peer_id: int) -> void:
	pass

@rpc("any_peer", "call_remote", "reliable")
func request_role(role: int) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	_assign_role(sender_id, role)

@rpc("any_peer", "call_remote", "reliable")
func request_start_game() -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if not connected_players.has(sender_id):
		printerr("[Server] Ignoring start request from unknown peer %d" % sender_id)
		return
	if connected_players.size() < max_players:
		print("[Server] Start request ignored until all players join")
		return
	_broadcast_game_start()

@rpc("any_peer", "call_remote", "unreliable_ordered")
func relay_player_snapshot(player_id: int, snapshot: Dictionary, tick: int) -> void:
	for pid in connected_players:
		if pid != multiplayer.get_remote_sender_id():
			rpc_id(pid, "receive_player_snapshot", player_id, snapshot, tick)

@rpc("authority", "call_remote", "unreliable_ordered")
func receive_player_snapshot(_player_id: int, _snapshot: Dictionary, _tick: int) -> void:
	pass  # Implemented on clients

@rpc("authority", "call_remote", "reliable")
func receive_authoritative_player_snapshot(_player_id: int, _snapshot: Dictionary) -> void:
	pass

@rpc("any_peer", "call_remote", "reliable")
func receive_player_input(player_id: int, packet: Dictionary) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != player_id:
		printerr("[Server] Ignoring player input from %d for player %d" % [sender_id, player_id])
		return
	if not connected_players.has(player_id):
		return

	if not _server_players.has(player_id):
		var packet_position: Vector2 = packet.get("pos", Vector2.ZERO)
		var spawn_position := _get_spawn_position(player_id, packet_position)
		var body := _create_server_player(player_id, spawn_position)
		_server_players[player_id] = body

		var initial_state := PlayerMovementStateScript.new()
		initial_state.position = body.global_position
		initial_state.velocity = body.velocity
		initial_state.on_floor = body.is_on_floor()
		_authoritative_states[player_id] = initial_state

	_pending_inputs[player_id] = packet

func _physics_process(delta: float) -> void:
	for player_id in _server_players.keys():
		var body := _server_players[player_id] as CharacterBody2D
		if body == null:
			continue
		var packet: Dictionary = _pending_inputs.get(player_id, {})
		var previous_state := _authoritative_states.get(player_id) as PlayerMovementState
		if previous_state == null:
			previous_state = PlayerMovementStateScript.new()
			previous_state.position = body.global_position
			previous_state.velocity = body.velocity
			previous_state.on_floor = body.is_on_floor()
		var next_state := PlayerMovementSimulator.step(previous_state, packet, _movement_config, delta)
		_authoritative_states[player_id] = next_state
		body.global_position = next_state.position
		body.velocity = next_state.velocity
		body.move_and_slide()
		var ack_tick := int(packet.get("t", 0))
		_publish_authoritative_snapshot(player_id, body, ack_tick)

func _create_server_player(peer_id: int, initial_position: Vector2) -> CharacterBody2D:
	var body := CharacterBody2D.new()
	body.name = "ServerPlayer_%d" % peer_id
	body.collision_layer = SERVER_PLAYER_COLLISION_LAYER
	body.collision_mask = SERVER_PLAYER_COLLISION_MASK
	body.global_position = initial_position
	body.velocity = Vector2.ZERO

	var shape := CollisionShape2D.new()
	shape.position = SERVER_PLAYER_COLLISION_OFFSET
	var rectangle := RectangleShape2D.new()
	rectangle.size = SERVER_PLAYER_COLLISION_SIZE
	shape.shape = rectangle
	body.add_child(shape)
	add_child(body)
	print("[Server] Spawned authoritative player %d at %s" % [peer_id, str(initial_position)])
	return body

func _get_spawn_position(peer_id: int, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	if _loaded_map == null:
		return fallback

	var role := int(player_roles.get(peer_id, 0))
	var preferred_name := "PlayerSpawn2" if role == 1 else "PlayerSpawn"
	var preferred := _find_node_recursive(_loaded_map, preferred_name) as Node2D
	if preferred != null:
		return preferred.global_position

	var default_spawn := _find_node_recursive(_loaded_map, "PlayerSpawn") as Node2D
	if default_spawn != null:
		return default_spawn.global_position

	return fallback

func _find_node_recursive(root: Node, node_name: String) -> Node:
	return root.find_child(node_name, true, false)

func _simulate_server_player(body: CharacterBody2D, packet: Dictionary, delta: float) -> void:
	var input_dir: float = clampf(float(packet.get("x", 0.0)), -1.0, 1.0)
	var jump_pressed: bool = bool(packet.get("j", false))
	var down_pressed: bool = bool(packet.get("d", false))

	if absf(input_dir) > 0.0:
		body.velocity.x = move_toward(body.velocity.x, input_dir * _movement_config.max_speed, _movement_config.acceleration * delta)
	else:
		body.velocity.x = move_toward(body.velocity.x, 0.0, _movement_config.deceleration * delta)

	if not body.is_on_floor():
		body.velocity.y += _movement_config.gravity * delta
	elif jump_pressed:
		body.velocity.y = _movement_config.jump_velocity

	if down_pressed and not body.is_on_floor():
		body.velocity.y += _movement_config.gravity * delta * 0.5

	body.move_and_slide()

func _publish_authoritative_snapshot(player_id: int, body: CharacterBody2D, ack_tick: int) -> void:
	var state := PlayerMovementStateScript.new()
	state.position = body.global_position
	state.velocity = body.velocity
	state.on_floor = body.is_on_floor()
	_authoritative_states[player_id] = state

	var snapshot := state.to_snapshot(ack_tick)
	var sender_id := player_id
	if connected_players.has(player_id):
		rpc_id(sender_id, "receive_authoritative_player_snapshot", player_id, snapshot)
	for pid in connected_players:
		if pid != player_id:
			rpc_id(pid, "receive_player_snapshot", player_id, snapshot, ack_tick)

# --- Gameplay Event Relays ---

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_collect_gem(gem_path: String) -> void:
	rpc("sync_collect_gem", gem_path)

@rpc("authority", "call_local", "reliable")
func sync_collect_gem(_gem_path: String) -> void:
	pass

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_player_failed() -> void:
	rpc("sync_player_failed")

@rpc("authority", "call_local", "reliable")
func sync_player_failed() -> void:
	pass

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_level_completed() -> void:
	rpc("sync_level_completed")

@rpc("authority", "call_local", "reliable")
func sync_level_completed() -> void:
	pass

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_next_level(level_index: int) -> void:
	rpc("sync_next_level", level_index)

@rpc("authority", "call_local", "reliable")
func sync_next_level(_level_index: int) -> void:
	pass

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_restart_level() -> void:
	rpc("sync_restart_level")

@rpc("authority", "call_local", "reliable")
func sync_restart_level() -> void:
	pass

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_pressure_button_state(button_path: String, is_pressed: bool) -> void:
	rpc("sync_pressure_button_state", button_path, is_pressed)

@rpc("authority", "call_local", "reliable")
func sync_pressure_button_state(_button_path: String, _is_pressed: bool) -> void:
	pass

@rpc("any_peer", "call_remote", "unreliable_ordered")
func rpc_request_push_block_state(block_path: String, pos: Vector2, rot: float, linear_velocity: Vector2, angular_velocity: float) -> void:
	rpc("sync_push_block_state", block_path, pos, rot, linear_velocity, angular_velocity)

@rpc("authority", "call_local", "unreliable_ordered")
func sync_push_block_state(_block_path: String, _pos: Vector2, _rot: float, _linear_velocity: Vector2, _angular_velocity: float) -> void:
	pass
