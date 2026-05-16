class_name CollectibleGem
extends Area2D

enum GemElement { FIRE, WATER }

signal collected(gem: CollectibleGem, player: PrototypePlayer)
signal wrong_element_touched(gem: CollectibleGem, player: PrototypePlayer)

@export var gem_element: GemElement = GemElement.FIRE
@export var visual_path: NodePath = ^"Visual"

var _is_collected: bool = false
var _base_color: Color = Color.WHITE

@onready var _visual: Polygon2D = get_node_or_null(visual_path) as Polygon2D

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_apply_element_color()

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
