class_name GameManager
extends Node2D

enum GameState { BOOT, LOADING_LEVEL, PLAYING, PAUSED, WON, LOST, RESTARTING }

@export var level_scene: PackedScene
@export var player_scene: PackedScene
@export var level_root_path: NodePath = ^"LevelRoot"
@export var hud_path: NodePath = ^"HUD"

var _state: GameState = GameState.BOOT
var _current_level: PrototypeLevel
var _player: CharacterBody2D
var _is_reloading: bool = false

@onready var _level_root: Node2D = get_node(level_root_path) as Node2D
@onready var _hud: PrototypeHUD = get_node(hud_path) as PrototypeHUD

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_hud.restart_requested.connect(_restart_level)
	_hud.resume_requested.connect(_resume_game)
	_load_level()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("restart"):
		_restart_level()
		get_viewport().set_input_as_handled()

func _load_level() -> void:
	if not level_scene or not player_scene:
		push_error("GameManager needs level_scene and player_scene.")
		return
	if _is_reloading:
		return

	_is_reloading = true
	get_tree().paused = false
	_set_state(GameState.LOADING_LEVEL)
	for child in _level_root.get_children():
		child.queue_free()

	await get_tree().process_frame

	_current_level = level_scene.instantiate() as PrototypeLevel
	_level_root.add_child(_current_level)
	_current_level.level_completed.connect(_on_level_completed)
	_current_level.player_failed.connect(_on_player_failed)
	_current_level.exit_locked.connect(_on_exit_locked)
	_current_level.gem_progress_changed.connect(_on_gem_progress_changed)
	_spawn_player()
	_is_reloading = false
	_set_state(GameState.PLAYING)

func _spawn_player() -> void:
	_player = player_scene.instantiate() as CharacterBody2D
	_current_level.attach_player(_player)
	if _player.has_method("reset_to_spawn"):
		_player.call("reset_to_spawn", _current_level.get_spawn_position())

func _toggle_pause() -> void:
	if _state == GameState.PLAYING:
		_set_state(GameState.PAUSED)
	elif _state == GameState.PAUSED:
		_set_state(GameState.PLAYING)

func _resume_game() -> void:
	if _state == GameState.PAUSED:
		_set_state(GameState.PLAYING)

func _restart_level() -> void:
	if _state == GameState.LOADING_LEVEL or _is_reloading:
		return
	get_tree().paused = false
	_set_player_control_enabled(false)
	_set_state(GameState.RESTARTING)
	call_deferred("_load_level")

func _on_level_completed() -> void:
	if _state != GameState.PLAYING:
		return
	_set_player_control_enabled(false)
	_set_state(GameState.WON)

func _on_player_failed(_player_node: Node2D) -> void:
	if _state != GameState.PLAYING:
		return
	_set_player_control_enabled(false)
	_set_state(GameState.LOST)

func _on_exit_locked(remaining: int, _gem_element: int) -> void:
	if _state != GameState.PLAYING:
		return
	_hud.show_status("Gate locked. Gems remaining: %s" % remaining, false)

func _on_gem_progress_changed(collected: int, required: int) -> void:
	_hud.set_gem_progress(collected, required)

func _set_player_control_enabled(is_enabled: bool) -> void:
	if is_instance_valid(_player):
		if _player.has_method("set_control_enabled"):
			_player.call("set_control_enabled", is_enabled)
		else:
			_player.set_physics_process(is_enabled)

func _set_state(next_state: GameState) -> void:
	_state = next_state
	match _state:
		GameState.LOADING_LEVEL:
			get_tree().paused = false
			_set_player_control_enabled(false)
			_hud.set_paused(false)
			_hud.set_gem_progress(0, 0)
			_hud.show_status("Loading prototype...", false)
		GameState.PLAYING:
			get_tree().paused = false
			_set_player_control_enabled(true)
			_hud.set_paused(false)
			_hud.show_status("Reach the exit. Collect matching gems.", false)
		GameState.PAUSED:
			_hud.show_status("Paused", false)
			_hud.set_paused(true)
			get_tree().paused = true
		GameState.WON:
			get_tree().paused = false
			_set_player_control_enabled(false)
			_hud.set_paused(false)
			_hud.show_status("Level complete! Press R to restart.", true)
		GameState.LOST:
			get_tree().paused = false
			_set_player_control_enabled(false)
			_hud.set_paused(false)
			_hud.show_status("You fell into danger. Press R to restart.", true)
		GameState.RESTARTING:
			get_tree().paused = false
			_set_player_control_enabled(false)
			_hud.set_paused(false)
			_hud.show_status("Restarting...", false)
		_:
			pass
