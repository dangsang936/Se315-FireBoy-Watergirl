class_name GameplayRPC
extends Node

# ------------------------------------------------------------------
# SERVER -> ALL CLIENTS: load a level by ID.
# Server calls this to tell all clients which level to load.
# ------------------------------------------------------------------
@rpc("authority", "call_local", "reliable")
func notify_load_level(level_id: String):
	print("Load màn chơi: ", level_id)

# ------------------------------------------------------------------
# SERVER -> ALL CLIENTS: a player died from a hazard (legacy stub).
# Superseded by sync_player_failed; kept for backwards compatibility.
# Legacy listen-server flow; do not use in authorized server mode.
# ------------------------------------------------------------------
@rpc("authority", "call_local", "reliable")
func notify_player_died(player_id: int, hazard_type: String):
	print("Player ", player_id, " vừa chết do: ", hazard_type)

# ------------------------------------------------------------------
# Legacy listen-server flow; do not use in authorized server mode.
# Superseded by sync_level_completed below.
# ------------------------------------------------------------------
@rpc("authority", "call_local", "reliable")
func notify_level_completed(time_taken: float):
	print("Màn chơi hoàn thành trong ", time_taken, " giây!")

# ------------------------------------------------------------------
# SERVER -> ALL CLIENTS: player fell into a hazard — game over.
# Server calls this after verifying collision on its physics world.
# Clients react by entering LOST state; they do NOT self-trigger this.
# ------------------------------------------------------------------
@rpc("authority", "call_remote", "reliable")
func sync_player_failed(failed_player_id: int) -> void:
	# Forward to NetworkManager signal so GameManager._on_player_failed_received fires.
	var nm := get_node_or_null("/root/NetworkManager")
	if nm != null and nm.has_signal("player_failed_received"):
		nm.emit_signal("player_failed_received")
	print("[Client] Player %d failed (server-authoritative)." % failed_player_id)

# ------------------------------------------------------------------
# SERVER -> ALL CLIENTS: both players reached the exit with all gems.
# Server calls this after verifying exit-door and gem conditions.
# Clients react by entering WON state; they do NOT self-trigger this.
# ------------------------------------------------------------------
@rpc("authority", "call_remote", "reliable")
func sync_level_completed() -> void:
	# Forward to NetworkManager signal so GameManager._on_level_completed_received fires.
	var nm := get_node_or_null("/root/NetworkManager")
	if nm != null and nm.has_signal("level_completed_received"):
		nm.emit_signal("level_completed_received")
	print("[Client] Level completed (server-authoritative).")

@rpc("authority", "call_remote", "reliable")
func sync_next_level(level_index: int) -> void:
	var nm := get_node_or_null("/root/NetworkManager")
	if nm != null and nm.has_signal("next_level_received"):
		nm.emit_signal("next_level_received", level_index)
	print("[Client] Loading next level index %d (server-authoritative)." % level_index)

@rpc("authority", "call_remote", "unreliable_ordered")
func sync_push_block(block_name: String, pos: Vector2, rot: float) -> void:
	var blocks := get_tree().get_nodes_in_group("push_block")
	# Primary: match by name — unambiguous and O(n).
	var target_block: Node2D = null
	for b: Node in blocks:
		if b.name == block_name:
			target_block = b as Node2D
			break
	# Fallback: nearest block by position (handles legacy scenes with unnamed blocks).
	if target_block == null:
		var best_dist: float = 200.0
		for b: Node in blocks:
			if "global_position" in b:
				var d: float = (b as Node2D).global_position.distance_to(pos)
				if d < best_dist:
					best_dist = d
					target_block = b as Node2D
	if target_block == null:
		return
	target_block.global_position = pos
	target_block.rotation = rot
	if target_block is RigidBody2D:
		(target_block as RigidBody2D).linear_velocity = Vector2.ZERO
		(target_block as RigidBody2D).angular_velocity = 0.0

@rpc("authority", "call_remote", "reliable")
func sync_gem_collected(gem_name: String, pos: Vector2 = Vector2.ZERO) -> void:
	# Primary: look up by name within the collectible_gem group — O(n), reliable.
	var gems := get_tree().get_nodes_in_group("collectible_gem")
	var target_gem: Node = null
	for g: Node in gems:
		if g.name == gem_name:
			target_gem = g
			break
	# Fallback: nearest gem by position if name lookup fails (e.g. duplicate names).
	if target_gem == null and pos != Vector2.ZERO:
		var best_dist: float = 200.0  # max snap distance
		for g: Node in gems:
			if "global_position" in g:
				var d: float = g.get("global_position").distance_to(pos)
				if d < best_dist:
					best_dist = d
					target_gem = g
	if target_gem != null and target_gem.has_method("client_collect_gem"):
		target_gem.client_collect_gem()

@rpc("authority", "call_remote", "reliable")
func sync_gem_progress(collected_count: int) -> void:
	var managers = get_tree().get_nodes_in_group("gem_manager")
	for gm in managers:
		if gm.has_method("client_sync_progress_rpc"):
			gm.client_sync_progress_rpc(collected_count)

# ------------------------------------------------------------------
# SERVER -> ALL CLIENTS: a pressure button's pressed state changed.
# Server calls this whenever _is_pressed flips after physics update.
# Clients apply the visual state and update the linked bridge.
# button_node_path is the scene-tree path relative to scene root so
# clients can look up the correct node without ambiguity.
# ------------------------------------------------------------------
@rpc("authority", "call_remote", "reliable")
func sync_button_state(button_node_path: String, is_pressed: bool) -> void:
	var button := get_tree().root.get_node_or_null(button_node_path)
	if button == null:
		# Try direct node name search as a fallback
		var buttons := get_tree().get_nodes_in_group("pressure_button")
		for b: Node in buttons:
			if b.name == button_node_path.get_file():
				button = b
				break
	if button == null or not button.has_method("client_apply_pressed_state"):
		return
	button.client_apply_pressed_state(is_pressed)
