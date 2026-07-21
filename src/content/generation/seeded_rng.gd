class_name SeededRng
extends RefCounted

const UINT32_MASK := 0xFFFFFFFF
const UINT32_RANGE := 0x100000000
const ZERO_SEED_STATE := 0x6D2B79F5

var state: int

func _init(seed: int = 0) -> void:
	var normalized := seed & UINT32_MASK
	state = ZERO_SEED_STATE if normalized == 0 else normalized

func next_u32() -> int:
	var value := state
	value = (value ^ ((value << 13) & UINT32_MASK)) & UINT32_MASK
	value = (value ^ (value >> 17)) & UINT32_MASK
	value = (value ^ ((value << 5) & UINT32_MASK)) & UINT32_MASK
	state = value
	return state

func range_int(minimum: int, maximum: int) -> int:
	if maximum < minimum:
		return 0
	var span := maximum - minimum + 1
	if span < 1 or span > UINT32_RANGE:
		return 0
	return minimum + (next_u32() % span)

func weighted_index(weights: Array) -> int:
	if weights.is_empty():
		return -1
	var total := 0
	for value in weights:
		if typeof(value) != TYPE_INT or int(value) <= 0:
			return -1
		total += int(value)
		if total > UINT32_RANGE:
			return -1
	var target := next_u32() % total
	var cursor := 0
	for index in weights.size():
		cursor += int(weights[index])
		if target < cursor:
			return index
	return -1
