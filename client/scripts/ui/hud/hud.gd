class_name PrototypeHUD
extends CanvasLayer

signal restart_requested
signal resume_requested

@onready var _status_label: Label = $Root/MarginContainer/VBoxContainer/StatusLabel as Label
@onready var _gem_label: Label = $Root/MarginContainer/VBoxContainer/GemLabel as Label
@onready var _hint_label: Label = $Root/MarginContainer/VBoxContainer/HintLabel as Label
@onready var _pause_menu: PrototypePauseMenu = $PauseMenu as PrototypePauseMenu

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_menu.restart_requested.connect(_on_pause_menu_restart_requested)
	_pause_menu.resume_requested.connect(_on_pause_menu_resume_requested)
	set_paused(false)
	set_gem_progress(0, 0)
	show_status("Loading prototype...", false)

func show_status(message: String, show_restart: bool) -> void:
	_status_label.text = message
	_hint_label.text = "Press R to restart." if show_restart else "Move: A/D  Jump: W  Pause: Esc"
	_hint_label.visible = true

func set_paused(is_paused: bool) -> void:
	_pause_menu.set_paused_view(is_paused)

func set_gem_progress(collected: int, required: int) -> void:
	if required <= 0:
		_gem_label.visible = false
		_gem_label.text = ""
		return
	_gem_label.visible = true
	_gem_label.text = "Gems: %s/%s" % [collected, required]

func _on_pause_menu_restart_requested() -> void:
	restart_requested.emit()

func _on_pause_menu_resume_requested() -> void:
	resume_requested.emit()
