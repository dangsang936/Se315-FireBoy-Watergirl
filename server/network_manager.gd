# server/network_manager.gd
# Dedicated server using Godot's built-in ENetMultiplayerPeer
extends Node

const PORT: int = 9999
const MAX_PLAYERS: int = 2

var peer: ENetMultiplayerPeer = null
var connected_players: Array[int] = []
var player_roles: Dictionary = {}

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

	var role: int = 0 # Default to Fireboy
	if player_roles.values().has(0):
		role = 1 # Watergirl

	player_roles[id] = role
	rpc_id(id, "receive_role_assignment", role)
	print("[Server] Assigned role %d to player %d" % [role, id])

	_broadcast_player_list()

	if connected_players.size() == MAX_PLAYERS:
		print("[Server] Lobby full, starting game!")
		for pid in connected_players:
			rpc_id(pid, "notify_game_start")

func _on_peer_disconnected(id: int) -> void:
	connected_players.erase(id)
	player_roles.erase(id)
	print("[Server] Player disconnected: %d (remaining: %d)" % [id, connected_players.size()])

	for pid in connected_players:
		rpc_id(pid, "notify_peer_disconnected", id)

	_broadcast_player_list()

func _broadcast_player_list() -> void:
	for pid in connected_players:
		rpc_id(pid, "receive_player_list", connected_players)
		rpc_id(pid, "receive_all_roles", player_roles)

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

# ------------------------------------------------------------------
# Relay RPCs – the server receives movement from one client and
# broadcasts it to the others.
# ------------------------------------------------------------------

@rpc("any_peer", "call_remote", "unreliable_ordered")
func relay_player_position(player_id: int, position: Vector2, tick: int) -> void:
	# Forward to all OTHER clients
	for pid in connected_players:
		if pid != multiplayer.get_remote_sender_id():
			rpc_id(pid, "receive_player_position", player_id, position, tick)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func relay_player_state(player_id: int, state: Dictionary, tick: int) -> void:
	for pid in connected_players:
		if pid != multiplayer.get_remote_sender_id():
			rpc_id(pid, "receive_player_state", player_id, state, tick)

@rpc("authority", "call_remote", "unreliable_ordered")
func receive_player_position(_player_id: int, _position: Vector2, _tick: int) -> void:
	pass  # Implemented on clients

@rpc("authority", "call_remote", "unreliable_ordered")
func receive_player_state(_player_id: int, _state: Dictionary, _tick: int) -> void:
	pass  # Implemented on clients

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
