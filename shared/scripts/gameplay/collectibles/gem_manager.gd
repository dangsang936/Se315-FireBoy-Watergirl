class_name GemManager
extends Node2D

signal gem_progress_changed(collected: int, required: int)

var _required_gems: Array[CollectibleGem] = []
var _collected_gems: Array[Variant] = []
var _is_configured: bool = false
var _active_gem_element: int = 0

var required_count: int:
	get:
		return _required_gems.size()

func _ready() -> void:
	add_to_group("gem_manager")

func configure_all() -> void:
	if not _is_configured:
		_required_gems.clear()
		_collected_gems.clear()
		_collect_required_gems(self)
		for gem: CollectibleGem in _required_gems:
			if not gem.collected.is_connected(_on_gem_collected):
				gem.collected.connect(_on_gem_collected)
		_is_configured = true
	_emit_progress()

func configure_for_player(player: PrototypePlayer) -> void:
	configure_all()

func is_unlocked() -> bool:
	if not _is_configured:
		return true
	return required_count == 0 or _collected_gems.size() >= required_count

func get_remaining_count() -> int:
	return max(_required_gems.size() - _collected_gems.size(), 0)

func get_active_gem_element() -> int:
	return _active_gem_element

func get_collected_count() -> int:
	return _collected_gems.size()

func get_required_count() -> int:
	return _required_gems.size()

func _collect_required_gems(root: Node) -> void:
	for child: Node in root.get_children():
		var gem := child as CollectibleGem
		if gem != null:
			_required_gems.append(gem)
		_collect_required_gems(child)

func _on_gem_collected(gem: CollectibleGem, _player: PrototypePlayer) -> void:
	if not _required_gems.has(gem):
		return
	if _collected_gems.has(gem):
		return
	_collected_gems.append(gem)
	_emit_progress()

func client_mark_collected_by_path(gem_path: String) -> void:
	var level := _find_level_root()
	if level == null:
		return
	var gem := level.get_node_or_null(NodePath(gem_path)) as CollectibleGem
	if gem != null and _required_gems.has(gem) and not _collected_gems.has(gem):
		_collected_gems.append(gem)
		_emit_progress()

func client_sync_progress_rpc(collected_count: int) -> void:
	_collected_gems.clear()
	for i in range(collected_count):
		_collected_gems.append(null)
	_emit_progress()

func _find_level_root() -> Node:
	var node: Node = self
	while node != null:
		if node is PrototypeLevel:
			return node
		node = node.get_parent()
	return null

func _emit_progress() -> void:
	gem_progress_changed.emit(_collected_gems.size(), _required_gems.size())
