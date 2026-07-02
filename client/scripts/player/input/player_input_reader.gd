class_name PlayerInputReader
extends Node

var horizontal_direction: float = 0.0
var jump_just_pressed: bool = false
var jump_pressed: bool = false
var jump_just_released: bool = false
var move_down_pressed: bool = false
var climb_direction: float = 0.0
var climb_up_pressed: bool = false
var climb_down_pressed: bool = false

var _jump_key_was_pressed: bool = false
var _jump_pressed_since_update: bool = false
var _jump_released_since_update: bool = false

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("jump"):
		_jump_pressed_since_update = true
		jump_pressed = true
		climb_up_pressed = true
		climb_direction = _read_climb_direction()
		return
	if event.is_action_released("jump"):
		_jump_released_since_update = true
		jump_pressed = false
		climb_up_pressed = false
		climb_direction = _read_climb_direction()
		return
	if event.is_action_pressed("move_down"):
		move_down_pressed = true
		climb_down_pressed = true
		climb_direction = _read_climb_direction()
		return
	if event.is_action_released("move_down"):
		move_down_pressed = false
		climb_down_pressed = false
		climb_direction = _read_climb_direction()
		return

	var key_event := event as InputEventKey
	if key_event == null or key_event.echo:
		return
	if key_event.physical_keycode == KEY_S or key_event.keycode == KEY_S:
		move_down_pressed = key_event.pressed
		climb_down_pressed = key_event.pressed
		climb_direction = _read_climb_direction()
		return
	if key_event.physical_keycode != KEY_W and key_event.keycode != KEY_W:
		return
	if key_event.pressed:
		_jump_pressed_since_update = true
		jump_pressed = true
		climb_up_pressed = true
		climb_direction = _read_climb_direction()
		return
	_jump_released_since_update = true
	jump_pressed = false
	climb_up_pressed = false
	climb_direction = _read_climb_direction()

func update_from_input(control_enabled: bool) -> void:
	if not control_enabled:
		clear_transient_input()
		return

	horizontal_direction = _read_horizontal_direction()
	var jump_key_pressed: bool = Input.is_physical_key_pressed(KEY_W)
	jump_pressed = Input.is_action_pressed("jump") or jump_key_pressed
	climb_up_pressed = jump_pressed
	climb_down_pressed = Input.is_action_pressed("move_down") or Input.is_physical_key_pressed(KEY_S)
	jump_just_pressed = Input.is_action_just_pressed("jump") or _jump_pressed_since_update or (jump_key_pressed and not _jump_key_was_pressed)
	jump_just_released = Input.is_action_just_released("jump") or _jump_released_since_update or (_jump_key_was_pressed and not jump_key_pressed)
	_jump_pressed_since_update = false
	_jump_released_since_update = false
	_jump_key_was_pressed = jump_key_pressed
	move_down_pressed = climb_down_pressed
	climb_direction = _read_climb_direction()

func clear_transient_input() -> void:
	horizontal_direction = 0.0
	jump_just_pressed = false
	jump_pressed = false
	jump_just_released = false
	move_down_pressed = false
	climb_direction = 0.0
	climb_up_pressed = false
	climb_down_pressed = false
	_jump_key_was_pressed = false
	_jump_pressed_since_update = false
	_jump_released_since_update = false

func has_climb_input() -> bool:
	return climb_up_pressed or climb_down_pressed

func _read_horizontal_direction() -> float:
	var direction: float = Input.get_axis("move_left", "move_right")
	if Input.is_physical_key_pressed(KEY_A):
		direction -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		direction += 1.0
	return clampf(direction, -1.0, 1.0)

func _read_climb_direction() -> float:
	if climb_up_pressed and climb_down_pressed:
		return 0.0
	if climb_up_pressed:
		return -1.0
	if climb_down_pressed:
		return 1.0
	return 0.0
