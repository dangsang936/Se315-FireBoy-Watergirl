extends Control

const GAME_SCENE_PATH: String = "res://scenes/bootstrap/game.tscn"
const REQUIRED_PLAYERS: int = 2
const FIREBOY_ROLE: int = 0
const WATERGIRL_ROLE: int = 1

@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var fireboy_button: Button = $VBoxContainer/RoleButtons/FireboyButton
@onready var watergirl_button: Button = $VBoxContainer/RoleButtons/WatergirlButton
@onready var player_list_label: Label = $VBoxContainer/PlayerList
@onready var start_game_button: Button = $VBoxContainer/StartGameButton

func _ready() -> void:
	if not fireboy_button.pressed.is_connected(_on_fireboy_pressed):
		fireboy_button.pressed.connect(_on_fireboy_pressed)
	if not watergirl_button.pressed.is_connected(_on_watergirl_pressed):
		watergirl_button.pressed.connect(_on_watergirl_pressed)
	if not start_game_button.pressed.is_connected(_on_start_game_pressed):
		start_game_button.pressed.connect(_on_start_game_pressed)
	_connect_network_signals()
	fireboy_button.grab_focus()
	_refresh_lobby()

func _exit_tree() -> void:
	_disconnect_network_signals()

func _connect_network_signals() -> void:
	if not NetworkManager.connected_to_server.is_connected(_on_connected):
		NetworkManager.connected_to_server.connect(_on_connected)
	if not NetworkManager.connection_failed.is_connected(_on_connection_failed):
		NetworkManager.connection_failed.connect(_on_connection_failed)
	if not NetworkManager.disconnected_from_server.is_connected(_on_disconnected):
		NetworkManager.disconnected_from_server.connect(_on_disconnected)
	if not NetworkManager.player_list_updated.is_connected(_on_player_list_updated):
		NetworkManager.player_list_updated.connect(_on_player_list_updated)
	if not NetworkManager.role_assigned.is_connected(_on_role_assigned):
		NetworkManager.role_assigned.connect(_on_role_assigned)
	if not NetworkManager.game_started.is_connected(_on_game_started):
		NetworkManager.game_started.connect(_on_game_started)

func _disconnect_network_signals() -> void:
	if NetworkManager.connected_to_server.is_connected(_on_connected):
		NetworkManager.connected_to_server.disconnect(_on_connected)
	if NetworkManager.connection_failed.is_connected(_on_connection_failed):
		NetworkManager.connection_failed.disconnect(_on_connection_failed)
	if NetworkManager.disconnected_from_server.is_connected(_on_disconnected):
		NetworkManager.disconnected_from_server.disconnect(_on_disconnected)
	if NetworkManager.player_list_updated.is_connected(_on_player_list_updated):
		NetworkManager.player_list_updated.disconnect(_on_player_list_updated)
	if NetworkManager.role_assigned.is_connected(_on_role_assigned):
		NetworkManager.role_assigned.disconnect(_on_role_assigned)
	if NetworkManager.game_started.is_connected(_on_game_started):
		NetworkManager.game_started.disconnect(_on_game_started)

func _refresh_lobby() -> void:
	var player_count := NetworkManager.connected_players.size()
	var is_ready_to_start := NetworkManager.is_connected_to_server() and player_count >= REQUIRED_PLAYERS
	
	var am_i_host := false
	if player_count > 0:
		am_i_host = (NetworkManager.connected_players[0] == multiplayer.get_unique_id())
	
	start_game_button.visible = am_i_host
	start_game_button.disabled = not is_ready_to_start

	if not NetworkManager.is_connected_to_server():
		status_label.text = "Connecting to server..."
	elif is_ready_to_start:
		if am_i_host:
			status_label.text = "Player 2 joined. Ready to start."
		else:
			status_label.text = "Player 2 joined. Waiting for host to start..."
	else:
		status_label.text = "Waiting for Player 2 to join..."

	_update_role_buttons()
	_update_player_list()

func _update_role_buttons() -> void:
	var my_peer_id := multiplayer.get_unique_id()
	fireboy_button.disabled = _is_role_taken_by_other(FIREBOY_ROLE, my_peer_id)
	watergirl_button.disabled = _is_role_taken_by_other(WATERGIRL_ROLE, my_peer_id)
	fireboy_button.text = _get_role_button_text("Fireboy", FIREBOY_ROLE, my_peer_id)
	watergirl_button.text = _get_role_button_text("Watergirl", WATERGIRL_ROLE, my_peer_id)

func _is_role_taken_by_other(role: int, my_peer_id: int) -> bool:
	for peer_id in NetworkManager.player_roles:
		if peer_id != my_peer_id and NetworkManager.player_roles[peer_id] == role:
			return true
	return false

func _get_role_button_text(label: String, role: int, my_peer_id: int) -> String:
	if NetworkManager.player_roles.get(my_peer_id, -1) == role:
		return "%s (You)" % label
	if _is_role_taken_by_other(role, my_peer_id):
		return "%s (Taken)" % label
	return label

func _update_player_list() -> void:
	if NetworkManager.connected_players.is_empty():
		player_list_label.text = "Players in room:\n- Host connecting..."
		return

	var text := "Players in room:\n"
	for peer_id in NetworkManager.connected_players:
		var role_name := "Unknown"
		if NetworkManager.player_roles.has(peer_id):
			var role: int = NetworkManager.player_roles[peer_id]
			role_name = "Fireboy" if role == 0 else "Watergirl"
		var my_tag := " (You)" if peer_id == multiplayer.get_unique_id() else ""
		text += "- Peer %d: %s%s\n" % [peer_id, role_name, my_tag]
	player_list_label.text = text

func _on_start_game_pressed() -> void:
	start_game_button.disabled = true
	status_label.text = "Starting game..."
	NetworkManager.start_game()

func _on_fireboy_pressed() -> void:
	NetworkManager.request_role(FIREBOY_ROLE)

func _on_watergirl_pressed() -> void:
	NetworkManager.request_role(WATERGIRL_ROLE)

func _on_connected() -> void:
	_refresh_lobby()

func _on_connection_failed() -> void:
	status_label.text = "Connection failed."
	start_game_button.disabled = true
	player_list_label.text = ""

func _on_disconnected() -> void:
	status_label.text = "Disconnected from server."
	start_game_button.disabled = true
	player_list_label.text = ""

func _on_player_list_updated(_players: Array[int]) -> void:
	_refresh_lobby()

func _on_role_assigned(_role: int) -> void:
	_refresh_lobby()

func _on_game_started() -> void:
	print("[HostWaitingRoom] Loading gameplay scene %s" % GAME_SCENE_PATH)
	SceneLoader.load_scene(GAME_SCENE_PATH)
