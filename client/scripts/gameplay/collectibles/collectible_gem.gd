class_name CollectibleGem
extends Area2D

enum GemElement { FIRE, WATER }

const GEM_COLLISION_LAYER: int = 32
const GEM_COLLISION_MASK: int = 2

signal collected(gem: CollectibleGem, player: PrototypePlayer)
signal wrong_element_touched(gem: CollectibleGem, player: PrototypePlayer)

@export var gem_element: GemElement = GemElement.FIRE
@export var visual_path: NodePath = ^"AnimatedSprite2D"

var _is_collected: bool = false
var _base_modulate: Color = Color.WHITE

@onready var _visual: CanvasItem = get_node_or_null(visual_path) as CanvasItem

func _ready() -> void:
	collision_layer = GEM_COLLISION_LAYER
	collision_mask = GEM_COLLISION_MASK
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	_cache_visual_state()

func can_collect(player: PrototypePlayer) -> bool:
	return int(player.get_element()) == int(gem_element)

func _on_body_entered(body: Node2D) -> void:
	if _is_collected:
		return

	var player := body as PrototypePlayer
	if player == null or not player.is_in_group("player"):
		return

	if not can_collect(player):
		wrong_element_touched.emit(self, player)
		_play_wrong_element_feedback()
		return

	_is_collected = true
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	visible = false
	collected.emit(self, player)

func _cache_visual_state() -> void:
	if _visual == null:
		return
	_base_modulate = _visual.modulate

func _play_wrong_element_feedback() -> void:
	if _visual == null:
		return
	var tween := create_tween()
	tween.tween_property(_visual, "modulate", Color(1.0, 1.0, 1.0, 0.35), 0.05)
	tween.tween_property(_visual, "modulate", _base_modulate, 0.12)
