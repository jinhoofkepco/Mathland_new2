class_name UiPolicy
extends RefCounted

var _reduced_motion := false
var _tactile_controls: Array[WeakRef] = []

func register_tactile(control: Control) -> bool:
	if control == null or not is_instance_valid(control) or not "reduced_motion" in control:
		return false
	_prune_controls()
	for reference in _tactile_controls:
		var registered: Variant = reference.get_ref()
		if registered == control:
			control.set("reduced_motion", _reduced_motion)
			return true
	control.set("reduced_motion", _reduced_motion)
	_tactile_controls.append(weakref(control))
	return true

func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	_prune_controls()
	for reference in _tactile_controls:
		var control: Variant = reference.get_ref()
		if control != null:
			control.set("reduced_motion", enabled)

func reduced_motion_enabled() -> bool:
	return _reduced_motion

func registered_count() -> int:
	_prune_controls()
	return _tactile_controls.size()

func _prune_controls() -> void:
	var active: Array[WeakRef] = []
	for reference in _tactile_controls:
		var control: Variant = reference.get_ref()
		if control != null and is_instance_valid(control):
			active.append(reference)
	_tactile_controls = active
