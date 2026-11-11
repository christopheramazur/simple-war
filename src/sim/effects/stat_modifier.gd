class_name StatModifier
extends RefCounted
## One modifier on one stat (GDD 02 §2.13 Modifier order, E2Q1).
##
## FLAT adds `amount` (raw fixed, in the stat's unit).
## INCREASED adds `amount` percent to a pool shared by every INCREASED on
## the stat ("+50% increased" is amount = Fixed.from_int(50)); negative is
## "reduced".
## MORE multiplies by (100 + amount)% on its own; negative is "less".
## OVERRIDE sets the value outright.

enum Kind { FLAT, INCREASED, MORE, OVERRIDE }

const KIND_NAMES: Array[StringName] = [&"flat", &"increased", &"more", &"override"]

var stat: String = ""
var kind: Kind = Kind.FLAT
## Raw fixed value; see the class comment for what it means per kind.
var amount: int = 0
## What applied it, e.g. "status:inspired" or "item:flak". Orders the trace.
var source: String = ""


static func make(stat_id: String, mod_kind: Kind, mod_amount: int, mod_source: String) -> StatModifier:
	var m := StatModifier.new()
	m.stat = stat_id
	m.kind = mod_kind
	m.amount = mod_amount
	m.source = mod_source
	return m


## Canonical order: source, then amount. Makes traces and MORE application
## independent of the order effects were applied in.
static func before(a: StatModifier, b: StatModifier) -> bool:
	if a.source != b.source:
		return a.source < b.source
	return a.amount < b.amount
