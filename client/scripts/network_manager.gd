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
signal remote_player_position_received(player_id: int, position: Vector2)
signal remote_player_state_received(player_id: int, state: Dictionary)
signal game_started
signal peer_disconnected(peer_id: int)

var peer: ENetMultiplayerPeer = null
var my_role: int = -1
var server_ip: String = DEFAULT_SERVER_IP
var server_port: int = DEFAULT_PORT

var connected_players: Array[int] = []
var player_roles: Dictionary = {}

func _ready() -> void:
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--server-ip="):
			server_ip = arg.split("=")[1]
		elif arg.begins_with("--port="):
			server_port = int(arg.split("=")[1])

func connect_to_server(ip: String = "", port: int = 0) -> Error:
	if ip != "":
		server_ip = ip
	if port > 0:
		server_port = port

	peer = ENetMultiplayerPeer.new()
	var error := peer.create_client(server_ip, server_port)
	if error != OK:
		printerr("[Client] Failed to connect to %s:%d – %s" % [server_ip, server_port, error_string(error)])
		return error

	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.server_disconnected.connect(_on_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)

	print("[Client] Connecting to %s:%d …" % [server_ip, server_port])
	return OK

func disconnect_from_server() -> void:
	if peer:
		peer.close()
		peer = null
	multiplayer.multiplayer_peer = null
	my_role = -1
	connected_players.clear()
	player_roles.clear()
	disconnected_from_server.emit()

func is_connected_to_server() -> bool:
	return peer != null and multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func _on_connected() -> void:
	print("[Client] Connected! Peer ID: %d" % multiplayer.get_unique_id())
	connected_to_server.emit()

func _on_disconnected() -> void:
	disconnected_from_server.emit()

func _on_connection_failed() -> void:
	printerr("[Client] Connection failed")
	disconnected_from_server.emit()

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
func receive_player_position(player_id: int, position: Vector2) -> void:
	remote_player_position_received.emit(player_id, position)

@rpc("authority", "call_remote", "unreliable_ordered")
func receive_player_state(player_id: int, state: Dictionary) -> void:
	remote_player_state_received.emit(player_id, state)

func send_position(position: Vector2) -> void:
	if not is_connected_to_server():
		return
	rpc_id(1, "relay_player_position", multiplayer.get_unique_id(), position)

func send_state(state: Dictionary) -> void:
	if not is_connected_to_server():
		return
	rpc_id(1, "relay_player_state", multiplayer.get_unique_id(), state)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func relay_player_position(_player_id: int, _position: Vector2) -> void:
	pass

@rpc("any_peer", "call_remote", "unreliable_ordered")
func relay_player_state(_player_id: int, _state: Dictionary) -> void:
	pass
