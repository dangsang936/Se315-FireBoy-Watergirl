extends Control

const FIREBOY_ROLE: int = 0
const WATERGIRL_ROLE: int = 1

@onready var ip_input: LineEdit = $VBoxContainer/IPContainer/IPInput
@onready var port_input: LineEdit = $VBoxContainer/PortContainer/PortInput
@onready var connect_button: Button = $VBoxContainer/ConnectButton
@onready var fireboy_button: Button = $VBoxContainer/RoleButtons/FireboyButton
@onready var watergirl_button: Button = $VBoxContainer/RoleButtons/WatergirlButton
@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var player_list_label: Label = $VBoxContainer/PlayerList

func _ready() -> void:
	# Kết nối UI signals
	connect_button.pressed.connect(_on_connect_pressed)
	fireboy_button.pressed.connect(_on_fireboy_pressed)
	watergirl_button.pressed.connect(_on_watergirl_pressed)
	
	# Kết nối NetworkManager signals
	NetworkManager.connected_to_server.connect(_on_connected)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.disconnected_from_server.connect(_on_disconnected)
	NetworkManager.player_list_updated.connect(_on_player_list_updated)
	NetworkManager.role_assigned.connect(_on_role_assigned)
	if NetworkManager.has_signal("game_started"):
		NetworkManager.game_started.connect(_on_game_started)

func _on_connect_pressed() -> void:
	var ip = ip_input.text
	var port = port_input.text.to_int()
	
	if ip == "":
		ip = "127.0.0.1"
	if port <= 0:
		port = 9999
		
	status_label.text = "Connecting..."
	connect_button.disabled = true
	
	var err = NetworkManager.connect_to_server(ip, port)
	if err != OK:
		status_label.text = "Failed to create client."
		connect_button.disabled = false

func _on_connected() -> void:
	status_label.text = "Connected! Waiting for players..."
	_update_role_buttons()

func _on_connection_failed() -> void:
	status_label.text = "Connection failed."
	connect_button.disabled = false
	player_list_label.text = ""
	_update_role_buttons()

func _on_disconnected() -> void:
	status_label.text = "Disconnected from server."
	connect_button.disabled = false
	player_list_label.text = ""
	_update_role_buttons()

func _on_player_list_updated(players: Array[int]) -> void:
	var text = "Players in lobby:\n"
	for pid in players:
		var role_name = "Unknown"
		if NetworkManager.player_roles.has(pid):
			var role = NetworkManager.player_roles[pid]
			role_name = "Fireboy" if role == 0 else "Watergirl"
		var my_tag = " (You)" if pid == multiplayer.get_unique_id() else ""
		text += "- Peer %d: %s%s\n" % [pid, role_name, my_tag]
	player_list_label.text = text
	_update_role_buttons()

func _on_role_assigned(role: int) -> void:
	# trigger re-render of list if need be
	_on_player_list_updated(NetworkManager.connected_players)

func _on_game_started() -> void:
	print("[LobbyUI] Loading gameplay scene res://scenes/bootstrap/game.tscn")
	SceneLoader.load_scene("res://scenes/bootstrap/game.tscn")

func _update_role_buttons() -> void:
	var my_peer_id := multiplayer.get_unique_id()
	var is_connected := NetworkManager.is_connected_to_server()
	fireboy_button.disabled = not is_connected or _is_role_taken_by_other(FIREBOY_ROLE, my_peer_id)
	watergirl_button.disabled = not is_connected or _is_role_taken_by_other(WATERGIRL_ROLE, my_peer_id)
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

func _on_fireboy_pressed() -> void:
	NetworkManager.request_role(FIREBOY_ROLE)

func _on_watergirl_pressed() -> void:
	NetworkManager.request_role(WATERGIRL_ROLE)
