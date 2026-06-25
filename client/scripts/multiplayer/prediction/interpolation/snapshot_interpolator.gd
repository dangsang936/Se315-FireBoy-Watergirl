# client/scripts/multiplayer/prediction/interpolation/snapshot_interpolator.gd
class_name SnapshotInterpolator
extends RefCounted

const MAX_SNAPSHOTS: int = 30
const INTERPOLATION_DELAY: float = 0.10 # 100ms delay to buffer snapshots and avoid jitter

var _buffer: Array = []
var _local_time: float = 0.0

func _init() -> void:
	clear()

func clear() -> void:
	_buffer.clear()
	_local_time = 0.0

func update(delta: float) -> void:
	_local_time += delta

func push_snapshot(tick: int, pos: Vector2, vel: Vector2, anim: String, flip_h: bool) -> void:
	# Avoid adding duplicate or older ticks
	for s in _buffer:
		if s.tick == tick:
			return

	var snapshot = {
		"tick": tick,
		"timestamp": _local_time,
		"pos": pos,
		"vel": vel,
		"anim": anim,
		"flip_h": flip_h
	}

	_buffer.append(snapshot)
	_buffer.sort_custom(func(a, b): return a.tick < b.tick)

	if _buffer.size() > MAX_SNAPSHOTS:
		_buffer.remove_at(0)

func sample() -> Dictionary:
	if _buffer.is_empty():
		return {}

	if _buffer.size() == 1:
		var s = _buffer[0]
		return {
			"pos": s.pos,
			"vel": s.vel,
			"anim": s.anim,
			"flip_h": s.flip_h,
			"extrapolating": false
		}

	var target_time = _local_time - INTERPOLATION_DELAY

	var left = null
	var right = null

	for i in range(_buffer.size()):
		var s = _buffer[i]
		if s.timestamp <= target_time:
			left = s
		elif s.timestamp > target_time:
			right = s
			break

	# Target time is older than the oldest buffered snapshot
	if left == null:
		left = _buffer[0]
		return {
			"pos": left.pos,
			"vel": left.vel,
			"anim": left.anim,
			"flip_h": left.flip_h,
			"extrapolating": false
		}

	# Target time is newer than the newest snapshot (extrapolate using velocity)
	if right == null:
		var latest = _buffer[_buffer.size() - 1]
		var time_diff = target_time - latest.timestamp
		var extrapolated_pos = latest.pos + latest.vel * time_diff
		return {
			"pos": extrapolated_pos,
			"vel": latest.vel,
			"anim": latest.anim,
			"flip_h": latest.flip_h,
			"extrapolating": true
		}

	# Normal interpolation between two snapshots
	var span = right.timestamp - left.timestamp
	var t = 0.0
	if span > 0.0001:
		t = (target_time - left.timestamp) / span
	t = clampf(t, 0.0, 1.0)

	var interpolated_pos = left.pos.lerp(right.pos, t)

	return {
		"pos": interpolated_pos,
		"vel": left.vel.lerp(right.vel, t),
		"anim": left.anim if t < 0.5 else right.anim,
		"flip_h": left.flip_h if t < 0.5 else right.flip_h,
		"extrapolating": false
	}
