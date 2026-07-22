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
	var staged: Array[Node] = []
	for _index in prewarm_count:
		var created := _instantiate_validated(scene)
		if created == null:
			for staged_instance in staged:
				staged_instance.free()
			return false
		staged.append(created)
	_scene = scene
	_configured = true
	for staged_instance in staged:
		_adopt_instance(staged_instance)
		_available.append(staged_instance)
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
	var instance := _instantiate_validated(_scene)
	if instance == null:
		return null
	_adopt_instance(instance)
	return instance

func _instantiate_validated(scene: PackedScene) -> Node:
	var instance := scene.instantiate()
	if instance == null or not instance.has_signal("finished") or not instance.has_method("reset_for_pool"):
		if instance != null:
			instance.free()
		return null
	return instance

func _adopt_instance(instance: Node) -> void:
	add_child(instance)
	instance.finished.connect(_on_burst_finished)
	instance.reset_for_pool()
	_total_created += 1

func _on_burst_finished(burst: Node) -> void:
	release(burst)
