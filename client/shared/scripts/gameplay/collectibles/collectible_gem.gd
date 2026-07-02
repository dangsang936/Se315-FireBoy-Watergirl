class_name CollectibleGem
extends Area2D

enum GemElement { FIRE, WATER }

signal collected(gem: CollectibleGem, player: PrototypePlayer)
signal wrong_element_touched(gem: CollectibleGem, player: PrototypePlayer)

const GEM_COLLISION_LAYER: int = 32
const GEM_COLLISION_MASK: int = 2

@export var gem_element: GemElement = GemElement.FIRE
@export var visual_path: NodePath = ^"Visual"

var _is_collected: bool = false
var _base_color: Color = Color.WHITE

@onready var _visual: Polygon2D = get_node_or_null(visual_path) as Polygon2D

func _ready() -> void:
	add_to_group("collectible_gem")
	collision_layer = GEM_COLLISION_LAYER
	collision_mask = GEM_COLLISION_MASK
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	monitoring = true
	monitorable = true
	_apply_element_color()

func can_collect(player: PrototypePlayer) -> bool:
	return player != null and int(player.element) == int(gem_element)

func _on_body_entered(body: Node2D) -> void:
	if _is_collected or not body.is_in_group("player"):
		return

	var player := body as PrototypePlayer
	if player == null:
		return
	if player.get("is_local") == false:
		return

	if not can_collect(player):
		wrong_element_touched.emit(self, player)
		return

	var network_manager := get_node_or_null("/root/NetworkManager")
	if network_manager != null and bool(network_manager.call("is_connected_to_server")):
		var level := _find_level_root()
		var gem_path := str(level.get_path_to(self)) if level != null else str(get_path())
		network_manager.call("send_collect_gem", gem_path)
		return

	_collect_locally(player)

func _find_level_root() -> Node:
	var node: Node = self
	while node != null:
		if node is PrototypeLevel:
			return node
		node = node.get_parent()
	return null

func _collect_locally(player: PrototypePlayer) -> void:
	if _is_collected:
		return
	_is_collected = true
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	visible = false
	collected.emit(self, player)

func collect_remotely() -> void:
	if _is_collected:
		return
	_is_collected = true
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	visible = false

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
