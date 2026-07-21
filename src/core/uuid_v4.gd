class_name UuidV4
extends RefCounted

static func generate() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80

	var hexadecimal := ""
	for byte in bytes:
		hexadecimal += "%02x" % byte
	return "%s-%s-%s-%s-%s" % [
		hexadecimal.substr(0, 8),
		hexadecimal.substr(8, 4),
		hexadecimal.substr(12, 4),
		hexadecimal.substr(16, 4),
		hexadecimal.substr(20, 12),
	]

static func is_valid(value: String) -> bool:
	var expression := RegEx.new()
	expression.compile("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
	return expression.search(value) != null
