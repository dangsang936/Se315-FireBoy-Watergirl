class_name PlayerMovementState
extends Resource

var position: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var on_floor: bool = false
var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0
var anim: String = "idle"
var flip_h: bool = false

func duplicate_state() -> PlayerMovementState:
	var copy := PlayerMovementState.new()
	copy.position = position
	copy.velocity = velocity
	copy.on_floor = on_floor
	copy.coyote_timer = coyote_timer
	copy.jump_buffer_timer = jump_buffer_timer
	copy.anim = anim
	copy.flip_h = flip_h
	return copy

func to_snapshot(ack_tick: int) -> Dictionary:
	return {
		"ack_tick": ack_tick,
		"pos": position,
		"vel": velocity,
		"on_floor": on_floor,
		"anim": anim,
		"flip_h": flip_h,
	}

static func from_snapshot(snapshot: Dictionary) -> PlayerMovementState:
	var state := PlayerMovementState.new()
	state.position = snapshot.get("pos", Vector2.ZERO)
	state.velocity = snapshot.get("vel", Vector2.ZERO)
	state.on_floor = bool(snapshot.get("on_floor", false))
	state.anim = String(snapshot.get("anim", "idle"))
	state.flip_h = bool(snapshot.get("flip_h", false))
	state.coyote_timer = float(snapshot.get("coyote", 0.0))
	state.jump_buffer_timer = float(snapshot.get("jump_buffer", 0.0))
	return state
