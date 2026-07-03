extends SceneTree

const GAME_SCENE: PackedScene = preload("res://scenes/bootstrap/game.tscn")
const LEVEL_ONE_SCENE: PackedScene = preload("res://scenes/levels/real_level_blank.tscn")
const LEVEL_TWO_SCENE: PackedScene = preload("res://scenes/levels/real_level_blank_2.tscn")
const DEFAULT_PORT: int = 9999
const SERVER_IP: String = "127.0.0.1"
const CONNECT_RETRY_COUNT: int = 10
const CONNECT_RETRY_DELAY_SEC: float = 0.5
const HOST_START_DELAY_SEC: float = 0.5
const HOST_NEXT_LEVEL_DELAY_SEC: float = 2.0
const PROBE_TIMEOUT_SEC: float = 25.0

var _failures: Array[String] = []
var _probe_role: String = "join"
var _network_manager: Node
var _game: GameManager
var _game_started: bool = false
var _connected: bool = false
var _start_requested: bool = false
var _next_level_triggered: bool = false
var _completed: bool = false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_parse_args()
	_network_manager = root.get_node_or_null("NetworkManager")
	_require(_network_manager != null, "NetworkManager autoload is required.")
	if _network_manager == null:
		_finish()
		return

	_connect_network_signals()
	_start_timeout()

	if _probe_role == "host":
		_network_manager.call("host_room", DEFAULT_PORT)
		await _wait_until(func() -> bool:
			return _connected
		, 10.0, "Host failed to connect to local server.")
	else:
		await _connect_joiner()

	if _failures.is_empty():
		await _wait_until(func() -> bool:
			return _completed
		, 15.0, "%s probe did not reach level 2 in time." % _probe_role.capitalize())

	_finish()

func _parse_args() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		args = OS.get_cmdline_args()
	for arg: String in args:
		if arg.begins_with("--probe-role="):
			_probe_role = arg.get_slice("=", 1).strip_edges().to_lower()

func _connect_network_signals() -> void:
	_network_manager.connected_to_server.connect(_on_connected_to_server)
	_network_manager.connection_failed.connect(_on_connection_failed)
	_network_manager.disconnected_from_server.connect(_on_disconnected_from_server)
	_network_manager.player_list_updated.connect(_on_player_list_updated)
	_network_manager.game_started.connect(_on_game_started)

func _start_timeout() -> void:
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = PROBE_TIMEOUT_SEC
	timer.timeout.connect(func() -> void:
		_require(false, "%s probe timed out after %.1fs." % [_probe_role.capitalize(), PROBE_TIMEOUT_SEC])
		_finish()
	)
	root.add_child(timer)
	timer.start()

func _connect_joiner() -> void:
	for attempt: int in CONNECT_RETRY_COUNT:
		var error: Error = _network_manager.call("connect_to_server", SERVER_IP, DEFAULT_PORT)
		if error == OK:
			var connected := await _wait_until(func() -> bool:
				return _connected
			, CONNECT_RETRY_DELAY_SEC + 2.0, "")
			if connected:
				return
		await create_timer(CONNECT_RETRY_DELAY_SEC).timeout
	_require(false, "Joiner failed to connect to host after retries.")

func _on_connected_to_server() -> void:
	_connected = true
	print("[%s] Connected to server." % _probe_role)

func _on_connection_failed() -> void:
	print("[%s] Connection failed." % _probe_role)

func _on_disconnected_from_server() -> void:
	if not _completed:
		_require(false, "%s disconnected before verification finished." % _probe_role.capitalize())
		_finish()

func _on_player_list_updated(players: Array[int]) -> void:
	print("[%s] Players in room: %s" % [_probe_role, players])
	if _probe_role == "host" and players.size() >= 2 and not _start_requested:
		_start_requested = true
		_request_start_game()

func _request_start_game() -> void:
	await create_timer(HOST_START_DELAY_SEC).timeout
	if _network_manager != null and _network_manager.call("is_connected_to_server"):
		print("[host] Requesting game start.")
		_network_manager.call("start_game")

func _on_game_started() -> void:
	if _game_started:
		return
	_game_started = true
	print("[%s] Game started signal received." % _probe_role)
	_spawn_game()

func _spawn_game() -> void:
	_game = GAME_SCENE.instantiate() as GameManager
	_game.set("level_scene", LEVEL_ONE_SCENE)
	_game.set("level_scenes", [LEVEL_ONE_SCENE, LEVEL_TWO_SCENE])
	root.add_child(_game)
	await process_frame
	await process_frame
	for _frame in 8:
		await physics_frame
	print("[%s] Gameplay scene loaded." % _probe_role)

	if _probe_role == "host" and not _next_level_triggered:
		_next_level_triggered = true
		_trigger_next_level()
	else:
		_watch_for_level_two()

func _trigger_next_level() -> void:
	await create_timer(HOST_NEXT_LEVEL_DELAY_SEC).timeout
	if not is_instance_valid(_game):
		_require(false, "Host game scene was freed before next-level trigger.")
		return
	var hud: Node = _game.get_node_or_null("HUD")
	_require(hud != null, "Host game should contain HUD.")
	if hud == null:
		return
	_game.set("_state", GameManager.ManagerState.WON)
	print("[host] Triggering next level through HUD signal.")
	hud.emit_signal("next_level_requested")
	_watch_for_level_two()

func _watch_for_level_two() -> void:
	await _wait_until(func() -> bool:
		if not is_instance_valid(_game):
			return false
		var current_level_ref: Variant = _game.get("_current_level")
		if current_level_ref == null:
			return false
		if not is_instance_valid(current_level_ref):
			return false
		var current_level_path: String = String(current_level_ref.get("scene_file_path"))
		return current_level_path.ends_with("real_level_blank_2.tscn")
	, 8.0, "%s did not load level 2." % _probe_role.capitalize())
	if _failures.is_empty():
		_completed = true
		print("[%s] Multiplayer next-level probe passed." % _probe_role)

func _wait_until(predicate: Callable, timeout_sec: float, failure_message: String) -> bool:
	var deadline_ms := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while Time.get_ticks_msec() < deadline_ms:
		if predicate.call():
			return true
		await process_frame
	if failure_message != "":
		_require(false, failure_message)
	return false

func _finish() -> void:
	if is_instance_valid(_game):
		_game.queue_free()
		await process_frame
	if is_instance_valid(_network_manager) and _network_manager.call("is_connected_to_server"):
		_network_manager.call("disconnect_from_server")
	await process_frame
	if _failures.is_empty():
		quit(0)
		return
	for failure: String in _failures:
		printerr(failure)
	quit(1)

func _require(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
