class_name TargetPolicy
extends RefCounted
## Which unit a shot goes to, and whether queued damage already covers a unit
## (GDD 02 §2.6, sw-txnj.1). Static only: the fire pass, the read model and the
## workshop probes ask the same question the same way. Range and sight come
## from CombatSystem.shot_gate, so this file never re-derives them.
##
## Spread: a target whose queued damage already covers its HP is skipped while
## another is in reach; a covered target is only the fallback.


## Nearest living target in range and sight, preferring ones whose queued
## damage doesn't already cover their HP. -1 if none in reach. The shot gate
## (and its line of sight) runs only for a target nearer than the best so far
## (sw-arse): both tests must pass for a target to be taken, so testing the
## cheap one first picks the same unit with fewer traces.
static func pick(state: BattleState, urow: int, targets: PackedInt64Array, w: int, m: int, pending: Dictionary) -> int:
	var u := state.units
	var best := -1
	var best_d := 1 << 62
	var fallback := -1
	var fallback_d := 1 << 62
	for t in targets:
		if u.hp[t] <= 0:
			continue
		var d := Fixed.distance(u.x[urow], u.y[urow], u.x[t], u.y[t])
		var is_covered := covered(u, t, pending)
		if (is_covered and d >= fallback_d) or (not is_covered and d >= best_d):
			continue
		if CombatSystem.shot_gate(state, urow, t, w, m, d) != CombatSystem.GATE_OK:
			continue
		if is_covered:
			fallback_d = d
			fallback = t
		else:
			best_d = d
			best = t
	return best if best >= 0 else fallback


## True when the expected damage already queued on the unit covers its HP.
## `pending` holds each queued hit through the victim's defences without
## evasion and block (DamagePipeline.preview), so armour counts (sw-pd2l.3).
static func covered(u: BattleUnits, t: int, pending: Dictionary) -> bool:
	return int(pending.get(t, 0)) >= u.hp[t]
