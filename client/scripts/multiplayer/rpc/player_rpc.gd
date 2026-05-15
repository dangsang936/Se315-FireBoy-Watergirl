extends Node

# ---------------------------------------------------------
# CLIENT GỬI LÊN SERVER (Input)
# Any_peer: Bất kỳ client nào cũng gọi được
# Call_remote: Chỉ chạy trên máy nhận (Server), không chạy trên máy gọi
# Unreliable: Nhanh, không cần chờ xác nhận (phù hợp cho di chuyển)
# ---------------------------------------------------------
@rpc("any_peer", "call_remote", "unreliable")
func request_movement(input_dir: Vector2, jump_pressed: bool):
	if multiplayer.is_server():
		var sender_id = multiplayer.get_remote_sender_id()
		# TODO trên Server: Lấy input này -> Đưa vào PlayerModel -> Tính toán logic vật lý thật
		pass

@rpc("any_peer", "call_remote", "reliable")
func request_interact(puzzle_id: String):
	# Reliable: Đảm bảo gói tin tương tác công tắc không bị rớt mạng
	if multiplayer.is_server():
		var sender_id = multiplayer.get_remote_sender_id()
		# TODO trên Server: Kiểm tra xem người chơi có đứng gần công tắc không -> Bật công tắc
		pass

# ---------------------------------------------------------
# SERVER GỬI VỀ CLIENT (Đồng bộ)
# Authority: Chỉ Server (chủ phòng) mới có quyền gọi hàm này
# Call_local: Chạy trên cả các máy Client và cả máy Server (nếu Server là host kiêm client)
# ---------------------------------------------------------
@rpc("authority", "call_local", "unreliable")
func sync_position(player_id: int, pos: Vector2, vel: Vector2, anim: String):
	# TODO trên Client: Tìm nhân vật có player_id tương ứng
	# Nội suy (Interpolate) từ vị trí cũ sang 'pos' mới để di chuyển mượt mà
	pass

@rpc("authority", "call_local", "reliable")
func sync_player_death(player_id: int, death_cause: String):
	# TODO trên Client: Phát animation chết, hiện màn hình Game Over
	pass
