class_name CollectibleGem
extends Area2D

enum GemElement { FIRE, WATER }

signal collected(gem: CollectibleGem, player_id: int)
signal wrong_element_touched(gem: CollectibleGem, player_id: int)

@export var gem_element: GemElement = GemElement.FIRE
@export var visual_path: NodePath = ^"Visual"

var _is_collected: bool = false
var _base_color: Color = Color.WHITE

@onready var _visual: Polygon2D = get_node_or_null(visual_path) as Polygon2D

func _ready() -> void:
	if multiplayer.is_server():
		body_entered.connect(_on_body_entered)
	_apply_element_color()

func can_collect(player_element: int) -> bool:
	return player_element == int(gem_element)

func _on_body_entered(body: Node2D) -> void:
	if _is_collected:
		return

	if not body.is_in_group("player"):
		return
		
	var pid: int = 0
	var p_element: int = 0
	
	if body.has_method("get_element"):
		pid = body.get("player_id")
		p_element = int(body.get_element())
	else:
		pid = body.get_meta("player_id", 0)
		p_element = body.get_meta("element", 0)

	if pid == 0:
		return

	if not can_collect(p_element):
		wrong_element_touched.emit(self, pid)
		rpc("client_wrong_element")
		return

	_is_collected = true
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	visible = false
	collected.emit(self, pid)
	var rpc_node = get_node_or_null("/root/GameplayRPC")
	if rpc_node:
		rpc_node.rpc("sync_gem_collected", name)

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
