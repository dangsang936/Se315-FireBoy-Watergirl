# server/network_manager.gd
# Dedicated server using Godot's built-in ENetMultiplayerPeer
extends Node

const DEFAULT_PORT: int = 9999
const DEFAULT_MAX_PLAYERS: int = 2
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

func _ready() -> void:
	_parse_args()
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
	if not _authoritative_states.has(player_id):
		var initial_state := PlayerMovementStateScript.new()
		initial_state.position = packet.get("pos", Vector2.ZERO)
		initial_state.velocity = packet.get("vel", Vector2.ZERO)
		initial_state.on_floor = packet.get("on_floor", false)
		_authoritative_states[player_id] = initial_state

	var state: PlayerMovementState = _authoritative_states[player_id]
	var next_state: PlayerMovementState = PlayerMovementSimulator.step(state, packet, _movement_config, _server_tick_delta)
	_authoritative_states[player_id] = next_state

	var ack_tick := int(packet.get("t", 0))
	var snapshot := next_state.to_snapshot(ack_tick)
	rpc_id(sender_id, "receive_authoritative_player_snapshot", player_id, snapshot)
	for pid in connected_players:
		if pid != sender_id:
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
func rpc_request_restart_level() -> void:
	rpc("sync_restart_level")

@rpc("authority", "call_local", "reliable")
func sync_restart_level() -> void:
	pass
