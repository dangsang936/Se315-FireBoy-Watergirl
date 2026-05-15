class_name PrototypePauseMenu
extends Control

signal resume_requested
signal restart_requested

@onready var _resume_button: Button = $CenterContainer/PanelContainer/VBoxContainer/ResumeButton as Button
@onready var _restart_button: Button = $CenterContainer/PanelContainer/VBoxContainer/RestartButton as Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_resume_button.pressed.connect(_on_resume_button_pressed)
	_restart_button.pressed.connect(_on_restart_button_pressed)
	hide()


func set_paused_view(is_visible: bool) -> void:
	visible = is_visible
	if is_visible:
		_resume_button.grab_focus()


func _on_resume_button_pressed() -> void:
	resume_requested.emit()


func _on_restart_button_pressed() -> void:
	restart_requested.emit()
