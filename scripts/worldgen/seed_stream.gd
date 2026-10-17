extends RefCounted
## One independent, named random stream plus the engine-independent hash behind it.
## Godot's RandomNumberGenerator is deliberately not used so blueprints stay stable
## across engine upgrades. All arithmetic is masked to 32 bits; products are split
## into 16-bit halves so no intermediate exceeds GDScript's signed 64-bit int.
## Create one stream per consumer and never share an instance, so one consumer's
## draws cannot shift another's results.

const MASK := 0xFFFFFFFF
const FNV_OFFSET := 0x811C9DC5
const FNV_PRIME := 0x01000193

var state := 0

func _init(seed_text: String) -> void:
	state = hash32(seed_text)

## FNV-1a over UTF-8 bytes.
static func hash32(text: String) -> int:
	var h := FNV_OFFSET
	for byte in text.to_utf8_buffer():
		h = ((h ^ byte) * FNV_PRIME) & MASK
	return h

static func hex32(value: int) -> String:
	return "%08x" % (value & MASK)

## Unsigned 32-bit multiply modulo 2^32.
static func mul32(a: int, b: int) -> int:
	var low := a * (b & 0xFFFF)
	var high := (a * (b >> 16)) & 0xFFFF
	return (low + (high << 16)) & MASK

## Mulberry32.
func next_u32() -> int:
	state = (state + 0x6D2B79F5) & MASK
	var z := state
	z = mul32(z ^ (z >> 15), z | 1)
	z = z ^ ((z + mul32(z ^ (z >> 7), z | 61)) & MASK)
	return (z ^ (z >> 14)) & MASK

## Uniform in [0, 1).
func next_float() -> float:
	return float(next_u32()) / 4294967296.0

func range_float(low: float, high: float) -> float:
	return low + (high - low) * next_float()

## Picks an index from entries of {"weight": float}. Entries must already be in a
## deterministic order. Returns -1 when every weight is zero.
func pick_weighted(entries: Array) -> int:
	var total := 0.0
	for entry in entries:
		total += float(entry.weight)
	if total <= 0.0:
		return -1
	var roll := next_float() * total
	for i in entries.size():
		roll -= float(entries[i].weight)
		if roll < 0.0:
			return i
	return entries.size() - 1
