class_name SeededRng
extends RefCounted

const UINT32_MASK := 0xFFFFFFFF
const UINT32_RANGE := 0x100000000
const ZERO_SEED_STATE := 0x6D2B79F5
const SAFE_INTEGER_MIN := -9007199254740991
const SAFE_INTEGER_MAX := 9007199254740991

var state: int
var is_valid := true
var last_error := ""

func _init(seed: int = 0) -> void:
	if seed < 0 or seed > UINT32_MASK:
		is_valid = false
		last_error = "INVALID_SEED"
		state = 0
		return
	state = ZERO_SEED_STATE if seed == 0 else seed

func next_u32() -> int:
	if not is_valid:
		return -1
	var value := state
	value = (value ^ ((value << 13) & UINT32_MASK)) & UINT32_MASK
	value = (value ^ (value >> 17)) & UINT32_MASK
	value = (value ^ ((value << 5) & UINT32_MASK)) & UINT32_MASK
	state = value
	return state

func range_int(minimum: int, maximum: int) -> int:
	if (
		not is_valid
		or minimum < SAFE_INTEGER_MIN
		or minimum > SAFE_INTEGER_MAX
		or maximum < SAFE_INTEGER_MIN
		or maximum > SAFE_INTEGER_MAX
		or maximum < minimum
		or maximum - minimum > UINT32_MASK
	):
		last_error = "INVALID_RANGE"
		return -1
	var span := maximum - minimum + 1
	return minimum + (next_u32() % span)

func weighted_index(weights: Array) -> int:
	if weights.is_empty():
		return -1
	var total := 0
	for value in weights:
		if typeof(value) != TYPE_INT or int(value) <= 0:
			return -1
		if int(value) > UINT32_RANGE - total:
			return -1
		total += int(value)
	var target := next_u32() % total
	var cursor := 0
	for index in weights.size():
		cursor += int(weights[index])
		if target < cursor:
			return index
	return -1
