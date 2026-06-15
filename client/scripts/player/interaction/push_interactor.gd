class_name PushInteractor
extends Node

var owner_player: PrototypePlayer
var collision_shape: CollisionShape2D
var last_push_contact: bool = false

func setup(player: PrototypePlayer, shape: CollisionShape2D) -> void:
	owner_player = player
	collision_shape = shape

func register_contacts(push_direction: float) -> bool:
	last_push_contact = false
	if owner_player == null or push_direction == 0.0:
		return false

	if _register_push_block_probe(push_direction):
		last_push_contact = true

	for index: int in owner_player.get_slide_collision_count():
		var collision := owner_player.get_slide_collision(index)
		var collider := collision.get_collider()
		var collider_node := collider as Node2D
		if collider_node == null or not collider_node.has_method("register_push_attempt"):
			continue
		if absf(collision.get_normal().x) < 0.35:
			continue
		if signf(push_direction) != -signf(collision.get_normal().x):
			continue
		collider_node.call("register_push_attempt", owner_player, push_direction)
		last_push_contact = true

	return last_push_contact

func clear_contact() -> void:
	last_push_contact = false

func _register_push_block_probe(push_direction: float) -> bool:
	if owner_player == null or collision_shape == null or collision_shape.shape == null:
		return false

	var rectangle := collision_shape.shape as RectangleShape2D
	if rectangle == null:
		return false

	var half_size: Vector2 = rectangle.size * 0.5
	var center: Vector2 = collision_shape.global_position
	var probe_height: float = maxf(rectangle.size.y - owner_player.push_probe_vertical_padding * 2.0, 2.0)
	var probe_shape := RectangleShape2D.new()
	probe_shape.size = Vector2(owner_player.push_probe_distance, probe_height)
	var probe_center := Vector2(center.x + signf(push_direction) * (half_size.x + owner_player.push_probe_distance * 0.5), center.y)
	var shape_query := PhysicsShapeQueryParameters2D.new()
	shape_query.shape = probe_shape
	shape_query.transform = Transform2D(0.0, probe_center)
	shape_query.exclude = [owner_player.get_rid()]
	shape_query.collision_mask = owner_player.collision_mask
	var space_state: PhysicsDirectSpaceState2D = owner_player.get_world_2d().direct_space_state
	for hit: Dictionary in space_state.intersect_shape(shape_query, 8):
		var shape_collider := hit.get("collider") as Node2D
		if shape_collider == null or not shape_collider.has_method("register_push_attempt"):
			continue
		shape_collider.call("register_push_attempt", owner_player, push_direction)
		return true

	var side_x: float = center.x + signf(push_direction) * half_size.x
	var probe_start_x: float = side_x + signf(push_direction) * 0.05
	var probe_end_x: float = side_x + signf(push_direction) * owner_player.push_probe_distance
	var vertical_span: float = maxf(half_size.y - owner_player.push_probe_vertical_padding, 0.0)
	var sample_offsets: Array[float] = [-vertical_span, 0.0, vertical_span]

	for y_offset: float in sample_offsets:
		var from: Vector2 = Vector2(probe_start_x, center.y + y_offset)
		var to: Vector2 = Vector2(probe_end_x, center.y + y_offset)
		var query := PhysicsRayQueryParameters2D.create(from, to)
		query.exclude = [owner_player.get_rid()]
		query.collision_mask = owner_player.collision_mask
		var hit: Dictionary = space_state.intersect_ray(query)
		if hit.is_empty():
			continue

		var collider_node := hit.get("collider") as Node2D
		if collider_node == null or not collider_node.has_method("register_push_attempt"):
			continue

		collider_node.call("register_push_attempt", owner_player, push_direction)
		return true

	return false
