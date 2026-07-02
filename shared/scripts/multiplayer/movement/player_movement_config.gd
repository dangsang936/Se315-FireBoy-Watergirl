class_name PlayerMovementConfig
extends Resource

@export var max_speed: float = 105.0
@export var acceleration: float = 1700.0
@export var deceleration: float = 1100.0
@export var air_acceleration: float = 1200.0
@export var air_deceleration: float = 480.0
@export var gravity: float = 414.0
@export var jump_velocity: float = -220.0
@export var run_jump_height_multiplier: float = 1.05
@export var coyote_time: float = 0.08
@export var jump_buffer_time: float = 0.10
@export var max_fall_speed: float = 330.0
@export var fast_fall_gravity_multiplier: float = 1.25
@export var animation_move_threshold: float = 5.0

static func create_default() -> PlayerMovementConfig:
	return PlayerMovementConfig.new()
