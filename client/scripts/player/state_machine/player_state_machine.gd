class_name PlayerStateMachine
extends Node

signal state_changed(current_state_name: StringName, previous_state_name: StringName)

@export var initial_state_name: StringName = &"idle"
@export var disabled_state_name: StringName = &"disabled"

var owner_player: PrototypePlayer
var current_state: PlayerStateNode
var previous_state: PlayerStateNode
var last_state_name: StringName = &""

var _states: Dictionary = {}

func setup(player: PrototypePlayer) -> void:
	owner_player = player
	_states.clear()
	for child: Node in get_children():
		var state := child as PlayerStateNode
		if state == null:
			continue
		state.setup(player, self)
		if _states.has(state.state_name):
			push_error("Duplicate player state: %s" % state.state_name)
			continue
		_states[state.state_name] = state

func start() -> void:
	transition_to(initial_state_name, true)

func physics_update(delta: float) -> void:
	if current_state == null:
		start()
	if current_state != null:
		current_state.physics_update(delta)

func transition_from_player_context() -> void:
	if owner_player == null:
		return
	if not owner_player.is_control_enabled():
		transition_to(disabled_state_name)
		return
	if get_current_state_name() == &"climb" and owner_player.is_ladder_available():
		transition_to(&"climb")
		return
	if owner_player.is_ladder_available() and owner_player.has_ladder_climb_input():
		transition_to(&"climb")
		return
	if not owner_player.is_on_floor():
		transition_to(&"airborne")
		return
	if owner_player.has_push_contact() and owner_player.has_move_intent():
		transition_to(&"push")
		return
	if owner_player.has_move_intent() or owner_player.is_horizontally_moving():
		transition_to(&"run")
		return
	transition_to(initial_state_name)

func transition_to(target_state_name: StringName, force: bool = false) -> bool:
	if not _states.has(target_state_name):
		push_error("Unknown player state transition target: %s" % target_state_name)
		return false

	var next_state := _states[target_state_name] as PlayerStateNode
	if next_state == null:
		push_error("Invalid player state node for target: %s" % target_state_name)
		return false
	if current_state == next_state and not force:
		return true

	var old_state := current_state
	if old_state != null:
		old_state.exit(next_state)

	previous_state = old_state
	current_state = next_state
	last_state_name = old_state.state_name if old_state != null else &""
	current_state.enter(old_state)
	state_changed.emit(current_state.state_name, last_state_name)
	return true

func reset_to_initial() -> void:
	transition_to(initial_state_name, true)

func force_disabled() -> void:
	transition_to(disabled_state_name)

func get_current_state_name() -> StringName:
	if current_state == null:
		return &""
	return current_state.state_name

func get_previous_state_name() -> StringName:
	return last_state_name

func has_state(state_name_to_check: StringName) -> bool:
	return _states.has(state_name_to_check)

func get_registered_state_names() -> Array[StringName]:
	var names: Array[StringName] = []
	for state_name_key: Variant in _states.keys():
		names.append(state_name_key as StringName)
	names.sort()
	return names
