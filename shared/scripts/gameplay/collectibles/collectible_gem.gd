class_name CollectibleGem
extends Area2D

enum GemElement { FIRE, WATER }

signal collected(gem: CollectibleGem, player: Node2D)
signal wrong_element_touched(gem: CollectibleGem, player: Node2D)

const GEM_COLLISION_LAYER: int = 32
const GEM_COLLISION_MASK: int = 2

@export var gem_element: GemElement = GemElement.FIRE
@export var visual_path: NodePath = ^"Visual"

var _is_collected: bool = false
var _base_color: Color = Color.WHITE

@onready var _visual: Polygon2D = get_node_or_null(visual_path) as Polygon2D

func _ready() -> void:
	add_to_group("collectible_gem")
	if multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
		# Server (or offline) runs collision detection and is the sole authority
		# on whether a gem is collected.
		body_entered.connect(_on_body_entered)
		monitoring = true
		monitorable = true
		collision_layer = GEM_COLLISION_LAYER
		collision_mask = GEM_COLLISION_MASK
	else:
		# Clients never self-collect — state arrives via GameplayRpc.sync_gem_collected.
		monitoring = false
		monitorable = false
	_apply_element_color()

func can_collect(player: Node2D) -> bool:
	return _get_player_element(player) == int(gem_element)

func _on_body_entered(body: Node2D) -> void:
	if _is_collected or not body.is_in_group("player"):
		return
		
	var player := body
	var pid := _get_player_id(player)

	if pid == 0:
		return

	if not can_collect(player):
		wrong_element_touched.emit(self, player)
		# Tell clients to play the "wrong element" animation
		rpc("client_wrong_element")
		return 

	var msg: String = "[Server] Player " + str(pid) + " collect gem: " + name
	print(msg)
	
	var nm = get_node_or_null("/root/NetworkManager")
	if nm and nm.has_method("s_print"):
		nm.s_print(msg)
		
	_is_collected = true
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	visible = false
	
	# --> THE FIX: Broadcast to all clients to visually hide the gem! <--
	var rpc_node := get_node_or_null("/root/GameplayRpc")
	if rpc_node and rpc_node.has_method("sync_gem_collected"):
		rpc_node.rpc("sync_gem_collected", name, global_position)
		
	collected.emit(self, player)

@rpc("authority", "call_local", "reliable")
func client_collect_gem() -> void:
	_is_collected = true
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	visible = false

@rpc("authority", "call_local", "reliable")
func client_wrong_element() -> void:
	_play_wrong_element_feedback()

func _apply_element_color() -> void:
	if _visual == null:
		return
	match gem_element:
		GemElement.WATER:
			_base_color = Color(0.18, 0.62, 1.0, 0.95)
		_:
			_base_color = Color(1.0, 0.2, 0.08, 0.95)
	_visual.color = _base_color
	_visual.modulate = Color.WHITE

func _play_wrong_element_feedback() -> void:
	if _visual == null:
		return
	var tween := create_tween()
	tween.tween_property(_visual, "modulate", Color(1.0, 1.0, 1.0, 0.35), 0.05)
	tween.tween_property(_visual, "modulate", Color.WHITE, 0.12)

func _get_player_id(player: Node2D) -> int:
	if player == null:
		return 0
	if player.has_meta("player_id"):
		return int(player.get_meta("player_id"))
	if "player_id" in player:
		return int(player.get("player_id"))
	return 0

func _get_player_element(player: Node2D) -> int:
	if player == null:
		return -1
	if player.has_meta("element"):
		return int(player.get_meta("element"))
	if player.has_method("get_element"):
		return int(player.call("get_element"))
	if "element" in player:
		return int(player.get("element"))
	return -1
