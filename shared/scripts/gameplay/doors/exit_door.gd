class_name ExitDoor
extends Area2D

signal player_entered(player_id: int)
signal player_exited(player_id: int)

func _ready() -> void:
	if multiplayer.is_server():
		body_entered.connect(_on_body_entered)
		body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		var pid: int = body.get("player_id") if "player_id" in body else body.get_meta("player_id", 0)
		if pid != 0:
			player_entered.emit(pid)

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		var pid: int = body.get("player_id") if "player_id" in body else body.get_meta("player_id", 0)
		if pid != 0:
			player_exited.emit(pid)

@rpc("authority", "call_local", "reliable")
func client_set_door_visual(is_open: bool) -> void:
	# Visual logic here later
	pass
