class_name ProfileRecord
extends RefCounted

const PinVerifierScript = preload("res://src/profiles/pin_verifier.gd")
const UuidV4Script = preload("res://src/core/uuid_v4.gd")

const AVATAR_IDS := ["moa_mint", "moa_sky", "moa_coral"]
const DEFAULT_SETTINGS := {
	"adaptive_difficulty": false,
	"timing_aids": true,
	"timers_enabled": true,
	"reduced_motion": false,
	"effect_quality": "high",
	"master_db": 0.0,
	"music_db": -6.0,
	"sfx_db": 0.0,
	"voice_db": 0.0,
	"voice_enabled": true,
}
const BOOLEAN_SETTINGS := [
	"adaptive_difficulty", "timing_aids", "timers_enabled", "reduced_motion", "voice_enabled",
]
const AUDIO_SETTINGS := ["master_db", "music_db", "sfx_db", "voice_db"]
const MIN_AUDIO_DB := -80.0
const MAX_AUDIO_DB := 0.0
const MAX_SAFE_INTEGER := 9007199254740991

static func create(profile_id: String, nickname: Variant, avatar_id: Variant, pin_data: Dictionary, created_at: int) -> Dictionary:
	var normalized_nickname := normalize_nickname(nickname)
	if normalized_nickname.is_empty() or not is_valid_avatar(avatar_id):
		return {}
	if not pin_data.has("pin_salt") or not pin_data.has("pin_verifier"):
		return {}
	return {
		"profile_id": profile_id,
		"nickname": normalized_nickname,
		"avatar_id": avatar_id,
		"pin_salt": pin_data.pin_salt,
		"pin_verifier": pin_data.pin_verifier,
		"failed_attempts": 0,
		"locked_until": 0,
		"settings": DEFAULT_SETTINGS.duplicate(true),
		"created_at": created_at,
	}

static func from_dictionary(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var record: Dictionary = value
	var profile_id: Variant = record.get("profile_id", null)
	var nickname: Variant = record.get("nickname", null)
	var avatar_id: Variant = record.get("avatar_id", null)
	var pin_salt: Variant = record.get("pin_salt", null)
	var pin_verifier: Variant = record.get("pin_verifier", null)
	var failed_attempts: Variant = record.get("failed_attempts", null)
	var locked_until: Variant = record.get("locked_until", null)
	var created_at: Variant = record.get("created_at", null)
	if not profile_id is String or not UuidV4Script.is_valid(profile_id):
		return {}
	var normalized_nickname := normalize_nickname(nickname)
	if normalized_nickname.is_empty() or normalized_nickname != nickname or not is_valid_avatar(avatar_id):
		return {}
	if not pin_salt is String or not pin_verifier is String:
		return {}
	if Marshalls.base64_to_raw(pin_salt).size() != PinVerifierScript.SALT_BYTES:
		return {}
	if Marshalls.base64_to_raw(pin_verifier).size() != PinVerifierScript.VERIFIER_BYTES:
		return {}
	if not _is_nonnegative_integer(failed_attempts) or failed_attempts > 5:
		return {}
	if not _is_nonnegative_integer(locked_until) or not _is_nonnegative_integer(created_at):
		return {}
	var settings := normalized_settings(record.get("settings", null))
	if settings.is_empty():
		return {}
	return {
		"profile_id": profile_id,
		"nickname": normalized_nickname,
		"avatar_id": avatar_id,
		"pin_salt": pin_salt,
		"pin_verifier": pin_verifier,
		"failed_attempts": int(failed_attempts),
		"locked_until": int(locked_until),
		"settings": settings,
		"created_at": int(created_at),
	}

static func normalize_nickname(value: Variant) -> String:
	if not value is String:
		return ""
	var normalized := (value as String).strip_edges()
	var codepoint_count := normalized.to_utf32_buffer().size()
	if codepoint_count < 1 or codepoint_count > 16:
		return ""
	return normalized

static func is_valid_avatar(value: Variant) -> bool:
	return value is String and value in AVATAR_IDS

static func apply_settings_patch(settings: Variant, patch: Variant) -> Dictionary:
	if not settings is Dictionary or not patch is Dictionary or (patch as Dictionary).is_empty():
		return {}
	var normalized := normalized_settings(settings)
	if normalized.is_empty():
		return {}
	for key in (patch as Dictionary):
		if not normalized.has(key) or not _is_valid_setting(key, patch[key]):
			return {}
		if key in AUDIO_SETTINGS:
			normalized[key] = float(patch[key])
		else:
			normalized[key] = patch[key]
	return normalized

static func normalized_settings(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var settings: Dictionary = value
	if settings.size() != DEFAULT_SETTINGS.size():
		return {}
	var normalized := {}
	for key in DEFAULT_SETTINGS:
		if not settings.has(key) or not _is_valid_setting(key, settings[key]):
			return {}
		normalized[key] = float(settings[key]) if key in AUDIO_SETTINGS else settings[key]
	return normalized

static func _is_valid_setting(key: Variant, value: Variant) -> bool:
	if key in BOOLEAN_SETTINGS:
		return value is bool
	if key == "effect_quality":
		return value is String and value in ["low", "medium", "high"]
	if key in AUDIO_SETTINGS:
		return (value is int or value is float) and value >= MIN_AUDIO_DB and value <= MAX_AUDIO_DB
	return false

static func _is_nonnegative_integer(value: Variant) -> bool:
	if value is int:
		return value >= 0
	return value is float and is_finite(value) and value >= 0.0 and value <= MAX_SAFE_INTEGER and value == floor(value)
