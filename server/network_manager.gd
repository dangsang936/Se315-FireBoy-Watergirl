# server/network_manager.gd
# Dedicated server using Godot's built-in ENetMultiplayerPeer
extends Node

const PORT: int = 9999
const MAX_PLAYERS: int = 2

var peer: ENetMultiplayerPeer = null
var connected_players: Array[int] = []

func _ready() -> void:
	_start_server()

func _start_server() -> void:
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_server(PORT, MAX_PLAYERS)
	if error != OK:
		printerr("[Server] Failed to create server on port %d: %s" % [PORT, error_string(error)])
		return

	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	print("[Server] Server started on port %d (max %d players)" % [PORT, MAX_PLAYERS])

func _on_peer_connected(id: int) -> void:
	connected_players.append(id)
	print("[Server] Player connected: %d (total: %d)" % [id, connected_players.size()])

	_broadcast_player_list()

	var role: int = connected_players.find(id)
	rpc_id(id, "receive_role_assignment", role)
	print("[Server] Assigned role %d to player %d" % [role, id])

func _on_peer_disconnected(id: int) -> void:
	connected_players.erase(id)
	print("[Server] Player disconnected: %d (remaining: %d)" % [id, connected_players.size()])
	_broadcast_player_list()

func _broadcast_player_list() -> void:
	for pid in connected_players:
		rpc_id(pid, "receive_player_list", connected_players)

@rpc("authority", "call_remote", "reliable")
func receive_role_assignment(_role: int) -> void:
	pass

@rpc("authority", "call_remote", "reliable")
func receive_player_list(_players: Array) -> void:
	pass

@rpc("any_peer", "call_remote", "unreliable_ordered")
func relay_player_position(player_id: int, position: Vector2) -> void:
	for pid in connected_players:
		if pid != multiplayer.get_remote_sender_id():
			rpc_id(pid, "receive_player_position", player_id, position)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func relay_player_state(player_id: int, state: Dictionary) -> void:
	for pid in connected_players:
		if pid != multiplayer.get_remote_sender_id():
			rpc_id(pid, "receive_player_state", player_id, state)

@rpc("authority", "call_remote", "unreliable_ordered")
func receive_player_position(_player_id: int, _position: Vector2) -> void:
	pass

@rpc("authority", "call_remote", "unreliable_ordered")
func receive_player_state(_player_id: int, _state: Dictionary) -> void:
	pass
