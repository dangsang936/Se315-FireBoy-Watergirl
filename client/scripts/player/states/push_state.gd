class_name PushState
extends PlayerStateNode

func _init() -> void:
	state_name = &"push"
	animation_name = &"running"
	is_movement_state = true

func enter(_previous_state: PlayerStateNode) -> void:
	owner_player.set_player_state_from_state_name(state_name)
	owner_player.play_running_animation()

func exit(_next_state: PlayerStateNode) -> void:
	pass

func physics_update(delta: float) -> void:
	owner_player.apply_player_movement(delta)
	owner_player.play_motion_animation()
