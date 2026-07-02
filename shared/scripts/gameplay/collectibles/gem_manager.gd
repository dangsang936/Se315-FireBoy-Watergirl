class_name GemManager
extends Node2D

signal gem_progress_changed(collected: int, required: int)

var _required_gems: Array[CollectibleGem] = []
var _collected_gems: Array[Variant] = [] # Use Variant to hold nulls on client
var _is_configured: bool = false
var _active_gem_element: int = 0
var required_count: int:
	get:
		return _required_gems.size()

func _ready() -> void:
	add_to_group("gem_manager")

func configure_all() -> void:
	_configure_required_gems([])

func configure_for_player(player: Node2D) -> void:
	var active_elements: Array[int] = []
	var element := _get_player_element(player)
	if element >= 0:
		_active_gem_element = element
		active_elements.append(element)
	_configure_required_gems(active_elements)

func configure_for_players(players: Array[Node]) -> void:
	var active_elements: Array[int] = []
	for player: Node in players:
		var element := _get_player_element(player as Node2D)
		if element >= 0 and not active_elements.has(element):
			active_elements.append(element)
	if active_elements.size() == 1:
		_active_gem_element = active_elements[0]
	_configure_required_gems(active_elements)

func is_unlocked() -> bool:
	if not _is_configured:
		return true
	return required_count == 0 or _collected_gems.size() >= required_count

func get_remaining_count() -> int:
	return max(_required_gems.size() - _collected_gems.size(), 0)

func get_active_gem_element() -> int:
	return _active_gem_element

func _on_gem_collected(gem: CollectibleGem, _player: Node2D) -> void:
	if not _required_gems.has(gem):
		return
	if _collected_gems.has(gem):
		return
	_collected_gems.append(gem)
	
	var rpc_node := get_node_or_null("/root/GameplayRpc")
	if rpc_node == null:
		rpc_node = get_node_or_null("/root/GameplayRPC")
	if rpc_node:
		rpc_node.rpc("sync_gem_progress", _collected_gems.size())

func client_sync_progress_rpc(collected_count: int) -> void:
	_collected_gems.clear()
	for i in range(collected_count):
		_collected_gems.append(null)
	_emit_progress()

func _emit_progress() -> void:
	gem_progress_changed.emit(_collected_gems.size(), _required_gems.size())

func _configure_required_gems(active_elements: Array[int]) -> void:
	_required_gems.clear()
	_collected_gems.clear()

	for child: Node in get_children():
		var gem := child as CollectibleGem
		if gem == null:
			continue
		if active_elements.is_empty() or active_elements.has(int(gem.gem_element)):
			_required_gems.append(gem)
			if multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
				if not gem.collected.is_connected(_on_gem_collected):
					gem.collected.connect(_on_gem_collected)

	_is_configured = true
	_emit_progress()

func _get_player_element(player: Node2D) -> int:
	if player == null:
		return -1
	if player.has_meta("element"):
		return int(player.get_meta("element"))
	if player.has_method("get_element"):
		return int(player.call("get_element"))
	if "element" in player:
		return int(player.get("element"))
	return -1
