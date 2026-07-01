class_name PlayerModel
extends RefCounted

enum CharacterType { FIREBOY, WATERGIRL }
enum Status { ALIVE, DEAD, FINISHED }

var player_id: int = 0
var char_type: CharacterType
var status: Status = Status.ALIVE

# Dữ liệu vật lý cơ bản
var position: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO

# Hàm khởi tạo
func _init(id: int, type: CharacterType):
	self.player_id = id
	self.char_type = type

# Hàm tiện ích để check điều kiện
func is_dead() -> bool:
	return status == Status.DEAD
