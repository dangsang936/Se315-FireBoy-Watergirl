extends Node

var current_tick: int = 0

func _physics_process(delta):
	if multiplayer.is_server(): return # Code này chạy trên Client
	
	current_tick += 1
	# Giả lập bấm nút sang phải
	var mock_input = InputPacket.create(current_tick, 1.0, false)
	
	# Gửi qua RPC đã tạo ở Phase 1
	rpc_id(1, "receive_mock_input", mock_input) # 1 luôn là ID của Server

# --- HÀM CHẠY TRÊN SERVER ---
@rpc("any_peer", "call_remote", "unreliable")
func receive_mock_input(packet: Dictionary):
	if multiplayer.is_server():
		var client_id = multiplayer.get_remote_sender_id()
		print("Server nhận input từ %s tại tick %d: di chuyển %f" % [client_id, packet.t, packet.x])
		
		# Giả lập tính toán: di chuyển nhân vật 10 pixel mỗi tick
		var mock_new_position = Vector2(packet.x * 10, 0)
		
		# Gửi trả vị trí về lại Client
		rpc_id(client_id, "receive_mock_position", mock_new_position)

# --- HÀM CLIENT NHẬN LẠI TỪ SERVER ---
@rpc("authority", "call_remote", "unreliable")
func receive_mock_position(pos: Vector2):
	print("Client nhận vị trí mới từ Server: ", pos)
