# server/network_manager.gd
extends Node

const DEFAULT_PORT: int = 9999
const MAX_PLAYERS: int = 2

const PLAYER_SPEED: float = 105.0
const PLAYER_JUMP_VELOCITY: float = -220.0
const PLAYER_ACCELERATION: float = 1700.0
const PLAYER_DECELERATION: float = 1100.0
const PLAYER_AIR_ACCELERATION: float = 1200.0
const PLAYER_AIR_DECELERATION: float = 480.0
const PLAYER_RUN_JUMP_HEIGHT_MULTIPLIER: float = 1.05
const PLAYER_GRAVITY_SCALE: float = 0.46
const PLAYER_COYOTE_TIME: float = 0.08
const PLAYER_JUMP_BUFFER_TIME: float = 0.10
const PLAYER_MAX_FALL_SPEED: float = 330.0
const PLAYER_FAST_FALL_GRAVITY_MULTIPLIER: float = 1.25
const PLAYER_ANIMATION_MOVE_THRESHOLD: float = 5.0
const SNAPSHOT_SEND_RATE: float = 20.0  # Hz — server broadcasts world state at this rate
const PROTOTYPE_LEVEL_PHYSICS_SCENE: PackedScene = preload("res://shared/scenes/levels/prototype_level.tscn")
const PLAYERS_PATH: NodePath = ^"Players"
const PLAYER_SPAWN_PATH: NodePath = ^"Players/PlayerSpawn"
const PLAYER_SPAWN_2_PATH: NodePath = ^"Players/PlayerSpawn2"

var peer: ENetMultiplayerPeer = null
var server_port: int = DEFAULT_PORT
var connected_players: Array[int] = []
var player_roles: Dictionary = {}

var server_players: Dictionary = {}
var latest_inputs: Dictionary = {}
var _authoritative_states: Dictionary = {}
var _world_root: Node2D = null
var _players_root: Node2D = null
var _player_spawn: Marker2D = null
var _player_spawn_2: Marker2D = null
var _gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var _log_box: RichTextLabel
var _snapshot_accumulator: float = 0.0

func _ready() -> void:
	_read_command_line_args()
	_create_log_ui()
	_create_movement_world()
	_start_server()

func _physics_process(delta: float) -> void:
	for peer_id: int in server_players.keys():
		_simulate_player(peer_id, delta)

	_snapshot_accumulator += delta
	var send_interval: float = 1.0 / SNAPSHOT_SEND_RATE
	if _snapshot_accumulator >= send_interval:
		_snapshot_accumulator -= send_interval
		_broadcast_world_snapshot()

func _start_server() -> void:
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_server(server_port, MAX_PLAYERS)
	if error != OK:
		s_print("[Server] Failed to create server on port %d: %s" % [server_port, error_string(error)])
		return

	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	s_print("[Server] Server started on port %d (max %d players)" % [server_port, MAX_PLAYERS])

func _read_command_line_args() -> void:
	for arg: String in OS.get_cmdline_args():
		if arg.begins_with("--port="):
			var parsed_port := int(arg.split("=")[1])
			if parsed_port > 0:
				server_port = parsed_port

func _on_peer_connected(id: int) -> void:
	connected_players.append(id)
	s_print("[Server] Player connected: %d (total: %d)" % [id, connected_players.size()])

	_assign_role(id, _first_available_role())

	if connected_players.size() == MAX_PLAYERS:
		s_print("[Server] Lobby full, starting game!")
		for pid in connected_players:
			rpc_id(pid, "notify_game_start")

func _on_peer_disconnected(id: int) -> void:
	connected_players.erase(id)
	player_roles.erase(id)
	latest_inputs.erase(id)
	_authoritative_states.erase(id)
	_despawn_server_player(id)
	s_print("[Server] Player disconnected: %d (remaining: %d)" % [id, connected_players.size()])

	for pid in connected_players:
		rpc_id(pid, "notify_peer_disconnected", id)

	_broadcast_player_list()

func _broadcast_player_list() -> void:
	for pid in connected_players:
		rpc_id(pid, "receive_player_list", connected_players)
		rpc_id(pid, "receive_all_roles", player_roles)

func _first_available_role() -> int:
	if player_roles.values().has(0):
		return 1
	return 0

func _assign_role(sender_id: int, role: int) -> void:
	if not (sender_id in connected_players):
		return

	var requested_role := clampi(role, 0, MAX_PLAYERS - 1)
	for peer_id in player_roles.keys():
		if int(peer_id) != sender_id and int(player_roles[peer_id]) == requested_role:
			rpc_id(sender_id, "receive_role_assignment", int(player_roles.get(sender_id, _first_available_role())))
			return

	var previous_role := int(player_roles.get(sender_id, -1))
	player_roles[sender_id] = requested_role
	if previous_role != requested_role:
		_despawn_server_player(sender_id)
	if not server_players.has(sender_id):
		_spawn_server_player(sender_id, requested_role)

	rpc_id(sender_id, "receive_role_assignment", requested_role)
	s_print("[Server] Assigned role %d to player %d" % [requested_role, sender_id])
	_broadcast_player_list()

func _create_movement_world() -> void:
	_world_root = PROTOTYPE_LEVEL_PHYSICS_SCENE.instantiate() as Node2D
	if _world_root == null:
		push_error("[Server] Failed to instantiate prototype level physics scene.")
		return

	_world_root.name = "AuthoritativeMovementWorld"
	add_child(_world_root)

	_players_root = _world_root.get_node_or_null(PLAYERS_PATH) as Node2D
	_player_spawn = _world_root.get_node_or_null(PLAYER_SPAWN_PATH) as Marker2D
	_player_spawn_2 = _world_root.get_node_or_null(PLAYER_SPAWN_2_PATH) as Marker2D

	if _players_root == null:
		push_error("[Server] Shared physics scene missing Players node.")
	if _player_spawn == null:
		push_error("[Server] Shared physics scene missing Players/PlayerSpawn node.")
	if _player_spawn_2 == null:
		push_warning("[Server] Shared physics scene missing Players/PlayerSpawn2 node; role 1 will fall back to PlayerSpawn.")

func _spawn_server_player(peer_id: int, role: int) -> void:
	if server_players.has(peer_id):
		return

	var body := CharacterBody2D.new()
	body.name = "ServerPlayer_%d" % peer_id
	
	body.collision_layer = 1
	body.collision_mask = 1
	body.add_to_group("player")
	body.set_meta("player_id", peer_id)
	body.set_meta("element", role)

	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(10, 10)
	collision.shape = shape
	collision.position = Vector2(0, -5)
	body.add_child(collision) 

	var parent := _players_root if _players_root != null else _world_root
	parent.add_child(body)
	collision.force_update_transform()
	var spawn := _player_spawn
	if role == 1 and _player_spawn_2 != null:
		spawn = _player_spawn_2
	if spawn != null:
		body.global_position = spawn.global_position
	else:
		body.global_position = Vector2.ZERO

	server_players[peer_id] = {
		"body": body,
		"coyote": 0.0,
		"jump_buffer": 0.0,
		"anim": "idle"
	}
	latest_inputs[peer_id] = _neutral_input()
	_authoritative_states[peer_id] = _create_authoritative_snapshot(peer_id)
	
func _despawn_server_player(peer_id: int) -> void:
	if not server_players.has(peer_id):
		return
	var state: Dictionary = server_players[peer_id]
	var body := state.get("body") as Node
	if is_instance_valid(body):
		body.queue_free()
	server_players.erase(peer_id)

func _neutral_input() -> Dictionary:
	return {
		"t": 0,
		"x": 0.0,
		"j": false,
		"d": false
	}

func _sanitize_input_packet(packet: Dictionary) -> Dictionary:
	return {
		"t": int(packet.get("t", 0)),
		"x": clampf(float(packet.get("x", 0.0)), -1.0, 1.0),
		"j": bool(packet.get("j", false)),
		"d": bool(packet.get("d", false))
	}

func _simulate_player(peer_id: int, delta: float) -> void:
	var state: Dictionary = server_players[peer_id]
	var body := state.get("body") as CharacterBody2D
	if body == null:
		return

	var input: Dictionary = latest_inputs.get(peer_id, _neutral_input())
	var direction := float(input.get("x", 0.0))
	var jump_pressed := bool(input.get("j", false))
	var move_down_pressed := bool(input.get("d", false))

	var coyote := float(state.get("coyote", 0.0))
	var jump_buffer := float(state.get("jump_buffer", 0.0))
	var velocity := body.velocity

	if jump_pressed:
		jump_buffer = PLAYER_JUMP_BUFFER_TIME
	else:
		jump_buffer = maxf(jump_buffer - delta, 0.0)

	if body.is_on_floor():
		coyote = PLAYER_COYOTE_TIME
	else:
		coyote = maxf(coyote - delta, 0.0)
		var gravity_multiplier: float = PLAYER_FAST_FALL_GRAVITY_MULTIPLIER if move_down_pressed and velocity.y > 0.0 else 1.0
		velocity.y = minf(velocity.y + _gravity * PLAYER_GRAVITY_SCALE * gravity_multiplier * delta, PLAYER_MAX_FALL_SPEED)

	if jump_buffer > 0.0 and coyote > 0.0:
		var run_factor: float = clampf(absf(velocity.x) / PLAYER_SPEED, 0.0, 1.0)
		velocity.y = PLAYER_JUMP_VELOCITY * lerpf(1.0, PLAYER_RUN_JUMP_HEIGHT_MULTIPLIER, run_factor)
		jump_buffer = 0.0
		coyote = 0.0

	var current_acceleration: float = PLAYER_ACCELERATION if body.is_on_floor() else PLAYER_AIR_ACCELERATION
	var current_deceleration: float = PLAYER_DECELERATION if body.is_on_floor() else PLAYER_AIR_DECELERATION
	if direction != 0.0:
		velocity.x = move_toward(velocity.x, direction * PLAYER_SPEED, current_acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, current_deceleration * delta)

	body.velocity = velocity
	body.move_and_slide()

	if direction != 0.0:
		var push_dir = signf(direction)
		for i in body.get_slide_collision_count():
			var col = body.get_slide_collision(i)
			var collider = col.get_collider()
			if collider != null and collider.has_method("register_push_attempt"):
				if absf(col.get_normal().x) > 0.35 and signf(push_dir) == -signf(col.get_normal().x):
					collider.call("register_push_attempt", body, push_dir)

	state["coyote"] = coyote
	state["jump_buffer"] = jump_buffer
	state["anim"] = "running" if direction != 0.0 or absf(body.velocity.x) > PLAYER_ANIMATION_MOVE_THRESHOLD else "idle"
	server_players[peer_id] = state

	if jump_pressed:
		input["j"] = false
		latest_inputs[peer_id] = input
	_authoritative_states[peer_id] = _create_authoritative_snapshot(peer_id)
		
func _broadcast_player_sync(peer_id: int) -> void:
	var state: Dictionary = server_players.get(peer_id, {})
	var body := state.get("body") as CharacterBody2D
	if body == null:
		return
	var input: Dictionary = latest_inputs.get(peer_id, _neutral_input())
	var snapshot := _create_authoritative_snapshot(peer_id)
	var packet := {
		"t": int(input.get("t", 0)),
		"id": peer_id,
		"p": body.global_position,
		"v": body.velocity,
		"a": String(state.get("anim", "idle")),
		"ack_tick": int(snapshot.get("ack_tick", 0)),
		"pos": snapshot.get("pos", body.global_position),
		"vel": snapshot.get("vel", body.velocity),
		"on_floor": bool(snapshot.get("on_floor", false)),
		"anim": String(snapshot.get("anim", "idle")),
		"flip_h": bool(snapshot.get("flip_h", false))
	}
	for pid in connected_players:
		rpc_id(pid, "receive_player_sync", packet)

# Builds one packet containing all player snapshots and broadcasts it once per
# send interval.  Replaces the old per-player, per-frame _broadcast_player_sync
# loop.  Reduces RPC count from (players × clients × 60) to (clients × 20) Hz.
func _broadcast_world_snapshot() -> void:
	if connected_players.is_empty() or server_players.is_empty():
		return

	var players_data: Array = []
	for peer_id: int in server_players.keys():
		var state: Dictionary = server_players.get(peer_id, {})
		var body := state.get("body") as CharacterBody2D
		if body == null:
			continue
		var input: Dictionary = latest_inputs.get(peer_id, _neutral_input())
		var snapshot := _create_authoritative_snapshot(peer_id)
		players_data.append({
			"id": peer_id,
			"t": int(input.get("t", 0)),
			"ack_tick": int(snapshot.get("ack_tick", 0)),
			"pos": snapshot.get("pos", body.global_position),
			"vel": snapshot.get("vel", body.velocity),
			"on_floor": bool(snapshot.get("on_floor", false)),
			"anim": String(snapshot.get("anim", "idle")),
			"flip_h": bool(snapshot.get("flip_h", false))
		})

	if players_data.is_empty():
		return

	var world_packet := { "players": players_data }
	for pid: int in connected_players:
		rpc_id(pid, "receive_world_snapshot", world_packet)

func _create_authoritative_snapshot(peer_id: int) -> Dictionary:
	var state: Dictionary = server_players.get(peer_id, {})
	var body := state.get("body") as CharacterBody2D
	var input: Dictionary = latest_inputs.get(peer_id, _neutral_input())
	if body == null:
		return {
			"ack_tick": int(input.get("t", 0)),
			"pos": Vector2.ZERO,
			"vel": Vector2.ZERO,
			"on_floor": true,
			"anim": "idle",
			"flip_h": false
		}
	return {
		"ack_tick": int(input.get("t", 0)),
		"pos": body.global_position,
		"vel": body.velocity,
		"on_floor": body.is_on_floor(),
		"anim": String(state.get("anim", "idle")),
		"flip_h": body.velocity.x < 0.0
	}
		
func _create_log_ui() -> void:
	var canvas = CanvasLayer.new()
	add_child(canvas)
	_log_box = RichTextLabel.new()
	_log_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_log_box.scroll_following = true
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.8)
	_log_box.add_theme_stylebox_override("normal", style)
	canvas.add_child(_log_box)

func s_print(msg: String) -> void:
	print(msg)
	if _log_box:
		_log_box.text += msg + "\n"

# ==================================================================
# RPC DEFINITIONS
# ==================================================================

@rpc("authority", "call_remote", "reliable")
func receive_level_restart() -> void:
	pass

@rpc("authority", "call_remote", "reliable")
func receive_role_assignment(_role: int) -> void:
	pass

@rpc("authority", "call_remote", "reliable")
func receive_player_list(_players: Array) -> void:
	pass

@rpc("authority", "call_remote", "reliable")
func receive_all_roles(_roles: Dictionary) -> void:
	pass

@rpc("any_peer", "call_remote", "reliable")
func request_role(role: int) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		return
	_assign_role(sender_id, role)

@rpc("authority", "call_remote", "reliable")
func notify_game_start() -> void:
	pass

@rpc("any_peer", "call_remote", "reliable")
func request_start_game() -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0 or not (sender_id in connected_players):
		return
	for pid in connected_players:
		rpc_id(pid, "notify_game_start")

@rpc("authority", "call_remote", "reliable")
func notify_peer_disconnected(_peer_id: int) -> void:
	pass

@rpc("authority", "call_remote", "unreliable_ordered")
func receive_player_snapshot(_player_id: int, _snapshot: Dictionary, _tick: int) -> void:
	pass

@rpc("authority", "call_remote", "unreliable_ordered")
func receive_authoritative_player_snapshot(_player_id: int, _snapshot: Dictionary) -> void:
	pass

@rpc("authority", "call_remote", "unreliable_ordered")
func receive_player_sync(_packet: Dictionary) -> void:
	pass

@rpc("authority", "call_remote", "unreliable_ordered")
func receive_world_snapshot(_packet: Dictionary) -> void:
	pass

# LEGACY — relay_player_snapshot is the old client-authoritative RPC.
# In authorized server mode this handler is intentionally a no-op: the server
# ignores any position data pushed by clients and derives world state solely
# from receive_player_input → _simulate_player → _broadcast_player_sync.
# Stub kept so the RPC signature stays registered and stray legacy calls do
# not cause "unknown RPC" errors on the server.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func relay_player_snapshot(_player_id: int, _snapshot: Dictionary, _tick: int) -> void:
	pass  # No-op: server does not trust client-supplied position data.

@rpc("any_peer", "call_remote", "unreliable_ordered")
func rpc_submit_input(packet: Dictionary) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0 or not (sender_id in connected_players):
		return
	latest_inputs[sender_id] = _sanitize_input_packet(packet)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_collect_gem(gem_path: String) -> void:
	# NOTE: This path is the LEGACY client-request flow kept for offline/debug
	# compatibility only.  In multiplayer, gem collection is driven entirely by
	# server-side physics (CollectibleGem._on_body_entered runs on server,
	# calls GameplayRpc.sync_gem_collected).  A client should never need to
	# call this in a live game.
	#
	# If called, validate that the gem actually exists and is not yet collected
	# on the server world before relaying — never trust the client blindly.
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != 0 and not (sender_id in connected_players):
		return

	# Find the gem node in the authoritative world and check its collected flag.
	var gem_node: Node = null
	if is_instance_valid(_world_root):
		gem_node = _world_root.get_node_or_null(gem_path)
	if gem_node == null:
		s_print("[Server] rpc_request_collect_gem: gem not found '%s' (ignored)" % gem_path)
		return
	# Reject if already collected according to server state.
	if "_is_collected" in gem_node and bool(gem_node.get("_is_collected")):
		s_print("[Server] rpc_request_collect_gem: gem already collected '%s' (ignored)" % gem_path)
		return

	# Server-side gem state is authoritative; this relay is only reached in
	# offline/debug mode.  In online play the gem node triggers its own RPC.
	s_print("[Server] rpc_request_collect_gem: relaying '%s' from peer %d" % [gem_path, sender_id])
	for pid: int in connected_players:
		rpc_id(pid, "sync_collect_gem", gem_path)

@rpc("authority", "call_local", "reliable")
func sync_collect_gem(_gem_path: String) -> void:
	pass

# ------------------------------------------------------------------
# DISABLED — server now drives player_failed via prototype_level.gd
# which calls GameplayRpc.sync_player_failed after verifying the
# collision on its own physics world.  Clients must NOT self-report
# failure; any such call is ignored with a warning.
# ------------------------------------------------------------------
@rpc("any_peer", "call_remote", "reliable")
func rpc_request_player_failed() -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	s_print("[Server] WARNING: rpc_request_player_failed called by peer %d — ignored (server-authoritative)." % sender_id)
	# No-op: server determines player failure from its own physics simulation.

@rpc("authority", "call_local", "reliable")
func sync_player_failed() -> void:
	pass

# ------------------------------------------------------------------
# DISABLED — server now drives level_completed via prototype_level.gd
# which calls GameplayRpc.sync_level_completed after verifying exit
# door and gem conditions on the server world.  Client requests are
# ignored to prevent spoofing.
# ------------------------------------------------------------------
@rpc("any_peer", "call_remote", "reliable")
func rpc_request_level_completed() -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	s_print("[Server] WARNING: rpc_request_level_completed called by peer %d — ignored (server-authoritative)." % sender_id)
	# No-op: server determines level completion from its own physics simulation.

@rpc("authority", "call_local", "reliable")
func sync_level_completed() -> void:
	pass

# ------------------------------------------------------------------
# Fallback broadcast helpers — called by prototype_level.gd when
# GameplayRPC autoload is not in the scene tree (e.g. headless server
# that has not added GameplayRPC as an autoload).  These forward the
# event to every connected client using the NetworkManager's own
# registered RPC stubs.
# ------------------------------------------------------------------

func _broadcast_player_failed_rpc(failed_player_id: int) -> void:
	var rpc_node := get_node_or_null("/root/GameplayRpc")
	if rpc_node == null:
		rpc_node = get_node_or_null("/root/GameplayRPC")
	if rpc_node != null:
		rpc_node.rpc("sync_player_failed", failed_player_id)
		return
	# GameplayRPC not present — use NetworkManager stubs as last resort.
	for pid: int in connected_players:
		rpc_id(pid, "receive_player_failed_event", failed_player_id)

func _broadcast_level_completed_rpc() -> void:
	var rpc_node := get_node_or_null("/root/GameplayRpc")
	if rpc_node == null:
		rpc_node = get_node_or_null("/root/GameplayRPC")
	if rpc_node != null:
		rpc_node.rpc("sync_level_completed")
		return
	# GameplayRPC not present — use NetworkManager stubs as last resort.
	for pid: int in connected_players:
		rpc_id(pid, "receive_level_completed_event")

# Client-side receive stubs for the last-resort path above.
@rpc("authority", "call_remote", "reliable")
func receive_player_failed_event(_failed_player_id: int) -> void:
	pass  # Handled by client NetworkManager signal → GameManager

@rpc("authority", "call_remote", "reliable")
func receive_level_completed_event() -> void:
	pass  # Handled by client NetworkManager signal → GameManager
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != 0 and not (sender_id in connected_players):
		return
	s_print("[Server] Restart requested by peer %d. Resetting world." % sender_id)
	if is_instance_valid(_world_root):
		_world_root.queue_free()
	server_players.clear()
	_create_movement_world()
	for pid in connected_players:
		if player_roles.has(pid):
			var role = player_roles[pid]
			latest_inputs[pid] = _neutral_input()
			_spawn_server_player(pid, role)
	for pid in connected_players:
		rpc_id(pid, "sync_restart_level")

@rpc("authority", "call_local", "reliable")
func sync_restart_level() -> void:
	pass

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
func server_teleport_player(pos: Vector2) -> void:
	var sender = multiplayer.get_remote_sender_id()
	if server_players.has(sender):
		var body = server_players[sender]["body"]
		body.global_position = pos
		body.velocity = Vector2.ZERO
		latest_inputs[sender] = _neutral_input() 

@rpc("any_peer", "call_remote", "reliable")
func server_stop_movement() -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender in latest_inputs:
		latest_inputs[sender] = _neutral_input()
		if server_players.has(sender):
			var body = server_players[sender]["body"]
			body.velocity = Vector2.ZERO
