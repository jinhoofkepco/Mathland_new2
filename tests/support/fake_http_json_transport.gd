class_name FakeHttpJsonTransport
extends RefCounted

var requests: Array[Dictionary] = []
var responses: Array[Dictionary] = []

func enqueue(response: Dictionary) -> void:
	responses.append(response.duplicate(true))

func request_json(method: String, url: String, headers: Dictionary, body: Variant = null) -> Dictionary:
	requests.append({
		"method": method,
		"url": url,
		"headers": headers.duplicate(true),
		"body": body.duplicate(true) if body is Dictionary or body is Array else body,
	})
	if responses.is_empty():
		return {"ok": false, "status": 0, "error": "network_unavailable", "body": {}}
	return responses.pop_front().duplicate(true)
