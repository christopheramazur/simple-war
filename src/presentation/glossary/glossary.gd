class_name Glossary
extends RefCounted
## Defined terms for hoverable tooltips (GDD 07, 01 pillar 3, R1Q3, R3Q10,
## R8Q10). Terms are package data (kind "term"), so mods add their own.
## Every string goes through a translation key: "term.<id>.name",
## "term.<id>.text" and "glossary.<key>" for value phrases, with the data's
## (or EN's) English as the fallback until translation tables exist.
##
## Context-aware values: a term's `context` says where its live value comes
## from, read from what the UI already holds for the hovered squad:
##   ctx = {"inspection": Inspection.squad(...) / BattleSession.inspect,
##          "unit": index into its units (optional), "squad": the squad's
##          battle observation (pools, own squads only)}.
##   - "stat:<id>": the stat's effective value, with its base when modified.
##   - "pool:<name>": the pool's band and value / capacity.
##   - "band": every pool's band.
##   - "bad_hit": the Bad Hit threshold, half the unit's effective base HP
##     (temporary HP never counts): "(5 HP)", or "(Any Hit)" under 2 HP.
##   - "units": living units out of the starting count.
## `change` is 1 when the value is modified for the better (shown green with
## ▲), -1 for the worse (red, ▼): never colour alone.

const EN: Dictionary = {
	"glossary.value.bad_hit": "({hp} HP)",
	"glossary.value.any_hit": "(Any Hit)",
	"glossary.value.modified": "{value} (base {base})",
	"glossary.value.pool": "{band} · {value} / {capacity}",
	"glossary.value.units": "{alive} of {start} units",
	"glossary.see": "See also: {terms}",
}

var errors: PackedStringArray = PackedStringArray()
## Term ID -> {"name", "text", "category", "aliases", "see", "context", "lower"}.
var _terms: Dictionary = {}
## [phrase (lower case), term ID], longest phrase first.
var _links: Array = []


static func from_templates(t: TemplateTable) -> Glossary:
	var g := Glossary.new()
	var ids := PackedStringArray()
	for tid in t.ids():
		if t.kind_of(tid) == "term" and not t.is_abstract(tid):
			ids.append(tid)
	ids.sort()
	for tid in ids:
		var v := t.values_of(tid)
		var ctx := String(v.get("context", ""))
		if not _valid_context(ctx):
			g.errors.append("%s: unknown context '%s'" % [tid, ctx])
		g._terms[tid] = {"name": String(v["name"]), "text": String(v["text"]), "category": String(v.get("category", "")),
			"aliases": PackedStringArray(v.get("aliases", [])), "see": PackedStringArray(v.get("see", [])),
			"context": ctx, "lower": bool(v.get("lower_is_better", false))}
	for tid in ids:
		for s: String in g._terms[tid]["see"]:
			if not g._terms.has(s):
				g.errors.append("%s: 'see' names unknown term '%s'" % [tid, s])
		var phrases := PackedStringArray([g.name_of(tid)])
		var raw := String(g._terms[tid]["name"])
		if raw.contains("("):
			phrases.append(raw.get_slice("(", 0).strip_edges())
		phrases.append_array(g._terms[tid]["aliases"])
		for p in phrases:
			for form in [p, p + "s"]:
				g._links.append([form.to_lower(), tid])
	g._links.sort_custom(func(a: Array, b: Array) -> bool:
		if a[0].length() != b[0].length():
			return a[0].length() > b[0].length()
		return a[0] < b[0])
	return g


static func _valid_context(ctx: String) -> bool:
	return ctx in ["", "bad_hit", "band", "units"] or ctx.begins_with("stat:") \
		or (ctx.begins_with("pool:") and DataSchema.SIMPL.has(ctx.get_slice(":", 1)))


func ids() -> PackedStringArray:
	var out := PackedStringArray(_terms.keys())
	out.sort()
	return out


func has(id: String) -> bool:
	return _terms.has(id)


func name_of(id: String) -> String:
	return _t("term.%s.name" % id, _terms[id]["name"]) if _terms.has(id) else id


func text_of(id: String) -> String:
	return _t("term.%s.text" % id, _terms[id]["text"]) if _terms.has(id) else ""


## The term a word or phrase stands for (name, alias or plural), or "".
func term_for(phrase: String) -> String:
	var p := phrase.to_lower()
	for l: Array in _links:
		if l[0] == p:
			return l[1]
	return ""


## Splits text into spans, linking every defined term (whole words,
## longest match first): [{"text", "term" (ID or "")}].
func link(text: String) -> Array:
	var out := []
	var low := text.to_lower()
	var i := 0
	var plain := ""
	while i < text.length():
		var hit := ""
		var hit_len := 0
		if i == 0 or not _word_char(text[i - 1]):
			for l: Array in _links:
				var ph: String = l[0]
				var n := ph.length()
				if low.substr(i, n) == ph and (i + n >= text.length() or not _word_char(text[i + n])):
					hit = l[1]
					hit_len = n
					break
		if hit.is_empty():
			plain += text[i]
			i += 1
			continue
		if not plain.is_empty():
			out.append({"text": plain, "term": ""})
			plain = ""
		out.append({"text": text.substr(i, hit_len), "term": hit})
		i += hit_len
	if not plain.is_empty():
		out.append({"text": plain, "term": ""})
	return out


## The text as BBCode with each term a [url=term:<id>] link.
func bbcode(text: String) -> String:
	var s := ""
	for span: Dictionary in link(text):
		var t: String = String(span["text"]).replace("[", "[lb]")
		s += t if span["term"] == "" else "[url=term:%s]%s[/url]" % [span["term"], t]
	return s


## A tooltip for a term, with its live value from `ctx` (see above):
## {"id", "title", "text", "value" ("" = none), "change" (-1, 0, 1),
## "see" (names)}.
func tooltip(id: String, ctx: Dictionary = {}) -> Dictionary:
	if not _terms.has(id):
		return {}
	var out := {"id": id, "title": name_of(id), "text": text_of(id), "value": "", "change": 0, "see": []}
	for s: String in _terms[id]["see"]:
		(out["see"] as Array).append(name_of(s))
	var ctx_name: String = _terms[id]["context"]
	if ctx_name.is_empty() or ctx.is_empty():
		return out
	var lower: bool = _terms[id]["lower"]
	if ctx_name.begins_with("stat:"):
		var e := _stat(ctx, ctx_name.get_slice(":", 1))
		if not e.is_empty():
			_modified(out, e["value"], e["base"], String(e.get("unit", "")), lower)
	elif ctx_name.begins_with("pool:"):
		var pools: Dictionary = (ctx.get("squad", {}) as Dictionary).get("pools", {})
		var p: Dictionary = pools.get(ctx_name.get_slice(":", 1), {})
		if not p.is_empty():
			out["value"] = _f("glossary.value.pool", {"band": _t("band." + String(p["band"]), String(p["band"]).capitalize()),
				"value": Fixed.to_display(p["value"]), "capacity": Fixed.to_display(p["capacity"])})
	elif ctx_name == "band":
		var pools: Dictionary = (ctx.get("squad", {}) as Dictionary).get("pools", {})
		var parts := PackedStringArray()
		for name: String in DataSchema.SIMPL:
			if pools.has(name):
				parts.append("%s %s" % [_t("pool." + name, name.capitalize()), _t("band." + String(pools[name]["band"]),
					String(pools[name]["band"]).capitalize())])
		out["value"] = " · ".join(parts)
	elif ctx_name == "bad_hit":
		var e := _stat(ctx, "unit.hp")
		if not e.is_empty():
			var half: int = e["value"] / 2
			out["value"] = _w("glossary.value.any_hit") if e["value"] < 2 * Fixed.ONE \
				else _f("glossary.value.bad_hit", {"hp": Fixed.to_display(half)})
			out["change"] = signi(e["value"] - e["base"])
	elif ctx_name == "units":
		var st: Dictionary = (ctx.get("inspection", {}) as Dictionary).get("strength", {})
		if not st.is_empty():
			out["value"] = _f("glossary.value.units", {"alive": st["alive"], "start": st["start"]})
			out["change"] = -1 if st["alive"] < st["start"] else 0
	return out


## The stat entry from the hovered unit (else the squad, else its first
## unit) of the inspection in ctx.
func _stat(ctx: Dictionary, stat: String) -> Dictionary:
	var insp: Dictionary = ctx.get("inspection", {})
	var units: Array = insp.get("units", [])
	var lists := []
	var ui: int = ctx.get("unit", -1)
	if ui >= 0 and ui < units.size():
		lists.append(units[ui]["stats"])
	lists.append(insp.get("stats", []))
	if not units.is_empty():
		lists.append(units[0]["stats"])
	for l: Array in lists:
		for e: Dictionary in l:
			if e["stat"] == stat:
				return e
	return {}


func _modified(out: Dictionary, value: int, base: int, unit: String, lower: bool) -> void:
	var v := Fixed.to_display(value) + unit
	if value == base:
		out["value"] = v
		return
	out["value"] = _f("glossary.value.modified", {"value": v, "base": Fixed.to_display(base) + unit})
	out["change"] = signi(value - base) * (-1 if lower else 1)


static func _word_char(c: String) -> bool:
	return c == "_" or (c.to_lower() != c.to_upper()) or c.is_valid_int()


static func _f(key: String, args: Dictionary) -> String:
	return _t(key, EN.get(key, key)).format(args)


static func _w(key: String) -> String:
	return _t(key, EN.get(key, key))


static func _t(key: String, fallback: String) -> String:
	var s := String(TranslationServer.translate(key))
	return fallback if s == key else s
