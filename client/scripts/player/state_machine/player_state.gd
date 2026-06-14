class_name PlayerStateNode
extends Node

@export var state_name: StringName = &""
@export var is_movement_state: bool = true
@export var animation_name: StringName = &""

var owner_player: PrototypePlayer
var state_machine: PlayerStateMachine

func setup(player: PrototypePlayer, machine: PlayerStateMachine) -> void:
	owner_player = player
	state_machine = machine
	if state_name == &"":
		state_name = StringName(name)

func enter(_previous_state: PlayerStateNode) -> void:
	pass

func exit(_next_state: PlayerStateNode) -> void:
	pass

func physics_update(_delta: float) -> void:
	pass

func get_stable_name() -> StringName:
	return state_name
