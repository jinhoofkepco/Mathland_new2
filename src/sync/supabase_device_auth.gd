class_name SupabaseDeviceAuth
extends RefCounted

const UuidV4Script = preload("res://src/core/uuid_v4.gd")

var _transport: Variant
var _credential_store: Variant
var _config: Dictionary
var _device_id := ""
var _access_token := ""

func _init(transport: Variant, credential_store: Variant, config: Dictionary, device_id: String) -> void:
	_transport = transport
	_credential_store = credential_store
	_config = config.duplicate(true)
	_device_id = device_id

static func is_valid_public_config(config: Variant) -> bool:
	if not config is Dictionary:
		return false
	var value: Dictionary = config
	if value.size() != 2 or not value.has("supabase_url") or not value.has("publishable_key"):
		return false
	if not value.supabase_url is String or not value.publishable_key is String:
		return false
	var url := String(value.supabase_url)
	var lower_url := url.to_lower()
	var key := String(value.publishable_key)
	var origin_pattern := RegEx.new()
	if origin_pattern.compile("^https://[A-Za-z0-9.-]+(?::[0-9]+)?/?$") != OK:
		return false
	return (
		origin_pattern.search(url) != null
		and not url.contains("@")
		and not lower_url.contains("localhost")
		and not lower_url.contains("127.0.0.1")
		and key.begins_with("sb_publishable_")
		and not key.to_lower().contains("service_role")
		and not key.contains("\n")
		and not key.contains("\r")
	)

func ensure_session(force_refresh: bool = false) -> Dictionary:
	if not is_valid_public_config(_config):
		return {"ok": false, "error": "invalid_public_config"}
	if _transport == null or not _transport.has_method("request_json"):
		return {"ok": false, "error": "transport_unavailable"}
	if _credential_store == null or not _credential_store.has_method("is_available") or not _credential_store.is_available():
		return {"ok": false, "error": "secure_credentials_unavailable"}
	if not force_refresh and not _access_token.is_empty():
		return {"ok": true}
	var refresh_token := String(_credential_store.load_refresh_token())
	if not refresh_token.is_empty():
		var refreshed: Dictionary = await _transport.request_json(
			"POST",
			"%s/auth/v1/token?grant_type=refresh_token" % _base_url(),
			_public_headers(),
			{"refresh_token": refresh_token}
		)
		if refreshed.get("ok", false):
			return _accept_tokens(refreshed.get("body", {}))
		if force_refresh:
			_access_token = ""
			return {"ok": false, "error": "auth_refresh_failed", "status": int(refreshed.get("status", 0))}
		if int(refreshed.get("status", 0)) not in [400, 401, 403]:
			return {"ok": false, "error": "auth_refresh_failed", "status": int(refreshed.get("status", 0))}
		_credential_store.clear_refresh_token()
	var signed_up: Dictionary = await _transport.request_json(
		"POST",
		"%s/auth/v1/signup" % _base_url(),
		_public_headers(),
		{}
	)
	if not signed_up.get("ok", false):
		return {"ok": false, "error": "anonymous_signup_failed", "status": int(signed_up.get("status", 0))}
	return _accept_tokens(signed_up.get("body", {}))

func pair(code: String, profile_id: String, display_name: String = "") -> Dictionary:
	if not _is_pairing_code(code):
		return {"ok": false, "error": "invalid_pairing_code"}
	if profile_id.is_empty() or _device_id.is_empty() or display_name.strip_edges().is_empty():
		return {"ok": false, "error": "invalid_pairing_context"}
	var session: Dictionary = await ensure_session()
	if not session.get("ok", false):
		return session
	var request_body := {
		"code": code,
		"deviceId": _device_id,
		"profileLocalId": profile_id,
		"displayName": display_name.strip_edges(),
	}
	var response: Dictionary = await _pair_request(request_body)
	if int(response.get("status", 0)) == 401:
		var refreshed: Dictionary = await ensure_session(true)
		if not refreshed.get("ok", false):
			return refreshed
		response = await _pair_request(request_body)
	if not response.get("ok", false):
		return {"ok": false, "error": _pair_error(response), "status": int(response.get("status", 0))}
	var response_body: Variant = response.get("body", {})
	if not response_body is Dictionary:
		return {"ok": false, "error": "invalid_pairing_response"}
	var body: Dictionary = response_body
	if (
		body.size() != 4
		or not _is_uuid(body.get("deviceBindingId"))
		or not _is_uuid(body.get("familyId"))
		or not _is_uuid(body.get("cloudProfileId"))
		or body.get("profileLocalId") != profile_id
	):
		return {"ok": false, "error": "invalid_pairing_response"}
	return {
		"ok": true,
		"device_binding_id": String(body.deviceBindingId),
		"family_id": String(body.familyId),
		"cloud_profile_id": String(body.cloudProfileId),
		"profile_local_id": String(body.profileLocalId),
	}

func authorization_header() -> String:
	return "" if _access_token.is_empty() else "Bearer %s" % _access_token

func clear_session() -> void:
	_access_token = ""
	if _credential_store != null and _credential_store.has_method("clear_refresh_token"):
		_credential_store.clear_refresh_token()

func _pair_request(body: Dictionary) -> Dictionary:
	var headers := _public_headers()
	headers["Authorization"] = authorization_header()
	return await _transport.request_json(
		"POST",
		"%s/functions/v1/pair-device" % _base_url(),
		headers,
		body
	)

func _accept_tokens(body_value: Variant) -> Dictionary:
	if not body_value is Dictionary:
		return {"ok": false, "error": "invalid_auth_response"}
	var body: Dictionary = body_value
	var access_token := String(body.get("access_token", ""))
	var refresh_token := String(body.get("refresh_token", ""))
	if access_token.is_empty() or refresh_token.is_empty():
		return {"ok": false, "error": "invalid_auth_response"}
	if not _credential_store.save_refresh_token(refresh_token):
		return {"ok": false, "error": "refresh_token_storage_failed"}
	_access_token = access_token
	return {"ok": true}

func _public_headers() -> Dictionary:
	return {
		"Content-Type": "application/json",
		"apikey": String(_config.get("publishable_key", "")),
	}

func _base_url() -> String:
	return String(_config.get("supabase_url", "")).rstrip("/")

func _pair_error(response: Dictionary) -> String:
	match int(response.get("status", 0)):
		400:
			return "invalid_pairing_request"
		401:
			return "authentication"
		403:
			return "permission"
		404, 409, 410:
			return "pairing_code_unavailable"
	return "pairing_network" if int(response.get("status", 0)) <= 0 or int(response.get("status", 0)) >= 500 else "pairing_failed"

func _is_pairing_code(code: String) -> bool:
	if code.length() != 6:
		return false
	for character in code:
		if character < "0" or character > "9":
			return false
	return true

func _is_uuid(value: Variant) -> bool:
	return value is String and UuidV4Script.is_valid(value)
