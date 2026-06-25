extends Control

# UI References
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
	# Random default nickname
	name_input.text = "Player_" + str(randi() % 900 + 100)
	room_name_input.text = name_input.text + "'s Room"

	# Connect Buttons
	quick_match_btn.pressed.connect(_on_quick_match_pressed)
	host_btn.pressed.connect(_on_host_pressed)
	refresh_btn.pressed.connect(_on_refresh_pressed)
	direct_btn.pressed.connect(_on_direct_pressed)
	leave_btn.pressed.connect(_on_leave_pressed)

	# Connect NetworkManager Signals
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
	lan_checkbox.editable = not in_room
	active_room.visible = in_room
	
	if not in_room:
		# Reset slots text
		fireboy_name.text = "Waiting for player..."
		watergirl_name.text = "Waiting for player..."

# --- Button Handlers ---

func _on_quick_match_pressed() -> void:
	status_label.text = "Finding a match on master server..."
	quick_match_btn.disabled = true
	
	NetworkManager.request_matchmake(func(status: int, response: Dictionary):
		quick_match_btn.disabled = false
		if status == 200:
			var action = response.get("action", "")
			if action == "host":
				status_label.text = "No empty rooms found. Hosting a new matchmaking room..."
				var name_to_use = name_input.text + "'s Match"
				var err = NetworkManager.host_game(name_to_use, 9999, lan_checkbox.button_pressed)
				if err != OK:
					status_label.text = "Failed to host matchmaking lobby."
			elif action == "join":
				var ip = response.get("ip", "127.0.0.1")
				var port = int(response.get("port", 9999))
				status_label.text = "Match found! Connecting to " + ip + ":" + str(port) + "..."
				NetworkManager.connect_to_server(ip, port)
		else:
			status_label.text = "Matchmaking failed. Is the Master Server running?"
	)

func _on_host_pressed() -> void:
	var rname = room_name_input.text.strip_edges()
	if rname == "":
		rname = name_input.text + "'s Lobby"
	
	status_label.text = "Hosting room: " + rname + "..."
	var err = NetworkManager.host_game(rname, 9999, lan_checkbox.button_pressed)
	if err != OK:
		status_label.text = "Failed to host lobby."

func _on_refresh_pressed() -> void:
	status_label.text = "Refreshing room list..."
	NetworkManager.fetch_rooms()

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

# --- Network Signal Callbacks ---

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
	_update_ui_state(false)

func _on_disconnected_from_server() -> void:
	status_label.text = "Disconnected from server."
	_update_ui_state(false)

func _on_player_list_updated(players: Array[int]) -> void:
	# Clear slots
	fireboy_name.text = "Waiting for player..."
	watergirl_name.text = "Waiting for player..."
	
	# Determine player tags and update slots
	for pid in players:
		var role = -1
		if NetworkManager.player_roles.has(pid):
			role = NetworkManager.player_roles[pid]
		
		var my_tag = " (You)" if pid == multiplayer.get_unique_id() or (NetworkManager.is_host and pid == 1) else ""
		var label_text = "Peer %d%s" % [pid, my_tag]
		if pid == 1 and NetworkManager.is_host:
			label_text = name_input.text + my_tag + " (Host)"
		elif pid != 1 and NetworkManager.is_host:
			label_text = "Peer %d (Guest)" % pid
		elif pid == 1 and not NetworkManager.is_host:
			label_text = "Host"
		else:
			label_text = name_input.text + my_tag + " (Guest)"

		if role == 0:
			fireboy_name.text = label_text
		elif role == 1:
			watergirl_name.text = label_text

func _on_role_assigned(_role: int) -> void:
	# Force re-render of slot tags
	_on_player_list_updated(NetworkManager.connected_players)

func _on_game_started() -> void:
	status_label.text = "Game starting! Loading level..."
	get_tree().change_scene_to_file("res://scenes/bootstrap/game.tscn")

func _on_rooms_list_received(rooms: Array) -> void:
	# Clear old items
	for child in room_list_container.get_children():
		child.queue_free()
		
	if rooms.size() == 0:
		status_label.text = "No active rooms found."
		var no_room_lbl = Label.new()
		no_room_lbl.text = "No rooms hosted. Be the first!"
		no_room_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		no_room_lbl.modulate = Color(0.5, 0.5, 0.5)
		room_list_container.add_child(no_room_lbl)
		return
		
	status_label.text = "Found " + str(rooms.size()) + " room(s)."
	
	# Populate list
	for room in rooms:
		var room_id = room.get("id", "")
		var rname = room.get("name", "Unnamed Room")
		var rip = room.get("ip", "127.0.0.1")
		var rport = int(room.get("port", 9999))
		var rplayers = int(room.get("players", 1))
		var rmax = int(room.get("max_players", 2))
		
		# Card Row
		var card = PanelContainer.new()
		var card_style = StyleBoxFlat.new()
		card_style.bg_color = Color(0.12, 0.15, 0.2, 1.0)
		card_style.set_corner_radius_all(6)
		card.add_theme_stylebox_override("panel", card_style)
		
		var margin = MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 10)
		margin.add_theme_constant_override("margin_top", 6)
		margin.add_theme_constant_override("margin_right", 10)
		margin.add_theme_constant_override("margin_bottom", 6)
		card.add_child(margin)
		
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 15)
		margin.add_child(hbox)
		
		# Room Details Label
		var label = Label.new()
		label.text = "%s (%s:%d) - Players: %d/%d" % [rname, rip, rport, rplayers, rmax]
		label.size_flags_horizontal = SIZE_EXPAND_FILL
		hbox.add_child(label)
		
		# Join Button
		var join_btn = Button.new()
		join_btn.text = "JOIN"
		_style_button(join_btn, Color(0.15, 0.5, 0.7, 1.0))
		join_btn.custom_minimum_size = Vector2(80, 0)
		
		# If lobby is full, disable join
		if rplayers >= rmax:
			join_btn.disabled = True
			join_btn.text = "FULL"
			
		join_btn.pressed.connect(func():
			status_label.text = "Connecting to " + rip + ":" + str(rport) + "..."
			NetworkManager.connect_to_server(rip, rport)
		)
		hbox.add_child(join_btn)
		
		room_list_container.add_child(card)
