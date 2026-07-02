extends Control

const FIREBOY_ROLE: int = 0
const WATERGIRL_ROLE: int = 1

@onready var name_input: LineEdit = $"CenterContainer/MainPanel/Margin/Layout/NameSection/NameInput"
@onready var tabs: TabContainer = $"CenterContainer/MainPanel/Margin/Layout/TabPanel/Tabs"
@onready var quick_match_btn: Button = $"CenterContainer/MainPanel/Margin/Layout/TabPanel/Tabs/Matchmaking/VBox/QuickMatchBtn"
@onready var room_name_input: LineEdit = $"CenterContainer/MainPanel/Margin/Layout/TabPanel/Tabs/Server Browser/VBox/Toolbar/RoomNameInput"
@onready var host_btn: Button = $"CenterContainer/MainPanel/Margin/Layout/TabPanel/Tabs/Server Browser/VBox/Toolbar/HostBtn"
@onready var refresh_btn: Button = $"CenterContainer/MainPanel/Margin/Layout/TabPanel/Tabs/Server Browser/VBox/Toolbar/RefreshBtn"
@onready var room_list_container: VBoxContainer = $"CenterContainer/MainPanel/Margin/Layout/TabPanel/Tabs/Server Browser/VBox/Scroll/RoomList"

@onready var ip_input: LineEdit = $"CenterContainer/MainPanel/Margin/Layout/TabPanel/Tabs/Direct Connect/VBox/IPRow/IPInput"
@onready var port_input: LineEdit = $"CenterContainer/MainPanel/Margin/Layout/TabPanel/Tabs/Direct Connect/VBox/PortRow/PortInput"
@onready var direct_btn: Button = $"CenterContainer/MainPanel/Margin/Layout/TabPanel/Tabs/Direct Connect/VBox/DirectBtn"

@onready var active_room: VBoxContainer = $"CenterContainer/MainPanel/Margin/Layout/ActiveRoom"
@onready var room_title: Label = $"CenterContainer/MainPanel/Margin/Layout/ActiveRoom/RoomTitle"
@onready var fireboy_name: Label = $"CenterContainer/MainPanel/Margin/Layout/ActiveRoom/Slots/FireboySlot/Margin/VBox/PlayerName"
@onready var watergirl_name: Label = $"CenterContainer/MainPanel/Margin/Layout/ActiveRoom/Slots/WatergirlSlot/Margin/VBox/PlayerName"
@onready var leave_btn: Button = $"CenterContainer/MainPanel/Margin/Layout/ActiveRoom/LeaveBtn"

@onready var status_label: Label = $"CenterContainer/MainPanel/Margin/Layout/StatusLine/StatusLabel"
@onready var lan_checkbox: CheckBox = $"CenterContainer/MainPanel/Margin/Layout/StatusLine/LANCheckbox"

# Themes & Styling
@onready var main_panel: PanelContainer = $"CenterContainer/MainPanel"
@onready var tab_panel: PanelContainer = $"CenterContainer/MainPanel/Margin/Layout/TabPanel"
@onready var fireboy_slot: PanelContainer = $"CenterContainer/MainPanel/Margin/Layout/ActiveRoom/Slots/FireboySlot"
@onready var watergirl_slot: PanelContainer = $"CenterContainer/MainPanel/Margin/Layout/ActiveRoom/Slots/WatergirlSlot"

func _ready() -> void:
	# Kết nối UI signals
	quick_match_btn.pressed.connect(_on_quick_match_pressed)
	host_btn.pressed.connect(_on_host_pressed)
	refresh_btn.pressed.connect(_on_refresh_pressed)
	direct_btn.pressed.connect(_on_direct_pressed)
	leave_btn.pressed.connect(_on_leave_pressed)

	# Kết nối NetworkManager signals
	NetworkManager.connected_to_server.connect(_on_connected_to_server)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.disconnected_from_server.connect(_on_disconnected_from_server)
	NetworkManager.player_list_updated.connect(_on_player_list_updated)
	NetworkManager.role_assigned.connect(_on_role_assigned)
	NetworkManager.game_started.connect(_on_game_started)
	NetworkManager.rooms_list_received.connect(_on_rooms_list_received)

	# Apply premium glassmorphic UI styles programmatically
	_apply_styling()
	_update_ui_state(false)

func _apply_styling() -> void:
	# Base Colors
	var bg_panel = Color(0.1, 0.12, 0.16, 0.85) # Semi-translucent dark slate
	var bg_inner = Color(0.07, 0.08, 0.1, 0.9)
	var border_color = Color(0.2, 0.25, 0.35, 1.0)
	var orange_fire = Color(0.98, 0.45, 0.09, 1.0)
	var blue_water = Color(0.0, 0.6, 1.0, 1.0)

	# Main Panel style
	var style_main = StyleBoxFlat.new()
	style_main.bg_color = bg_panel
	style_main.set_corner_radius_all(16)
	style_main.border_width_left = 2
	style_main.border_width_top = 2
	style_main.border_width_right = 2
	style_main.border_width_bottom = 2
	style_main.border_color = border_color
	style_main.shadow_color = Color(0, 0, 0, 0.5)
	style_main.shadow_size = 20
	main_panel.add_theme_stylebox_override("panel", style_main)

	# Inner Tab Panel style
	var style_tab = StyleBoxFlat.new()
	style_tab.bg_color = bg_inner
	style_tab.set_corner_radius_all(8)
	tab_panel.add_theme_stylebox_override("panel", style_tab)

	# Fireboy Slot Style (Orange accent)
	var style_fire = StyleBoxFlat.new()
	style_fire.bg_color = Color(0.98, 0.45, 0.09, 0.08)
	style_fire.set_corner_radius_all(10)
	style_fire.border_width_left = 2
	style_fire.border_width_top = 2
	style_fire.border_width_right = 2
	style_fire.border_width_bottom = 2
	style_fire.border_color = orange_fire
	fireboy_slot.add_theme_stylebox_override("panel", style_fire)

	# Watergirl Slot Style (Blue accent)
	var style_water = StyleBoxFlat.new()
	style_water.bg_color = Color(0.0, 0.6, 1.0, 0.08)
	style_water.set_corner_radius_all(10)
	style_water.border_width_left = 2
	style_water.border_width_top = 2
	style_water.border_width_right = 2
	style_water.border_width_bottom = 2
	style_water.border_color = blue_water
	watergirl_slot.add_theme_stylebox_override("panel", style_water)

	# Apply button styles
	_style_button(quick_match_btn, Color(0.2, 0.6, 0.3, 1.0)) # Green button
	_style_button(host_btn, Color(0.8, 0.4, 0.1, 1.0)) # Orange button
	_style_button(refresh_btn, Color(0.25, 0.3, 0.4, 1.0))
	_style_button(direct_btn, Color(0.25, 0.45, 0.8, 1.0)) # Blue button
	_style_button(leave_btn, Color(0.7, 0.2, 0.2, 1.0)) # Red button

func _style_button(btn: Button, base_color: Color) -> void:
	var sb_normal = StyleBoxFlat.new()
	sb_normal.bg_color = base_color
	sb_normal.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", sb_normal)

	var sb_hover = StyleBoxFlat.new()
	sb_hover.bg_color = base_color.lightened(0.15)
	sb_hover.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("hover", sb_hover)

	var sb_pressed = StyleBoxFlat.new()
	sb_pressed.bg_color = base_color.darkened(0.15)
	sb_pressed.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("pressed", sb_pressed)

# --- UI State Controller ---

func _update_ui_state(in_room: bool) -> void:
	# Hide tabs and show active room if connected
	tabs.visible = not in_room
	name_input.editable = not in_room
	lan_checkbox.disabled = in_room
	active_room.visible = in_room

	if not in_room:
		# Reset slots text
		fireboy_name.text = "Waiting for player..."
		watergirl_name.text = "Waiting for player..."

# --- Button Handlers ---

func _on_quick_match_pressed() -> void:
	status_label.text = "Finding a match on master server..."
	quick_match_btn.disabled = true

	NetworkManager.request_matchmake(func(code: int, response: Dictionary):
		quick_match_btn.disabled = false
		if code == 200:
			var action = response.get("action", "")
			if action == "host":
				status_label.text = "No empty rooms found. Starting authorized server for matchmaking..."
				if not NetworkManager.room_created.is_connected(_on_lobby_room_created):
					NetworkManager.room_created.connect(_on_lobby_room_created, CONNECT_ONE_SHOT)
				if not NetworkManager.room_creation_failed.is_connected(_on_lobby_room_failed):
					NetworkManager.room_creation_failed.connect(_on_lobby_room_failed, CONNECT_ONE_SHOT)
				NetworkManager.host_room(9999)
			elif action == "join":
				var ip = response.get("ip", "127.0.0.1")
				var port = int(response.get("port", 9999))
				status_label.text = "Match found! Connecting to " + ip + ":" + str(port) + "..."
				NetworkManager.connect_to_server(ip, port)
		else:
			status_label.text = "Matchmaking failed. Is the Master Server running?"
	)

func _on_host_pressed() -> void:
	host_btn.disabled = true
	status_label.text = "Starting server..."

	# Connect one-shot signals before calling host_room so we catch the result.
	if not NetworkManager.room_created.is_connected(_on_lobby_room_created):
		NetworkManager.room_created.connect(_on_lobby_room_created, CONNECT_ONE_SHOT)
	if not NetworkManager.room_creation_failed.is_connected(_on_lobby_room_failed):
		NetworkManager.room_creation_failed.connect(_on_lobby_room_failed, CONNECT_ONE_SHOT)

	NetworkManager.host_room(9999)

func _on_lobby_room_created() -> void:
	# room_creation_failed one-shot may still be connected if room_created fired first.
	if NetworkManager.room_creation_failed.is_connected(_on_lobby_room_failed):
		NetworkManager.room_creation_failed.disconnect(_on_lobby_room_failed)
	host_btn.disabled = false
	status_label.text = "Waiting for opponent..."

func _on_lobby_room_failed(reason: String) -> void:
	if NetworkManager.room_created.is_connected(_on_lobby_room_created):
		NetworkManager.room_created.disconnect(_on_lobby_room_created)
	host_btn.disabled = false
	status_label.text = "Failed to host: " + reason

func _on_refresh_pressed() -> void:
	status_label.text = "Refreshing room list..."
	NetworkManager.fetch_rooms()

func _on_rooms_list_received(rooms: Array) -> void:
	for child in room_list_container.get_children():
		child.queue_free()

	if rooms.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No rooms found."
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		room_list_container.add_child(empty_label)
		status_label.text = "No rooms found."
		return

	for room in rooms:
		if not room is Dictionary:
			continue
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var room_label := Label.new()
		room_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		room_label.text = "%s - %s/%s players" % [
			str(room.get("name", "Unnamed Room")),
			str(room.get("players", 0)),
			str(room.get("max_players", 2)),
		]
		row.add_child(room_label)

		var join_btn := Button.new()
		join_btn.text = "Join"
		join_btn.pressed.connect(func():
			var ip := str(room.get("ip", "127.0.0.1"))
			var port := int(room.get("port", 9999))
			status_label.text = "Connecting to " + ip + ":" + str(port) + "..."
			NetworkManager.connect_to_server(ip, port)
		)
		row.add_child(join_btn)
		room_list_container.add_child(row)

	status_label.text = "Found %d room(s)." % rooms.size()

func _on_direct_pressed() -> void:
	var ip = ip_input.text.strip_edges()
	var port = port_input.text.to_int()
	if ip == "":
		ip = "127.0.0.1"
	if port <= 0:
		port = 9999

	status_label.text = "Connecting directly to " + ip + ":" + str(port) + "..."
	NetworkManager.connect_to_server(ip, port)

func _on_leave_pressed() -> void:
	status_label.text = "Leaving lobby..."
	NetworkManager.disconnect_from_server()
	_update_ui_state(false)

func _on_connected_to_server() -> void:
	status_label.text = "Connected!"
	_update_ui_state(true)

	if NetworkManager.is_host:
		room_title.text = "Lobby: " + room_name_input.text
	else:
		room_title.text = "Lobby Room (Connected)"

	# Initial slot rendering
	_on_player_list_updated(NetworkManager.connected_players)

func _on_connection_failed() -> void:
	status_label.text = "Connection failed."

func _on_disconnected_from_server() -> void:
	status_label.text = "Disconnected from server."
	_update_ui_state(false)

func _on_player_list_updated(players: Array[int]) -> void:
	# Clear slots
	fireboy_name.text = "Waiting for player..."
	watergirl_name.text = "Waiting for player..."

	# Determine player tags and update slots
	for pid in players:
		var role := NetworkManager.player_roles.get(pid, -1)
		var my_tag := " (You)" if pid == multiplayer.get_unique_id() else ""
		var player_text := "Peer %d%s" % [pid, my_tag]
		if role == FIREBOY_ROLE:
			fireboy_name.text = player_text
		elif role == WATERGIRL_ROLE:
			watergirl_name.text = player_text

func _on_role_assigned(_role: int) -> void:
	# Force re-render of slot tags
	_on_player_list_updated(NetworkManager.connected_players)

func _on_game_started() -> void:
	print("[LobbyUI] Loading gameplay scene res://scenes/bootstrap/game.tscn")
	SceneLoader.load_scene("res://scenes/bootstrap/game.tscn")
