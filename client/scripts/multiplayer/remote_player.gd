class_name RemotePlayer
extends Node

var target_position: Vector2
var current_velocity: Vector2
var parent_body: CharacterBody2D
var _animated_sprite: AnimatedSprite2D

func _ready() -> void:
	parent_body = get_parent() as CharacterBody2D
	if parent_body:
		target_position = parent_body.global_position
		_animated_sprite = parent_body.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D

func _physics_process(delta: float) -> void:
	if not parent_body:
		return
		
	var diff: Vector2 = target_position - parent_body.global_position
	
	# If too far, snap position (fixes restart lag)
	if diff.length() > 200.0:
		parent_body.global_position = target_position
	else:
		# Use velocity. Physics engine happy. No bounce.
		parent_body.velocity = diff * 15.0
		parent_body.move_and_slide()

func update_position(pos: Vector2) -> void:
	target_position = pos

func update_state(state: Dictionary) -> void:
	if _animated_sprite:
		if state.has("flip_h"):
			_animated_sprite.flip_h = state["flip_h"]
		if state.has("anim") and _animated_sprite.sprite_frames.has_animation(state["anim"]):
			if _animated_sprite.animation != state["anim"] or not _animated_sprite.is_playing():
				_animated_sprite.play(state["anim"])
