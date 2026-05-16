class_name GemManager
extends Node2D

signal gem_progress_changed(collected: int, required: int)

var _active_gem_element: int = CollectibleGem.GemElement.FIRE
var _required_gems: Array[CollectibleGem] = []
var _collected_gems: Array[CollectibleGem] = []
var _is_configured: bool = false

func configure_for_player(player: PrototypePlayer) -> void:
	_active_gem_element = int(player.get_element())
	_required_gems.clear()
	_collected_gems.clear()

	for child: Node in get_children():
		var gem := child as CollectibleGem
		if gem == null:
			continue
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

func _on_gem_collected(gem: CollectibleGem, _player: PrototypePlayer) -> void:
	if not _required_gems.has(gem):
		return
	if _collected_gems.has(gem):
		return
	_collected_gems.append(gem)
	_emit_progress()

func _emit_progress() -> void:
	gem_progress_changed.emit(get_collected_count(), get_required_count())
