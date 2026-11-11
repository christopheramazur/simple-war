class_name MaxChange
extends RefCounted
## What happens to a current value when its maximum changes (E3Q2, GDD 02
## §2.13 Stats). Every current/max pair (HP, pools) goes through this.


## Keeps current/max unless `restores`. With `restores`, a rising maximum adds
## its increase to the current value instead (a falling one still keeps the
## ratio). Result is clamped to [0, new_max]. All values raw fixed.
## Example: 17.5/22.5 -> max 15 gives 11.666.../15.
static func rescale(current: int, old_max: int, new_max: int, restores: bool = false) -> int:
	if new_max <= 0:
		return 0
	if old_max <= 0:
		return new_max if restores else 0
	var v: int
	if restores and new_max > old_max:
		v = current + (new_max - old_max)
	else:
		v = Fixed.mul_ratio(current, new_max, old_max)
	return Fixed.clamp_fixed(v, 0, new_max)
