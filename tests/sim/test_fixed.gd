extends GutTest
## Fixed-point maths (FPDR): GDD 02 §2.1, R4Q8. Task sw-qio.1.

const ONE := Fixed.ONE


func test_round_div_ties_away_from_zero() -> void:
	assert_eq(Fixed.round_div(5, 2), 3)
	assert_eq(Fixed.round_div(-5, 2), -3)
	assert_eq(Fixed.round_div(5, -2), -3)
	assert_eq(Fixed.round_div(7, 2), 4)
	assert_eq(Fixed.round_div(1, 3), 0)
	assert_eq(Fixed.round_div(2, 3), 1)
	assert_eq(Fixed.round_div(-2, 3), -1)


func test_sign_symmetry() -> void:
	for a in [1, 3, 32767, 32768, 98305, 123456789]:
		assert_eq(Fixed.mul(-a, 3 * ONE / 7), -Fixed.mul(a, 3 * ONE / 7), "mul %d" % a)
		assert_eq(Fixed.div(-a, 7 * ONE), -Fixed.div(a, 7 * ONE), "div %d" % a)


func test_mul_div() -> void:
	assert_eq(Fixed.mul(3 * ONE, Fixed.HALF), 3 * ONE / 2)
	assert_eq(Fixed.div(ONE, 3 * ONE), 21845)
	assert_eq(Fixed.div(2 * ONE, 3 * ONE), 43691)
	assert_eq(Fixed.from_ratio(1, 4), ONE / 4)
	assert_eq(Fixed.mul_ratio(10 * ONE, 1, 3), 218453)


func test_conversions() -> void:
	assert_eq(Fixed.from_int(-3), -3 * ONE)
	assert_eq(Fixed.to_int_round(ONE + Fixed.HALF), 2)
	assert_eq(Fixed.to_int_round(-ONE - Fixed.HALF), -2)
	assert_eq(Fixed.to_int_floor(-1), -1)


func test_parse_decimal() -> void:
	assert_eq(Fixed.parse_decimal("1.25").value, 81920)
	assert_eq(Fixed.parse_decimal("-0.5").value, -32768)
	assert_eq(Fixed.parse_decimal("+7").value, 7 * ONE)
	assert_eq(Fixed.parse_decimal(".5").value, Fixed.HALF)
	assert_eq(Fixed.parse_decimal("0.1").value, 6554)
	assert_false(Fixed.parse_decimal("abc").ok)
	assert_false(Fixed.parse_decimal("1.2.3").ok)
	assert_false(Fixed.parse_decimal("").ok)
	assert_false(Fixed.parse_decimal("1.0000000001").ok)


func test_to_decimal_string() -> void:
	assert_eq(Fixed.to_decimal_string(81920, 2), "1.25")
	assert_eq(Fixed.to_decimal_string(-32768, 1), "-0.5")
	assert_eq(Fixed.to_decimal_string(ONE / 3, 4), "0.3333")
	assert_eq(Fixed.to_decimal_string(5 * ONE, 0), "5")


func test_sqrt_and_length() -> void:
	assert_eq(Fixed.isqrt(0), 0)
	assert_eq(Fixed.isqrt(15), 3)
	assert_eq(Fixed.isqrt(16), 4)
	assert_eq(Fixed.isqrt_round(20), 4)
	assert_eq(Fixed.isqrt_round(21), 5)
	assert_eq(Fixed.fsqrt(4 * ONE), 2 * ONE)
	assert_eq(Fixed.fsqrt(2 * ONE), 92682)
	assert_eq(Fixed.length(3 * ONE, 4 * ONE), 5 * ONE)
	assert_eq(Fixed.distance(ONE, ONE, 4 * ONE, 5 * ONE), 5 * ONE)


func test_sin_cos_exact_points() -> void:
	assert_eq(Fixed.fsin(0), 0)
	assert_eq(Fixed.fsin(Fixed.ANGLE_QUARTER), ONE)
	assert_eq(Fixed.fsin(Fixed.ANGLE_HALF), 0)
	assert_eq(Fixed.fsin(3 * Fixed.ANGLE_QUARTER), -ONE)
	assert_eq(Fixed.fcos(0), ONE)
	assert_eq(Fixed.fcos(Fixed.ANGLE_HALF), -ONE)
	assert_eq(Fixed.fsin(8192), 46341, "sin 45 degrees")
	assert_eq(Fixed.fsin(Fixed.ANGLE_FULL + 100), Fixed.fsin(100), "wraps")


func test_sin_symmetry_and_identity() -> void:
	for a in range(0, Fixed.ANGLE_FULL, 997):
		assert_eq(Fixed.fsin(-a), -Fixed.fsin(a), "odd at %d" % a)
		var s := Fixed.fsin(a)
		var c := Fixed.fcos(a)
		var unit := Fixed.mul(s, s) + Fixed.mul(c, c)
		assert_almost_eq(unit, ONE, 2, "sin^2+cos^2 at %d" % a)


func test_atan2_axes() -> void:
	assert_eq(Fixed.atan2(0, ONE), 0)
	assert_eq(Fixed.atan2(ONE, 0), Fixed.ANGLE_QUARTER)
	assert_eq(Fixed.atan2(0, -ONE), Fixed.ANGLE_HALF)
	assert_eq(Fixed.atan2(-ONE, 0), 3 * Fixed.ANGLE_QUARTER)
	assert_almost_eq(Fixed.atan2(ONE, ONE), 8192, 1)
	assert_eq(Fixed.atan2(0, 0), 0)


func test_atan2_round_trip() -> void:
	for a in range(0, Fixed.ANGLE_FULL, 641):
		var back := Fixed.atan2(Fixed.fsin(a), Fixed.fcos(a))
		var diff := ((back - a + Fixed.ANGLE_HALF) & Fixed.ANGLE_MASK) - Fixed.ANGLE_HALF
		assert_true(absi(diff) <= 2, "angle %d came back as %d" % [a, back])
