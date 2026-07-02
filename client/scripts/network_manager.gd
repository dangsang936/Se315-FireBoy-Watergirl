# client/scripts/network_manager.gd
extends Node

const DEFAULT_SERVER_IP: String = "127.0.0.1"
const DEFAULT_PORT: int = 9999

signal connected_to_server
signal connection_failed
signal disconnected_from_server
signal role_assigned(role: int)
signal player_list_updated(players: Array[int])
signal remote_player_snapshot_received(player_id: int, snapshot: Dictionary, tick: int)
signal authoritative_player_snapshot_received(player_id: int, snapshot: Dictionary)
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
var hosted_server_pid: int = -1

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

func _snapshot_from_player_sync(packet: Dictionary) -> Dictionary:
	return {
		"ack_tick": int(packet.get("ack_tick", packet.get("t", current_tick))),
		"pos": packet.get("pos", packet.get("p", Vector2.ZERO)),
		"vel": packet.get("vel", packet.get("v", Vector2.ZERO)),
		"on_floor": bool(packet.get("on_floor", false)),
		"anim": String(packet.get("anim", packet.get("a", "idle"))),
		"flip_h": bool(packet.get("flip_h", false)),
	}

# LEGACY — do NOT call in authorized server mode.
# In authorized mode the server owns position; clients only send inputs via
# send_player_input().  send_snapshot() / relay_player_snapshot are kept
# solely for offline debug or listen-server legacy testing.
# send_snapshot() is only reachable from _send_network_state() which is
# itself gated by _LEGACY_SEND_SNAPSHOT_ENABLED = false in player.gd.
func send_snapshot(snapshot: Dictionary, tick: int) -> void:
	if not is_connected_to_server():
		return
	rpc_id(1, "relay_player_snapshot", multiplayer.get_unique_id(), snapshot, tick)

func send_player_input(packet: Dictionary) -> void:
	if not is_connected_to_server():
		return
	rpc_id(1, "rpc_submit_input", packet)

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

func send_collect_gem(gem_path: String) -> void:
	if not is_connected_to_server():
		return
	rpc_id(1, "rpc_request_collect_gem", gem_path)

func send_player_failed() -> void:
	if not is_connected_to_server():
		return
	rpc_id(1, "rpc_request_player_failed")

func send_level_completed() -> void:
	if not is_connected_to_server():
		return
	rpc_id(1, "rpc_request_level_completed")

func send_restart_level() -> void:
	if not is_connected_to_server():
		return
	rpc_id(1, "rpc_request_restart_level")

# ============================================================
# HOST ROOM
# ============================================================
signal room_created
signal room_creation_failed(reason: String)

func host_room(port: int = DEFAULT_PORT) -> void:
	_disconnect_host_room_result_signals()

	var start_error := _start_server_process(port)
	if start_error != OK:
		room_creation_failed.emit("Could not start local server: %s" % error_string(start_error))
		return

	await get_tree().create_timer(0.5).timeout
	_connect_host_room_result_signals()
	var connect_error := connect_to_server(DEFAULT_SERVER_IP, port)
	if connect_error != OK:
		_disconnect_host_room_result_signals()
		room_creation_failed.emit("Could not connect to local server: %s" % error_string(connect_error))

func start_game() -> void:
	if not is_connected_to_server():
		return
	rpc_id(1, "request_start_game")

func _start_server_process(port: int) -> Error:
	if hosted_server_pid > 0:
		return OK

	var server_project_path := _get_server_project_path()
	if not DirAccess.dir_exists_absolute(server_project_path):
		return ERR_FILE_NOT_FOUND

	var executable_path := OS.get_executable_path()
	var args := PackedStringArray([
		"--headless",
		"--path",
		server_project_path,
		"--port=%d" % port,
	])
	hosted_server_pid = OS.create_process(executable_path, args, false)
	if hosted_server_pid <= 0:
		hosted_server_pid = -1
		return FAILED
	return OK

func _get_server_project_path() -> String:
	var client_project_path := ProjectSettings.globalize_path("res://")
	return client_project_path.path_join("../server").simplify_path()

func _connect_host_room_result_signals() -> void:
	if not connected_to_server.is_connected(_on_host_room_connected):
		connected_to_server.connect(_on_host_room_connected, CONNECT_ONE_SHOT)
	if not connection_failed.is_connected(_on_host_room_connection_failed):
		connection_failed.connect(_on_host_room_connection_failed, CONNECT_ONE_SHOT)

func _disconnect_host_room_result_signals() -> void:
	if connected_to_server.is_connected(_on_host_room_connected):
		connected_to_server.disconnect(_on_host_room_connected)
	if connection_failed.is_connected(_on_host_room_connection_failed):
		connection_failed.disconnect(_on_host_room_connection_failed)

func _on_host_room_connected() -> void:
	_disconnect_host_room_result_signals()
	room_created.emit()

func _on_host_room_connection_failed() -> void:
	_disconnect_host_room_result_signals()
	room_creation_failed.emit("Local server did not accept the connection")

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

## Returns the best LAN IPv4 address of this machine.
## Skips loopback (127.x, ::1) and IPv6 addresses.
## Prefers private ranges: 192.168.x.x, 10.x.x.x, 172.16-31.x.x.
## Returns an empty string if no suitable address is found (master server
## will then fall back to the TCP source address).
func get_lan_ip() -> String:
	var addresses: PackedStringArray = IP.get_local_addresses()
	var best: String = ""
	for addr in addresses:
		# Skip IPv6 and loopback addresses
		if ":" in addr:
			continue
		if addr.begins_with("127."):
			continue
		# Check for private IPv4 ranges (prefer these)
		if addr.begins_with("192.168.") or addr.begins_with("10."):
			return addr  # Best match – return immediately
		# 172.16.0.0 – 172.31.255.255
		if addr.begins_with("172."):
			var parts := addr.split(".")
			if parts.size() == 4:
				var second := parts[1].to_int()
				if second >= 16 and second <= 31:
					return addr
		# Keep as fallback (public / other private IP on this machine)
		if best == "":
			best = addr
	return best

func register_room_to_master(room_name: String, port: int, use_lan: bool = false) -> void:
	var ip_to_send: String = get_lan_ip() if use_lan else ""
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

# ==================================================================
# LEGACY — LISTEN-SERVER MODEL (do NOT call from production UI)
# ==================================================================
# host_game_listen_server_legacy() turns the client itself into the
# ENet server (listen-server).  This conflicts with the team's
# authorized-server architecture where a dedicated server project is
# spawned by host_room() and both players connect to it as plain
# clients.  Keeping this function here only for reference / offline
# debugging.  No UI should call this in the main flow.
# Use host_room() instead.
# ==================================================================
func host_game_listen_server_legacy(room_name: String, port: int = DEFAULT_PORT, use_lan: bool = false) -> Error:
	if peer:
		_reset_connection_state(true)

	if not use_lan:
		setup_upnp(port)

	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, 2) 
	if error != OK:
		printerr("[NetworkManager][LEGACY] Failed to host server on port %d: %s" % [port, error_string(error)])
		_reset_connection_state(false)
		return error

	multiplayer.multiplayer_peer = peer
	
	if not multiplayer.peer_connected.is_connected(_on_client_peer_connected):
		multiplayer.peer_connected.connect(_on_client_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_client_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_client_peer_disconnected)

	print("[NetworkManager][LEGACY] Hosted listen-server on port %d" % port)
	
	my_role = 0
	connected_players.append(1)
	player_roles[1] = my_role
	is_host = true

	register_room_to_master(room_name, port, use_lan)

	connected_to_server.emit()
	role_assigned.emit(my_role)
	player_list_updated.emit(connected_players)
	return OK

func _on_client_peer_connected(id: int) -> void:
	if not is_host:
		return
	print("[NetworkManager] Peer connected to host: %d" % id)
	if not id in connected_players:
		connected_players.append(id)
	
	var role = 1
	player_roles[id] = role
	
	rpc_id(id, "receive_role_assignment", role)
	_broadcast_player_list()
	
	player_list_updated.emit(connected_players)
	
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

var _upnp_thread: Thread = null
var _upnp_instance: UPNP = null
var _upnp_mapped_port: int = 0

func setup_upnp(port: int) -> void:
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

# ==================================================================
# RPC DEFINITIONS
# ==================================================================

@rpc("authority", "call_remote", "reliable")
func receive_level_restart() -> void:
	restart_level_received.emit()

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

@rpc("any_peer", "call_remote", "reliable")
func request_role(role: int) -> void:
	if not is_connected_to_server():
		return
	rpc_id(1, "request_role", role)

@rpc("authority", "call_remote", "reliable")
func notify_game_start() -> void:
	var current_scene_path := "<none>"
	if get_tree().current_scene != null:
		current_scene_path = get_tree().current_scene.scene_file_path
	print("[Client] Game starting! peer=%d current_scene=%s" % [multiplayer.get_unique_id(), current_scene_path])
	game_started.emit()

@rpc("any_peer", "call_remote", "reliable")
func request_start_game() -> void:
	pass

@rpc("authority", "call_remote", "reliable")
func notify_peer_disconnected(peer_id: int) -> void:
	print("[Client] Peer disconnected: %d" % peer_id)
	if peer_id in connected_players:
		connected_players.erase(peer_id)
	player_roles.erase(peer_id)
	peer_disconnected.emit(peer_id)
	player_list_updated.emit(connected_players)

@rpc("authority", "call_remote", "unreliable_ordered")
func receive_player_snapshot(player_id: int, snapshot: Dictionary, tick: int) -> void:
	remote_player_snapshot_received.emit(player_id, snapshot, tick)

@rpc("authority", "call_remote", "unreliable_ordered")
func receive_authoritative_player_snapshot(player_id: int, snapshot: Dictionary) -> void:
	authoritative_player_snapshot_received.emit(player_id, snapshot)

@rpc("authority", "call_remote", "unreliable_ordered")
func receive_player_sync(packet: Dictionary) -> void:
	var player_id := int(packet.get("id", 0))
	if player_id == 0:
		return
	var snapshot := _snapshot_from_player_sync(packet)
	var tick := int(snapshot.get("ack_tick", packet.get("t", current_tick)))
	remote_player_snapshot_received.emit(player_id, snapshot, tick)
	if player_id == multiplayer.get_unique_id():
		authoritative_player_snapshot_received.emit(player_id, snapshot)

# Batched world snapshot — sent by the server at SNAPSHOT_SEND_RATE Hz instead
# of a separate receive_player_sync call per player per frame.
# packet = { "players": [ { "id", "t", "ack_tick", "pos", "vel", "on_floor",
#                            "anim", "flip_h" }, … ] }
@rpc("authority", "call_remote", "unreliable_ordered")
func receive_world_snapshot(packet: Dictionary) -> void:
	var my_id := multiplayer.get_unique_id()
	var entries: Array = packet.get("players", [])
	for entry in entries:
		var player_id := int(entry.get("id", 0))
		if player_id == 0:
			continue
		var snapshot := _snapshot_from_player_sync(entry)
		var tick := int(snapshot.get("ack_tick", entry.get("t", current_tick)))
		remote_player_snapshot_received.emit(player_id, snapshot, tick)
		if player_id == my_id:
			authoritative_player_snapshot_received.emit(player_id, snapshot)

# LEGACY — relay_player_snapshot is the old client-authoritative RPC where
# clients pushed their own position to be relayed to peers.  In authorized
# server mode the server never reads this; it only processes receive_player_input.
# Kept as a stub so existing RPC signatures remain valid.  No production code
# path calls this.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func relay_player_snapshot(_player_id: int, _snapshot: Dictionary, _tick: int) -> void:
	pass

@rpc("any_peer", "call_remote", "unreliable_ordered")
func rpc_submit_input(_packet: Dictionary) -> void:
	pass

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_collect_gem(_gem_path: String) -> void:
	pass

@rpc("authority", "call_local", "reliable")
func sync_collect_gem(gem_path: String) -> void:
	gem_collected_received.emit(gem_path)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_player_failed() -> void:
	pass

@rpc("authority", "call_local", "reliable")
func sync_player_failed() -> void:
	player_failed_received.emit()

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_level_completed() -> void:
	pass

@rpc("authority", "call_local", "reliable")
func sync_level_completed() -> void:
	level_completed_received.emit()

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_restart_level() -> void:
	pass

@rpc("authority", "call_local", "reliable")
func sync_restart_level() -> void:
	restart_level_received.emit()

@rpc("any_peer", "call_remote", "unreliable_ordered")
func relay_player_position(_player_id: int, _pos: Vector2) -> void:
	pass

@rpc("any_peer", "call_remote", "unreliable_ordered")
func relay_player_state(_player_id: int, _state: Dictionary) -> void:
	pass

@rpc("authority", "call_remote", "unreliable_ordered")
func receive_player_position(_player_id: int, _pos: Vector2) -> void:
	pass

@rpc("authority", "call_remote", "unreliable_ordered")
func receive_player_state(_player_id: int, _state: Dictionary) -> void:
	pass

@rpc("any_peer", "call_remote", "reliable")
func server_teleport_player(_pos: Vector2) -> void:
	pass

@rpc("any_peer", "call_remote", "reliable")
func server_stop_movement() -> void:
	pass
