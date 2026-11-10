extends GutTest
## Package format, loader and schema validation. GDD 03 §3.7. Task sw-cgl.1.

const CORE := "res://data/packages/core"
const TMP := "user://test_packages"


func _write(path: String, data: Variant) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data) if typeof(data) != TYPE_STRING else data)
	f.close()


func _mod(id: String, deps: Array, data_files: Dictionary, extra: Dictionary = {}) -> String:
	var dir := TMP.path_join(id)
	var manifest := {"format": 1, "id": id, "version": "1.0.0", "dependencies": deps, "data": data_files.keys()}
	manifest.merge(extra, true)
	_write(dir.path_join("manifest.json"), manifest)
	for rel: String in data_files:
		if _safe(rel):
			_write(dir.path_join(rel), data_files[rel])
	return dir


func _safe(rel: String) -> bool:
	return not rel.contains("..")


func before_each() -> void:
	_rm(TMP)


func after_all() -> void:
	_rm(TMP)


func _rm(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_rm(path.path_join(sub))
	DirAccess.remove_absolute(path)


func _has(errors: PackedStringArray, fragment: String) -> bool:
	for e in errors:
		if e.contains(fragment):
			return true
	return false


func test_core_package_loads_and_validates() -> void:
	var l := PackageLoader.load_dirs(PackedStringArray([CORE]))
	assert_true(l.is_valid(), "\n".join(l.errors))
	assert_eq(l.package_ids(), PackedStringArray(["core"]))
	assert_eq(l.data_hash.length(), 64)
	assert_eq(l.templates.kind_of("rifle_squad"), "squad")
	assert_eq(l.templates.values_of("hf_militia")["doctrine"], "humanity_first")
	assert_eq(l.templates.values_of("carbine")["damage_type"], "kinetic", "inherited")


func test_hash_is_stable() -> void:
	var a := PackageLoader.load_dirs(PackedStringArray([CORE]))
	var b := PackageLoader.load_dirs(PackedStringArray([CORE]))
	assert_eq(a.data_hash, b.data_hash)


func test_mod_patches_and_adds_after_dependency() -> void:
	var mod := _mod("zz_tweaks", [{"id": "core", "min_version": "0.1.0"}], {
		"defs/tweaks.json": {
			"templates": [{"id": "elite_rifles", "parent": "rifle_squad", "values": {"value": 150}}],
			"patches": [{"id": "rifle", "values": {"range": 45, "modes": {"aimed": {"damage": 4}}}}],
		},
	})
	var l := PackageLoader.load_dirs(PackedStringArray([mod, CORE]))
	assert_true(l.is_valid(), "\n".join(l.errors))
	assert_eq(l.package_ids(), PackedStringArray(["core", "zz_tweaks"]), "dependency first")
	assert_eq(l.templates.values_of("rifle")["range"], 45)
	assert_eq(l.templates.values_of("rifle")["modes"]["aimed"]["damage"], 4)
	assert_eq(l.templates.values_of("rifle")["modes"]["aimed"]["shots"], 1, "rest kept")
	assert_eq(l.templates.values_of("carbine")["modes"]["aimed"]["damage"], 4, "children see the patch")
	assert_eq(l.templates.values_of("elite_rifles")["value"], 150)
	var core_only := PackageLoader.load_dirs(PackedStringArray([CORE]))
	assert_ne(l.data_hash, core_only.data_hash)


func test_rejects_bad_packages() -> void:
	var cyc_a := _mod("cyc_a", [{"id": "cyc_b"}], {})
	var cyc_b := _mod("cyc_b", [{"id": "cyc_a"}], {})
	var missing := _mod("needs_ghost", [{"id": "ghost"}], {})
	var old := _mod("needs_new_core", [{"id": "core", "min_version": "9.0.0"}], {})
	var unsafe := _mod("unsafe", [], {"../escape.json": {}}, {"assets": {"evil": "x.gd"}})
	var l := PackageLoader.load_dirs(PackedStringArray([CORE, cyc_a, cyc_b, missing, old, unsafe]))
	assert_false(l.is_valid())
	assert_true(_has(l.errors, "dependency cycle"), "\n".join(l.errors))
	assert_true(_has(l.errors, "missing dependency 'ghost'"), "\n".join(l.errors))
	assert_true(_has(l.errors, "needs core >= 9.0.0"), "\n".join(l.errors))
	assert_true(_has(l.errors, "unsafe data path"), "\n".join(l.errors))
	assert_true(_has(l.errors, "disallowed type .gd"), "\n".join(l.errors))


func test_schema_errors_are_reported() -> void:
	var mod := _mod("broken", [{"id": "core"}], {
		"defs/bad.json": {
			"templates": [
				{"id": "bad_squad", "parent": "rifle_squad", "values": {"value": -5, "sight": "far", "colour": "red"}},
				{"id": "bad_unit", "kind": "unit", "values": {"hp": 5, "defense": "rifle", "movement": "foot"}},
			],
			"patches": [{"id": "nonexistent", "values": {}}],
		},
	})
	var l := PackageLoader.load_dirs(PackedStringArray([CORE, mod]))
	assert_true(_has(l.errors, "'value' below minimum"), "\n".join(l.errors))
	assert_true(_has(l.errors, "'sight' must be an integer or decimal string"), "\n".join(l.errors))
	assert_true(_has(l.errors, "unknown field 'colour'"), "\n".join(l.errors))
	assert_true(_has(l.errors, "'defense' must reference a defense template"), "\n".join(l.errors))
	assert_true(_has(l.errors, "patch targets unknown template 'nonexistent'"), "\n".join(l.errors))


func test_load_roots_discovers_packages() -> void:
	_mod("found_me", [{"id": "core"}], {})
	var l := PackageLoader.load_roots(PackedStringArray(["res://data/packages", TMP]))
	assert_true(l.is_valid(), "\n".join(l.errors))
	assert_eq(l.package_ids(), PackedStringArray(["core", "found_me"]))
