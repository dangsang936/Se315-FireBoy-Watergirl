class_name EdgeCorrection
extends Node

var owner_player: PrototypePlayer
var correction_applied_this_frame: bool = false

func setup(player: PrototypePlayer) -> void:
	owner_player = player

func try_apply(delta: float, input_direction: float) -> bool:
	correction_applied_this_frame = false
	if owner_player == null or not owner_player.edge_correction_enabled:
		return false
	if owner_player.is_on_floor():
		return false
	if owner_player.velocity.y > -owner_player.edge_correction_min_rise_speed:
		return false

	var travel_sign: float = signf(owner_player.velocity.x)
	if travel_sign == 0.0:
		travel_sign = signf(input_direction)
	if travel_sign == 0.0:
		return false

	var motion := owner_player.velocity * delta
	if motion.y >= 0.0:
		return false
	if not owner_player.test_move(owner_player.global_transform, motion):
		return false

	var correction_step: float = maxf(owner_player.edge_correction_step, 0.5)
	var correction_distance: float = maxf(owner_player.edge_correction_distance, correction_step)
	var offset: float = correction_step
	while offset <= correction_distance + 0.001:
		var shifted_transform := owner_player.global_transform.translated(Vector2(travel_sign * offset, 0.0))
		if owner_player.test_move(shifted_transform, Vector2.ZERO):
			offset += correction_step
			continue
		if not owner_player.test_move(shifted_transform, motion):
			owner_player.global_position.x += travel_sign * offset
			correction_applied_this_frame = true
			return true
		offset += correction_step
	return false

func clear_state() -> void:
	correction_applied_this_frame = false
