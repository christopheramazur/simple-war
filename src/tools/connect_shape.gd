class_name ConnectShape
extends RefCounted
## Which piece of a wall or road to draw, from its neighbours (GDD 03 §3.5:
## a feature's `connects` list; drawing only, the rules never read it). The
## four sides are north, east, south, west, as a bit mask: N=1, E=2, S=4, W=8.

const N := 1
const E := 2
const S := 4
const W := 8

const ISOLATED := "isolated"
const END := "end"
const STRAIGHT := "straight"
const CORNER := "corner"
const TEE := "tee"
const CROSS := "cross"


## The mask of sides that join: `joins` is a Callable(dx, dy) -> bool.
static func mask_of(joins: Callable) -> int:
	var m := 0
	if joins.call(0, -1):
		m |= N
	if joins.call(1, 0):
		m |= E
	if joins.call(0, 1):
		m |= S
	if joins.call(-1, 0):
		m |= W
	return m


## {"shape", "turn"}: the piece's name, and how many clockwise quarter turns
## from its base drawing. Base drawings: an end points north, a straight run
## is north-south, a corner joins north and east, a tee is missing its west
## side.
static func of(mask: int) -> Dictionary:
	var m := mask & 15
	match m:
		0:
			return {"shape": ISOLATED, "turn": 0}
		N, E, S, W:
			return {"shape": END, "turn": _turn(m, N)}
		5, 10:
			return {"shape": STRAIGHT, "turn": 0 if m == 5 else 1}
		3, 6, 12, 9:
			return {"shape": CORNER, "turn": _turn(m, 3)}
		15:
			return {"shape": CROSS, "turn": 0}
	return {"shape": TEE, "turn": _turn(15 & ~m, W)}


## Quarter turns clockwise that carry `base` onto `m`: a side or a pair of
## adjacent sides.
static func _turn(m: int, base: int) -> int:
	var cur := base
	for t in 4:
		if cur == m:
			return t
		cur = ((cur << 1) | (cur >> 3)) & 15
	return 0


## The inverse of `of`: the sides (a mask) of the piece `shape` turned `turn`
## quarter turns clockwise from its base drawing. Isolated joins no side.
static func sides_of(shape: String, turn: int) -> int:
	var base := 0
	match shape:
		END:
			base = N
		STRAIGHT:
			base = N | S
		CORNER:
			base = N | E
		TEE:
			base = N | E | S
		CROSS:
			base = 15
	for _q in posmod(turn, 4):
		base = ((base << 1) | (base >> 3)) & 15
	return base
