class_name GemManager
extends Node2D

signal gem_progress_changed(collected: int, required: int)

var _active_gem_element: int = CollectibleGem.GemElement.FIRE
var _required_gems: Array[CollectibleGem] = []
var _collected_gems: Array[CollectibleGem] = []
var _is_configured: bool = false

func configure_for_element(element: int) -> void:
	_active_gem_element = element
	_required_gems.clear()
	_collected_gems.clear()

	for child: Node in get_children():
		var gem := child as CollectibleGem
		if gem == null:
			continue
		
		if multiplayer.is_server():
			if not gem.collected.is_connected(_on_gem_collected):
				gem.collected.connect(_on_gem_collected)
				
		if int(gem.gem_element) == _active_gem_element:
			_required_gems.append(gem)

	_is_configured = true
	_emit_progress()

func is_unlocked() -> bool:
	if not _is_configured:
		return true
	var required_count := _required_gems.size()
	return required_count == 0 or _collected_gems.size() >= required_count

func get_remaining_count() -> int:
	return max(_required_gems.size() - _collected_gems.size(), 0)

func get_collected_count() -> int:
	return _collected_gems.size()

func get_required_count() -> int:
	return _required_gems.size()

func get_active_gem_element() -> int:
	return _active_gem_element

func _on_gem_collected(gem: CollectibleGem, _player_id: int) -> void:
	if not _required_gems.has(gem):
		return
	if _collected_gems.has(gem):
		return
	_collected_gems.append(gem)
	rpc("client_sync_progress", _collected_gems.size())

@rpc("authority", "call_local", "reliable")
func client_sync_progress(collected_count: int) -> void:
	var needed = collected_count - _collected_gems.size()
	if needed > 0:
		for i in range(needed):
			_collected_gems.append(null) # Dummy fill on client for count
	_emit_progress()

func _emit_progress() -> void:
	gem_progress_changed.emit(get_collected_count(), get_required_count())
