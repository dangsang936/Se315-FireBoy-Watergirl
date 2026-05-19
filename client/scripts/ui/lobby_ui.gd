extends Control

@onready var ip_input: LineEdit = $VBoxContainer/IPContainer/IPInput
@onready var port_input: LineEdit = $VBoxContainer/PortContainer/PortInput
@onready var connect_button: Button = $VBoxContainer/ConnectButton
@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var player_list_label: Label = $VBoxContainer/PlayerList

func _ready() -> void:
	# Kết nối UI signals
	connect_button.pressed.connect(_on_connect_pressed)
	
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

func _on_connection_failed() -> void:
	status_label.text = "Connection failed."
	connect_button.disabled = false

func _on_disconnected() -> void:
	status_label.text = "Disconnected from server."
	connect_button.disabled = false
	player_list_label.text = ""

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

func _on_role_assigned(role: int) -> void:
	# trigger re-render of list if need be
	_on_player_list_updated(NetworkManager.connected_players)

func _on_game_started() -> void:
	get_tree().change_scene_to_file("res://scenes/bootstrap/game.tscn")
