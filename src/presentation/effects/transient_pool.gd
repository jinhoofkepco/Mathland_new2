class_name TransientPool
extends Node

var _scene: PackedScene
var _available: Array[Node] = []
var _active: Dictionary = {}
var _total_created := 0
var _configured := false

func configure(scene: PackedScene, prewarm_count: int = 8) -> bool:
	if _configured or scene == null or prewarm_count < 0:
		return false
	_scene = scene
	_configured = true
	for _index in prewarm_count:
		var created := _create_instance()
		if created == null:
			return false
		_available.append(created)
	return true

func acquire() -> Node:
	if not _configured:
		return null
	var burst: Node
	if _available.is_empty():
		burst = _create_instance()
	else:
		burst = _available.pop_back()
	if burst == null:
		return null
	_active[burst.get_instance_id()] = burst
	return burst

func release(burst: Node) -> bool:
	if burst == null:
		return false
	var instance_id := burst.get_instance_id()
	if not _active.has(instance_id) or _active[instance_id] != burst:
		return false
	_active.erase(instance_id)
	burst.reset_for_pool()
	_available.append(burst)
	return true

func total_created() -> int:
	return _total_created

func active_count() -> int:
	return _active.size()

func available_count() -> int:
	return _available.size()

func _create_instance() -> Node:
	var instance := _scene.instantiate()
	if instance == null or not instance.has_signal("finished") or not instance.has_method("reset_for_pool"):
		if instance != null:
			instance.free()
		return null
	add_child(instance)
	instance.finished.connect(_on_burst_finished)
	instance.reset_for_pool()
	_total_created += 1
	return instance

func _on_burst_finished(burst: Node) -> void:
	release(burst)
