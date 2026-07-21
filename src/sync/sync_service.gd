class_name SyncService
extends RefCounted

signal status_changed(status: Dictionary)
signal diagnostic(code: String)

func status() -> Dictionary:
	return {"state": "unavailable", "pending_count": 0, "last_success_at": null}

func request_sync() -> Dictionary:
	return {"ok": false, "error": "not_implemented"}
