class_name MathlandExpressionEngine
extends RefCounted

const Contract = preload("res://src/content/generated/content_contract_v1.gd")
const ExpressionResultScript = preload("res://src/content/expression/expression_result.gd")

const MAX_SOURCE_LENGTH := 512
const MAX_TOKENS := 128
const MAX_NESTING := 16

const TOKEN_CHARACTERS := {
	"+": "plus",
	"-": "minus",
	"*": "star",
	"/": "slash",
	"%": "percent",
	"(": "left_paren",
	")": "right_paren",
	",": "comma",
}

var _tokens: Array[Dictionary] = []
var _current := 0
var _parse_error: Variant = null

func evaluate(source: String, variables: Dictionary = {}) -> MathlandExpressionResult:
	var tokenized := _tokenize(source)
	if not tokenized["ok"]:
		return tokenized["result"]
	_tokens.assign(tokenized["tokens"])
	_current = 0
	_parse_error = null
	var expression: Variant = _parse_additive(0)
	if _parse_error != null:
		return _parse_error
	if expression == null:
		return _failure("INVALID_TOKEN", _peek()["offset"])
	if not _check("eof"):
		return _failure("TRAILING_INPUT", _peek()["offset"])
	var evaluated := _evaluate_node(expression, variables)
	if not evaluated["ok"]:
		return evaluated["result"]
	return ExpressionResultScript.new(true, evaluated["value"], "", -1)

func _tokenize(source: String) -> Dictionary:
	if _utf16_length(source) > MAX_SOURCE_LENGTH:
		return {"ok": false, "result": _failure("TOO_COMPLEX", MAX_SOURCE_LENGTH)}
	var tokens: Array[Dictionary] = []
	var index := 0
	while index < source.length():
		var character := source.substr(index, 1)
		if character in [" ", "\t", "\n", "\r"]:
			index += 1
			continue
		var start := index
		var kind := String(TOKEN_CHARACTERS.get(character, ""))
		if not kind.is_empty():
			index += 1
			var token_limit: Variant = _append_token(tokens, kind, character, source, start)
			if token_limit != null:
				return {"ok": false, "result": token_limit}
			continue
		if _is_ascii_digit(character):
			index += 1
			while index < source.length() and _is_ascii_digit(source.substr(index, 1)):
				index += 1
			var token_limit: Variant = _append_token(
				tokens, "integer", source.substr(start, index - start), source, start
			)
			if token_limit != null:
				return {"ok": false, "result": token_limit}
			continue
		if _is_identifier_start(character):
			index += 1
			while index < source.length() and _is_identifier_continue(source.substr(index, 1)):
				index += 1
			var token_limit: Variant = _append_token(
				tokens, "identifier", source.substr(start, index - start), source, start
			)
			if token_limit != null:
				return {"ok": false, "result": token_limit}
			continue
		return {"ok": false, "result": _failure("INVALID_TOKEN", _utf16_offset(source, index))}
	if tokens.is_empty():
		return {"ok": false, "result": _failure("EMPTY", 0)}
	tokens.append({"kind": "eof", "lexeme": "", "offset": _utf16_length(source)})
	return {"ok": true, "tokens": tokens}

func _append_token(
	tokens: Array[Dictionary], kind: String, lexeme: String, source: String, source_index: int
) -> Variant:
	var offset := _utf16_offset(source, source_index)
	if tokens.size() >= MAX_TOKENS:
		return _failure("TOO_COMPLEX", offset)
	tokens.append({"kind": kind, "lexeme": lexeme, "offset": offset})
	return null

func _parse_additive(depth: int) -> Variant:
	var expression: Variant = _parse_multiplicative(depth)
	while _parse_error == null and expression != null and _match(["plus", "minus"]):
		var operator := _previous()
		var right: Variant = _parse_multiplicative(depth)
		if right == null:
			return null
		expression = {
			"kind": "binary",
			"operator": "+" if operator["kind"] == "plus" else "-",
			"left": expression,
			"right": right,
			"offset": operator["offset"],
		}
	return expression

func _parse_multiplicative(depth: int) -> Variant:
	var expression: Variant = _parse_unary(depth)
	while (
		_parse_error == null
		and expression != null
		and _match(["star", "slash", "percent"])
	):
		var operator := _previous()
		var right: Variant = _parse_unary(depth)
		if right == null:
			return null
		var symbol: String = {"star": "*", "slash": "/", "percent": "%"}[operator["kind"]]
		expression = {
			"kind": "binary",
			"operator": symbol,
			"left": expression,
			"right": right,
			"offset": operator["offset"],
		}
	return expression

func _parse_unary(depth: int) -> Variant:
	if not _match(["minus"]):
		return _parse_primary(depth)
	var operator := _previous()
	if depth >= MAX_NESTING:
		_parse_error = _failure("TOO_COMPLEX", operator["offset"])
		return null
	var operand: Variant = _parse_unary(depth + 1)
	if operand == null:
		return null
	return {"kind": "unary", "operand": operand, "offset": operator["offset"]}

func _parse_primary(depth: int) -> Variant:
	if _match(["integer"]):
		var token := _previous()
		var parsed_integer := _parse_safe_integer(token["lexeme"], token["offset"])
		if not parsed_integer["ok"]:
			_parse_error = parsed_integer["result"]
			return null
		return {"kind": "integer", "value": parsed_integer["value"], "offset": token["offset"]}

	if _match(["identifier"]):
		var identifier := _previous()
		if not _match(["left_paren"]):
			return {
				"kind": "variable",
				"name": identifier["lexeme"],
				"offset": identifier["offset"],
			}
		if depth >= MAX_NESTING:
			_parse_error = _failure("TOO_COMPLEX", identifier["offset"])
			return null
		var arguments: Array = []
		if not _check("right_paren"):
			while true:
				var argument: Variant = _parse_additive(depth + 1)
				if argument == null:
					return null
				arguments.append(argument)
				if not _match(["comma"]):
					break
		if not _match(["right_paren"]):
			_parse_error = _failure("INVALID_TOKEN", _peek()["offset"])
			return null
		return {
			"kind": "call",
			"name": identifier["lexeme"],
			"arguments": arguments,
			"offset": identifier["offset"],
		}

	if _match(["left_paren"]):
		var left_paren := _previous()
		if depth >= MAX_NESTING:
			_parse_error = _failure("TOO_COMPLEX", left_paren["offset"])
			return null
		var expression: Variant = _parse_additive(depth + 1)
		if expression == null:
			return null
		if not _match(["right_paren"]):
			_parse_error = _failure("INVALID_TOKEN", _peek()["offset"])
			return null
		return expression

	_parse_error = _failure("INVALID_TOKEN", _peek()["offset"])
	return null

func _evaluate_node(node: Dictionary, variables: Dictionary) -> Dictionary:
	match node["kind"]:
		"integer":
			return _internal_success(node["value"])
		"variable":
			if not variables.has(node["name"]):
				return _internal_failure("UNKNOWN_IDENTIFIER", node["offset"])
			var raw_value: Variant = variables[node["name"]]
			if not _is_safe_integer(raw_value):
				return _internal_failure("OVERFLOW", node["offset"])
			return _internal_success(int(raw_value))
		"unary":
			var operand := _evaluate_node(node["operand"], variables)
			if not operand["ok"]:
				return operand
			return _checked_value(-int(operand["value"]), node["offset"])
		"binary":
			var left := _evaluate_node(node["left"], variables)
			if not left["ok"]:
				return left
			var right := _evaluate_node(node["right"], variables)
			if not right["ok"]:
				return right
			return _evaluate_binary(
				node["operator"], int(left["value"]), int(right["value"]), node["offset"]
			)
		"call":
			var function_name := String(node["name"])
			if function_name not in ["mod", "quotient", "digit", "gcd", "lcm"]:
				return _internal_failure("UNKNOWN_FUNCTION", node["offset"])
			var arguments: Array = node["arguments"]
			if arguments.size() != 2:
				return _internal_failure("ARITY", node["offset"])
			var left := _evaluate_node(arguments[0], variables)
			if not left["ok"]:
				return left
			var right := _evaluate_node(arguments[1], variables)
			if not right["ok"]:
				return right
			return _evaluate_call(
				function_name, int(left["value"]), int(right["value"]), node["offset"]
			)
	return _internal_failure("INVALID_TOKEN", int(node.get("offset", 0)))

func _evaluate_binary(operator: String, left: int, right: int, offset: int) -> Dictionary:
	match operator:
		"+":
			if (right > 0 and left > Contract.SAFE_INTEGER_MAX - right) or (
				right < 0 and left < Contract.SAFE_INTEGER_MIN - right
			):
				return _internal_failure("OVERFLOW", offset)
			return _internal_success(left + right)
		"-":
			if (right > 0 and left < Contract.SAFE_INTEGER_MIN + right) or (
				right < 0 and left > Contract.SAFE_INTEGER_MAX + right
			):
				return _internal_failure("OVERFLOW", offset)
			return _internal_success(left - right)
		"*":
			return _checked_multiply(left, right, offset)
		"/":
			if right == 0:
				return _internal_failure("DIVIDE_BY_ZERO", offset)
			if left % right != 0:
				return _internal_failure("NON_INTEGRAL_DIVISION", offset)
			return _internal_success(_truncate_quotient(left, right))
		"%":
			if right == 0:
				return _internal_failure("DIVIDE_BY_ZERO", offset)
			return _internal_success(_positive_modulo(left, right))
	return _internal_failure("INVALID_TOKEN", offset)

func _evaluate_call(name: String, left: int, right: int, offset: int) -> Dictionary:
	match name:
		"mod":
			if right == 0:
				return _internal_failure("DIVIDE_BY_ZERO", offset)
			return _internal_success(_positive_modulo(left, right))
		"quotient":
			if right == 0:
				return _internal_failure("DIVIDE_BY_ZERO", offset)
			return _internal_success(_truncate_quotient(left, right))
		"digit":
			var absolute := absi(left)
			if right < 1 or right > str(absolute).length():
				return _internal_failure("DIGIT_RANGE", offset)
			for _index in range(right - 1):
				@warning_ignore("integer_division")
				absolute = absolute / 10
			return _internal_success(absolute % 10)
		"gcd":
			return _internal_success(_greatest_common_divisor(left, right))
		"lcm":
			if left == 0 or right == 0:
				return _internal_success(0)
			var gcd_value := _greatest_common_divisor(left, right)
			var reduced := _truncate_quotient(left, gcd_value)
			var multiplied := _checked_multiply(reduced, right, offset)
			if not multiplied["ok"]:
				return multiplied
			return _internal_success(absi(int(multiplied["value"])))
	return _internal_failure("UNKNOWN_FUNCTION", offset)

func _checked_multiply(left: int, right: int, offset: int) -> Dictionary:
	if left == 0 or right == 0:
		return _internal_success(0)
	var absolute_left := absi(left)
	var absolute_right := absi(right)
	@warning_ignore("integer_division")
	var allowed := int(Contract.SAFE_INTEGER_MAX / absolute_left)
	if absolute_right > allowed:
		return _internal_failure("OVERFLOW", offset)
	return _internal_success(left * right)

func _positive_modulo(dividend: int, divisor: int) -> int:
	var positive_divisor := absi(divisor)
	return ((dividend % positive_divisor) + positive_divisor) % positive_divisor

func _truncate_quotient(dividend: int, divisor: int) -> int:
	@warning_ignore("integer_division")
	var magnitude := int(absi(dividend) / absi(divisor))
	return -magnitude if (dividend < 0) != (divisor < 0) else magnitude

func _greatest_common_divisor(left: int, right: int) -> int:
	var a := absi(left)
	var b := absi(right)
	while b != 0:
		var remainder := a % b
		a = b
		b = remainder
	return a

func _parse_safe_integer(source: String, offset: int) -> Dictionary:
	var value := 0
	for index in source.length():
		var digit := source.unicode_at(index) - 48
		@warning_ignore("integer_division")
		if value > int((Contract.SAFE_INTEGER_MAX - digit) / 10):
			return _internal_failure("OVERFLOW", offset)
		value = value * 10 + digit
	return _internal_success(value)

func _checked_value(value: int, offset: int) -> Dictionary:
	if value < Contract.SAFE_INTEGER_MIN or value > Contract.SAFE_INTEGER_MAX:
		return _internal_failure("OVERFLOW", offset)
	return _internal_success(value)

func _is_safe_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return int(value) >= Contract.SAFE_INTEGER_MIN and int(value) <= Contract.SAFE_INTEGER_MAX
	if typeof(value) == TYPE_FLOAT:
		var number := float(value)
		return (
			is_finite(number)
			and number == floor(number)
			and number >= Contract.SAFE_INTEGER_MIN
			and number <= Contract.SAFE_INTEGER_MAX
		)
	return false

func _match(kinds: Array[String]) -> bool:
	for kind in kinds:
		if _check(kind):
			_current += 1
			return true
	return false

func _check(kind: String) -> bool:
	return _peek()["kind"] == kind

func _peek() -> Dictionary:
	return _tokens[_current] if _current < _tokens.size() else _tokens.back()

func _previous() -> Dictionary:
	return _tokens[_current - 1]

func _internal_success(value: int) -> Dictionary:
	return {"ok": true, "value": value}

func _internal_failure(code: String, offset: int) -> Dictionary:
	return {"ok": false, "result": _failure(code, offset)}

func _failure(code: String, offset: int) -> MathlandExpressionResult:
	return ExpressionResultScript.new(false, 0, code, offset)

func _is_ascii_digit(character: String) -> bool:
	return character >= "0" and character <= "9"

func _is_identifier_start(character: String) -> bool:
	return (
		(character >= "A" and character <= "Z")
		or (character >= "a" and character <= "z")
		or character == "_"
	)

func _is_identifier_continue(character: String) -> bool:
	return _is_identifier_start(character) or _is_ascii_digit(character)

func _utf16_length(value: String) -> int:
	return _utf16_offset(value, value.length())

func _utf16_offset(value: String, end_index: int) -> int:
	var code_units := 0
	for index in end_index:
		code_units += 2 if value.unicode_at(index) > 0xFFFF else 1
	return code_units
