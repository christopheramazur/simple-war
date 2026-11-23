extends SceneTree
## hx godot check helper: flags `x.method(` calls where x is declared with a native Godot class type
## (param, `var x: T`, `var x := T.new()`, `for x: T`) and ClassDB says T (or a parent) has no such method.
## GDScript's own analyzer only fails these at runtime. Heuristic, per function; prints `NMLINT <res>:<line>: msg`.
## Usage: godot --headless --script harness/godot/native_method_lint.gd -- res://a.gd res://b.gd

var _decl := RegEx.new()
var _decl_new := RegEx.new()
var _call := RegEx.new()
var _func := RegEx.new()

func _init() -> void:
	_decl.compile(r"\b(\w+)\s*:\s*([A-Z]\w*)\s*(?=[,)=\n]|$)")
	_decl_new.compile(r"\bvar\s+(\w+)\s*:?=\s*([A-Z]\w*)\.new\(")
	_call.compile(r"(?<![\w.\]\)])(\w+)\.(\w+)\(")
	_func.compile(r"^\s*(static\s+)?func\s")
	for path in OS.get_cmdline_user_args():
		_lint(path)
	quit()

func _lint(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var types := {}  # var name -> native class, reset per function
	var n := 0
	while not f.eof_reached():
		var line := f.get_line()
		n += 1
		var code := line.split("#")[0]  # crude: strings containing # are rare enough
		if _func.search(code):
			types = {}
		var skip := code.strip_edges().begins_with("class ")
		for m in _decl.search_all(code):
			var t := m.get_string(2)
			if ClassDB.class_exists(t):
				types[m.get_string(1)] = t
			else:
				types.erase(m.get_string(1))  # a script class shadows: stop tracking
		for m in _decl_new.search_all(code):
			var t := m.get_string(2)
			if ClassDB.class_exists(t):
				types[m.get_string(1)] = t
		if skip:
			continue
		for m in _call.search_all(code):
			var v := m.get_string(1)
			var meth := m.get_string(2)
			if types.has(v) and not ClassDB.class_has_method(types[v], meth, false) and meth != "new":
				print("NMLINT %s:%d: %s is %s, which has no method %s()" % [path, n, v, types[v], meth])
