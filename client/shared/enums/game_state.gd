class_name GameState

enum State {
	MAIN_MENU,
	LOBBY,
	ROOM_WAITING,      # Đợi đủ 2 người
	LOADING_LEVEL,     # Đang load map
	PLAYING,           # Đang giải đố
	LEVEL_COMPLETED,   # Cả 2 đã đến cửa
	RESULT_SCREEN      # Hiện điểm/thời gian
}
