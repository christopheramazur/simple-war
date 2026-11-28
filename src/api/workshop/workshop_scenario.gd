class_name WorkshopScenario
extends RefCounted
## One behaviour-workshop scenario (sw-tho3.3, U1 B3, GDD 05 §5.7): a
## hand-placed micro-battle, its scripted orders, variants and probes, read
## from data/sim/workshop/<id>.json. The schema is data/sim/workshop/README.md.
##
## Loading validates everything and quantizes every decimal once, here, so
## nothing downstream touches a float (README "Fixed point"):
##   decimal -> thousandths: round(v * 1000), ties away from zero
##   thousandths -> fixed:   Fixed.round_div(milli * Fixed.ONE, 1000)
## Positions, facings and patches become fixed; probe bounds and compare
## factors stay in thousandths ("milli"), the unit probe values are in.
## Errors read "<file>: <field path>: <problem>".

const DIR := "res://data/sim/workshop"
const STATUSES: Array[String] = ["gate", "pending", "explore"]
const PACKAGES: Dictionary = {
	"rules-fixture": "res://tests/fixtures/rules",
	"core": "res://data/packages/core",
}
## The variant every scenario has: the file's own script and patches.
const BASE := "base"
## Probe kinds read from one snapshot (`at`) and over a window (`over`);
## spacing works both ways.
const AT_KINDS: Array[String] = ["activity", "hold", "fire", "distance", "within", "spacing"]
const OVER_KINDS: Array[String] = ["damage", "dps", "dps_engaged", "first_shot", "shooters", "first_shot_ticks",
		"shots", "duty", "victims", "kills", "spacing", "moved", "first_kill", "mean_kill", "wipe", "waste"]
const NEEDS_TARGET: Array[String] = ["fire", "distance", "within", "first_kill", "mean_kill", "wipe", "waste"]
const VICTIM_KEYS: Array[String] = ["distinct", "max_per_victim", "overkill"]
## LineOfFire.check codes by name.
const FIRE_CODES: Array[String] = ["out_of_range", "shot", "blocked", "min_range", "no_target"]
const RELS: Array[String] = [">=", "<=", ">", "<", "=="]
## Patch stats: per unit (hp fixed, ammo whole) or a squad pool (fixed).
const PATCH_STATS: Array[String] = ["hp", "ammo", "stamina", "instinct", "morale", "prowess", "legend", "fire_policy", "pin"]
const ORDER_KEYS: Array[String] = ["squad", "type", "x", "y", "target", "run", "abilities", "unchecked"]
const VARIANT_KEYS: Array[String] = ["script", "patch", "place", "doc"]

var path: String = ""
var id: String = ""
var component: String = ""
var doc: String = ""
var status: String = "gate"
var package: String = "rules-fixture"
## The battle scenario in the package whose rules and map the run uses.
var map: String = "duel_crossroads"
## Flatten the map to its base ground (no cover, no walls).
var open: bool = false
var seed_value: int = 1
var turns: int = 1
## Take a BattleProbe snapshot every N ticks (plus every tick an `at` probe
## names, and the end of every turn).
var probe_stride: int = 1
## [{key, player, squad, x, y (fixed), facing (angle), dummy {armed, hp
## (fixed, -1 = own), stationary}, patch {stat: fixed or int}}]
var squads: Array = []
## turn (int) or (turn, tick) Vector2i -> [order with squad/target keys; x, y
## fixed]. A Vector2i key is a mid-turn order: it takes effect after `tick`
## ticks of that turn have run (file key "<turn>@<tick>").
var orders: Dictionary = {}
## name -> {script: {turn: orders}, patch: {key: {stat: value}}, place:
## {key: [x, y] fixed}}
var variants: Dictionary = {}
## [{id, kind, squad, target, pending, variants (the expectation holds in
## these; default base), at {turn, tick} | over {t0, k0, t1, k1}, expect}]
var probes: Array = []
## [{metric, probe, sub, lhs, rhs, rel, factor (milli)}]
var compare: Array = []
var errors: PackedStringArray = PackedStringArray()


static func load_file(file: String) -> WorkshopScenario:
	var s := WorkshopScenario.new()
	s.path = file
	if not FileAccess.file_exists(file):
		s.errors.append("%s: no such file" % file)
		return s
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(file)) != OK:
		s.errors.append("%s: line %d: %s" % [file, json.get_error_line(), json.get_error_message()])
		return s
	s._read(json.data)
	return s


static func from_dict(d: Variant, label: String = "<dict>") -> WorkshopScenario:
	var s := WorkshopScenario.new()
	s.path = label
	s._read(d)
	return s


## A scenario by ID from DIR, or a path.
static func find(id_or_path: String) -> WorkshopScenario:
	if id_or_path.ends_with(".json"):
		return load_file(id_or_path)
	return load_file(DIR.path_join(id_or_path + ".json"))


## Every scenario file in `dir`, sorted.
static func list(dir: String = DIR) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".json"):
			out.append(dir.path_join(f))
	out.sort()
	return out


func is_valid() -> bool:
	return errors.is_empty()


func variant_names() -> PackedStringArray:
	var out := PackedStringArray([BASE])
	var names: Array = variants.keys()
	names.sort()
	for n: String in names:
		out.append(n)
	return out


## The squads and script a variant runs: its `script` turns replace the base
## script's turn (its start orders and its mid-turn orders alike; other turns
## stay), its `patch` merges shallowly over each squad's base patch (stat by
## stat), and its `place` moves squads. {} if unknown.
func resolved(variant: String) -> Dictionary:
	if variant != BASE and not variants.has(variant):
		return {}
	var sq: Array = squads.duplicate(true)
	var sc: Dictionary = orders.duplicate(true)
	if variant != BASE:
		var v: Dictionary = variants[variant]
		var turns_named := {}
		for k: Variant in v["script"]:
			turns_named[turn_of(k)] = true
		for bk: Variant in sc.keys():
			if turns_named.has(turn_of(bk)):
				sc.erase(bk)
		for k: Variant in v["script"]:
			sc[k] = (v["script"][k] as Array).duplicate(true)
		for d: Dictionary in sq:
			var p: Dictionary = v["patch"].get(d["key"], {})
			(d["patch"] as Dictionary).merge(p, true)
			if v["place"].has(d["key"]):
				d["x"] = v["place"][d["key"]][0]
				d["y"] = v["place"][d["key"]][1]
	return {"squads": sq, "script": sc}


## The turn a script key belongs to: an int turn, or the turn of a (turn, tick).
static func turn_of(k: Variant) -> int:
	return (k as Vector2i).x if typeof(k) == TYPE_VECTOR2I else int(k)


# --- quantization ------------------------------------------------------------

## Thousandths of a JSON number, ties away from zero (the one float step).
static func milli(v: Variant) -> int:
	return int(round(float(v) * 1000.0))


## A JSON number as fixed, through thousandths.
static func to_fixed(v: Variant) -> int:
	return Fixed.round_div(milli(v) * Fixed.ONE, 1000)


## Degrees (0 = east, 90 = south, counter to the screen's y-down) to a
## fixed angle (Fixed.ANGLE_FULL per turn), through thousandths.
static func to_angle(v: Variant) -> int:
	var m := posmod(milli(v), 360000)
	return Fixed.round_div(m * Fixed.ANGLE_FULL, 360000) & Fixed.ANGLE_MASK


# --- reading -----------------------------------------------------------------

func _err(field: String, msg: String) -> void:
	errors.append("%s: %s: %s" % [path, field, msg])


static func _is_num(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


static func _is_whole(v: Variant) -> bool:
	return _is_num(v) and float(v) == floorf(float(v))


func _read(d: Variant) -> void:
	if typeof(d) != TYPE_DICTIONARY:
		_err("(root)", "must be an object")
		return
	var known := ["id", "component", "doc", "status", "package", "map", "open", "seed", "turns",
		"probe_stride", "squads", "script", "variants", "probes", "compare"]
	for k: String in d:
		if not k in known:
			_err(k, "unknown field (known: %s)" % ", ".join(known))
	id = _str(d, "id", "", true)
	if id != "" and path.ends_with(".json") and path.get_file().get_basename() != id:
		_err("id", "'%s' must match the file name '%s'" % [id, path.get_file()])
	component = _str(d, "component", "", true)
	doc = _str(d, "doc", "", false)
	status = _str(d, "status", "gate", false)
	if not status in STATUSES:
		_err("status", "'%s' is not one of %s" % [status, ", ".join(STATUSES)])
	package = _str(d, "package", "rules-fixture", false)
	if not PACKAGES.has(package):
		_err("package", "'%s' is not one of %s" % [package, ", ".join(PACKAGES.keys())])
	map = _str(d, "map", "duel_crossroads", false)
	if d.has("open") and typeof(d["open"]) != TYPE_BOOL:
		_err("open", "must be true or false")
	open = d.get("open", false) == true
	seed_value = _int(d, "seed", 1, 0)
	turns = _int(d, "turns", 1, 1)
	probe_stride = _int(d, "probe_stride", 1, 1)
	_read_squads(d.get("squads"))
	var keys := {}
	for s: Dictionary in squads:
		keys[s["key"]] = s
	orders = _read_script(d.get("script", {}), "script", keys)
	_read_variants(d.get("variants", {}), keys)
	_read_probes(d.get("probes", []), keys)
	_read_compare(d.get("compare", []))
	if status == "explore" and not probes.is_empty():
		_err("probes", "an explore scenario has no probes (make it pending or gate)")


func _str(d: Dictionary, k: String, def: String, required: bool) -> String:
	if not d.has(k):
		if required:
			_err(k, "missing")
		return def
	if typeof(d[k]) != TYPE_STRING or (d[k] as String).is_empty():
		_err(k, "must be a non-empty string")
		return def
	return d[k]


func _int(d: Dictionary, k: String, def: int, lo: int) -> int:
	if not d.has(k):
		return def
	if not _is_whole(d[k]) or int(d[k]) < lo:
		_err(k, "must be a whole number >= %d" % lo)
		return def
	return int(d[k])


func _read_squads(v: Variant) -> void:
	if typeof(v) != TYPE_ARRAY or (v as Array).is_empty():
		_err("squads", "must be a non-empty list")
		return
	var seen := {}
	for i in (v as Array).size():
		var f := "squads[%d]" % i
		var s: Variant = v[i]
		if typeof(s) != TYPE_DICTIONARY:
			_err(f, "must be an object")
			continue
		for k: String in s:
			if not k in ["key", "player", "squad", "at", "facing", "dummy", "patch"]:
				_err("%s.%s" % [f, k], "unknown field")
		var key: Variant = s.get("key")
		if typeof(key) != TYPE_STRING or (key as String).is_empty():
			_err(f + ".key", "must be a non-empty string")
			continue
		if seen.has(key):
			_err(f + ".key", "'%s' is used twice" % key)
			continue
		seen[key] = true
		var out := {"key": key, "player": 1, "squad": "", "x": 0, "y": 0, "facing": 0,
			"dummy": {"armed": true, "hp": -1, "stationary": false}, "patch": {}}
		if not s.has("player") or not _is_whole(s["player"]) or int(s["player"]) < 1:
			_err(f + ".player", "must be a player number (1, 2, ...)")
		else:
			out["player"] = int(s["player"])
		if typeof(s.get("squad")) != TYPE_STRING or (s.get("squad") as String).is_empty():
			_err(f + ".squad", "must be a squad template ID")
		else:
			out["squad"] = s["squad"]
		var at: Variant = s.get("at")
		if typeof(at) != TYPE_ARRAY or (at as Array).size() != 2 or not _is_num(at[0]) or not _is_num(at[1]):
			_err(f + ".at", "must be [x, y] in metres")
		else:
			out["x"] = to_fixed(at[0])
			out["y"] = to_fixed(at[1])
		if s.has("facing"):
			if not _is_num(s["facing"]):
				_err(f + ".facing", "must be degrees (0 = east, 180 = west)")
			else:
				out["facing"] = to_angle(s["facing"])
		if s.has("dummy"):
			_read_dummy(s["dummy"], f + ".dummy", out["dummy"])
		out["patch"] = _read_patch(s.get("patch", {}), f + ".patch")
		squads.append(out)


func _read_dummy(v: Variant, f: String, out: Dictionary) -> void:
	if typeof(v) != TYPE_DICTIONARY:
		_err(f, "must be an object {armed, hp, stationary}")
		return
	for k: String in v:
		match k:
			"armed", "stationary":
				if typeof(v[k]) != TYPE_BOOL:
					_err("%s.%s" % [f, k], "must be true or false")
				else:
					out[k] = v[k]
			"hp":
				if not _is_num(v[k]) or float(v[k]) <= 0.0:
					_err(f + ".hp", "must be a positive number (HP per unit)")
				else:
					out["hp"] = to_fixed(v[k])
			_:
				_err("%s.%s" % [f, k], "unknown field (armed, hp, stationary)")


func _read_patch(v: Variant, f: String) -> Dictionary:
	var out := {}
	if typeof(v) != TYPE_DICTIONARY:
		_err(f, "must be an object {stat: value}")
		return out
	for k: String in v:
		if not k in PATCH_STATS:
			_err("%s.%s" % [f, k], "unknown stat (known: %s)" % ", ".join(PATCH_STATS))
		elif k == "fire_policy":
			# The squad's targeting policy (TargetPolicy, sw-pd2l.4), stored
			# as its index in DataSchema.FIRE_POLICIES.
			var i := DataSchema.FIRE_POLICIES.find(str(v[k])) if typeof(v[k]) == TYPE_STRING else -1
			if i < 0:
				_err("%s.%s" % [f, k], "must be one of %s" % ", ".join(DataSchema.FIRE_POLICIES))
			else:
				out[k] = i
		elif k == "pin":
			# Pools that ignore every flow (BattleSquads.pinned, sw-pd2l.5):
			# a list of pool names, stored as a bitmask.
			var mask := 0
			if typeof(v[k]) != TYPE_ARRAY:
				_err("%s.%s" % [f, k], "must be a list of pools (%s)" % ", ".join(DataSchema.SIMPL))
			else:
				for pn: Variant in v[k]:
					var pi := DataSchema.SIMPL.find(str(pn))
					if pi < 0:
						_err("%s.%s" % [f, k], "unknown pool '%s' (known: %s)" % [str(pn), ", ".join(DataSchema.SIMPL)])
					else:
						mask |= 1 << pi
			out[k] = mask
		elif k == "ammo":
			if not _is_whole(v[k]) or int(v[k]) < 0:
				_err("%s.%s" % [f, k], "must be a whole number >= 0")
			else:
				out[k] = int(v[k])
		elif not _is_num(v[k]) or float(v[k]) < 0.0 or (k == "hp" and float(v[k]) <= 0.0):
			_err("%s.%s" % [f, k], "must be a number >= 0" if k != "hp" else "must be a positive number")
		else:
			out[k] = to_fixed(v[k])
	return out


## {"<turn>": [orders], "<turn>@<tick>": [orders]} -> {turn: [orders],
## Vector2i(turn, tick): [orders]}; squad and target stay keys. A mid-turn
## key takes effect after `tick` ticks of that turn (1 .. ticks - 1).
func _read_script(v: Variant, f: String, keys: Dictionary) -> Dictionary:
	var out := {}
	if typeof(v) != TYPE_DICTIONARY:
		_err(f, "must be an object {\"<turn>\": [orders]}")
		return out
	for tk: String in v:
		var tf := "%s.%s" % [f, tk]
		var parts := tk.split("@")
		var ok := parts.size() <= 2 and parts[0].is_valid_int() and int(parts[0]) >= 1
		if parts.size() == 2:
			ok = ok and parts[1].is_valid_int() and int(parts[1]) >= 1
		if not ok:
			_err(tf, "the key must be a turn number (1, 2, ...) or \"<turn>@<tick>\" (tick >= 1)")
			continue
		var t := int(parts[0])
		var key: Variant = t if parts.size() == 1 else Vector2i(t, int(parts[1]))
		if t > turns:
			_err(tf, "turn %d is past the scenario's %d turns" % [t, turns])
		if typeof(v[tk]) != TYPE_ARRAY:
			_err(tf, "must be a list of orders")
			continue
		var orders: Array = []
		for i in (v[tk] as Array).size():
			var o: Variant = _read_order(v[tk][i], "%s[%d]" % [tf, i], keys)
			if o != null:
				orders.append(o)
		out[key] = orders
	return out


func _read_order(o: Variant, f: String, keys: Dictionary) -> Variant:
	if typeof(o) != TYPE_DICTIONARY:
		_err(f, "must be an order object")
		return null
	var out := {}
	for k: String in o:
		if not k in ORDER_KEYS:
			_err("%s.%s" % [f, k], "unknown field (BattleOrders: %s)" % ", ".join(ORDER_KEYS))
			return null
	var key: Variant = o.get("squad")
	if typeof(key) != TYPE_STRING or not keys.has(key):
		_err(f + ".squad", "must be a squad key from squads")
		return null
	if keys[key]["dummy"]["stationary"]:
		_err(f + ".squad", "'%s' is a stationary dummy and takes no orders" % key)
		return null
	out["squad"] = key
	var t: Variant = o.get("type", "hold")
	if typeof(t) != TYPE_STRING or not BattleOrders.TYPES.has(t):
		_err(f + ".type", "must be one of %s" % ", ".join(BattleOrders.TYPES.keys()))
		return null
	out["type"] = t
	for k: String in ["x", "y"]:
		if o.has(k):
			if not _is_num(o[k]):
				_err("%s.%s" % [f, k], "must be metres")
				return null
			out[k] = to_fixed(o[k])
	if o.has("target"):
		if typeof(o["target"]) != TYPE_STRING or not keys.has(o["target"]):
			_err(f + ".target", "must be a squad key from squads")
			return null
		out["target"] = o["target"]
	for k: String in ["run", "abilities"]:
		if o.has(k):
			out[k] = o[k]
	if o.has("unchecked"):
		if typeof(o["unchecked"]) != TYPE_BOOL:
			_err(f + ".unchecked", "must be true or false")
			return null
		out["unchecked"] = o["unchecked"]
	return out


func _read_variants(v: Variant, keys: Dictionary) -> void:
	if typeof(v) != TYPE_DICTIONARY:
		_err("variants", "must be an object {name: {script, patch}}")
		return
	for name: String in v:
		var f := "variants.%s" % name
		if name == BASE:
			_err(f, "'base' is the file's own script and patches; pick another name")
			continue
		var d: Variant = v[name]
		if typeof(d) != TYPE_DICTIONARY:
			_err(f, "must be an object {script, patch}")
			continue
		for k: String in d:
			if not k in VARIANT_KEYS:
				_err("%s.%s" % [f, k], "unknown field (%s)" % ", ".join(VARIANT_KEYS))
		var place := {}
		var lv: Variant = d.get("place", {})
		if typeof(lv) != TYPE_DICTIONARY:
			_err(f + ".place", "must be an object {squad key: [x, y]}")
		else:
			for key: String in lv:
				var at: Variant = lv[key]
				if not keys.has(key):
					_err("%s.place.%s" % [f, key], "not a squad key")
				elif typeof(at) != TYPE_ARRAY or (at as Array).size() != 2 or not _is_num(at[0]) or not _is_num(at[1]):
					_err("%s.place.%s" % [f, key], "must be [x, y] in metres")
				else:
					place[key] = [to_fixed(at[0]), to_fixed(at[1])]
		var patch := {}
		var pv: Variant = d.get("patch", {})
		if typeof(pv) != TYPE_DICTIONARY:
			_err(f + ".patch", "must be an object {squad key: {stat: value}}")
		else:
			for key: String in pv:
				if not keys.has(key):
					_err("%s.patch.%s" % [f, key], "not a squad key")
				else:
					patch[key] = _read_patch(pv[key], "%s.patch.%s" % [f, key])
		variants[name] = {"script": _read_script(d.get("script", {}), f + ".script", keys), "patch": patch, "place": place}


## "end" | "t<turn>" (after it resolved) | "t<turn>:<tick>" -> {turn, tick};
## turn -1 = the end of the run, tick -1 = after the turn resolved.
func _parse_at(v: Variant, f: String) -> Dictionary:
	if typeof(v) == TYPE_STRING and v == "end":
		return {"turn": -1, "tick": -1}
	var m := _turn_tick(v)
	if m.is_empty():
		_err(f, "must be \"end\", \"t<turn>\" or \"t<turn>:<tick>\"")
	return m


func _turn_tick(v: Variant) -> Dictionary:
	if typeof(v) != TYPE_STRING or not (v as String).begins_with("t"):
		return {}
	var parts := (v as String).substr(1).split(":")
	if parts.size() > 2 or not parts[0].is_valid_int() or int(parts[0]) < 1 or int(parts[0]) > turns:
		return {}
	if parts.size() == 2 and (not parts[1].is_valid_int() or int(parts[1]) < 0):
		return {}
	return {"turn": int(parts[0]), "tick": int(parts[1]) if parts.size() == 2 else -1}


## "all" | "t<a>" | "t<a>-t<b>" | "t<a>:<k0>-<k1>" -> {t0, k0, t1, k1}
## (both ends inclusive; k1 -1 = the turn's last tick).
func _parse_over(v: Variant, f: String) -> Dictionary:
	var bad := "must be \"all\", \"t<turn>\", \"t<a>-t<b>\" or \"t<turn>:<tick>-<tick>\""
	if typeof(v) != TYPE_STRING:
		_err(f, bad)
		return {}
	var s: String = v
	if s == "all":
		return {"t0": 1, "k0": 0, "t1": turns, "k1": -1}
	if s.contains(":"):
		var head := s.split(":")
		var a := _turn_tick(head[0])
		var ks := head[1].split("-") if head.size() == 2 else PackedStringArray()
		if a.is_empty() or ks.size() != 2 or not ks[0].is_valid_int() or not ks[1].is_valid_int() \
				or int(ks[0]) < 0 or int(ks[1]) < int(ks[0]):
			_err(f, bad)
			return {}
		return {"t0": a["turn"], "k0": int(ks[0]), "t1": a["turn"], "k1": int(ks[1])}
	var ts := s.split("-")
	var t0 := _turn_tick(ts[0])
	var t1 := _turn_tick(ts[1]) if ts.size() == 2 else t0
	if ts.size() > 2 or t0.is_empty() or t1.is_empty() or t1["turn"] < t0["turn"]:
		_err(f, bad)
		return {}
	return {"t0": t0["turn"], "k0": 0, "t1": t1["turn"], "k1": -1}


func _read_probes(v: Variant, keys: Dictionary) -> void:
	if typeof(v) != TYPE_ARRAY:
		_err("probes", "must be a list")
		return
	var ids := {}
	var kinds: Array[String] = AT_KINDS.duplicate()
	for k in OVER_KINDS:
		if not k in kinds:
			kinds.append(k)
	for i in (v as Array).size():
		var f := "probes[%d]" % i
		var p: Variant = v[i]
		if typeof(p) != TYPE_DICTIONARY:
			_err(f, "must be an object")
			continue
		var pid: Variant = p.get("id")
		if typeof(pid) != TYPE_STRING or (pid as String).is_empty() or (pid as String).contains("."):
			_err(f + ".id", "must be a non-empty string without dots")
			continue
		f = "probes.%s" % pid
		if ids.has(pid):
			_err(f, "the id is used twice")
			continue
		ids[pid] = true
		var kind := ""
		for k: String in p:
			if k in kinds:
				if kind != "":
					_err(f, "has two kinds ('%s' and '%s'); one per probe" % [kind, k])
				kind = k
			elif not k in ["id", "at", "over", "squad", "target", "pending", "variants", "doc"]:
				_err("%s.%s" % [f, k], "unknown field (kinds: %s)" % ", ".join(kinds))
		if kind == "":
			_err(f, "needs one kind: %s" % ", ".join(kinds))
			continue
		var out := {"id": pid, "kind": kind, "squad": "", "target": "", "pending": p.get("pending", false) == true}
		if p.has("pending") and typeof(p["pending"]) != TYPE_BOOL:
			_err(f + ".pending", "must be true or false")
		out["variants"] = PackedStringArray([BASE])
		if p.has("variants"):
			var names := variant_names()
			var vs: Variant = p["variants"]
			if typeof(vs) == TYPE_STRING and vs == "all":
				out["variants"] = names
			elif typeof(vs) != TYPE_ARRAY or (vs as Array).is_empty() 					or (vs as Array).any(func(n: Variant) -> bool: return not n in names):
				_err(f + ".variants", "must be \"all\" or a list of variant names (%s)" % ", ".join(names))
			else:
				out["variants"] = PackedStringArray(vs)
		if p.has("at") == p.has("over"):
			_err(f, "needs exactly one of 'at' or 'over'")
			continue
		if p.has("at"):
			if not kind in AT_KINDS:
				_err(f + ".at", "'%s' is measured over a window: use 'over'" % kind)
				continue
			out["at"] = _parse_at(p["at"], f + ".at")
		else:
			if not kind in OVER_KINDS:
				_err(f + ".over", "'%s' is read at one moment: use 'at'" % kind)
				continue
			out["over"] = _parse_over(p["over"], f + ".over")
		for k: String in ["squad", "target"]:
			if p.has(k):
				if typeof(p[k]) != TYPE_STRING or not keys.has(p[k]):
					_err("%s.%s" % [f, k], "must be a squad key from squads")
				else:
					out[k] = p[k]
		if out["squad"] == "":
			_err(f + ".squad", "missing")
		if kind in NEEDS_TARGET and out["target"] == "":
			_err(f + ".target", "'%s' needs a target squad key" % kind)
		out["expect"] = _read_expect(kind, p[kind], "%s.%s" % [f, kind])
		probes.append(out)


## Expectations: null = report only; for numbers a number (equal after
## quantizing) or {min, max} (thousandths); names: a name or a list of them;
## within: true/false; victims: {distinct|max_per_victim|overkill: number or range}.
func _read_expect(kind: String, v: Variant, f: String) -> Variant:
	if v == null:
		return null
	match kind:
		"activity":
			return _names(v, f, BattleActivity.Squad.keys())
		"hold":
			return _names(v, f, BattleActivity.Hold.keys())
		"fire":
			return _names(v, f, FIRE_CODES)
		"within":
			if typeof(v) != TYPE_BOOL:
				_err(f, "must be true or false (or null)")
			return v == true
		"victims":
			if typeof(v) != TYPE_DICTIONARY:
				_err(f, "must be an object {%s: number or {min, max}}" % ", ".join(VICTIM_KEYS))
				return null
			var out := {}
			for k: String in v:
				if not k in VICTIM_KEYS:
					_err("%s.%s" % [f, k], "unknown field (%s)" % ", ".join(VICTIM_KEYS))
				else:
					out[k] = _range(v[k], "%s.%s" % [f, k])
			return out
	return _range(v, f)


func _names(v: Variant, f: String, allowed: Array) -> Variant:
	var list: Array = v if typeof(v) == TYPE_ARRAY else [v]
	var out := PackedStringArray()
	var up := allowed.map(func(a: Variant) -> String: return String(a).to_upper())
	for n: Variant in list:
		if typeof(n) != TYPE_STRING or not (n as String).to_upper() in up:
			_err(f, "'%s' is not one of %s" % [n, ", ".join(allowed)])
		else:
			out.append((n as String).to_upper())
	return out


## A number -> {min = max = it}; {min, max} -> thousandths; either end optional.
func _range(v: Variant, f: String) -> Variant:
	if _is_num(v):
		return {"min": milli(v), "max": milli(v)}
	if typeof(v) != TYPE_DICTIONARY or v.is_empty():
		_err(f, "must be a number or {min, max}")
		return null
	var out := {}
	for k: String in v:
		if not k in ["min", "max"] or not _is_num(v[k]):
			_err("%s.%s" % [f, k], "only min and max, as numbers")
		else:
			out[k] = milli(v[k])
	return out


func _read_compare(v: Variant) -> void:
	if typeof(v) != TYPE_ARRAY:
		_err("compare", "must be a list")
		return
	var probe_ids := {}
	for p: Dictionary in probes:
		probe_ids[p["id"]] = p
	var names := variant_names()
	for i in (v as Array).size():
		var f := "compare[%d]" % i
		var c: Variant = v[i]
		if typeof(c) != TYPE_DICTIONARY:
			_err(f, "must be an object {metric, lhs, rhs, rel, factor}")
			continue
		var metric: Variant = c.get("metric")
		var parts := String(metric).split(".") if typeof(metric) == TYPE_STRING else PackedStringArray()
		if parts.is_empty() or not probe_ids.has(parts[0]) or parts.size() > 2:
			_err(f + ".metric", "must be a probe id (or <victims probe>.<%s>)" % "|".join(VICTIM_KEYS))
			continue
		var kind: String = probe_ids[parts[0]]["kind"]
		if kind in ["activity", "hold", "fire", "within"]:
			_err(f + ".metric", "'%s' is a %s probe; compare needs a number" % [parts[0], kind])
			continue
		if (kind == "victims") != (parts.size() == 2) or (parts.size() == 2 and not parts[1] in VICTIM_KEYS):
			_err(f + ".metric", "a victims probe needs one of .%s; other kinds take none" % ", .".join(VICTIM_KEYS))
			continue
		var out := {"metric": metric, "probe": parts[0], "sub": parts[1] if parts.size() == 2 else "",
			"rel": c.get("rel", ">="), "factor": milli(c.get("factor", 1)) if _is_num(c.get("factor", 1)) else 1000,
			"pending": c.get("pending", false) == true}
		for k: String in ["lhs", "rhs"]:
			if typeof(c.get(k)) != TYPE_STRING or not c[k] in names:
				_err("%s.%s" % [f, k], "must be a variant name (%s)" % ", ".join(names))
			else:
				out[k] = c[k]
		if not out["rel"] in RELS:
			_err(f + ".rel", "must be one of %s" % " ".join(RELS))
		if not _is_num(c.get("factor", 1)):
			_err(f + ".factor", "must be a number")
		for k: String in c:
			if not k in ["metric", "lhs", "rhs", "rel", "factor", "pending", "doc"]:
				_err("%s.%s" % [f, k], "unknown field")
		compare.append(out)
