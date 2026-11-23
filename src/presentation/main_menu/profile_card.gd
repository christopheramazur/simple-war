class_name ProfileCard
extends RefCounted
## The skirmish profile card text (sw-kif, GDD 05 R7Q15/R7Q19): the feel
## sentence, a difficulty label, a handicap line, fuzz and think time. Every
## number is read from a ProfileController built from the same profile values
## the AI plays with, so defaults for omitted keys are the ones used
## (displayed == used). Display only: no gameplay effect.

const DEFAULT_DIFFICULTY := "Unrated"


## The card as {"feel", "difficulty", "handicap", "fuzz", "think", "fuzz_pct",
## "think_ms"}; the last two are the raw numbers the lines state.
static func describe(values: Dictionary) -> Dictionary:
	var pc := ProfileController.new(2, values)
	return {
		"feel": String(values.get("text", "")),
		"difficulty": String(values.get("difficulty", DEFAULT_DIFFICULTY)),
		"handicap": "No handicap: plays by the same rules and sees what you see.",
		"fuzz_pct": pc.fuzz_pct,
		"think_ms": pc.think_ms,
		"fuzz": _fuzz_line(pc.fuzz_pct),
		"think": _think_line(pc.think_ms),
	}


static func _fuzz_line(pct: int) -> String:
	if pct <= 0:
		return "Fuzz 0%: always takes its best-scoring move."
	var how := "sometimes picks a near-best move" if pct < 25 else "often picks a near-best move instead of the best"
	return "Fuzz %d%%: %s, so it is less predictable." % [pct, how]


static func _think_line(ms: int) -> String:
	return "Think limit %s: a runaway-script cap; it does not change how well the AI plays." % _seconds(ms)


static func _seconds(ms: int) -> String:
	if ms % 1000 == 0:
		return "%d s" % (ms / 1000)
	return "%.1f s" % (ms / 1000.0)


## The card as one wrapped label's text.
static func text(values: Dictionary) -> String:
	var d := describe(values)
	var lines := PackedStringArray()
	lines.append("%s · %s" % [d["difficulty"], d["feel"]] if not String(d["feel"]).is_empty() else String(d["difficulty"]))
	lines.append(String(d["handicap"]))
	lines.append(String(d["fuzz"]))
	lines.append(String(d["think"]))
	return "\n".join(lines)
