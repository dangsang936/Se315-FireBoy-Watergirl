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
