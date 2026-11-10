class_name TemplateTable
extends RefCounted
## Archetype templates: authoring-time inheritance, flattened once at load.
## GDD 03 §3.1, R6Q18.
##
## Input: an Array of definitions (parsed from package JSON):
##     {"id": "rifle_squad", "parent": "infantry", "kind": "squad",
##      "abstract": false, "values": {...}}
## - `parent` is optional. A chain may be at most MAX_DEPTH templates long
##   (root -> child -> grandchild). Cycles and missing parents are errors.
## - `kind` is inherited; a child may not change it.
## - Overrides merge recursively into dictionaries; anything else replaces.
##   An override of `null` removes the key.
## - Numbers: JSON gives floats. Integral floats become ints; a fractional
##   float is an error (write fixed-point values as decimal strings, "1.25").
## - `abstract` templates can't be instantiated (not inherited).
##
## Output: an immutable table. Every flattened value records which template
## set it (provenance), for tooltips and data audits. Spawning copies values
## (`instantiate`); there is no live inheritance.

const MAX_DEPTH: int = 3

## Validation errors; the table is unusable unless this is empty.
var errors: PackedStringArray = PackedStringArray()

var _order: PackedStringArray = PackedStringArray()
var _flat: Dictionary = {}
var _kind: Dictionary = {}
var _abstract: Dictionary = {}
var _provenance: Dictionary = {}


static func build(defs: Array) -> TemplateTable:
	var t := TemplateTable.new()
	t._build(defs)
	return t


func is_valid() -> bool:
	return errors.is_empty()


func ids() -> PackedStringArray:
	return _order.duplicate()


func has(template_id: String) -> bool:
	return _flat.has(template_id)


func kind_of(template_id: String) -> String:
	return _kind.get(template_id, "")


func is_abstract(template_id: String) -> bool:
	return _abstract.get(template_id, false)


## The flattened values (read-only). Use `instantiate` to get a mutable copy.
func values_of(template_id: String) -> Dictionary:
	assert(has(template_id), "TemplateTable: unknown template %s" % template_id)
	return _flat[template_id]


## A deep, mutable copy of the flattened values, for spawning.
func instantiate(template_id: String) -> Dictionary:
	assert(has(template_id), "TemplateTable: unknown template %s" % template_id)
	assert(not is_abstract(template_id), "TemplateTable: %s is abstract" % template_id)
	return (_flat[template_id] as Dictionary).duplicate(true)


## Which template set the value at `path` ("a/b/c"), or "" if none.
func provenance(template_id: String, path: String) -> String:
	return (_provenance.get(template_id, {}) as Dictionary).get(path, "")


func _build(defs: Array) -> void:
	var by_id: Dictionary = {}
	for i in defs.size():
		var d: Variant = defs[i]
		if typeof(d) != TYPE_DICTIONARY or typeof(d.get("id")) != TYPE_STRING or (d.get("id") as String).is_empty():
			errors.append("definition #%d: needs a non-empty string id" % i)
			continue
		var tid: String = d["id"]
		if by_id.has(tid):
			errors.append("%s: duplicate id" % tid)
			continue
		by_id[tid] = d
		_order.append(tid)
	for tid in _order:
		_resolve(tid, by_id)
	if not errors.is_empty():
		_flat.clear()
		_provenance.clear()
		_kind.clear()
		_abstract.clear()


func _resolve(tid: String, by_id: Dictionary) -> void:
	# Build the chain root..tid, checking cycles, missing parents and depth.
	var chain: Array[String] = []
	var cur := tid
	while true:
		if chain.has(cur):
			errors.append("%s: inheritance cycle through %s" % [tid, cur])
			return
		chain.push_front(cur)
		var parent: Variant = (by_id[cur] as Dictionary).get("parent")
		if parent == null or (parent is String and (parent as String).is_empty()):
			break
		if not by_id.has(parent):
			errors.append("%s: missing parent '%s'" % [cur, parent])
			return
		cur = parent
	if chain.size() > MAX_DEPTH:
		errors.append("%s: inheritance chain %s is deeper than %d" % [tid, " -> ".join(chain), MAX_DEPTH])
		return
	var kind := ""
	var flat: Dictionary = {}
	var prov: Dictionary = {}
	for link in chain:
		var d: Dictionary = by_id[link]
		var k: String = str(d.get("kind", ""))
		if not k.is_empty():
			if not kind.is_empty() and k != kind:
				errors.append("%s: kind '%s' differs from parent kind '%s'" % [link, k, kind])
				return
			kind = k
		var vals: Variant = d.get("values", {})
		if typeof(vals) != TYPE_DICTIONARY:
			errors.append("%s: values must be an object" % link)
			return
		_merge(flat, vals, "", link, prov, tid)
	if kind.is_empty():
		errors.append("%s: no kind in its chain" % tid)
		return
	_deep_read_only(flat)
	_flat[tid] = flat
	_kind[tid] = kind
	_abstract[tid] = bool((by_id[tid] as Dictionary).get("abstract", false))
	_provenance[tid] = prov


func _merge(into: Dictionary, over: Dictionary, prefix: String, source: String, prov: Dictionary, tid: String) -> void:
	for key: Variant in over:
		var k := str(key)
		var path := k if prefix.is_empty() else prefix + "/" + k
		var v: Variant = over[key]
		if v == null:
			into.erase(k)
			_erase_prov(prov, path)
			continue
		if typeof(v) == TYPE_DICTIONARY and typeof(into.get(k)) == TYPE_DICTIONARY:
			_merge(into[k], v, path, source, prov, tid)
			continue
		var norm: Variant = _normalize(v, path, tid)
		into[k] = norm
		_erase_prov(prov, path)
		_record_prov(norm, path, source, prov)


func _normalize(v: Variant, path: String, tid: String) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			var f: float = v
			if f != floorf(f):
				errors.append("%s: %s is fractional (%s); use a decimal string" % [tid, path, f])
				return 0
			return int(f)
		TYPE_DICTIONARY:
			var out := {}
			for key: Variant in v:
				out[str(key)] = _normalize(v[key], path + "/" + str(key), tid)
			return out
		TYPE_ARRAY:
			var arr := []
			for i in (v as Array).size():
				arr.append(_normalize(v[i], "%s/%d" % [path, i], tid))
			return arr
		_:
			return v


func _record_prov(v: Variant, path: String, source: String, prov: Dictionary) -> void:
	prov[path] = source
	if typeof(v) == TYPE_DICTIONARY:
		for key: Variant in v:
			_record_prov(v[key], path + "/" + str(key), source, prov)


func _erase_prov(prov: Dictionary, path: String) -> void:
	var prefix := path + "/"
	for p: Variant in prov.keys():
		var ps: String = p
		if ps == path or ps.begins_with(prefix):
			prov.erase(ps)


static func _deep_read_only(v: Variant) -> void:
	if typeof(v) == TYPE_DICTIONARY:
		for key: Variant in v:
			_deep_read_only(v[key])
		(v as Dictionary).make_read_only()
	elif typeof(v) == TYPE_ARRAY:
		for item: Variant in v:
			_deep_read_only(item)
		(v as Array).make_read_only()
