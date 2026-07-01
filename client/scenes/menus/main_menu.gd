extends MainMenu

func _ready() -> void:
	super._ready()
	%NewGameButton.grab_focus()

func _on_new_game_button_pressed() -> void:
	_disconnect_room_created_signal()
	_disconnect_room_failed_signal()
	_disable_buttons()
	_set_status("Starting server...")
	_connect_host_signals()
	NetworkManager.host_room(9999)

func _on_room_created() -> void:
	_disconnect_room_failed_signal()
	SceneLoader.load_scene("res://scenes/ui/host_waiting_room.tscn")

func _on_room_failed(reason: String) -> void:
	_disconnect_room_created_signal()
	_set_status("Failed: %s" % reason)
	_enable_buttons()

func _on_join_room_button_pressed() -> void:
	SceneLoader.load_scene("res://scenes/ui/lobby.tscn")

func _disable_buttons() -> void:
	for btn in [%NewGameButton, %JoinRoomButton, %OptionsButton, %ExitButton]:
		btn.disabled = true

func _enable_buttons() -> void:
	for btn in [%NewGameButton, %JoinRoomButton, %OptionsButton, %ExitButton]:
		btn.disabled = false

func _set_status(text: String) -> void:
	%StatusLabel.text = text

func _connect_host_signals() -> void:
	var created_callable := Callable(self, "_on_room_created")
	var failed_callable := Callable(self, "_on_room_failed")
	if not NetworkManager.room_created.is_connected(created_callable):
		NetworkManager.room_created.connect(created_callable, CONNECT_ONE_SHOT)
	if not NetworkManager.room_creation_failed.is_connected(failed_callable):
		NetworkManager.room_creation_failed.connect(failed_callable, CONNECT_ONE_SHOT)

func _disconnect_room_created_signal() -> void:
	var created_callable := Callable(self, "_on_room_created")
	if NetworkManager.room_created.is_connected(created_callable):
		NetworkManager.room_created.disconnect(created_callable)

func _disconnect_room_failed_signal() -> void:
	var failed_callable := Callable(self, "_on_room_failed")
	if NetworkManager.room_creation_failed.is_connected(failed_callable):
		NetworkManager.room_creation_failed.disconnect(failed_callable)
