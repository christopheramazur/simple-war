class_name Fixed
extends RefCounted
## Fixed-point arithmetic with Defined Rounding (FPDR). GDD 02 §2.1, R4Q8.
##
## A fixed value is a plain 64-bit `int` holding the real number times ONE
## (Q47.16). The simulation never uses floats.
##
## Rounding rule (the "defined rounding"): every operation that drops precision
## rounds to the nearest representable value, ties away from zero. This is
## sign-symmetric: f(-x) == -f(x).
##
## Ranges: mul() needs |a * b| < 2^63 (both operands under ~2^31 raw, i.e.
## |value| < 32768); div() needs |a| < 2^47 raw. length() needs |x|, |y| < 2^31 raw.
##
## Angles are binary angles: one full turn is ANGLE_FULL (65536), so angle
## arithmetic wraps with `& ANGLE_MASK`.

const FRAC_BITS: int = 16
const ONE: int = 1 << FRAC_BITS
const HALF: int = ONE >> 1

const ANGLE_BITS: int = 16
const ANGLE_FULL: int = 1 << ANGLE_BITS
const ANGLE_MASK: int = ANGLE_FULL - 1
const ANGLE_HALF: int = ANGLE_FULL >> 1
const ANGLE_QUARTER: int = ANGLE_FULL >> 2

## pi * 2^30, used only to build the sine table with integer maths.
const _PI_Q30: int = 3373259426
const _Q30: int = 1 << 30

## atan(2^-i) in units of 2^24 per turn, for CORDIC vectoring (atan2).
const _ATAN_Q24: Array[int] = [
	2097152, 1238021, 654136, 332050, 166669, 83416, 41718, 20860, 10430,
	5215, 2608, 1304, 652, 326, 163, 81, 41, 20, 10, 5, 3, 1,
]

## sin over one quarter turn, one entry per binary-angle unit (0..ANGLE_QUARTER).
static var _sin_quarter: PackedInt64Array = PackedInt64Array()


# --- conversion ------------------------------------------------------------

static func from_int(i: int) -> int:
	return i * ONE


## num / den as a fixed value, rounded by the FPDR rule.
static func from_ratio(num: int, den: int) -> int:
	return round_div(num * ONE, den)


static func to_int_round(a: int) -> int:
	return round_div(a, ONE)


static func to_int_floor(a: int) -> int:
	return a >> FRAC_BITS


## Parses a decimal string such as "-1.25" without touching floats.
## Returns `{ok: bool, value: int, error: String}`.
static func parse_decimal(text: String) -> Dictionary:
	var s := text.strip_edges()
	var neg := false
	if s.begins_with("-"):
		neg = true
		s = s.substr(1)
	elif s.begins_with("+"):
		s = s.substr(1)
	var parts := s.split(".")
	if s.is_empty() or parts.size() > 2:
		return {"ok": false, "value": 0, "error": "not a decimal: '%s'" % text}
	var int_part: String = parts[0]
	var frac_part: String = parts[1] if parts.size() == 2 else ""
	if int_part.is_empty() and frac_part.is_empty():
		return {"ok": false, "value": 0, "error": "not a decimal: '%s'" % text}
	for part: String in [int_part, frac_part]:
		for ch in part:
			if ch < "0" or ch > "9":
				return {"ok": false, "value": 0, "error": "not a decimal: '%s'" % text}
	if frac_part.length() > 9:
		return {"ok": false, "value": 0, "error": "more than 9 decimal places: '%s'" % text}
	var whole := int(int_part) if not int_part.is_empty() else 0
	var raw := whole * ONE
	if not frac_part.is_empty():
		var scale := 1
		for _i in frac_part.length():
			scale *= 10
		raw += round_div(int(frac_part) * ONE, scale)
	return {"ok": true, "value": -raw if neg else raw, "error": ""}


## Deterministic decimal text for tooltips, rounded by the FPDR rule.
static func to_decimal_string(a: int, places: int = 4) -> String:
	var scale := 1
	for _i in places:
		scale *= 10
	var scaled := round_div(a * scale, ONE)
	var neg := scaled < 0
	var mag := absi(scaled)
	var whole := mag / scale
	var frac := mag % scale
	var out := str(whole)
	if places > 0:
		out += "." + str(frac).pad_zeros(places)
	return ("-" + out) if neg else out


# --- arithmetic ------------------------------------------------------------

## Integer division rounded to nearest, ties away from zero.
static func round_div(n: int, d: int) -> int:
	assert(d != 0, "Fixed.round_div: division by zero")
	var neg := (n < 0) != (d < 0)
	var an := absi(n)
	var ad := absi(d)
	var q := an / ad
	var r := an % ad
	if r >= ad - r:
		q += 1
	return -q if neg else q


static func mul(a: int, b: int) -> int:
	return round_div(a * b, ONE)


static func div(a: int, b: int) -> int:
	return round_div(a * ONE, b)


## Multiply by a ratio in one rounding step: a * num / den.
static func mul_ratio(a: int, num: int, den: int) -> int:
	return round_div(a * num, den)


static func clamp_fixed(a: int, lo: int, hi: int) -> int:
	return mini(maxi(a, lo), hi)


## floor(sqrt(n)) for a non-negative integer n.
static func isqrt(n: int) -> int:
	assert(n >= 0, "Fixed.isqrt: negative input")
	if n < 2:
		return n
	var x := n
	var y := (x >> 1) + 1
	while y < x:
		x = y
		y = (x + n / x) >> 1
	return x


## round(sqrt(n)) for a non-negative integer n.
static func isqrt_round(n: int) -> int:
	var r := isqrt(n)
	if n - r * r > r:
		r += 1
	return r


static func fsqrt(a: int) -> int:
	return isqrt_round(a * ONE)


## Length of the vector (x, y), both fixed values; result is fixed.
static func length(x: int, y: int) -> int:
	return isqrt_round(x * x + y * y)


static func distance(ax: int, ay: int, bx: int, by: int) -> int:
	return length(bx - ax, by - ay)


# --- trigonometry (binary angles) ----------------------------------------

static func fsin(angle: int) -> int:
	_ensure_sin_table()
	var a := angle & ANGLE_MASK
	var quadrant := a >> (ANGLE_BITS - 2)
	var offset := a & (ANGLE_QUARTER - 1)
	match quadrant:
		0:
			return _sin_quarter[offset]
		1:
			return _sin_quarter[ANGLE_QUARTER - offset]
		2:
			return -_sin_quarter[offset]
		_:
			return -_sin_quarter[ANGLE_QUARTER - offset]


static func fcos(angle: int) -> int:
	return fsin(angle + ANGLE_QUARTER)


## Binary angle of the vector (x, y), measured from +x toward +y.
## Works for any int inputs (raw fixed or plain ints). atan2(0, 0) == 0.
static func atan2(y: int, x: int) -> int:
	if x == 0 and y == 0:
		return 0
	var angle := 0
	var cx := x
	var cy := y
	if cx < 0:
		cx = -cx
		cy = -cy
		angle = ANGLE_HALF << 8
	# Normalise magnitude to ~2^30 so CORDIC shifts keep precision.
	var big := maxi(absi(cx), absi(cy))
	while big < (1 << 29):
		cx <<= 1
		cy <<= 1
		big <<= 1
	while big >= (1 << 31):
		cx >>= 1
		cy >>= 1
		big >>= 1
	for i in _ATAN_Q24.size():
		var xs := cx >> i
		var ys := cy >> i
		if cy > 0:
			cx += ys
			cy -= xs
			angle += _ATAN_Q24[i]
		else:
			cx -= ys
			cy += xs
			angle -= _ATAN_Q24[i]
	return round_div(angle, 1 << 8) & ANGLE_MASK


## Builds the quarter-wave sine table with integer-only Taylor series (Q30),
## so every machine produces the identical table.
static func _ensure_sin_table() -> void:
	if _sin_quarter.size() == ANGLE_QUARTER + 1:
		return
	var table := PackedInt64Array()
	table.resize(ANGLE_QUARTER + 1)
	for a in ANGLE_QUARTER + 1:
		# x = a * 2pi / ANGLE_FULL, in Q30.
		var x := round_div(a * _PI_Q30, ANGLE_HALF)
		var x2 := round_div(x * x, _Q30)
		var term := x
		var total := x
		for k in range(1, 8):
			term = round_div(term * x2, _Q30)
			term = -round_div(term, (2 * k) * (2 * k + 1))
			total += term
		table[a] = round_div(total, 1 << (30 - FRAC_BITS))
	_sin_quarter = table
