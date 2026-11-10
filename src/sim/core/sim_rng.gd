class_name SimRng
extends RefCounted
## Sim-owned deterministic PRNG (xoshiro128**), 32-bit lanes kept in 64-bit
## ints and masked, so no operation can overflow. GDD 02 §2.1, R2Q6.
##
## Gameplay resolution never draws from this: there is no hidden randomness.
## It exists for content generation (map templates) and for test harnesses.

const M32: int = 0xFFFFFFFF

var _s0: int
var _s1: int
var _s2: int
var _s3: int


func _init(seed_value: int = 0) -> void:
	reseed(seed_value)


func reseed(seed_value: int) -> void:
	var base := seed_value & M32
	var hi := (seed_value >> 32) & M32
	_s0 = _fmix32((base + 0x9E3779B9) & M32)
	_s1 = _fmix32((base + _mul32(2, 0x9E3779B9) + hi) & M32)
	_s2 = _fmix32((base + _mul32(3, 0x9E3779B9)) & M32)
	_s3 = _fmix32((base + _mul32(4, 0x9E3779B9) + hi) & M32)
	if (_s0 | _s1 | _s2 | _s3) == 0:
		_s0 = 1


## Next uniformly distributed integer in [0, 2^32).
func next_u32() -> int:
	var result := _mul32(_rotl(_mul32(_s1, 5), 7), 9)
	var t := (_s1 << 9) & M32
	_s2 ^= _s0
	_s3 ^= _s1
	_s1 ^= _s2
	_s0 ^= _s3
	_s2 ^= t
	_s3 = _rotl(_s3, 11)
	return result


## Unbiased integer in [0, n). n must be in (0, 2^32].
func next_below(n: int) -> int:
	assert(n > 0 and n <= (1 << 32), "SimRng.next_below: n out of range")
	var limit := ((1 << 32) / n) * n
	var x := next_u32()
	while x >= limit:
		x = next_u32()
	return x % n


## Integer in [lo, hi], inclusive.
func next_range(lo: int, hi: int) -> int:
	assert(hi >= lo, "SimRng.next_range: hi < lo")
	return lo + next_below(hi - lo + 1)


func get_state() -> PackedInt64Array:
	return PackedInt64Array([_s0, _s1, _s2, _s3])


func set_state(state: PackedInt64Array) -> void:
	assert(state.size() == 4, "SimRng.set_state: need 4 lanes")
	_s0 = state[0] & M32
	_s1 = state[1] & M32
	_s2 = state[2] & M32
	_s3 = state[3] & M32


## (a * b) mod 2^32 without 64-bit overflow.
static func _mul32(a: int, b: int) -> int:
	var lo := (a & M32) * (b & 0xFFFF)
	var hi := (((a & M32) * ((b >> 16) & 0xFFFF)) & 0xFFFF) << 16
	return (lo + hi) & M32


static func _rotl(x: int, k: int) -> int:
	return ((x << k) | (x >> (32 - k))) & M32


static func _fmix32(h0: int) -> int:
	var h := h0 & M32
	h ^= h >> 16
	h = _mul32(h, 0x85EBCA6B)
	h ^= h >> 13
	h = _mul32(h, 0xC2B2AE35)
	h ^= h >> 16
	return h
