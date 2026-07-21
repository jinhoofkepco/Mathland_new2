class_name PrimeFactorizationGenerator
extends "res://src/content/generation/generators/arithmetic_generator_base.gd"

const KEYS: Array[String] = [
	"value_min", "value_max", "factor_count_min", "factor_count_max", "allowed_primes"
]
const MAX_SAFE_FACTOR_SLOTS := 52
const MILLER_RABIN_BASES: Array[int] = [2, 325, 9375, 28178, 450775, 9780504, 1795265022]

func validate_parameters(parameters: Dictionary) -> PackedStringArray:
	var issues := PackedStringArray()
	if not _has_exact_keys(parameters, KEYS):
		issues.append("PARAMETER_KEYS")
	var value_minimum: Variant = parameters.get("value_min")
	var value_maximum: Variant = parameters.get("value_max")
	if (
		not _is_nonnegative_safe_integer(value_minimum)
		or not _is_nonnegative_safe_integer(value_maximum)
		or int(value_minimum) < 1
		or int(value_maximum) < int(value_minimum)
	):
		issues.append("VALUE_RANGE")
	var count_minimum: Variant = parameters.get("factor_count_min")
	var count_maximum: Variant = parameters.get("factor_count_max")
	if (
		not _is_nonnegative_safe_integer(count_minimum)
		or not _is_nonnegative_safe_integer(count_maximum)
		or int(count_minimum) < 1
		or int(count_maximum) < int(count_minimum)
		or int(count_maximum) > MAX_SAFE_FACTOR_SLOTS
	):
		issues.append("FACTOR_COUNT_RANGE")
	var allowed: Variant = parameters.get("allowed_primes")
	if not allowed is Array or allowed.is_empty():
		issues.append("ALLOWED_PRIMES")
	else:
		var seen := {}
		var has_nonprime := false
		for candidate in allowed:
			if not _is_prime(candidate):
				has_nonprime = true
			seen[candidate] = true
		if has_nonprime:
			issues.append("ALLOWED_PRIMES")
		if seen.size() != allowed.size():
			issues.append("DUPLICATE_PRIMES")
	return issues

func generate(_activity: Dictionary, band: Dictionary, seed: int) -> Dictionary:
	var parameters: Variant = _parameters(band)
	if not parameters is Dictionary or not validate_parameters(parameters).is_empty():
		return _invalid()
	var allowed_primes: Array = parameters["allowed_primes"].duplicate()
	var rng := SeededRngScript.new(seed)
	for _attempt in MAX_ATTEMPTS:
		var factor_count: int = rng.range_int(
			parameters["factor_count_min"], parameters["factor_count_max"]
		)
		var factors: Array[int] = []
		var value := 1
		var overflowed := false
		for _slot in factor_count:
			var factor: int = allowed_primes[rng.range_int(0, allowed_primes.size() - 1)]
			factors.append(factor)
			@warning_ignore("integer_division")
			if value > Contract.SAFE_INTEGER_MAX / factor:
				overflowed = true
			elif not overflowed:
				value *= factor
		if overflowed or value < parameters["value_min"] or value > parameters["value_max"]:
			continue
		factors.sort()
		last_error = ""
		return {
			"resolved_parameters": {
				"value": value,
				"factors": factors.duplicate(),
				"factor_count": factor_count,
				"allowed_primes": allowed_primes.duplicate(),
			},
			"prompt": {"key":"question.prime_factorization","args":{"value":value}},
			"correct_answer": {
				"kind":"integer_list","values":factors.duplicate(),"order_matters":false
			},
		}
	return _unsatisfiable()

func _is_prime(value: Variant) -> bool:
	if not _is_nonnegative_safe_integer(value) or int(value) < 2:
		return false
	var candidate := int(value)
	if candidate in [2, 3]:
		return true
	if candidate % 2 == 0:
		return false
	var odd_part := candidate - 1
	var twos := 0
	while odd_part % 2 == 0:
		@warning_ignore("integer_division")
		odd_part = odd_part / 2
		twos += 1
	for raw_base in MILLER_RABIN_BASES:
		var base := raw_base % candidate
		if base == 0:
			continue
		var witness := _modular_power(base, odd_part, candidate)
		if witness == 1 or witness == candidate - 1:
			continue
		var composite := true
		for _round in range(1, twos):
			witness = _modular_multiply(witness, witness, candidate)
			if witness == candidate - 1:
				composite = false
				break
		if composite:
			return false
	return true

func _modular_power(base: int, exponent: int, modulus: int) -> int:
	var value := base % modulus
	var power := exponent
	var result := 1
	while power > 0:
		if power & 1:
			result = _modular_multiply(result, value, modulus)
		power >>= 1
		if power > 0:
			value = _modular_multiply(value, value, modulus)
	return result

func _modular_multiply(left: int, right: int, modulus: int) -> int:
	var addend := left % modulus
	var multiplier := right
	var result := 0
	while multiplier > 0:
		if multiplier & 1:
			result = _modular_add(result, addend, modulus)
		multiplier >>= 1
		if multiplier > 0:
			addend = _modular_add(addend, addend, modulus)
	return result

func _modular_add(left: int, right: int, modulus: int) -> int:
	return left - (modulus - right) if left >= modulus - right else left + right
