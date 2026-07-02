class_name DisabledState
extends PlayerStateNode

func _init() -> void:
	state_name = &"disabled"
	animation_name = &"idle"
	is_movement_state = false

func enter(_previous_state: PlayerStateNode) -> void:
	owner_player.set_player_state_from_state_name(state_name)
	owner_player.clear_player_motion()
	owner_player.play_idle_animation()

func exit(_next_state: PlayerStateNode) -> void:
	pass

func physics_update(_delta: float) -> void:
	owner_player.clear_player_motion()
