class_name TestCase
extends RefCounted

var assertion_count := 0
var failures: Array[String] = []

func assert_true(value: Variant, message: String = "") -> void:
	assertion_count += 1
	if not value:
		failures.append(message if not message.is_empty() else "Expected value to be true")

func assert_false(value: Variant, message: String = "") -> void:
	assertion_count += 1
	if value:
		failures.append(message if not message.is_empty() else "Expected value to be false")

func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	assertion_count += 1
	if actual != expected:
		failures.append(message if not message.is_empty() else "Expected %s, got %s" % [expected, actual])

func assert_ne(actual: Variant, unexpected: Variant, message: String = "") -> void:
	assertion_count += 1
	if actual == unexpected:
		failures.append(message if not message.is_empty() else "Did not expect %s" % [unexpected])

func assert_null(value: Variant, message: String = "") -> void:
	assertion_count += 1
	if value != null:
		failures.append(message if not message.is_empty() else "Expected value to be null")

func assert_not_null(value: Variant, message: String = "") -> void:
	assertion_count += 1
	if value == null:
		failures.append(message if not message.is_empty() else "Expected value not to be null")
