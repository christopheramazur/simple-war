class_name RulesText
extends RefCounted
## Rules text generated from compiled bundles (E1Q5). Every phrase goes
## through a translation key ("fx.<name>", "stat.<id>", "pool.<name>",
## "damage.<type>"); the English below is only the fallback until the
## translation tables exist. Authors never write rules text, only flavour.

const EN: Dictionary = {
	"fx.flat": "{sign}{amount}{unit} {stat}",
	"fx.increased": "{amount}% increased {stat}",
	"fx.reduced": "{amount}% reduced {stat}",
	"fx.more": "{amount}% more {stat}",
	"fx.less": "{amount}% less {stat}",
	"fx.override": "{stat} is {amount}{unit}",
	"fx.damage": "Deals {amount} {damage_type} damage",
	"fx.heal": "Restores {amount} HP",
	"fx.pool_flow": "{sign}{amount} {pool}",
	"fx.apply_bundle": "Applies {bundle}",
	"fx.order.hold": "Halts",
	"fx.order.fall_back": "Falls back",
	"fx.order.attack": "Attacks {who}",
	"fx.order.who.other": "them",
	"fx.order.who.source": "the source",
	"fx.order.who.allies": "the nearest ally",
	"fx.order.who.enemies": "the nearest enemy",
	"fx.order.who.squads": "the nearest squad",
	"ab.toggle": "Toggle.",
	"ab.reaction": "Reaction.",
	"ab.cost": "Costs {amount} {pool}.",
	"ab.upkeep": "Sinks {amount} {pool} per second while on; switches off at {band} {pool}.",
	"ab.cooldown": "Cooldown {seconds} s.",
	"ab.charges": "{n} uses per battle.",
	"ab.ready": "Readies for {seconds} s (sinks {prowess} Prowess per second), then:",
	"ab.lose_on": "Lost on {events}.",
	"ab.lose.move": "moving",
	"ab.lose.attack": "attacking",
	"ab.lose.damaged": "taking damage",
	"ab.lose.casualty": "a casualty",
	"ab.range": "Range {range} m.",
	"ab.or": " or ",
	"fx.when.apply": "On application: {text}",
	"fx.when.expire": "When it ends: {text}",
	"fx.when.every": "Every {seconds} s: {text}",
	"fx.when.attack": "On attack: {text}",
	"fx.when.hit": "On hit: {text}",
	"fx.when.damaged": "When damaged: {text}",
	"fx.when.kill": "On kill: {text}",
	"fx.when.casualty": "When the squad takes a casualty: {text}",
	"fx.when.accumulator": "Every {threshold} {event}: {text}",
	"fx.target.source": "{text} to the source",
	"fx.target.other": "{text} to them",
	"fx.target.allies": "{text} to allies{within}",
	"fx.target.enemies": "{text} to enemies{within}",
	"fx.target.squads": "{text} to squads{within}",
	"fx.within": " within {range} m",
	"fx.per.selector": "{text} per {who}{within}",
	"fx.per.pool": "{text} per {each} {pool}",
	"fx.per.accumulator": "{text} per {each} counted",
	"fx.who.allies": "ally",
	"fx.who.enemies": "enemy",
	"fx.who.squads": "squad",
	"fx.cond.band_at_least": "{text} while {pool} is at least {band}",
	"fx.cond.band_at_most": "{text} while {pool} is at most {band}",
	"fx.cond.moving": "{text} while moving",
	"fx.cond.not_moving": "{text} while stationary",
	"fx.cond.firing": "{text} while firing",
	"fx.cond.not_firing": "{text} while not firing",
	"fx.cond.hp_below": "{text} below {pct}% HP",
	"fx.cond.on_feature": "{text} in {features}",
	"fx.cooldown": "{text} (at most once every {seconds} s)",
	"fx.duration.seconds": "Lasts {seconds} s.",
	"fx.duration.turns": "Lasts {turns} turns.",
	"fx.stacks": "Stacks up to {n} times.",
	"fx.event.second": "seconds",
	"fx.event.attack": "shots",
	"fx.event.hit": "hits",
	"fx.event.damaged": "HP lost",
	"fx.event.casualty": "casualties",
	"fx.event.distance": "metres",
	"fx.event_one.second": "second",
	"fx.event_one.attack": "shot",
	"fx.event_one.hit": "hit",
	"fx.event_one.damaged": "HP lost",
	"fx.event_one.casualty": "casualty",
	"fx.event_one.distance": "metre",
	"fx.next_in": "Next in {n} {event}",
	"stat.unit.hp": "Max HP",
	"stat.unit.proficiency_pct": "Proficiency",
	"stat.weapon.modes.*.accuracy": "Accuracy",
	"stat.weapon.modes.*.damage": "Damage",
	"stat.weapon.range": "Range",
	"stat.defense.evasion_pct": "Evasion",
	"stat.defense.flat": "Flat Reduction",
	"stat.defense.resist_pct.kinetic": "Kinetic Resistance",
	"stat.defense.resist_pct.energy": "Energy Resistance",
	"stat.defense.resist_pct.explosive": "Explosive Resistance",
	"stat.defense.resist_pct.magic": "Magic Resistance",
	"stat.movement.walk": "Walk Speed",
	"stat.movement.run": "Run Speed",
	"stat.squad.sight": "Sight",
	"stat.squad.capture_rate": "Capture Rate",
	"stat.squad.concealment_pct": "Concealment",
	"stat.squad.detection_radius": "Detection Radius",
}


## One line per effect, then duration and stacking lines.
static func bundle_lines(fx: EffectRules, b: int, registry: StatRegistry, tps: int) -> PackedStringArray:
	var bd: Dictionary = fx.bundles[b]
	var out := PackedStringArray()
	for e: Dictionary in bd["effects"]:
		out.append(effect(fx, bd, e, registry, tps))
	if bd["seconds_ticks"] > 0:
		out.append(_f("fx.duration.seconds", {"seconds": _num(Fixed.from_ratio(bd["seconds_ticks"], tps))}))
	elif bd["turns"] > 0:
		out.append(_f("fx.duration.turns", {"turns": bd["turns"]}))
	if bd["policy"] == "stack":
		out.append(_f("fx.stacks", {"n": bd["max_stacks"]}))
	return out


static func effect(fx: EffectRules, bd: Dictionary, e: Dictionary, registry: StatRegistry, tps: int) -> String:
	var amount: int = e["amount"]
	var text := ""
	match e["op"]:
		"modify":
			var def: StatDef = registry.find(String(e["stat"]))
			var stat := stat_name(def.id) if def != null else String(e["stat"])
			var unit := ("%" if def != null and def.unit == "%" else "")
			match int(e["mod"]):
				StatModifier.Kind.FLAT:
					text = _f("fx.flat", {"sign": "+" if amount >= 0 else "-", "amount": _num(absi(amount)), "unit": unit, "stat": stat})
				StatModifier.Kind.INCREASED:
					text = _f("fx.increased" if amount >= 0 else "fx.reduced", {"amount": _num(absi(amount)), "stat": stat})
				StatModifier.Kind.MORE:
					text = _f("fx.more" if amount >= 0 else "fx.less", {"amount": _num(absi(amount)), "stat": stat})
				_:
					text = _f("fx.override", {"stat": stat, "amount": _num(amount), "unit": unit})
		"damage":
			text = _f("fx.damage", {"amount": _num(amount), "damage_type": _t("damage." + DataSchema.DAMAGE_TYPES[e["dtype"]], DataSchema.DAMAGE_TYPES[e["dtype"]])})
		"heal":
			text = _f("fx.heal", {"amount": _num(amount)})
		"pool_flow":
			text = _f("fx.pool_flow", {"sign": "+" if amount >= 0 else "-", "amount": _num(absi(amount)), "pool": _pool(e["pool"])})
		"apply_bundle":
			text = _f("fx.apply_bundle", {"bundle": fx.bundles[e["bundle"]]["name"]})
		"order":
			var order: String = DataSchema.ORDERS[e["order"]]
			text = _f("fx.order." + order, {"who": _w("fx.order.who." + str((e["target"] as Dictionary).get("select", "other")))})
	var per: Dictionary = e["per"]
	if not per.is_empty():
		match per["source"]:
			"selector":
				var sel: Dictionary = per["selector"]
				text = _f("fx.per.selector", {"text": text, "who": _w("fx.who." + str(sel["select"])), "within": _within(sel)})
			"pool":
				text = _f("fx.per.pool", {"text": text, "each": _num(per["each"]), "pool": _pool(per["pool"])})
			"accumulator":
				text = _f("fx.per.accumulator", {"text": text, "each": _num(per["each"])})
	var sel: Dictionary = e["target"]
	if not sel.is_empty() and sel["select"] != "self" and e["op"] != "order":
		text = _f("fx.target." + str(sel["select"]), {"text": text, "within": _within(sel)})
	text = _condition(text, e["cond"])
	var when: String = e["when"]
	match when:
		"while":
			pass
		"apply" when bd.get("instant", false):
			pass  # Applying is all an instant bundle does.
		"every":
			text = _f("fx.when.every", {"seconds": _num(Fixed.from_ratio(e["every"], tps)), "text": text})
		"accumulator":
			var acc: Dictionary = bd["acc"]
			text = _f("fx.when.accumulator", {"threshold": _num(acc["threshold"]), "event": _w("fx.event." + str(acc["event"])), "text": text})
		_:
			text = _f("fx.when." + when, {"text": text})
	if e["cooldown"] > 0:
		text = _f("fx.cooldown", {"text": text, "seconds": _num(Fixed.from_ratio(e["cooldown"], tps))})
	return text


## Accumulator progress, e.g. "Next in 2 hits" (E2Q9). `n` is fixed.
static func next_in(event: String, n: int) -> String:
	var word := _w(("fx.event_one." if n == Fixed.ONE else "fx.event.") + event)
	return _f("fx.next_in", {"n": _num(n), "event": word})


## Activation lines for ability `ab`, then its bundle's lines (E2Q10).
static func ability_lines(r: BattleRules, ab: int) -> PackedStringArray:
	var out := PackedStringArray()
	if r.ab_reaction[ab] == 1:
		out.append(_w("ab.reaction"))
	if r.ab_toggle[ab] == 1:
		out.append(_w("ab.toggle"))
	for p in 5:
		if r.ab_costs[ab][p] > 0:
			out.append(_f("ab.cost", {"amount": _num(r.ab_costs[ab][p]), "pool": _pool(p)}))
	for p in 5:
		if r.ab_upkeep[ab][p] > 0:
			out.append(_f("ab.upkeep", {"amount": _num(r.ab_upkeep[ab][p]), "pool": _pool(p),
				"band": DataSchema.BANDS[r.ab_auto_off_band[ab]].capitalize()}))
	if r.ab_cooldown_s[ab] > 0:
		out.append(_f("ab.cooldown", {"seconds": _num(r.ab_cooldown_s[ab])}))
	if r.ab_charges[ab] > 0:
		out.append(_f("ab.charges", {"n": r.ab_charges[ab]}))
	if r.ab_range[ab] >= 0:
		out.append(_f("ab.range", {"range": _num(r.ab_range[ab])}))
	if r.ab_ready_s[ab] > 0:
		out.append(_f("ab.ready", {"seconds": _num(r.ab_ready_s[ab]), "prowess": _num(r.ab_ready_prowess[ab])}))
	var lose := r.ab_lose_on[ab]
	if not lose.is_empty():
		var evs := PackedStringArray()
		for ev in lose:
			evs.append(_w("ab.lose." + ev))
		out.append(_f("ab.lose_on", {"events": _w("ab.or").join(evs)}))
	if r.ab_bundle[ab] >= 0:
		out.append_array(bundle_lines(r.fx, r.ab_bundle[ab], r.stats, r.tps))
	return out


## Display name of a stat: its translation, else a readable form of its ID.
static func stat_name(id: String) -> String:
	var fallback: String = EN.get("stat." + id, "")
	if fallback.is_empty():
		var parts := id.split(".")
		var leaf := parts[parts.size() - 1]
		if leaf in ["capacity", "start_pct", "neutral_pct", "drift_pct_per_s", "instinct_cost"] and parts.size() >= 2:
			leaf = parts[parts.size() - 2] + " " + leaf
		fallback = leaf.replace("_pct", "").replace("_", " ").capitalize()
	return _t("stat." + id, fallback)


static func _condition(text: String, c: Dictionary) -> String:
	if c.is_empty():
		return text
	if c.has("pool") and c.has("band_at_least"):
		text = _f("fx.cond.band_at_least", {"text": text, "pool": _pool(DataSchema.SIMPL.find(c["pool"])), "band": str(c["band_at_least"]).capitalize()})
	if c.has("pool") and c.has("band_at_most"):
		text = _f("fx.cond.band_at_most", {"text": text, "pool": _pool(DataSchema.SIMPL.find(c["pool"])), "band": str(c["band_at_most"]).capitalize()})
	if c.has("moving"):
		text = _f("fx.cond.moving" if c["moving"] else "fx.cond.not_moving", {"text": text})
	if c.has("firing"):
		text = _f("fx.cond.firing" if c["firing"] else "fx.cond.not_firing", {"text": text})
	if c.has("hp_below_pct"):
		text = _f("fx.cond.hp_below", {"text": text, "pct": c["hp_below_pct"]})
	if c.has("on_feature"):
		var names := PackedStringArray()
		for f: String in c["on_feature"]:
			names.append(_t("feature." + f, f.capitalize()))
		text = _f("fx.cond.on_feature", {"text": text, "features": _w("ab.or").join(names)})
	return text


static func _within(sel: Dictionary) -> String:
	return _f("fx.within", {"range": _num(sel["within"])}) if sel.get("within", -1) >= 0 else ""


static func _pool(p: int) -> String:
	var name: String = DataSchema.SIMPL[p]
	return _t("pool." + name, name.capitalize())


static func _num(v: int) -> String:
	return Fixed.to_display(v)


static func _f(key: String, args: Dictionary) -> String:
	return _t(key, EN.get(key, key)).format(args)


## A single word or phrase by key, English table as fallback.
static func _w(key: String) -> String:
	return _t(key, EN.get(key, key.get_slice(".", key.get_slice_count(".") - 1)))


static func _t(key: String, fallback: String) -> String:
	var s := String(TranslationServer.translate(key))
	return fallback if s == key else s
