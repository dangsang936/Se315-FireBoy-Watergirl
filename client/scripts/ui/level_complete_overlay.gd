class_name LevelCompleteOverlay
extends Control

signal play_again_requested
signal next_level_requested

@onready var _next_level_button: Button = $Dim/CenterContainer/PanelContainer/VBoxContainer/NextLevelButton as Button
@onready var _play_again_button: Button = $Dim/CenterContainer/PanelContainer/VBoxContainer/PlayAgainButton as Button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_play_again_button.pressed.connect(_on_play_again_pressed)
	_next_level_button.pressed.connect(_on_next_level_pressed)

func show_complete(has_next_level: bool) -> void:
	visible = true
	_next_level_button.visible = has_next_level
	_next_level_button.disabled = not has_next_level
	_play_again_button.grab_focus()

func hide_complete() -> void:
	visible = false

func _on_play_again_pressed() -> void:
	play_again_requested.emit()

func _on_next_level_pressed() -> void:
	next_level_requested.emit()
