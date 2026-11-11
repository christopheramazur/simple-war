class_name PackageLoader
extends RefCounted
## Loads content packages: official content and mods use the same format.
## GDD 03 §3.7, R6Q25, R6Q26.
##
## A package is a folder with `manifest.json`:
##   {"format": 1, "id": "core", "version": "0.1.0", "name": "...",
##    "dependencies": [{"id": "core", "min_version": "0.1.0"}],
##    "data": ["defs/weapons.json", ...],        # relative paths only
##    "assets": {"portrait_jeff": "art/jeff.png"}}  # id -> relative path
## Each data file is `{"templates": [...], "patches": [...]}`:
##   templates: archetype definitions (TemplateTable input), new ids only;
##   patches:   {"id": <existing template>, "values": {...}} merged into that
##              template's values (recursive; null removes), in load order.
##
## Load order: dependencies first; otherwise by package id. The merged data is
## flattened, schema-validated and hashed (the hash goes into saves/replays).
## Packages never run code: there is no script loading and no .pck support.

const FORMAT: int = 1
const ASSET_EXTENSIONS: Array[String] = ["png", "webp", "jpg", "jpeg", "ogg", "wav", "mp3", "ttf", "otf"]

## Result fields.
var errors: PackedStringArray = PackedStringArray()
var packages: Array[Dictionary] = []
var templates: TemplateTable
var data_hash: String = ""
## Asset id ("pkg:id") -> absolute path.
var assets: Dictionary = {}


## Loads the packages found directly under each root (one folder per package).
static func load_roots(roots: PackedStringArray) -> PackageLoader:
	var dirs := PackedStringArray()
	for root in roots:
		var d := DirAccess.open(root)
		if d == null:
			continue
		var names := d.get_directories()
		names.sort()
		for n in names:
			if FileAccess.file_exists(root.path_join(n).path_join("manifest.json")):
				dirs.append(root.path_join(n))
	return load_dirs(dirs)


## Loads exactly these package folders.
static func load_dirs(dirs: PackedStringArray) -> PackageLoader:
	var l := PackageLoader.new()
	l._load(dirs)
	return l


func is_valid() -> bool:
	return errors.is_empty()


func package_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for p in packages:
		out.append(p["id"])
	return out


func _load(dirs: PackedStringArray) -> void:
	var by_id: Dictionary = {}
	for dir in dirs:
		var m := _read_manifest(dir)
		if m.is_empty():
			continue
		if by_id.has(m["id"]):
			errors.append("package '%s' found twice" % m["id"])
			continue
		by_id[m["id"]] = m
	var order := _order(by_id)
	var defs: Array = []
	var index: Dictionary = {}
	for pid in order:
		var m: Dictionary = by_id[pid]
		packages.append(m)
		for rel: String in m.get("data", []):
			_read_data(m, rel, defs, index)
		var asset_map: Dictionary = m.get("assets", {})
		for aid: String in asset_map:
			_register_asset(m, aid, asset_map[aid])
	templates = TemplateTable.build(defs)
	errors.append_array(templates.errors)
	if templates.is_valid():
		errors.append_array(DataSchema.validate(templates))
	if errors.is_empty():
		data_hash = _hash(templates)


func _read_manifest(dir: String) -> Dictionary:
	var path := dir.path_join("manifest.json")
	var parsed: Variant = _read_json(path)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var m: Dictionary = parsed
	var ok := true
	if typeof(m.get("format")) != TYPE_FLOAT and typeof(m.get("format")) != TYPE_INT or int(m.get("format", 0)) != FORMAT:
		errors.append("%s: unsupported format (want %d)" % [path, FORMAT])
		ok = false
	for field in ["id", "version"]:
		if typeof(m.get(field)) != TYPE_STRING or (m[field] as String).is_empty():
			errors.append("%s: missing string '%s'" % [path, field])
			ok = false
	if ok and _version(m["version"]).is_empty():
		errors.append("%s: version must look like 1.2.3" % path)
		ok = false
	if not ok:
		return {}
	m["_dir"] = dir
	return m


func _order(by_id: Dictionary) -> PackedStringArray:
	var ids: Array = by_id.keys()
	ids.sort()
	var order := PackedStringArray()
	var state: Dictionary = {}
	for pid: String in ids:
		_visit(pid, by_id, state, order, [])
	return order


func _visit(pid: String, by_id: Dictionary, state: Dictionary, order: PackedStringArray, stack: Array) -> void:
	if state.get(pid) == "done":
		return
	if state.get(pid) == "visiting":
		errors.append("dependency cycle: %s" % " -> ".join(PackedStringArray(stack + [pid])))
		return
	state[pid] = "visiting"
	var deps: Array = (by_id[pid] as Dictionary).get("dependencies", [])
	var dep_ids: Array = []
	for dep: Variant in deps:
		if typeof(dep) != TYPE_DICTIONARY or typeof(dep.get("id")) != TYPE_STRING:
			errors.append("%s: bad dependency entry" % pid)
			continue
		var did: String = dep["id"]
		if not by_id.has(did):
			errors.append("%s: missing dependency '%s'" % [pid, did])
			continue
		var minv: String = dep.get("min_version", "0.0.0")
		if _compare_versions(by_id[did]["version"], minv) < 0:
			errors.append("%s: needs %s >= %s (found %s)" % [pid, did, minv, by_id[did]["version"]])
		dep_ids.append(did)
	dep_ids.sort()
	for did: String in dep_ids:
		_visit(did, by_id, state, order, stack + [pid])
	state[pid] = "done"
	order.append(pid)


func _read_data(m: Dictionary, rel: String, defs: Array, index: Dictionary) -> void:
	var pid: String = m["id"]
	if not _safe_rel(rel):
		errors.append("%s: unsafe data path '%s'" % [pid, rel])
		return
	var path: String = (m["_dir"] as String).path_join(rel)
	var parsed: Variant = _read_json(path)
	if parsed == null:
		return
	if typeof(parsed) != TYPE_DICTIONARY:
		errors.append("%s: a data file must be an object with \"templates\" and/or \"patches\"" % path)
		return
	for d: Variant in parsed.get("templates", []):
		if typeof(d) != TYPE_DICTIONARY:
			errors.append("%s: template entries must be objects" % path)
			continue
		var tid: String = str(d.get("id", ""))
		if index.has(tid):
			errors.append("%s: template '%s' already defined (use a patch)" % [path, tid])
			continue
		var copy: Dictionary = (d as Dictionary).duplicate(true)
		copy["_package"] = pid
		index[tid] = defs.size()
		defs.append(copy)
	for p: Variant in parsed.get("patches", []):
		if typeof(p) != TYPE_DICTIONARY or not index.has(str(p.get("id", ""))):
			errors.append("%s: patch targets unknown template '%s'" % [path, p.get("id") if typeof(p) == TYPE_DICTIONARY else p])
			continue
		var target: Dictionary = defs[index[str(p["id"])]]
		var vals: Dictionary = target.get("values", {})
		_patch(vals, p.get("values", {}))
		target["values"] = vals


static func _patch(into: Dictionary, over: Dictionary) -> void:
	for key: Variant in over:
		var v: Variant = over[key]
		if v == null:
			into.erase(key)
		elif typeof(v) == TYPE_DICTIONARY and typeof(into.get(key)) == TYPE_DICTIONARY:
			_patch(into[key], v)
		else:
			into[key] = v


func _register_asset(m: Dictionary, aid: String, rel: Variant) -> void:
	var pid: String = m["id"]
	if typeof(rel) != TYPE_STRING or not _safe_rel(rel):
		errors.append("%s: unsafe asset path for '%s'" % [pid, aid])
		return
	var ext := (rel as String).get_extension().to_lower()
	if not ASSET_EXTENSIONS.has(ext):
		errors.append("%s: asset '%s' has disallowed type .%s" % [pid, aid, ext])
		return
	assets["%s:%s" % [pid, aid]] = (m["_dir"] as String).path_join(rel)


## Loads an image asset through our own loader (never ResourceLoader on mod
## content, so packages can't smuggle scripts). Returns null if missing.
func load_texture(asset_id: String) -> Texture2D:
	var path: String = assets.get(asset_id, "")
	if path.is_empty():
		return null
	var img := Image.load_from_file(path)
	return ImageTexture.create_from_image(img) if img != null else null


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		errors.append("%s: file not found" % path)
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		errors.append("%s:%d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


static func _safe_rel(rel: String) -> bool:
	if rel.is_empty() or rel.is_absolute_path() or rel.begins_with("/") or rel.contains("\\") or rel.contains(":"):
		return false
	for part in rel.split("/"):
		if part == ".." or part == ".":
			return false
	return true


static func _version(v: String) -> PackedInt64Array:
	var parts := v.split(".")
	if parts.size() != 3:
		return PackedInt64Array()
	var out := PackedInt64Array()
	for p in parts:
		if not p.is_valid_int():
			return PackedInt64Array()
		out.append(int(p))
	return out


static func _compare_versions(a: String, b: String) -> int:
	var va := _version(a)
	var vb := _version(b)
	if va.is_empty() or vb.is_empty():
		return -1
	for i in 3:
		if va[i] != vb[i]:
			return -1 if va[i] < vb[i] else 1
	return 0


static func _hash(t: TemplateTable) -> String:
	var ids := t.ids()
	ids.sort()
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	for tid in ids:
		var line := "%s|%s|%s\n" % [tid, t.kind_of(tid), JSON.stringify(t.values_of(tid), "", true)]
		h.update(line.to_utf8_buffer())
	return h.finish().hex_encode()
