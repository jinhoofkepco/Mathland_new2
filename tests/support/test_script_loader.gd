class_name TestScriptLoader
extends RefCounted

func instantiate(script: Variant, path: String) -> Dictionary:
	if script == null or not script is Script:
		return {"ok": false, "error": "script_load_failed", "path": path}
	if not script.can_instantiate():
		return {"ok": false, "error": "script_not_instantiable", "path": path}
	var instance: Variant = script.new()
	if instance == null:
		return {"ok": false, "error": "script_instantiation_failed", "path": path}
	if not instance.has_method("run"):
		return {"ok": false, "error": "missing_run_method", "path": path}
	if not "failures" in instance:
		return {"ok": false, "error": "missing_failures_property", "path": path}
	return {"ok": true, "instance": instance}
