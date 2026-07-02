class_name ClimbState
extends PlayerStateNode

func _init() -> void:
	state_name = &"climb"
	animation_name = &"idle"
	is_movement_state = true

func enter(_previous_state: PlayerStateNode) -> void:
	owner_player.clear_precision_timers()
	owner_player.set_player_state_from_state_name(state_name)
	owner_player.play_idle_animation()

func exit(_next_state: PlayerStateNode) -> void:
	owner_player.clear_ladder_vertical_motion()

func physics_update(delta: float) -> void:
	owner_player.apply_ladder_movement(delta)
	owner_player.play_idle_animation()
