@tool
class_name BridgePlatform
extends StaticBody2D

signal state_changed(is_active: bool)

enum CascadeDirection { LEFT_TO_RIGHT, RIGHT_TO_LEFT }

const WORLD_COLLISION_LAYER: int = 1
const WORLD_COLLISION_MASK: int = 6

@export var bridge_size: Vector2 = Vector2(176.0, 14.0):
	set(value):
		bridge_size = Vector2(maxf(value.x, 48.0), maxf(value.y, 8.0))
		_sync_collision_shape()

@export var start_active: bool = false
@export var reveal_duration: float = 0.18
@export var hidden_y_offset: float = 28.0
@export var tile_stagger: float = 0.045
@export var cascade_direction: CascadeDirection = CascadeDirection.RIGHT_TO_LEFT
@export_range(0.0, 1.0, 0.05) var editor_preview_alpha: float = 0.24
@export var collision_shape_path: NodePath = ^"CollisionShape2D"
@export var visual_layer_path: NodePath = ^"Visual"

var _is_active: bool = false
var _piece_layers: Array[TileMapLayer] = []
var _piece_order: Array[int] = []
var _piece_progress: Array[float] = []
var _piece_base_positions: Array[Vector2] = []
var _piece_tweens: Array[Tween] = []
var _state_tween: Tween
var _piece_container: Node2D

@onready var _collision_shape: CollisionShape2D = get_node_or_null(collision_shape_path) as CollisionShape2D
@onready var _visual_layer: TileMapLayer = get_node_or_null(visual_layer_path) as TileMapLayer

func _ready() -> void:
	collision_layer = WORLD_COLLISION_LAYER
	collision_mask = WORLD_COLLISION_MASK
	_ensure_collision_shape()
	_sync_collision_shape()
	_configure_template_visual_layer()

	if Engine.is_editor_hint():
		_apply_editor_preview()
		return

	_build_piece_layers()
	_apply_state(start_active, false)

func activate() -> void:
	set_active(true)

func deactivate() -> void:
	set_active(false)

func set_active(is_active: bool) -> void:
	_apply_state(is_active, true)

func is_active() -> bool:
	return _is_active

func _ensure_collision_shape() -> void:
	if _collision_shape != null:
		return

	_collision_shape = CollisionShape2D.new()
	_collision_shape.name = "CollisionShape2D"
	add_child(_collision_shape)

func _sync_collision_shape() -> void:
	if _collision_shape == null:
		return

	var rectangle_shape := _collision_shape.shape as RectangleShape2D
	if rectangle_shape == null:
		rectangle_shape = RectangleShape2D.new()
		_collision_shape.shape = rectangle_shape

	rectangle_shape.size = bridge_size

func _configure_template_visual_layer() -> void:
	if _visual_layer == null:
		return

	_visual_layer.collision_enabled = false
	_visual_layer.navigation_enabled = false

func _apply_editor_preview() -> void:
	if _visual_layer != null:
		_visual_layer.visible = true
		_visual_layer.modulate = Color(1.0, 1.0, 1.0, 1.0 if start_active else editor_preview_alpha)
		_visual_layer.position = Vector2.ZERO

	if _collision_shape != null:
		_collision_shape.disabled = not start_active

func _build_piece_layers() -> void:
	_clear_piece_layers()
	if _visual_layer == null or _visual_layer.tile_set == null:
		return

	_piece_container = Node2D.new()
	_piece_container.name = "PieceVisuals"
	add_child(_piece_container)

	var used_cells: Array[Vector2i] = _visual_layer.get_used_cells()
	used_cells.sort_custom(_compare_cells_for_activation)

	var piece_index: int = 0
	for cell: Vector2i in used_cells:
		var source_id: int = _visual_layer.get_cell_source_id(cell)
		if source_id == -1:
			continue

		var piece := TileMapLayer.new()
		piece.name = "PieceVisual%d" % piece_index
		piece.tile_set = _visual_layer.tile_set
		piece.position = _visual_layer.position
		piece.z_index = _visual_layer.z_index
		piece.collision_enabled = false
		piece.navigation_enabled = false
		piece.occlusion_enabled = _visual_layer.occlusion_enabled
		piece.modulate = Color(1.0, 1.0, 1.0, 0.0)
		piece.visible = false

		var atlas_coords: Vector2i = _visual_layer.get_cell_atlas_coords(cell)
		var alternative_tile: int = _visual_layer.get_cell_alternative_tile(cell)
		piece.set_cell(cell, source_id, atlas_coords, alternative_tile)

		_piece_container.add_child(piece)
		_piece_layers.append(piece)
		_piece_order.append(piece_index)
		_piece_progress.append(0.0)
		_piece_base_positions.append(piece.position)
		_piece_tweens.append(null)
		piece_index += 1

	_visual_layer.visible = false

func _clear_piece_layers() -> void:
	_kill_piece_tweens()

	if _state_tween != null:
		_state_tween.kill()
		_state_tween = null

	if _piece_container != null and is_instance_valid(_piece_container):
		_piece_container.queue_free()

	_piece_layers.clear()
	_piece_order.clear()
	_piece_progress.clear()
	_piece_base_positions.clear()
	_piece_tweens.clear()
	_piece_container = null

func _kill_piece_tweens() -> void:
	for tween: Tween in _piece_tweens:
		if tween != null:
			tween.kill()

func _compare_cells_for_activation(a: Vector2i, b: Vector2i) -> bool:
	if a.x == b.x:
		return a.y < b.y

	if cascade_direction == CascadeDirection.RIGHT_TO_LEFT:
		return a.x > b.x
	return a.x < b.x

func _apply_state(is_active: bool, animate: bool) -> void:
	_is_active = is_active

	if Engine.is_editor_hint():
		_apply_editor_preview()
		return

	if _state_tween != null:
		_state_tween.kill()
		_state_tween = null

	_kill_piece_tweens()

	if _collision_shape != null and not _is_active:
		_collision_shape.disabled = true

	var target_progress: float = 1.0 if _is_active else 0.0
	var ordered_indices: Array[int] = _piece_order.duplicate()
	if not _is_active:
		ordered_indices.reverse()

	if not animate:
		for piece_index: int in _piece_order:
			_set_piece_progress(target_progress, piece_index)
		_finalize_state()
		state_changed.emit(_is_active)
		return

	var total_duration: float = 0.0
	for order_index: int in range(ordered_indices.size()):
		var piece_index: int = ordered_indices[order_index]
		if _is_active:
			_piece_layers[piece_index].visible = true

		var delay: float = tile_stagger * float(order_index)
		total_duration = maxf(total_duration, delay + reveal_duration)

		var tween := create_tween()
		tween.tween_method(
			Callable(self, "_set_piece_progress").bind(piece_index),
			_piece_progress[piece_index],
			target_progress,
			reveal_duration
		).set_delay(delay)
		_piece_tweens[piece_index] = tween

	_state_tween = create_tween()
	if total_duration > 0.0:
		_state_tween.tween_interval(total_duration)
	_state_tween.tween_callback(Callable(self, "_finalize_state"))

	state_changed.emit(_is_active)

func _set_piece_progress(next_progress: float, piece_index: int) -> void:
	if piece_index < 0 or piece_index >= _piece_layers.size():
		return

	var clamped_progress: float = clampf(next_progress, 0.0, 1.0)
	_piece_progress[piece_index] = clamped_progress

	var piece: TileMapLayer = _piece_layers[piece_index]
	piece.position = _piece_base_positions[piece_index] + Vector2(0.0, lerpf(hidden_y_offset, 0.0, clamped_progress))
	piece.modulate = Color(1.0, 1.0, 1.0, clamped_progress)
	piece.visible = clamped_progress > 0.001

func _finalize_state() -> void:
	if _is_active:
		for piece_index: int in _piece_order:
			_set_piece_progress(1.0, piece_index)
		if _collision_shape != null:
			_collision_shape.disabled = false
		return

	for piece_index: int in _piece_order:
		_set_piece_progress(0.0, piece_index)
	if _collision_shape != null:
		_collision_shape.disabled = true
