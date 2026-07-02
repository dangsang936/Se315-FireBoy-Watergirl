class_name PuzzleRPC
extends Node

# ---------------------------------------------------------
# CLIENT -> SERVER
# Gọi khi một Client tương tác với một vật thể giải đố.
# Prefix rpc_request_* vì đây là yêu cầu client gửi lên server.
# ---------------------------------------------------------
@rpc("any_peer", "call_remote", "reliable")
func rpc_request_interact_puzzle(puzzle_id: String, interaction_type: String):
	# Chỉ Server mới xử lý logic này
	if multiplayer.is_server():
		var sender_id = multiplayer.get_remote_sender_id()
		print("Server nhận yêu cầu từ player ", sender_id, " tương tác với: ", puzzle_id)
		
		# TODO trên Server: 
		# Gọi PuzzleSystem để kiểm tra xem player này có đủ điều kiện tương tác không
		# Nếu OK, gọi hàm sync_puzzle_state() bên dưới
		pass

# ---------------------------------------------------------
# SERVER -> CLIENT
# Gọi để ép tất cả Client cập nhật trạng thái của vật thể giải đố.
# Prefix sync_* vì đây là server đồng bộ trạng thái xuống client.
# ---------------------------------------------------------
@rpc("authority", "call_local", "reliable")
func sync_puzzle_state(puzzle_id: String, new_state: bool):
	print("Đồng bộ trạng thái puzzle: ", puzzle_id, " -> ", new_state)
	
	# TODO trên Client:
	# Tìm node có puzzle_id tương ứng trong Scene
	# Ví dụ: Nếu là cửa -> Gọi hàm open_door() hoặc close_door()
	# Nếu là công tắc -> Đổi sprite công tắc sang trạng thái gạt xuống
	pass
