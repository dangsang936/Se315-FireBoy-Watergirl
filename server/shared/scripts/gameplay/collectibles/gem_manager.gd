class_name GemManager
extends Node2D

signal gem_progress_changed(collected: int, required: int)

var _required_gems: Array[CollectibleGem] = []
var _collected_gems: Array[Variant] = []
var _collected_gem_paths: Dictionary = {}
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
		_is_configured = true
	else:
		_reconcile_collected_paths()
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
			_register_gem(gem)
		_collect_required_gems(child)

func _register_gem(gem: CollectibleGem) -> void:
	if not _required_gems.has(gem):
		_required_gems.append(gem)
	if not gem.collected.is_connected(_on_gem_collected):
		gem.collected.connect(_on_gem_collected)
	var gem_path := _get_gem_path(gem)
	if gem_path != "" and _collected_gem_paths.has(gem_path):
		_apply_collected_state(gem)
		_track_collected_gem(gem)

func _on_gem_collected(gem: CollectibleGem, _player: PrototypePlayer) -> void:
	if not _required_gems.has(gem):
		return
	var gem_path := _get_gem_path(gem)
	if gem_path != "":
		_collected_gem_paths[gem_path] = true
	if _track_collected_gem(gem):
		_emit_progress()

func client_mark_collected_by_path(gem_path: String) -> void:
	if gem_path == "":
		return
	var was_new := not _collected_gem_paths.has(gem_path)
	_collected_gem_paths[gem_path] = true
	var gem := _find_gem_by_path(gem_path)
	if gem != null:
		_apply_collected_state(gem)
		if _track_collected_gem(gem):
			was_new = true
	if was_new:
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

func _find_gem_by_path(gem_path: String) -> CollectibleGem:
	var level := _find_level_root()
	if level == null:
		return null
	return level.get_node_or_null(NodePath(gem_path)) as CollectibleGem

func _get_gem_path(gem: CollectibleGem) -> String:
	if gem == null:
		return ""
	var level := _find_level_root()
	if level == null:
		return str(gem.get_path())
	return str(level.get_path_to(gem))

func _apply_collected_state(gem: CollectibleGem) -> void:
	if gem != null and gem.has_method("collect_remotely"):
		gem.collect_remotely()

func _track_collected_gem(gem: CollectibleGem) -> bool:
	if gem == null or _collected_gems.has(gem):
		return false
	_collected_gems.append(gem)
	return true

func _reconcile_collected_paths() -> void:
	for gem_path in _collected_gem_paths.keys():
		var gem := _find_gem_by_path(str(gem_path))
		if gem != null:
			_apply_collected_state(gem)
			_track_collected_gem(gem)

func _emit_progress() -> void:
	gem_progress_changed.emit(_collected_gems.size(), _required_gems.size())
