class_name UiPanel
extends VBoxContainer
## Panel content as data (sw-ijp.4). A panel spec (`res://data/ui/panels/
## <id>.json`) lists sections; a read-only view model (a Dictionary the
## caller builds from the game's own answers) fills them. The panel never
## reads game state and never changes it: a button only emits `action_invoked`
## with the spec's action id and the arguments it bound from the model, and
## the screen decides what that does. No logic in the spec: it binds model
## keys (dotted paths) to a small set of widgets (GDD 04, R4Q20).
##
## Sections ("kind"):
##   label   bind (a model key) or text (literal), style, wrap
##   lines   bind (a list of {text, tone}), styles (tone -> style), default_style, wrap
##   button  bind (the text key) or text, disabled (a key), action (an id), args (keys), wrap
##   list    bind (a list), each (sections, run once per item with the item as the model)
##   row     sections (laid out side by side)
##   bar     bind (a {name, frac, tone, text} dict): a named stat bar
##   meter   bind (a {pool, label, label_style, tone, pct, floors, text, tip,
##           label_tip} dict): a segmented meter, segment edges and ticks at
##           the band floors (percent), text beside it, tips on hover
##   kv      bind (a {key, values: [{text, tone}]} dict), styles (tone -> style),
##           key_style: a dim key followed by values side by side
##   progress bind (a {frac} dict, 0..1): a thin progress bar
## A label also takes style_bind (a key holding its style) and tip (a key
## holding its tooltip).
## Every section also takes "show" (a key: drawn only when it is truthy).
## The top level is {"gap", "min_width", "sections"}.

signal action_invoked(action: String, args: Array)

const SHIPPED_DIR := "res://data/ui/panels"
const KINDS: Array[String] = ["label", "lines", "button", "list", "row", "bar", "meter", "kv", "progress"]
const KEYS: Dictionary = {
	"label": ["kind", "bind", "text", "style", "style_bind", "tip", "wrap", "show"],
	"bar": ["kind", "bind", "show"],
	"meter": ["kind", "bind", "show"],
	"kv": ["kind", "bind", "styles", "key_style", "show"],
	"progress": ["kind", "bind", "show"],
	"lines": ["kind", "bind", "styles", "default_style", "wrap", "show"],
	"button": ["kind", "bind", "text", "disabled", "action", "args", "wrap", "show"],
	"list": ["kind", "bind", "each", "show"],
	"row": ["kind", "sections", "show"],
}

static var _cache: Dictionary = {}


## The spec `id`, or {} (with an error pushed) if it is missing or invalid.
static func spec(id: String) -> Dictionary:
	if _cache.has(id):
		return _cache[id]
	var path := "%s/%s.json" % [SHIPPED_DIR, id]
	var out := {}
	if not FileAccess.file_exists(path):
		push_error("UiPanel: no panel spec " + path)
	else:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		var errors := validate(data)
		if errors.is_empty():
			out = data
		else:
			push_error("UiPanel: %s is not used: %s" % [path, "; ".join(errors)])
	_cache[id] = out
	return out


## What is wrong with a spec ([] if nothing).
static func validate(data: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if not data is Dictionary or not (data as Dictionary).get("sections") is Array:
		out.append("a panel needs a \"sections\" list")
		return out
	_check(data["sections"], out, "sections")
	return out


static func _check(sections: Array, out: PackedStringArray, where: String) -> void:
	for i in sections.size():
		var s: Variant = sections[i]
		var at := "%s[%d]" % [where, i]
		if not s is Dictionary:
			out.append("%s must be an object" % at)
			continue
		var kind := str(s.get("kind", ""))
		if not kind in KINDS:
			out.append("%s: unknown kind '%s'" % [at, kind])
			continue
		for k: String in s:
			if not k in KEYS[kind]:
				out.append("%s: '%s' has no key '%s'" % [at, kind, k])
		match kind:
			"list":
				if str(s.get("bind", "")).is_empty() or not s.get("each") is Array:
					out.append("%s: a list needs bind and an each list" % at)
				else:
					_check(s["each"], out, at + ".each")
			"row":
				if not s.get("sections") is Array:
					out.append("%s: a row needs sections" % at)
				else:
					_check(s["sections"], out, at + ".sections")
			"button":
				if str(s.get("action", "")).is_empty():
					out.append("%s: a button needs an action id" % at)
			"lines", "bar", "meter", "kv", "progress":
				if str(s.get("bind", "")).is_empty():
					out.append("%s: %s needs bind" % [at, kind])


## A panel for the spec `id` filled from `model`.
static func build(id: String, model: Dictionary) -> UiPanel:
	var p := UiPanel.new()
	p.show_model(spec(id), model)
	return p


## (Re)builds the content from `spec_data` and `model`.
func show_model(spec_data: Dictionary, model: Dictionary) -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	if spec_data.is_empty():
		return
	if spec_data.has("gap"):
		theme_type_variation = StringName(str(spec_data["gap"]))
	if spec_data.has("min_width"):
		custom_minimum_size = Vector2(float(spec_data["min_width"]), 0)
	_fill(self, spec_data["sections"], model)


func _fill(into: Container, sections: Array, model: Dictionary) -> void:
	for s: Dictionary in sections:
		if s.has("show") and not _truthy(lookup(model, str(s["show"]))):
			continue
		match str(s["kind"]):
			"label":
				var text := str(lookup(model, str(s["bind"]))) if s.has("bind") else str(s.get("text", ""))
				var style := str(lookup(model, str(s["style_bind"]))) if s.has("style_bind") else str(s.get("style", ""))
				var l := UiTheme.label(text, style, bool(s.get("wrap", false)))
				var tip := str(lookup(model, str(s["tip"]))) if s.has("tip") else ""
				if not tip.is_empty() and tip != "<null>":
					l.mouse_filter = Control.MOUSE_FILTER_STOP
					l.tooltip_text = tip
				into.add_child(l)
			"bar":
				var d: Variant = lookup(model, str(s["bind"]))
				if d is Dictionary:
					into.add_child(_bar(d))
			"meter":
				var d: Variant = lookup(model, str(s["bind"]))
				if d is Dictionary:
					into.add_child(_meter(d))
			"kv":
				var d: Variant = lookup(model, str(s["bind"]))
				if d is Dictionary:
					var styles: Dictionary = s.get("styles", {})
					var kr := HBoxContainer.new()
					kr.add_child(UiTheme.label(str(d.get("key", "")), str(s.get("key_style", ""))))
					for v: Dictionary in d.get("values", []):
						kr.add_child(UiTheme.label(str(v.get("text", "")), str(styles.get(str(v.get("tone", "")), ""))))
					into.add_child(kr)
			"progress":
				var f: Variant = lookup(model, str(s["bind"]))
				if f is Dictionary:
					into.add_child(_progress(float(f.get("frac", 0.0))))
			"lines":
				var styles: Dictionary = s.get("styles", {})
				var fallback := str(s.get("default_style", ""))
				for line: Variant in _list(lookup(model, str(s["bind"]))):
					var d: Dictionary = line if line is Dictionary else {"text": str(line)}
					into.add_child(UiTheme.label(str(d.get("text", "")), str(styles.get(str(d.get("tone", "")), fallback)), bool(s.get("wrap", true))))
			"button":
				var b := Button.new()
				b.text = str(lookup(model, str(s["bind"]))) if s.has("bind") else str(s.get("text", ""))
				if bool(s.get("wrap", true)):
					b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				b.disabled = s.has("disabled") and _truthy(lookup(model, str(s["disabled"])))
				var args := []
				for k: Variant in s.get("args", []):
					args.append(lookup(model, str(k)))
				var action := str(s["action"])
				b.set_meta(&"action", action)
				if not b.disabled:
					b.pressed.connect(func() -> void: action_invoked.emit(action, args))
				into.add_child(b)
			"list":
				for item: Variant in _list(lookup(model, str(s["bind"]))):
					_fill(into, s["each"], item if item is Dictionary else {"value": item})
			"row":
				var row := HBoxContainer.new()
				_fill(row, s["sections"], model)
				into.add_child(row)


static func _tone_ok(tone: String) -> String:
	return tone if (UiTheme.styles().get("tones", {}) as Dictionary).has(tone) else "Text"


static func _bar(d: Dictionary) -> Control:
	var tone := _tone_ok(str(d.get("tone", "Text")))
	var row := HBoxContainer.new()
	var l := UiTheme.label(str(d.get("name", "")), "Caption%sLabel" % tone)
	l.custom_minimum_size = Vector2(62, 0)
	row.add_child(l)
	var c := Control.new()
	c.custom_minimum_size = Vector2(70, 6)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.add_child(UiTheme.backdrop("LineBar"))
	var fill := Panel.new()
	fill.theme_type_variation = "%sBar" % tone
	fill.anchor_right = clampf(float(d.get("frac", 0.0)), 0.0, 1.0)
	fill.anchor_bottom = 1.0
	c.add_child(fill)
	row.add_child(c)
	var text := str(d.get("text", ""))
	if not text.is_empty():
		row.add_child(UiTheme.label(text, "CaptionDimLabel"))
	return row


static func _progress(frac: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(120, 5)
	c.add_child(UiTheme.backdrop("LineBar"))
	var f := Panel.new()
	f.theme_type_variation = "%sBar" % ("Accent" if (UiTheme.styles().get("tones", {}) as Dictionary).has("Accent") else "Text")
	f.anchor_right = clampf(frac, 0.0, 1.0)
	f.anchor_bottom = 1.0
	c.add_child(f)
	return c


static func _meter(d: Dictionary) -> Control:
	var tone := _tone_ok(str(d.get("tone", "Text")))
	var floors: Array = d.get("floors", [])
	var pct := float(d.get("pct", 0.0))
	var row := HBoxContainer.new()
	var l := UiTheme.label(str(d.get("label", "")), str(d.get("label_style", "")))
	l.custom_minimum_size = Vector2(80, 0)
	l.set_meta(&"pool", str(d.get("pool", "")))
	if not str(d.get("label_tip", "")).is_empty():
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		l.tooltip_text = str(d["label_tip"])
	row.add_child(l)
	var c := Control.new()
	# Narrow minimum, fills the room there is: the card fits its column (sw-7m6).
	c.custom_minimum_size = Vector2(60, 8)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.add_child(UiTheme.backdrop("ScreenBackgroundPanel"))
	for b in floors.size():
		var lo := 0.0 if b == 0 else float(floors[b])
		var hi := float(floors[b + 1]) if b + 1 < floors.size() else 100.0
		var seg := Panel.new()
		seg.theme_type_variation = "LineBar"
		seg.set_meta(&"band", b)
		seg.anchor_left = lo / 100.0
		seg.anchor_right = hi / 100.0
		seg.anchor_bottom = 1.0
		seg.offset_left = 1.0
		seg.offset_right = -1.0
		c.add_child(seg)
		var fill := clampf((pct - lo) / (hi - lo), 0.0, 1.0) if hi > lo else 0.0
		if fill > 0.0:
			var f := Panel.new()
			f.theme_type_variation = "%sBar" % tone
			f.anchor_right = fill
			f.anchor_bottom = 1.0
			seg.add_child(f)
	# Ticks at every inner floor, a little taller than the bar.
	for b in range(1, floors.size()):
		var tick := Panel.new()
		tick.theme_type_variation = "DimBar"
		tick.set_meta(&"tick", int(floors[b]))
		tick.anchor_left = float(floors[b]) / 100.0
		tick.anchor_right = tick.anchor_left
		tick.anchor_bottom = 1.0
		tick.offset_left = -1.0
		tick.offset_top = -2.0
		tick.offset_bottom = 2.0
		c.add_child(tick)
	row.add_child(c)
	row.add_child(UiTheme.label(str(d.get("text", "")), "CaptionDimLabel"))
	row.tooltip_text = str(d.get("tip", ""))
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.focus_mode = Control.FOCUS_ALL  # reachable by keyboard (sw-1jy.6)
	return row


## The value at a dotted path in `model` (null if absent).
static func lookup(model: Dictionary, path: String) -> Variant:
	var cur: Variant = model
	for part in path.split("."):
		if cur is Dictionary and (cur as Dictionary).has(part):
			cur = cur[part]
		else:
			return null
	return cur


static func _list(v: Variant) -> Array:
	if v is Array:
		return v
	return Array(v) if v is PackedStringArray else []


static func _truthy(v: Variant) -> bool:
	if v == null:
		return false
	if v is Array or v is Dictionary or v is String:
		return not v.is_empty()
	return bool(v)
