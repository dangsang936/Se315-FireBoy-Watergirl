class_name SyncPackets

# Gói tin đồng bộ vị trí người chơi (Gửi liên tục 30-60 lần/s)
static func create_player_sync(id: int, pos: Vector2, vel: Vector2, anim: String) -> Dictionary:
	return {
		"t": 1,          # t = type, 1 = PLAYER_SYNC
		"id": id,
		"p": pos,        # p = position
		"v": vel,        # v = velocity
		"a": anim        # a = animation state (VD: "run", "idle")
	}

# Gói tin đồng bộ câu đố (Chỉ gửi khi có người chạm vào nút/công tắc)
static func create_puzzle_sync(puzzle_id: String, is_active: bool) -> Dictionary:
	return {
		"t": 2,          # t = type, 2 = PUZZLE_SYNC
		"id": puzzle_id,
		"s": is_active   # s = state (true = mở cửa/bật công tắc)
	}
