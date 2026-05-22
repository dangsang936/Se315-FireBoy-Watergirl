class_name InputPacket

# Tối ưu dung lượng: chỉ gửi các giá trị cần thiết
static func create(tick: int, input_dir: float, jump_pressed: bool) -> Dictionary:
	return {
		"t": tick,           # Tick hiện tại của Client để Server đối chiếu (chống lag)
		"x": input_dir,      # Hướng trục X (-1.0, 0.0, 1.0)
		"j": jump_pressed    # Nút nhảy (true/false)
	}
