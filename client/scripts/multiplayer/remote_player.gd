# client/scripts/multiplayer/remote_player.gd
class_name RemotePlayer
extends Node

var target_position: Vector2
var current_velocity: Vector2
var parent_body: CharacterBody2D
var _animated_sprite: AnimatedSprite2D

var last_processed_position_tick: int = -1
var last_processed_state_tick: int = -1

var interpolator: SnapshotInterpolator = SnapshotInterpolator.new()

func _ready() -> void:
	parent_body = get_parent() as CharacterBody2D
	if parent_body:
		target_position = parent_body.global_position
		_animated_sprite = parent_body.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	interpolator.clear()

func _physics_process(delta: float) -> void:
	if not parent_body:
		return

	interpolator.update(delta)
	var sample = interpolator.sample()
	if not sample.is_empty():
		parent_body.global_position = sample["pos"]
		current_velocity = sample["vel"]
		_update_visuals(sample["anim"], sample["flip_h"])

func push_snapshot(snapshot: Dictionary, tick: int) -> void:
	var pos = snapshot.get("pos", parent_body.global_position if parent_body else Vector2.ZERO)
	var vel = snapshot.get("vel", Vector2.ZERO)
	var anim = snapshot.get("anim", "idle")
	var flip_h = snapshot.get("flip_h", false)
	interpolator.push_snapshot(tick, pos, vel, anim, flip_h)

# Backward compatibility functions
func update_position(pos: Vector2, tick: int) -> void:
	if tick < last_processed_position_tick:
		return
	last_processed_position_tick = tick
	target_position = pos
	
	var anim = _animated_sprite.animation if _animated_sprite else "idle"
	var flip_h = _animated_sprite.flip_h if _animated_sprite else false
	interpolator.push_snapshot(tick, pos, current_velocity, anim, flip_h)

func update_state(state: Dictionary, tick: int) -> void:
	if tick < last_processed_state_tick:
		return
	last_processed_state_tick = tick
	
	var pos = parent_body.global_position if parent_body else target_position
	var anim = state.get("anim", "idle")
	var flip_h = state.get("flip_h", false)
	interpolator.push_snapshot(tick, pos, current_velocity, anim, flip_h)

func _update_visuals(anim: String, flip_h: bool) -> void:
	if _animated_sprite:
		_animated_sprite.flip_h = flip_h
		if _animated_sprite.sprite_frames.has_animation(anim):
			if _animated_sprite.animation != anim or not _animated_sprite.is_playing():
				_animated_sprite.play(anim)
