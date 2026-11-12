class_name PackageEditor
extends RefCounted
## The data editor's model (GDD 04 §4.9, R8Q7): one content package's
## templates, browsable by kind with flattened values and provenance,
## validated as the game would load them, and edited one template at a
## time. Edits are textual: a template's own span in its JSON file is
## replaced and nothing else in the file changes, so hand formatting and
## diffs survive. Every edit is validated against the whole package first
## (schema, then each map, scenario and the glossary compiling) and refused
## if anything breaks. The future in-game campaign editor reuses this.

var dir: String = ""
## Load and parse problems (the package as it is on disk).
var errors: PackedStringArray = PackedStringArray()
var templates: TemplateTable
## Data files of the package (manifest "data", relative).
var files: PackedStringArray = PackedStringArray()
## Template ID -> data file (relative).
var _file_of: Dictionary = {}
## Data file -> its text.
var _text: Dictionary = {}


static func open(package_dir: String) -> PackageEditor:
	var e := PackageEditor.new()
	e.dir = package_dir
	e.reload()
	return e


func reload() -> void:
	errors = PackedStringArray()
	files = PackedStringArray()
	_file_of = {}
	_text = {}
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("manifest.json")))
	if typeof(manifest) != TYPE_DICTIONARY:
		errors.append("unreadable manifest.json")
		return
	for rel: String in (manifest as Dictionary).get("data", []):
		files.append(rel)
		var text := FileAccess.get_file_as_string(dir.path_join(rel))
		_text[rel] = text
		for id: String in spans(text):
			_file_of[id] = rel
	var loader := PackageLoader.load_dirs(PackedStringArray([dir]))
	templates = loader.templates
	errors.append_array(loader.errors)
	if templates != null and loader.errors.is_empty():
		errors.append_array(check(templates))


# --- browsing ------------------------------------------------------------------

func kinds() -> PackedStringArray:
	var out := {}
	for id in templates.ids():
		out[templates.kind_of(id)] = true
	var k := PackedStringArray(out.keys())
	k.sort()
	return k


func ids_of(kind: String) -> PackedStringArray:
	var out := PackedStringArray()
	for id in templates.ids():
		if templates.kind_of(id) == kind:
			out.append(id)
	out.sort()
	return out


func file_of(id: String) -> String:
	return _file_of.get(id, "")


## The template's definition exactly as written in its file.
func definition_text(id: String) -> String:
	var rel := file_of(id)
	if rel.is_empty():
		return ""
	var span: Array = spans(_text[rel])[id]
	return (_text[rel] as String).substr(span[0], span[1] - span[0])


## Flattened values with the template that set each top-level field:
## [{"field", "value", "from"}].
func flattened(id: String) -> Array:
	var out := []
	var v := templates.values_of(id)
	var keys := v.keys()
	keys.sort()
	for k: String in keys:
		out.append({"field": k, "value": v[k], "from": templates.provenance(id, k)})
	return out


# --- validation ----------------------------------------------------------------

## What loading would reject beyond the schema: every overworld map and
## scenario must compile, and the glossary too.
static func check(t: TemplateTable) -> PackedStringArray:
	var out := PackedStringArray()
	for id in t.ids():
		if t.is_abstract(id):
			continue
		match t.kind_of(id):
			"overworld_map":
				for e in OverworldRules.compile(t, id).errors:
					out.append("%s: %s" % [id, e])
			"scenario":
				for e in BattleRules.compile(t, id).errors:
					out.append("%s: %s" % [id, e])
	for e in Glossary.from_templates(t).errors:
		out.append("glossary: " + e)
	return out


## Errors the package would have with template `id` replaced by `text`
## (or, with id "", `text` added to `file`). Empty = safe to write.
func preview(id: String, text: String, file: String = "") -> PackedStringArray:
	var j := JSON.new()
	if j.parse(text) != OK:
		return PackedStringArray(["not valid JSON (line %d): %s" % [j.get_error_line(), j.get_error_message()]])
	var parsed: Variant = j.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return PackedStringArray(["not a JSON object"])
	var def: Dictionary = parsed
	if not id.is_empty() and str(def.get("id", "")) != id:
		return PackedStringArray(["the id must stay '%s' (add a new template instead)" % id])
	if id.is_empty():
		if str(def.get("id", "")).is_empty():
			return PackedStringArray(["a template needs an id"])
		if _file_of.has(str(def["id"])):
			return PackedStringArray(["'%s' already exists" % def["id"]])
		if not files.has(file):
			return PackedStringArray(["unknown data file '%s'" % file])
	var defs := []
	for rel in files:
		var data: Variant = JSON.parse_string(_text[rel])
		for d: Dictionary in (data as Dictionary).get("templates", []):
			defs.append(def if not id.is_empty() and str(d.get("id", "")) == id else d)
	if id.is_empty():
		defs.append(def)
	var t := TemplateTable.build(defs)
	if not t.is_valid():
		return t.errors
	var out := DataSchema.validate(t)
	if out.is_empty():
		out = check(t)
	return out


## Replaces one template's text in its file. Returns the errors (nothing is
## written unless there are none).
func replace(id: String, text: String) -> PackedStringArray:
	var rel := file_of(id)
	if rel.is_empty():
		return PackedStringArray(["unknown template '%s'" % id])
	var errs := preview(id, text)
	if not errs.is_empty():
		return errs
	var old: String = _text[rel]
	var span: Array = spans(old)[id]
	_write(rel, old.substr(0, span[0]) + text + old.substr(span[1]))
	return errs


## Appends a new template at the end of a data file's template list.
func add(text: String, file: String) -> PackedStringArray:
	var errs := preview("", text, file)
	if not errs.is_empty():
		return errs
	var old: String = _text[file]
	var close := _list_end(old)
	var head := old.substr(0, close).rstrip(" \t\r\n")
	var sep := "," if not head.ends_with("[") else ""
	_write(file, head + sep + "\n\t\t" + text + "\n\t" + old.substr(close))
	return errs


func _write(rel: String, text: String) -> void:
	var f := FileAccess.open(dir.path_join(rel), FileAccess.WRITE)
	f.store_string(text)
	f.close()
	reload()


# --- spans -----------------------------------------------------------------------

## Template ID -> [start, end) of its object in a data file's text: the
## top-level objects of the "templates" array, found by brace matching
## that skips strings.
static func spans(text: String) -> Dictionary:
	var out := {}
	var start := _list_start(text)
	if start < 0:
		return out
	var i := start
	var depth := 0
	var obj_start := -1
	var in_str := false
	while i < text.length():
		var c := text[i]
		if in_str:
			if c == "\\":
				i += 1
			elif c == "\"":
				in_str = false
		elif c == "\"":
			in_str = true
		elif c == "{" or c == "[":
			if depth == 0 and c == "{":
				obj_start = i
			depth += 1
		elif c == "}" or c == "]":
			depth -= 1
			if depth < 0:
				break
			if depth == 0 and c == "}" and obj_start >= 0:
				var j := JSON.new()
				var d: Variant = j.data if j.parse(text.substr(obj_start, i + 1 - obj_start)) == OK else null
				if typeof(d) == TYPE_DICTIONARY and (d as Dictionary).has("id"):
					out[str(d["id"])] = [obj_start, i + 1]
				obj_start = -1
		i += 1
	return out


## Index just after the "templates" array's "[".
static func _list_start(text: String) -> int:
	var k := text.find("\"templates\"")
	if k < 0:
		return -1
	var b := text.find("[", k)
	return b + 1 if b >= 0 else -1


## Index of the "]" closing the "templates" array.
static func _list_end(text: String) -> int:
	var i := _list_start(text)
	var depth := 0
	var in_str := false
	while i < text.length():
		var c := text[i]
		if in_str:
			if c == "\\":
				i += 1
			elif c == "\"":
				in_str = false
		elif c == "\"":
			in_str = true
		elif c == "{" or c == "[":
			depth += 1
		elif c == "}" or c == "]":
			if depth == 0:
				return i
			depth -= 1
		i += 1
	return text.length()
