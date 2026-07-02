class_name ClientPredictionController
extends RefCounted

const MAX_PENDING_INPUTS: int = 128
const IGNORE_THRESHOLD: float = 4.0
const SNAP_THRESHOLD: float = 16.0

var config: PlayerMovementConfig = PlayerMovementConfig.create_default()
var current_state: PlayerMovementState = PlayerMovementState.new()
var last_ack_tick: int = -1
var pending_inputs: Array[Dictionary] = []
var predicted_states: Dictionary = {}


func reset(position: Vector2, velocity: Vector2, on_floor: bool) -> void:
	current_state.position = position
	current_state.velocity = velocity
	current_state.on_floor = on_floor
	last_ack_tick = -1
	pending_inputs.clear()
	predicted_states.clear()


func predict(packet: Dictionary, delta: float) -> PlayerMovementState:
	var input_packet: Dictionary = {
		"t": int(packet.get("t", last_ack_tick + pending_inputs.size() + 1)),
		"x": float(packet.get("x", 0.0)),
		"j": bool(packet.get("j", false)),
		"d": bool(packet.get("d", false))
	}
	pending_inputs.append(input_packet)
	current_state = PlayerMovementSimulator.step(current_state, input_packet, config, delta)
	predicted_states[input_packet["t"]] = current_state.duplicate_state()
	_trim_buffers()
	return current_state.duplicate_state()


func reconcile(snapshot: Dictionary, delta: float) -> PlayerMovementState:
	var ack_tick: int = int(snapshot.get("ack_tick", -1))
	if ack_tick <= last_ack_tick:
		return current_state.duplicate_state()

	last_ack_tick = ack_tick
	var authoritative_state: PlayerMovementState = PlayerMovementState.from_snapshot(snapshot)
	var predicted_state: Variant = predicted_states.get(ack_tick)
	_drop_acknowledged_inputs(ack_tick)

	if predicted_state == null:
		current_state = authoritative_state
		predicted_states[ack_tick] = current_state.duplicate_state()
		_trim_buffers()
		return current_state.duplicate_state()

	var error: float = authoritative_state.position.distance_to((predicted_state as PlayerMovementState).position)
	if error <= IGNORE_THRESHOLD:
		current_state = (predicted_state as PlayerMovementState).duplicate_state()
		current_state.position = authoritative_state.position
		current_state.velocity = authoritative_state.velocity
		current_state.on_floor = authoritative_state.on_floor
		predicted_states[ack_tick] = current_state.duplicate_state()
		_trim_buffers()
		return current_state.duplicate_state()

	if error >= SNAP_THRESHOLD:
		current_state = authoritative_state
	else:
		current_state.position = current_state.position.lerp(authoritative_state.position, 0.25)
		current_state.velocity = authoritative_state.velocity
		current_state.on_floor = authoritative_state.on_floor

	var replayed_state: PlayerMovementState = _replay_pending_inputs(delta)
	predicted_states[ack_tick] = current_state.duplicate_state()
	_trim_buffers()
	return replayed_state


func _replay_pending_inputs(delta: float) -> PlayerMovementState:
	var replay_state: PlayerMovementState = current_state.duplicate_state()
	for pending_input: Dictionary in pending_inputs:
		replay_state = PlayerMovementSimulator.step(replay_state, pending_input, config, delta)
		predicted_states[int(pending_input.get("t", -1))] = replay_state.duplicate_state()
	current_state = replay_state
	return current_state.duplicate_state()


func _drop_acknowledged_inputs(ack_tick: int) -> void:
	pending_inputs = pending_inputs.filter(func(input_packet: Dictionary) -> bool:
		return int(input_packet.get("t", -1)) > ack_tick
	)
	var stale_ticks: Array[int] = []
	for tick in predicted_states.keys():
		if int(tick) <= ack_tick:
			stale_ticks.append(int(tick))
	for tick: int in stale_ticks:
		predicted_states.erase(tick)


func _trim_buffers() -> void:
	while pending_inputs.size() > MAX_PENDING_INPUTS:
		var dropped_packet: Dictionary = pending_inputs.pop_front()
		predicted_states.erase(int(dropped_packet.get("t", -1)))

	var sorted_ticks: Array[int] = []
	for tick in predicted_states.keys():
		sorted_ticks.append(int(tick))
	sorted_ticks.sort()
	while sorted_ticks.size() > MAX_PENDING_INPUTS:
		var oldest_tick: int = sorted_ticks.pop_front()
		predicted_states.erase(oldest_tick)
