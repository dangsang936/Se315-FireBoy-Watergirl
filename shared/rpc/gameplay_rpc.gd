class_name GameplayRPC
extends Node

@rpc("authority", "call_local", "reliable")
func rpc_load_level(level_id: String):
	print("Load màn chơi: ", level_id)

@rpc("authority", "call_local", "reliable")
func rpc_player_died(player_id: int, hazard_type: String):
	print("Player ", player_id, " vừa chết do: ", hazard_type)

@rpc("authority", "call_local", "reliable")
func rpc_level_completed(time_taken: float):
	print("Màn chơi hoàn thành trong ", time_taken, " giây!")

@rpc("authority", "call_remote", "unreliable_ordered")
func sync_push_block(block_name: String, pos: Vector2, rot: float) -> void:
	var blocks := get_tree().get_nodes_in_group("push_block")
	var best_block: Node2D = null
	var best_dist: float = 999999.0
	
	for b in blocks:
		var d = b.global_position.distance_to(pos)
		if d < best_dist:
			best_dist = d
			best_block = b
			
	if best_block != null and best_dist < 200.0:
		best_block.global_position = pos
		best_block.rotation = rot
		if best_block is RigidBody2D:
			best_block.linear_velocity = Vector2.ZERO
			best_block.angular_velocity = 0.0

@rpc("authority", "call_remote", "reliable")
func sync_gem_collected(gem_name: String, pos: Vector2 = Vector2.ZERO) -> void:
	var root = get_tree().root
	var best_gem = _find_closest_gem(root, pos, 99999.0, null)
	if best_gem:
		best_gem.client_collect_gem()

func _find_closest_gem(node: Node, pos: Vector2, best_dist: float, best_gem: Node) -> Node:
	if node.has_method("client_collect_gem") and "global_position" in node:
		var d = node.get("global_position").distance_to(pos)
		if d < best_dist:
			best_dist = d
			best_gem = node
	for child in node.get_children():
		best_gem = _find_closest_gem(child, pos, best_dist, best_gem)
		if best_gem and "global_position" in best_gem:
			best_dist = best_gem.get("global_position").distance_to(pos)
	return best_gem

@rpc("authority", "call_local", "reliable")
func sync_gem_progress(collected_count: int) -> void:
	var managers = get_tree().get_nodes_in_group("gem_manager")
	for gm in managers:
		if gm.has_method("client_sync_progress_rpc"):
			gm.client_sync_progress_rpc(collected_count)
			
	
