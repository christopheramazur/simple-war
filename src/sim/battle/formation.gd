class_name Formation
extends RefCounted
## Formation slot offsets. Local frame: +x forward, +y to the right; slot 0
## is the leader's position. Offsets are rotated by the squad facing.

const LINE: int = 0
const COLUMN: int = 1
const WEDGE: int = 2
const BLOB: int = 3


## World-space offset [dx, dy] (fixed) of `slot` in a formation of `count`.
static func offset(shape: int, slot: int, count: int, spacing: int, facing: int) -> PackedInt64Array:
	var lx := 0
	var ly := 0
	match shape:
		COLUMN:
			lx = -slot * spacing
		WEDGE:
			var rank := (slot + 1) / 2
			lx = -rank * spacing
			ly = rank * spacing * (1 if slot % 2 == 1 else -1)
		BLOB:
			var k := Fixed.isqrt(maxi(count - 1, 0)) + 1
			lx = -(slot / k) * spacing
			ly = Fixed.round_div((2 * (slot % k) - (k - 1)) * spacing, 2)
		_:
			ly = Fixed.round_div((2 * slot - (count - 1)) * spacing, 2)
	var c := Fixed.fcos(facing)
	var s := Fixed.fsin(facing)
	return PackedInt64Array([
		Fixed.mul(lx, c) - Fixed.mul(ly, s),
		Fixed.mul(lx, s) + Fixed.mul(ly, c),
	])
