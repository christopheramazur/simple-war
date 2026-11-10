class_name ClockConfig
extends Resource
## Turn timing, as data. Every number is a starting default (GDD 02 §2.2).
## Times are integer milliseconds.

## Planning budget each turn before reserve is drawn (R3Q1: ~60 s).
@export var planning_ms: int = 60000
## Reserve bank: starting amount, per-turn top-up and cap (R3Q1). The shape is
## settled; these numbers are placeholders until playtests.
@export var reserve_start_ms: int = 30000
@export var reserve_topup_ms: int = 10000
@export var reserve_cap_ms: int = 60000

## Parallel-battle planning bonus (R4Q2): +first_bonus for the 2nd battle,
## each next one slightly less, reaching bonus_total at bonus_cap_battles, then
## +bonus_beyond per extra battle.
@export var bonus_first_ms: int = 10000
@export var bonus_total_ms: int = 60000
@export var bonus_cap_battles: int = 10
@export var bonus_beyond_ms: int = 1000

## Reaction window (R2Q4, R3Q1): configurable off; doesn't draw reserve; more
## battles give more time. Duration numbers are placeholders.
@export var reaction_enabled: bool = true
@export var reaction_base_ms: int = 10000
@export var reaction_per_extra_battle_ms: int = 2000

## Intermission (R4Q1): cap 30 s, 10 s ranked; once at least half the players
## are ready, the remaining time drops to early_ms (if not already lower).
@export var intermission_ms: int = 30000
@export var intermission_ranked_ms: int = 10000
@export var intermission_early_ms: int = 3000
@export var ranked: bool = false

## Untimed accessibility option (R2Q2): phases wait for everyone to be ready.
@export var untimed: bool = false


## Total planning bonus for a player in `battles` battles (0 for 0 or 1).
func parallel_bonus_ms(battles: int) -> int:
	if battles <= 1:
		return 0
	var n := mini(battles, bonus_cap_battles)
	# Increments fall linearly: d_k = first - (k-2)*step for k = 2..cap, chosen so
	# they sum to bonus_total. B(n) = (n-1)*first - step*(n-1)(n-2)/2, with
	# step = 2*((cap-1)*first - total) / ((cap-1)(cap-2)). One rounding at the end.
	var c1 := bonus_cap_battles - 1
	var bonus: int
	if bonus_cap_battles <= 2:
		bonus = bonus_first_ms
	else:
		var num := ((n - 1) * bonus_first_ms) * (c1 * (c1 - 1)) - (c1 * bonus_first_ms - bonus_total_ms) * ((n - 1) * (n - 2))
		bonus = Fixed.round_div(num, c1 * (c1 - 1))
	if battles > bonus_cap_battles:
		bonus += (battles - bonus_cap_battles) * bonus_beyond_ms
	return bonus


func reaction_ms_for(battles: int) -> int:
	return reaction_base_ms + maxi(battles - 1, 0) * reaction_per_extra_battle_ms


func intermission_cap_ms() -> int:
	return intermission_ranked_ms if ranked else intermission_ms
