# server/network_manager.gd
# Dedicated server using Godot's built-in ENetMultiplayerPeer
extends Node

const PORT: int = 9999
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
const PROTOTYPE_LEVEL_PHYSICS_SCENE: PackedScene = preload("res://shared/scenes/levels/prototype_level.tscn")
const PLAYERS_PATH: NodePath = ^"Players"
const PLAYER_SPAWN_PATH: NodePath = ^"Players/PlayerSpawn"
const PLAYER_SPAWN_2_PATH: NodePath = ^"Players/PlayerSpawn2"

var peer: ENetMultiplayerPeer = null
var connected_players: Array[int] = []
var player_roles: Dictionary = {}

var server_players: Dictionary = {}
var latest_inputs: Dictionary = {}
var _world_root: Node2D = null
var _players_root: Node2D = null
var _player_spawn: Marker2D = null
var _player_spawn_2: Marker2D = null
var _gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

func _ready() -> void:
	_create_movement_world()
	_start_server()

func _physics_process(delta: float) -> void:
	for peer_id: int in server_players.keys():
		_simulate_player(peer_id, delta)
		_broadcast_player_sync(peer_id)

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
	_spawn_server_player(id, role)
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
	latest_inputs.erase(id)
	_despawn_server_player(id)
	print("[Server] Player disconnected: %d (remaining: %d)" % [id, connected_players.size()])

	for pid in connected_players:
		rpc_id(pid, "notify_peer_disconnected", id)

	_broadcast_player_list()

func _broadcast_player_list() -> void:
	for pid in connected_players:
		rpc_id(pid, "receive_player_list", connected_players)
		rpc_id(pid, "receive_all_roles", player_roles)

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
	
	# ALL layers and masks so it touches gems and boxes
	body.collision_layer = 1 # Back to default!
	body.collision_mask = 1

	body.add_to_group("player")
	body.set_meta("player_id", peer_id)
	body.set_meta("element", role)

	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(10, 10) # BIG shape to hit gem for sure
	collision.shape = shape
	# Fix levitate: offset shape to match client feet origin
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

	# NEW PUSH LOGIC FOR SERVER DUMMY
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
		
		
func _broadcast_player_sync(peer_id: int) -> void:
	var state: Dictionary = server_players.get(peer_id, {})
	var body := state.get("body") as CharacterBody2D
	if body == null:
		return
	var packet := {
		"t": 1,
		"id": peer_id,
		"p": body.global_position,
		"v": body.velocity,
		"a": String(state.get("anim", "idle"))
	}
	for pid in connected_players:
		rpc_id(pid, "receive_player_sync", packet)
		

# ------------------------------------------------------------------
# RPCs called ON clients (defined here so the server script compiles,
# but the real implementation lives in the client's network_manager).
# ------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func server_request_restart() -> void:
	print("[Server] Restarting world.")
	
	# Burn old world
	if is_instance_valid(_world_root):
		_world_root.queue_free()
	
	server_players.clear()
	
	# Build new world
	_create_movement_world()
	
	# Respawn players
	for pid in connected_players:
		if player_roles.has(pid):
			var role = player_roles[pid]
			latest_inputs[pid] = _neutral_input()
			_spawn_server_player(pid, role)
			
	# Tell clients
	for pid in connected_players:
		rpc_id(pid, "receive_level_restart")
@rpc("authority", "call_remote", "reliable")
func receive_level_restart() -> void:
	pass

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

@rpc("authority", "call_remote", "unreliable_ordered")
func receive_player_sync(_packet: Dictionary) -> void:
	pass

# ------------------------------------------------------------------
# Movement RPCs. Clients send input only; server owns positions.
# ------------------------------------------------------------------

@rpc("any_peer", "call_remote", "unreliable_ordered")
func server_receive_movement_input(packet: Dictionary) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0 or not (sender in connected_players):
		return
	latest_inputs[sender] = _sanitize_input_packet(packet)

# ------------------------------------------------------------------
# Legacy relay RPCs kept as compatibility stubs during migration.
# ------------------------------------------------------------------

@rpc("any_peer", "call_remote", "unreliable_ordered")
func relay_player_position(_player_id: int, _position: Vector2) -> void:
	pass

@rpc("any_peer", "call_remote", "unreliable_ordered")
func relay_player_state(_player_id: int, _state: Dictionary) -> void:
	pass

@rpc("authority", "call_remote", "unreliable_ordered")
func receive_player_position(_player_id: int, _position: Vector2) -> void:
	pass  # Implemented on clients

@rpc("authority", "call_remote", "unreliable_ordered")
func receive_player_state(_player_id: int, _state: Dictionary) -> void:
	pass  # Implemented on clients
@rpc("any_peer", "call_remote", "reliable")
func server_teleport_player(pos: Vector2) -> void:
	var sender = multiplayer.get_remote_sender_id()
	if server_players.has(sender):
		var body = server_players[sender]["body"]
		body.global_position = pos
		body.velocity = Vector2.ZERO
		latest_inputs[sender] = _neutral_input() # Stop running!
@rpc("any_peer", "call_remote", "reliable")
func server_stop_movement() -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender in latest_inputs:
		latest_inputs[sender] = _neutral_input()
		if server_players.has(sender):
			var body = server_players[sender]["body"]
			body.velocity = Vector2.ZERO
