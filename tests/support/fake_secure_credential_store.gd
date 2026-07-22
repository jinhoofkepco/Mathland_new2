class_name FakeSecureCredentialStore
extends RefCounted

var refresh_token := ""
var saved_tokens: Array[String] = []
var clear_calls := 0
var available := true

func is_available() -> bool:
	return available

func save_refresh_token(token: String) -> bool:
	if not available or token.is_empty():
		return false
	refresh_token = token
	saved_tokens.append(token)
	return true

func load_refresh_token() -> String:
	return refresh_token if available else ""

func clear_refresh_token() -> bool:
	if not available:
		return false
	clear_calls += 1
	refresh_token = ""
	return true

func has_refresh_token() -> bool:
	return available and not refresh_token.is_empty()
