class_name StatCalc
extends RefCounted
## Computes a stat's effective value from its base and modifiers, in the
## fixed order of GDD 02 §2.13 (E2Q1):
##   base -> flat -> summed increased -> each more -> override -> clamp -> round
## Pure and deterministic: modifiers are put in canonical order first, so the
## result never depends on the order effects were applied in.
##
## Intermediate maths is Q47.16 with FPDR rounding. The stat's own rounding
## (whole numbers for integral stats) happens once, at the end.
##
## Several overrides: the last in canonical order (source, then amount) wins;
## the trace lists all of them.

const HUNDRED: int = 100 * Fixed.ONE


## Effective value only (the per-tick fast path).
static func value(def: StatDef, base: int, mods: Array[StatModifier]) -> int:
	return _run(def, base, mods, null)


## Effective value plus the step trace the inspection window shows. Each step
## is {"step": name, "value": raw fixed after the step, "terms": [[source,
## amount], ...]}; steps that changed nothing are left out, except base and
## the final "result".
static func with_trace(def: StatDef, base: int, mods: Array[StatModifier]) -> Dictionary:
	var trace: Array[Dictionary] = []
	var v := _run(def, base, mods, trace)
	return {"stat": def.id, "value": v, "trace": trace}


static func _run(def: StatDef, base: int, mods: Array[StatModifier], trace: Variant) -> int:
	var flats: Array[StatModifier] = []
	var incs: Array[StatModifier] = []
	var mores: Array[StatModifier] = []
	var overs: Array[StatModifier] = []
	for m in mods:
		match m.kind:
			StatModifier.Kind.FLAT:
				flats.append(m)
			StatModifier.Kind.INCREASED:
				incs.append(m)
			StatModifier.Kind.MORE:
				mores.append(m)
			StatModifier.Kind.OVERRIDE:
				overs.append(m)
	var v := base
	if trace != null:
		trace.append({"step": "base", "value": v, "terms": []})

	if not flats.is_empty():
		flats.sort_custom(StatModifier.before)
		for m in flats:
			v += m.amount
		_note(trace, "flat", v, flats)

	if not incs.is_empty():
		incs.sort_custom(StatModifier.before)
		var total := 0
		for m in incs:
			total += m.amount
		v = Fixed.mul_ratio(v, maxi(HUNDRED + total, 0), HUNDRED)
		_note(trace, "increased", v, incs)

	if not mores.is_empty():
		mores.sort_custom(StatModifier.before)
		for m in mores:
			v = Fixed.mul_ratio(v, maxi(HUNDRED + m.amount, 0), HUNDRED)
		_note(trace, "more", v, mores)

	if not overs.is_empty():
		overs.sort_custom(StatModifier.before)
		v = overs[overs.size() - 1].amount
		_note(trace, "override", v, overs)

	var clamped := v
	if def.has_min:
		clamped = maxi(clamped, def.min_value)
	if def.has_max:
		clamped = mini(clamped, def.max_value)
	if clamped != v:
		v = clamped
		if trace != null:
			trace.append({"step": "clamp", "value": v, "terms": []})

	if def.integral:
		var rounded := Fixed.from_int(Fixed.to_int_round(v))
		if rounded != v:
			v = rounded
			if trace != null:
				trace.append({"step": "round", "value": v, "terms": []})

	if trace != null:
		trace.append({"step": "result", "value": v, "terms": []})
	return v


static func _note(trace: Variant, step: String, v: int, mods: Array[StatModifier]) -> void:
	if trace == null:
		return
	var terms := []
	for m in mods:
		terms.append([m.source, m.amount])
	trace.append({"step": step, "value": v, "terms": terms})
