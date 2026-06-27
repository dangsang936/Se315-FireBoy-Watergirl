class_name GameplayRPC
extends Node

# Server yêu cầu tất cả Client load màn chơi mới
@rpc("authority", "call_local", "reliable")
func rpc_load_level(level_id: String):
	print("Load màn chơi: ", level_id)
	# GameManager sẽ bắt sự kiện này để đổi State sang LOADING_LEVEL

# Server thông báo có người chơi bị chết (rớt dung nham/nước)
@rpc("authority", "call_local", "reliable")
func rpc_player_died(player_id: int, hazard_type: String):
	print("Player ", player_id, " vừa chết do: ", hazard_type)

# Server báo cả 2 đã đến cửa thành công
@rpc("authority", "call_local", "reliable")
func rpc_level_completed(time_taken: float):
	print("Màn chơi hoàn thành trong ", time_taken, " giây!")
	# Chuyển state sang RESULT_SCREEN
@rpc("authority", "call_remote", "unreliable_ordered")
func sync_push_block(block_name: String, pos: Vector2, rot: float) -> void:
	var blocks := get_tree().get_nodes_in_group("push_block")
	for b in blocks:
		if b.name == block_name:
			b.global_position = pos
			b.rotation = rot
			return

@rpc("authority", "call_remote", "reliable")
func sync_gem_collected(gem_name: String) -> void:
	# We fix gem here too before it breaks
	var root = get_tree().root
	_hide_gem_recursive(root, gem_name)

func _hide_gem_recursive(node: Node, gem_name: String) -> void:
	if node.name == gem_name and node.has_method("client_collect_gem"):
		node.client_collect_gem()
		return
	for child in node.get_children():
		_hide_gem_recursive(child, gem_name)
