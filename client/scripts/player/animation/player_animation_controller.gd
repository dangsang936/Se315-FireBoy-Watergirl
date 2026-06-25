class_name PlayerAnimationController
extends Node

@export var idle_animation_name: StringName = &"idle"
@export var running_animation_name: StringName = &"running"

var movement_threshold: float = 5.0
var _animated_sprite: AnimatedSprite2D

func setup(animated_sprite: AnimatedSprite2D, threshold: float) -> void:
	_animated_sprite = animated_sprite
	movement_threshold = threshold

func play_idle() -> void:
	_play_animation(idle_animation_name)

func play_running() -> void:
	_play_animation(running_animation_name)

func play_for_motion(has_move_intent: bool, horizontal_velocity: float) -> void:
	var is_moving: bool = absf(horizontal_velocity) > movement_threshold
	if has_move_intent or is_moving:
		play_running()
	else:
		play_idle()

func face_direction(direction: float) -> void:
	if _animated_sprite == null or direction == 0.0:
		return
	_animated_sprite.flip_h = direction < 0.0

func _play_animation(animation_name: StringName) -> void:
	if _animated_sprite == null or _animated_sprite.sprite_frames == null:
		return
	if not _animated_sprite.sprite_frames.has_animation(animation_name):
		return
	if _animated_sprite.animation != animation_name or not _animated_sprite.is_playing():
		_animated_sprite.play(animation_name)
