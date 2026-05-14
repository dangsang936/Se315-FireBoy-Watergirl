# client/scripts/network_manager.gd
extends Node

@export var player_scene: PackedScene  # Assign Fireboy or Watergirl scene

func _ready():
	# Connect to Photon servers
	FusionClient.connected.connect(_on_connected)
	FusionClient.player_joined.connect(_on_player_joined)
	FusionClient.player_left.connect(_on_player_left)
	
	FusionClient.connect_to_server("Player", "us")

func _on_connected():
	print("Connected to Photon!")
	# Join or create a room (max 2 players for co-op)
	FusionClient.join_or_create_room("firewater-room", {"max_players": 2})

func _on_player_joined(player_ref):
	print("Player joined: ", player_ref)
	# Spawn the appropriate character for this player
	_spawn_player(player_ref)

func _on_player_left(player_ref):
	print("Player left: ", player_ref)

func _spawn_player(player_ref):
	if player_ref.is_local:
		# First player = Fireboy, Second player = Watergirl
		var character = player_scene.instantiate()
		# Add FusionReplicator to sync this object
		add_child(character)
