class_name GemManager
extends Node2D

signal gem_progress_changed(collected: int, required: int)

var _required_gems: Array[CollectibleGem] = []
var _collected_gems: Array[Variant] = [] # Use Variant to hold nulls on client
var _is_configured: bool = false
var _active_gem_element: int = 0

func _ready() -> void:
	add_to_group("gem_manager")

func configure_all() -> void:
	if not _is_configured:
		_required_gems.clear()
		_collected_gems.clear()

		for child: Node in get_children():
			var gem := child as CollectibleGem
			if gem != null:
				_required_gems.append(gem)
				if multiplayer.is_server():
					if not gem.collected.is_connected(_on_gem_collected):
						gem.collected.connect(_on_gem_collected)
		
		_is_configured = true
		
	_emit_progress()

func is_unlocked() -> bool:
	if not _is_configured:
		return true
	return _collected_gems.size() >= _required_gems.size()

func get_remaining_count() -> int:
	return max(_required_gems.size() - _collected_gems.size(), 0)

func get_active_gem_element() -> int:
	return _active_gem_element

func _on_gem_collected(gem: CollectibleGem, _player_id: int) -> void:
	if not _required_gems.has(gem):
		return
	if _collected_gems.has(gem):
		return
	_collected_gems.append(gem)
	
	var rpc_node = get_node_or_null("/root/GameplayRPC")
	if rpc_node:
		rpc_node.rpc("sync_gem_progress", _collected_gems.size())

func client_sync_progress_rpc(collected_count: int) -> void:
	_collected_gems.clear()
	for i in range(collected_count):
		_collected_gems.append(null)
	_emit_progress()

func _emit_progress() -> void:
	gem_progress_changed.emit(_collected_gems.size(), _required_gems.size())
