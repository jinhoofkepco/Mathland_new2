class_name HttpJsonTransport
extends Node

const DEFAULT_TIMEOUT_SECONDS := 15.0

var _timeout_seconds := DEFAULT_TIMEOUT_SECONDS

func _init(timeout_seconds: float = DEFAULT_TIMEOUT_SECONDS) -> void:
	_timeout_seconds = clampf(timeout_seconds, 1.0, 60.0)

func request_json(method: String, url: String, headers: Dictionary, body: Variant = null) -> Dictionary:
	if not url.begins_with("https://"):
		return {"ok": false, "status": 0, "error": "https_required", "body": {}}
	var request := HTTPRequest.new()
	request.timeout = _timeout_seconds
	add_child(request)
	var packed_headers := PackedStringArray()
	for header_name_value in headers:
		var header_name := String(header_name_value)
		var header_value: Variant = headers[header_name_value]
		if header_value is String and not String(header_value).contains("\n") and not String(header_value).contains("\r"):
			packed_headers.append("%s: %s" % [header_name, String(header_value)])
	var request_body := "" if body == null else JSON.stringify(body)
	var method_id := _method_id(method)
	if method_id < 0:
		request.queue_free()
		return {"ok": false, "status": 0, "error": "unsupported_method", "body": {}}
	var start_error := request.request(url, packed_headers, method_id, request_body)
	if start_error != OK:
		request.queue_free()
		return {"ok": false, "status": 0, "error": "request_start_failed", "body": {}}
	var completed: Array = await request.request_completed
	request.queue_free()
	var transport_result := int(completed[0])
	var status_code := int(completed[1])
	var response_bytes: PackedByteArray = completed[3]
	if transport_result != HTTPRequest.RESULT_SUCCESS:
		return {
			"ok": false,
			"status": 0,
			"error": _transport_error(transport_result),
			"body": {},
		}
	var response_body: Variant = {}
	if not response_bytes.is_empty():
		var json := JSON.new()
		if json.parse(response_bytes.get_string_from_utf8()) != OK or not json.data is Dictionary:
			return {"ok": false, "status": status_code, "error": "invalid_json_response", "body": {}}
		response_body = json.data
	return {
		"ok": status_code >= 200 and status_code < 300,
		"status": status_code,
		"body": response_body,
	}

func _method_id(method: String) -> int:
	match method.to_upper():
		"GET":
			return HTTPClient.METHOD_GET
		"POST":
			return HTTPClient.METHOD_POST
		"PUT":
			return HTTPClient.METHOD_PUT
		"PATCH":
			return HTTPClient.METHOD_PATCH
		"DELETE":
			return HTTPClient.METHOD_DELETE
	return -1

func _transport_error(result: int) -> String:
	match result:
		HTTPRequest.RESULT_TIMEOUT:
			return "timeout"
		HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CANT_RESOLVE:
			return "network_unavailable"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "tls_failed"
	return "transport_failed"
