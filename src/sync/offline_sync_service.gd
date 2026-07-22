class_name OfflineSyncService
extends "res://src/sync/sync_service.gd"

var _journal: Variant

func _init(journal: Variant = null) -> void:
	_journal = journal

func status() -> Dictionary:
	return {"state": "offline", "pending_count": _pending_count(), "last_success_at": null}

func request_sync() -> Dictionary:
	diagnostic.emit("offline")
	status_changed.emit(status())
	return {"ok": false, "error": "offline"}

func _pending_count() -> int:
	if _journal == null or not _journal.has_method("replay"):
		return 0
	var replayed: Variant = _journal.replay()
	if not replayed is Dictionary or not replayed.get("ok", false) or not replayed.get("events", null) is Array:
		return 0
	return replayed.events.size()
