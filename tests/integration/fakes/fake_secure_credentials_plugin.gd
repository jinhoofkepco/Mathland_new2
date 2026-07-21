class_name FakeSecureCredentialsPlugin
extends RefCounted

var saved_token := ""
var save_calls := 0
var load_calls := 0
var clear_calls := 0
var contains_calls := 0
var accept_save := true
var accept_clear := true

func saveRefreshToken(token: String) -> bool:
	save_calls += 1
	if not accept_save:
		return false
	saved_token = token
	return true

func loadRefreshToken() -> String:
	load_calls += 1
	return saved_token

func clearRefreshToken() -> bool:
	clear_calls += 1
	if not accept_clear:
		return false
	saved_token = ""
	return true

func hasRefreshToken() -> bool:
	contains_calls += 1
	return not saved_token.is_empty()
