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
signal remote_player_snapshot_received(player_id: int, snapshot: Dictionary, tick: int)
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

# Master Server & Matchmaking Variables
const MASTER_SERVER_URL: String = "http://127.0.0.1:8080"
var is_host: bool = false
var current_room_id: String = ""
var heartbeat_timer: Timer = null

signal rooms_list_received(rooms: Array)
signal upnp_status(success: bool, external_ip: String)

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
	if is_host:
		unregister_room()
		cleanup_upnp()
		is_host = false
	
	if multiplayer.peer_connected.is_connected(_on_client_peer_connected):
		multiplayer.peer_connected.disconnect(_on_client_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_client_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_client_peer_disconnected)

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

@rpc("authority", "call_remote", "unreliable_ordered")
func receive_player_snapshot(player_id: int, snapshot: Dictionary, tick: int) -> void:
	remote_player_snapshot_received.emit(player_id, snapshot, tick)

func send_position(position: Vector2, tick: int) -> void:
	if not is_connected_to_server():
		return
	rpc_id(1, "relay_player_position", multiplayer.get_unique_id(), position, tick)

func send_state(state: Dictionary, tick: int) -> void:
	if not is_connected_to_server():
		return
	rpc_id(1, "relay_player_state", multiplayer.get_unique_id(), state, tick)

func send_snapshot(snapshot: Dictionary, tick: int) -> void:
	if not is_connected_to_server():
		return
	rpc_id(1, "relay_player_snapshot", multiplayer.get_unique_id(), snapshot, tick)

func send_stop_movement() -> void:
	if not is_connected_to_server():
		return
	var stop_snapshot := {
		"pos": Vector2.ZERO,
		"vel": Vector2.ZERO,
		"anim": "idle",
		"flip_h": false,
	}
	rpc_id(1, "relay_player_snapshot", multiplayer.get_unique_id(), stop_snapshot, current_tick)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func relay_player_position(_player_id: int, _position: Vector2, _tick: int) -> void:
	pass

@rpc("any_peer", "call_remote", "unreliable_ordered")
func relay_player_state(_player_id: int, _state: Dictionary, _tick: int) -> void:
	pass

@rpc("any_peer", "call_remote", "unreliable_ordered")
func relay_player_snapshot(_player_id: int, _snapshot: Dictionary, _tick: int) -> void:
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

# --- Master Server HTTP API Helpers ---

func _send_api_request(endpoint: String, method: int, body: Dictionary, callback: Callable) -> void:
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(func(result: int, response_code: int, headers: PackedStringArray, response_body: PackedByteArray):
		var response_data = {}
		if response_code == 200 or response_code == 201:
			var json = JSON.new()
			if json.parse(response_body.get_string_from_utf8()) == OK:
				if json.data is Dictionary or json.data is Array:
					response_data = json.data
		callback.call(response_code, response_data)
		http_request.queue_free()
	)
	var headers = ["Content-Type: application/json"]
	var query = JSON.stringify(body) if body.size() > 0 else ""
	var err = http_request.request(MASTER_SERVER_URL + endpoint, headers, method, query)
	if err != OK:
		printerr("[NetworkManager] HTTP Request error: ", err)
		callback.call(500, {})
		http_request.queue_free()

func fetch_rooms() -> void:
	_send_api_request("/api/rooms", HTTPClient.METHOD_GET, {}, func(status: int, response: Dictionary):
		if status == 200:
			var rooms = response.get("rooms", [])
			rooms_list_received.emit(rooms)
		else:
			print("[NetworkManager] Failed to fetch rooms from master server, status: ", status)
			rooms_list_received.emit([])
	)

func register_room_to_master(room_name: String, port: int, use_lan: bool = false) -> void:
	var ip_to_send = "127.0.0.1" if use_lan else ""
	var body = {
		"name": room_name,
		"port": port,
		"ip": ip_to_send
	}
	_send_api_request("/api/rooms/create", HTTPClient.METHOD_POST, body, func(status: int, response: Dictionary):
		if status == 201:
			current_room_id = response.get("room_id", "")
			print("[NetworkManager] Room registered on Master Server! ID: ", current_room_id)
			_start_heartbeat_loop()
		else:
			print("[NetworkManager] Failed to register room on Master Server. Status: ", status)
	)

func _start_heartbeat_loop() -> void:
	if heartbeat_timer:
		heartbeat_timer.queue_free()
	heartbeat_timer = Timer.new()
	heartbeat_timer.wait_time = 10.0
	heartbeat_timer.timeout.connect(_send_heartbeat)
	add_child(heartbeat_timer)
	heartbeat_timer.start()

func _send_heartbeat() -> void:
	if current_room_id == "":
		return
	var body = {
		"room_id": current_room_id,
		"players": connected_players.size()
	}
	_send_api_request("/api/rooms/heartbeat", HTTPClient.METHOD_POST, body, func(status: int, response: Dictionary):
		if status != 200:
			print("[NetworkManager] Heartbeat failed, status: ", status)
	)

func unregister_room() -> void:
	if current_room_id == "":
		return
	var body = {
		"room_id": current_room_id
	}
	_send_api_request("/api/rooms/remove", HTTPClient.METHOD_DELETE, body, func(status: int, response: Dictionary):
		print("[NetworkManager] Room unregistered, status: ", status)
	)
	current_room_id = ""
	if heartbeat_timer:
		heartbeat_timer.stop()
		heartbeat_timer.queue_free()
		heartbeat_timer = null

func request_matchmake(callback: Callable) -> void:
	_send_api_request("/api/rooms/matchmake", HTTPClient.METHOD_POST, {}, callback)

# --- ENet Listen Server (Host Mode) ---

func host_game(room_name: String, port: int = DEFAULT_PORT, use_lan: bool = false) -> Error:
	if peer:
		_reset_connection_state(true)

	if not use_lan:
		setup_upnp(port)

	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, 2) # Max 2 players
	if error != OK:
		printerr("[NetworkManager] Failed to host server on port %d: %s" % [port, error_string(error)])
		_reset_connection_state(false)
		return error

	multiplayer.multiplayer_peer = peer
	
	if not multiplayer.peer_connected.is_connected(_on_client_peer_connected):
		multiplayer.peer_connected.connect(_on_client_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_client_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_client_peer_disconnected)

	print("[NetworkManager] Hosted server on port %d" % port)
	
	# Host is Fireboy (role 0) by default in client-hosted lobby
	my_role = 0
	connected_players.append(1) # Host ID in multiplayer is always 1
	player_roles[1] = my_role
	is_host = true

	# Register on Master Server
	register_room_to_master(room_name, port, use_lan)

	connected_to_server.emit() # Notify UI we are connected (hosting)
	role_assigned.emit(my_role)
	player_list_updated.emit(connected_players)
	return OK

func _on_client_peer_connected(id: int) -> void:
	if not is_host:
		return
	print("[NetworkManager] Peer connected to host: %d" % id)
	if not id in connected_players:
		connected_players.append(id)
	
	# Assign the remaining role (Watergirl = 1)
	var role = 1
	player_roles[id] = role
	
	# Send assignments to peer
	rpc_id(id, "receive_role_assignment", role)
	_broadcast_player_list()
	
	# Notify UI
	player_list_updated.emit(connected_players)
	
	# Start game if full
	if connected_players.size() == 2:
		print("[NetworkManager] Lobby full! Starting game...")
		game_started.emit()
		for pid in connected_players:
			if pid != 1:
				rpc_id(pid, "notify_game_start")

func _on_client_peer_disconnected(id: int) -> void:
	if not is_host:
		return
	print("[NetworkManager] Peer disconnected from host: %d" % id)
	connected_players.erase(id)
	player_roles.erase(id)
	
	for pid in connected_players:
		if pid != 1:
			rpc_id(pid, "notify_peer_disconnected", id)
			
	_broadcast_player_list()
	peer_disconnected.emit(id)
	player_list_updated.emit(connected_players)

func _broadcast_player_list() -> void:
	if not is_host:
		return
	for pid in connected_players:
		if pid != 1:
			rpc_id(pid, "receive_player_list", connected_players)
			rpc_id(pid, "receive_all_roles", player_roles)

# --- UPnP Helper ---

var _upnp_thread: Thread = null
var _upnp_instance: UPNP = null
var _upnp_mapped_port: int = 0

func setup_upnp(port: int) -> void:
	# Chạy UPnP trên thread riêng để tránh freeze game
	if _upnp_thread and _upnp_thread.is_started():
		_upnp_thread.wait_to_finish()
	_upnp_mapped_port = port
	_upnp_thread = Thread.new()
	_upnp_thread.start(_upnp_thread_func.bind(port))

func _upnp_thread_func(port: int) -> void:
	var upnp = UPNP.new()
	upnp.discover_multicast_if = "0.0.0.0"
	upnp.discover_local_only = false

	var err = upnp.discover(2000, 2, "InternetGatewayDevice")
	if err != UPNP.UPNP_RESULT_SUCCESS:
		call_deferred("_upnp_completed", false, "", null)
		return

	var gateway = upnp.get_gateway()
	if not gateway or not gateway.is_valid_gateway():
		call_deferred("_upnp_completed", false, "", null)
		return

	# Map cả UDP và TCP cho ENet
	var map_result_udp = upnp.add_port_mapping(port, port, "FireBoyWaterGirl UDP", "UDP")
	var map_result_tcp = upnp.add_port_mapping(port, port, "FireBoyWaterGirl TCP", "TCP")

	if map_result_udp != UPNP.UPNP_RESULT_SUCCESS and map_result_tcp != UPNP.UPNP_RESULT_SUCCESS:
		call_deferred("_upnp_completed", false, "", null)
		return

	var ext_ip = upnp.query_external_address()
	call_deferred("_upnp_completed", true, ext_ip, upnp)

func _upnp_completed(success: bool, ext_ip: String, upnp_ref: UPNP) -> void:
	if _upnp_thread and _upnp_thread.is_started():
		_upnp_thread.wait_to_finish()
	_upnp_thread = null

	if success:
		_upnp_instance = upnp_ref
		print("[UPnP] Port mapped! External IP: ", ext_ip)
	else:
		_upnp_instance = null
		print("[UPnP] Failed – hosting will still work on LAN")

	upnp_status.emit(success, ext_ip)

func cleanup_upnp() -> void:
	if _upnp_instance and _upnp_mapped_port > 0:
		_upnp_instance.delete_port_mapping(_upnp_mapped_port, "UDP")
		_upnp_instance.delete_port_mapping(_upnp_mapped_port, "TCP")
		print("[UPnP] Port mappings removed")
	_upnp_instance = null
	_upnp_mapped_port = 0

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		cleanup_upnp()
		if _upnp_thread and _upnp_thread.is_started():
			_upnp_thread.wait_to_finish()

