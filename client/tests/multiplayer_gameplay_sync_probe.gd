extends SceneTree

const LEVEL_SCENE: PackedScene = preload("res://scenes/levels/real_level_blank.tscn")
const FIREBOY_SCENE: PackedScene = preload("res://scenes/players/fireboy.tscn")

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	await _verify_level_has_gameplay_nodes()
	await _verify_local_gem_overlap_collects()
	await _verify_push_block_accepts_local_push()
	if _failures.is_empty():
		print("Multiplayer gameplay sync probe passed.")
		quit(0)
		return
	for failure: String in _failures:
		printerr(failure)
	quit(1)

func _verify_level_has_gameplay_nodes() -> void:
	var level := LEVEL_SCENE.instantiate() as PrototypeLevel
	root.add_child(level)
	await process_frame
	_require(level.get_node_or_null("Collectibles") is GemManager, "real_level_blank must contain Collectibles with GemManager.")
	_require(level.get_node_or_null("Objects/PushBlock") is PushBlock, "real_level_blank must contain Objects/PushBlock.")
	_require(not get_nodes_in_group("collectible_gem").is_empty(), "real_level_blank must contain collectible_gem nodes.")
	level.queue_free()
	await process_frame

func _verify_local_gem_overlap_collects() -> void:
	var level := LEVEL_SCENE.instantiate() as PrototypeLevel
	root.add_child(level)
	await process_frame
	var gem := level.get_node_or_null("Collectibles/FireGem") as CollectibleGem
	var player := FIREBOY_SCENE.instantiate() as PrototypePlayer
	_require(gem != null, "real_level_blank must contain Collectibles/FireGem.")
	_require(player != null, "Fireboy scene must instantiate as PrototypePlayer.")
	if gem == null or player == null:
		level.queue_free()
		return
	level.attach_player(player)
	player.is_local = true
	player.global_position = gem.global_position
	player.velocity = Vector2.ZERO
	for frame in 6:
		await physics_frame
	_require(not gem.visible, "Local Fireboy overlap should collect and hide FireGem.")
	level.queue_free()
	await process_frame

func _verify_push_block_accepts_local_push() -> void:
	var level := LEVEL_SCENE.instantiate() as PrototypeLevel
	root.add_child(level)
	await process_frame
	var block := level.get_node_or_null("Objects/PushBlock") as PushBlock
	var player := FIREBOY_SCENE.instantiate() as PrototypePlayer
	_require(block != null, "real_level_blank must contain a PushBlock.")
	_require(player != null, "Fireboy scene must instantiate as PrototypePlayer.")
	if block == null or player == null:
		level.queue_free()
		return
	level.attach_player(player)
	player.is_local = true
	block.global_position = Vector2(0.0, -20.0)
	player.global_position = Vector2(-20.0, -20.0)
	block.linear_velocity = Vector2.ZERO
	block.angular_velocity = 0.0
	block.sleeping = false
	block.call("register_push_attempt", player, 1.0)
	for frame in 12:
		await physics_frame
	_require(block.linear_velocity.x > 0.0 or block.global_position.x > 0.0, "PushBlock should move after a local push attempt.")
	level.queue_free()
	await process_frame

func _require(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
