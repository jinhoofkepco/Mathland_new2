class_name PinVerifier
extends RefCounted

const SALT_BYTES := 16
const VERIFIER_BYTES := 32

static func is_valid(pin: Variant) -> bool:
	if not pin is String:
		return false
	var pin_bytes := (pin as String).to_utf8_buffer()
	if pin_bytes.size() != 4:
		return false
	for byte in pin_bytes:
		if byte < 48 or byte > 57:
			return false
	return true

static func create(pin: Variant) -> Dictionary:
	if not is_valid(pin):
		return {}
	var salt := Crypto.new().generate_random_bytes(SALT_BYTES)
	return {
		"pin_salt": Marshalls.raw_to_base64(salt),
		"pin_verifier": Marshalls.raw_to_base64(_hash(salt, pin as String)),
	}

static func verify(pin: Variant, salt_base64: Variant, verifier_base64: Variant) -> bool:
	if not is_valid(pin) or not salt_base64 is String or not verifier_base64 is String:
		return false
	var salt := Marshalls.base64_to_raw(salt_base64 as String)
	var expected := Marshalls.base64_to_raw(verifier_base64 as String)
	if salt.size() != SALT_BYTES:
		return false
	return _constant_time_equals(_hash(salt, pin as String), expected)

static func _hash(salt: PackedByteArray, pin: String) -> PackedByteArray:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(salt)
	context.update(pin.to_utf8_buffer())
	return context.finish()

static func _constant_time_equals(actual: PackedByteArray, expected: PackedByteArray) -> bool:
	var difference := actual.size() ^ expected.size()
	var comparison_length := maxi(actual.size(), expected.size())
	for index in comparison_length:
		var actual_byte := actual[index] if index < actual.size() else 0
		var expected_byte := expected[index] if index < expected.size() else 0
		difference |= actual_byte ^ expected_byte
	return difference == 0 and expected.size() == VERIFIER_BYTES
