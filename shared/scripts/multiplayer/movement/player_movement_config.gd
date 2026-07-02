class_name PlayerMovementConfig
extends Resource

@export var max_speed: float = 110.0
@export var acceleration: float = 1500.0
@export var deceleration: float = 1250.0
@export var gravity: float = 900.0
@export var jump_velocity: float = -236.0

static func create_default() -> PlayerMovementConfig:
	return PlayerMovementConfig.new()
