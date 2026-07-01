class_name PlayerMovementState
extends Resource

var position: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var on_floor: bool = false

func duplicate_state() -> PlayerMovementState:
	var copy := PlayerMovementState.new()
	copy.position = position
	copy.velocity = velocity
	copy.on_floor = on_floor
	return copy

func to_snapshot(ack_tick: int) -> Dictionary:
	return {
		"ack_tick": ack_tick,
		"pos": position,
		"vel": velocity,
		"on_floor": on_floor,
	}

static func from_snapshot(snapshot: Dictionary) -> PlayerMovementState:
	var state := PlayerMovementState.new()
	state.position = snapshot.get("pos", Vector2.ZERO)
	state.velocity = snapshot.get("vel", Vector2.ZERO)
	state.on_floor = bool(snapshot.get("on_floor", false))
	return state
