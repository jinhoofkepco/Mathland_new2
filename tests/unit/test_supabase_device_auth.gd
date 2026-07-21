extends "res://tests/support/test_case.gd"

const AuthScript = preload("res://src/sync/supabase_device_auth.gd")
const FakeTransportScript = preload("res://tests/support/fake_http_json_transport.gd")
const FakeCredentialsScript = preload("res://tests/support/fake_secure_credential_store.gd")

const CONFIG := {
	"supabase_url": "https://mathland.example.supabase.co",
	"publishable_key": "sb_publishable_test",
}

func run(_tree: SceneTree) -> void:
	_test_public_config_is_an_exact_https_origin()
	await _test_anonymous_signup_persists_only_refresh_token()
	await _test_stored_refresh_token_is_used_without_signup()
	await _test_pairing_uses_exact_wire_shape_and_retries_one_401()
	await _test_pairing_never_confuses_cloud_and_local_profile_ids()
	await _test_pairing_rejects_invalid_codes_without_network()

func _test_public_config_is_an_exact_https_origin() -> void:
	assert_true(AuthScript.is_valid_public_config(CONFIG))
	for invalid in [
		{},
		{"supabase_url": "http://mathland.example", "publishable_key": "sb_publishable_test"},
		{"supabase_url": "https://localhost", "publishable_key": "sb_publishable_test"},
		{"supabase_url": "https://LOCALHOST", "publishable_key": "sb_publishable_test"},
		{"supabase_url": "https://mathland.example/path", "publishable_key": "sb_publishable_test"},
		{"supabase_url": "https://mathland.example", "publishable_key": "service_role_secret"},
		{"supabase_url": "https://mathland.example", "publishable_key": "sb_publishable_test", "extra": true},
	]:
		assert_false(AuthScript.is_valid_public_config(invalid), "accepted unsafe config: %s" % invalid)

func _test_anonymous_signup_persists_only_refresh_token() -> void:
	var transport := FakeTransportScript.new()
	transport.enqueue(_response(200, {"access_token": "access-one", "refresh_token": "refresh-one"}))
	var credentials := FakeCredentialsScript.new()
	var auth := AuthScript.new(transport, credentials, CONFIG, "device-1")
	var result: Dictionary = await auth.ensure_session()
	assert_true(result.ok)
	assert_eq(auth.authorization_header(), "Bearer access-one")
	assert_eq(credentials.saved_tokens, ["refresh-one"])
	assert_false("access-one" in JSON.stringify(credentials), "access token escaped memory-only auth state")
	assert_eq(transport.requests.size(), 1)
	assert_eq(transport.requests[0].method, "POST")
	assert_eq(transport.requests[0].url, "%s/auth/v1/signup" % CONFIG.supabase_url)
	assert_eq(transport.requests[0].body, {})
	assert_eq(transport.requests[0].headers.get("apikey"), CONFIG.publishable_key)

func _test_stored_refresh_token_is_used_without_signup() -> void:
	var transport := FakeTransportScript.new()
	transport.enqueue(_response(200, {"access_token": "access-two", "refresh_token": "refresh-two"}))
	var credentials := FakeCredentialsScript.new()
	credentials.refresh_token = "refresh-old"
	var auth := AuthScript.new(transport, credentials, CONFIG, "device-2")
	var result: Dictionary = await auth.ensure_session()
	assert_true(result.ok)
	assert_true(transport.requests[0].url.ends_with("/auth/v1/token?grant_type=refresh_token"))
	assert_eq(transport.requests[0].body, {"refresh_token": "refresh-old"})
	assert_eq(credentials.refresh_token, "refresh-two")

func _test_pairing_uses_exact_wire_shape_and_retries_one_401() -> void:
	var transport := FakeTransportScript.new()
	transport.enqueue(_response(200, {"access_token": "access-a", "refresh_token": "refresh-a"}))
	transport.enqueue(_response(401, {"error": {"code": "AUTH_REQUIRED"}}))
	transport.enqueue(_response(200, {"access_token": "access-b", "refresh_token": "refresh-b"}))
	transport.enqueue(_response(200, {
		"deviceBindingId": "11111111-1111-4111-8111-111111111111",
		"familyId": "22222222-2222-4222-8222-222222222222",
		"cloudProfileId": "33333333-3333-4333-8333-333333333333",
		"profileLocalId": "profile-1",
	}))
	var auth := AuthScript.new(transport, FakeCredentialsScript.new(), CONFIG, "device-3")
	assert_true((await auth.ensure_session()).ok)
	var paired: Dictionary = await auth.pair("123456", "profile-1", "모아")
	assert_true(paired.ok)
	assert_eq(transport.requests.size(), 4)
	assert_eq(transport.requests[1].url, "%s/functions/v1/pair-device" % CONFIG.supabase_url)
	assert_eq(transport.requests[1].body, {
		"code": "123456",
		"deviceId": "device-3",
		"profileLocalId": "profile-1",
		"displayName": "모아",
	})
	assert_eq(transport.requests[1].headers.get("Authorization"), "Bearer access-a")
	assert_eq(transport.requests[3].headers.get("Authorization"), "Bearer access-b")
	assert_eq(paired, {
		"ok": true,
		"device_binding_id": "11111111-1111-4111-8111-111111111111",
		"family_id": "22222222-2222-4222-8222-222222222222",
		"cloud_profile_id": "33333333-3333-4333-8333-333333333333",
		"profile_local_id": "profile-1",
	})

func _test_pairing_never_confuses_cloud_and_local_profile_ids() -> void:
	var transport := FakeTransportScript.new()
	transport.enqueue(_response(200, {"access_token": "access", "refresh_token": "refresh"}))
	transport.enqueue(_response(200, {
		"deviceBindingId": "11111111-1111-4111-8111-111111111111",
		"familyId": "22222222-2222-4222-8222-222222222222",
		"cloudProfileId": "33333333-3333-4333-8333-333333333333",
		"profileLocalId": "33333333-3333-4333-8333-333333333333",
	}))
	var auth := AuthScript.new(transport, FakeCredentialsScript.new(), CONFIG, "device-3")
	var result: Dictionary = await auth.pair("123456", "local-profile", "모아")
	assert_eq(result.get("error"), "invalid_pairing_response")

func _test_pairing_rejects_invalid_codes_without_network() -> void:
	var transport := FakeTransportScript.new()
	var auth := AuthScript.new(transport, FakeCredentialsScript.new(), CONFIG, "device-4")
	for invalid in ["", "12345", "1234567", "12A456", "１２３４５６"]:
		var result: Dictionary = await auth.pair(invalid, "profile-1", "모아")
		assert_eq(result.get("error"), "invalid_pairing_code")
	assert_eq(transport.requests, [])

func _response(status: int, body: Dictionary) -> Dictionary:
	return {"ok": status >= 200 and status < 300, "status": status, "body": body.duplicate(true)}
