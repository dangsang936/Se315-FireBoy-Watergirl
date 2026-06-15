# client/scripts/network_manager.gd
# Client-side network manager using Godot's built-in ENetMultiplayerPeer
extends Node

const DEFAULT_SERVER_IP: String = "127.0.0.1"
const DEFAULT_PORT: int = 9999

signal connected_to_server
signal connection_failed
signal disconnected_from_server
signal role_assigned(role: int)
signal player_list_updated(players: Array[int])
signal remote_player_position_received(player_id: int, position: Vector2, tick: int)
signal remote_player_state_received(player_id: int, state: Dictionary, tick: int)
signal game_started
signal peer_disconnected(peer_id: int)
signal gem_collected_received(gem_path: String)
signal player_failed_received
signal level_completed_received
signal restart_level_received

var peer: ENetMultiplayerPeer = null
var my_role: int = -1
var server_ip: String = DEFAULT_SERVER_IP
var server_port: int = DEFAULT_PORT

var connected_players: Array[int] = []
var player_roles: Dictionary = {}
var current_tick: int = 0

func _physics_process(_delta: float) -> void:
	if is_connected_to_server():
		current_tick += 1

func _ready() -> void:
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--server-ip="):
			server_ip = arg.split("=")[1]
		elif arg.begins_with("--port="):
			server_port = int(arg.split("=")[1])

func connect_to_server(ip: String = "", port: int = 0) -> Error:
	if peer:
		_reset_connection_state(true)

	if ip != "":
		server_ip = ip
	if port > 0:
		server_port = port

	peer = ENetMultiplayerPeer.new()
	var error := peer.create_client(server_ip, server_port)
	if error != OK:
		printerr("[Client] Failed to connect to %s:%d – %s" % [server_ip, server_port, error_string(error)])
		_reset_connection_state(false)
		return error

	multiplayer.multiplayer_peer = peer
	if not multiplayer.connected_to_server.is_connected(_on_connected):
		multiplayer.connected_to_server.connect(_on_connected)
	if not multiplayer.server_disconnected.is_connected(_on_disconnected):
		multiplayer.server_disconnected.connect(_on_disconnected)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)

	print("[Client] Connecting to %s:%d …" % [server_ip, server_port])
	return OK

func disconnect_from_server() -> void:
	_reset_connection_state(true)
	disconnected_from_server.emit()

func _reset_connection_state(close_peer: bool = true) -> void:
	if peer:
		if close_peer:
			peer.close()
		peer = null
	multiplayer.multiplayer_peer = null
	my_role = -1
	connected_players.clear()
	player_roles.clear()
	current_tick = 0

func is_connected_to_server() -> bool:
	return peer != null and multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func _on_connected() -> void:
	print("[Client] Connected! Peer ID: %d" % multiplayer.get_unique_id())
	connected_to_server.emit()

func _on_disconnected() -> void:
	print("[Client] Disconnected from server")
	_reset_connection_state(false)
	disconnected_from_server.emit()

func _on_connection_failed() -> void:
	printerr("[Client] Connection failed")
	_reset_connection_state(false)
	connection_failed.emit()

@rpc("authority", "call_remote", "reliable")
func receive_role_assignment(role: int) -> void:
	my_role = role
	var role_name := "Fireboy" if role == 0 else "Watergirl"
	print("[Client] Role assigned: %s" % role_name)
	role_assigned.emit(role)

@rpc("authority", "call_remote", "reliable")
func receive_player_list(players: Array) -> void:
	var typed: Array[int] = []
	for p in players:
		typed.append(p as int)
	connected_players = typed
	player_list_updated.emit(typed)

@rpc("authority", "call_remote", "reliable")
func receive_all_roles(roles: Dictionary) -> void:
	player_roles = roles
	player_list_updated.emit(connected_players)

@rpc("authority", "call_remote", "reliable")
func notify_game_start() -> void:
	print("[Client] Game starting!")
	game_started.emit()

@rpc("authority", "call_remote", "reliable")
func notify_peer_disconnected(peer_id: int) -> void:
	print("[Client] Peer disconnected: %d" % peer_id)
	if peer_id in connected_players:
		connected_players.erase(peer_id)
	player_roles.erase(peer_id)
	peer_disconnected.emit(peer_id)
	player_list_updated.emit(connected_players)

@rpc("authority", "call_remote", "unreliable_ordered")
func receive_player_position(player_id: int, position: Vector2, tick: int) -> void:
	remote_player_position_received.emit(player_id, position, tick)

@rpc("authority", "call_remote", "unreliable_ordered")
func receive_player_state(player_id: int, state: Dictionary, tick: int) -> void:
	remote_player_state_received.emit(player_id, state, tick)

func send_position(position: Vector2, tick: int) -> void:
	if not is_connected_to_server():
		return
	rpc_id(1, "relay_player_position", multiplayer.get_unique_id(), position, tick)

func send_state(state: Dictionary, tick: int) -> void:
	if not is_connected_to_server():
		return
	rpc_id(1, "relay_player_state", multiplayer.get_unique_id(), state, tick)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func relay_player_position(_player_id: int, _position: Vector2, _tick: int) -> void:
	pass

@rpc("any_peer", "call_remote", "unreliable_ordered")
func relay_player_state(_player_id: int, _state: Dictionary, _tick: int) -> void:
	pass

# --- Reliable Gameplay Event RPCs ---

func send_collect_gem(gem_path: String) -> void:
	if not is_connected_to_server():
		return
	rpc_id(1, "rpc_request_collect_gem", gem_path)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_collect_gem(_gem_path: String) -> void:
	pass  # Server stub

@rpc("authority", "call_local", "reliable")
func sync_collect_gem(gem_path: String) -> void:
	gem_collected_received.emit(gem_path)

func send_player_failed() -> void:
	if not is_connected_to_server():
		return
	rpc_id(1, "rpc_request_player_failed")

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_player_failed() -> void:
	pass  # Server stub

@rpc("authority", "call_local", "reliable")
func sync_player_failed() -> void:
	player_failed_received.emit()

func send_level_completed() -> void:
	if not is_connected_to_server():
		return
	rpc_id(1, "rpc_request_level_completed")

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_level_completed() -> void:
	pass  # Server stub

@rpc("authority", "call_local", "reliable")
func sync_level_completed() -> void:
	level_completed_received.emit()

func send_restart_level() -> void:
	if not is_connected_to_server():
		return
	rpc_id(1, "rpc_request_restart_level")

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_restart_level() -> void:
	pass  # Server stub

@rpc("authority", "call_local", "reliable")
func sync_restart_level() -> void:
	restart_level_received.emit()
