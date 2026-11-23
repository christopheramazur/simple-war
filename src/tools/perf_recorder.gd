class_name PerfRecorder
extends Node
## Opt-in performance capture for playtests. Launch the game with the user
## argument `--perf` (`Godot... --path . -- --perf`) and the main menu starts
## one recorder for the whole run; without it every call here is a no-op.
##
## Every SAMPLE_SEC it appends a row to user://perf/<stamp>/samples.csv:
## frame times over the window (mean, p95, max), Godot's monitors (process
## and physics time, static memory, objects, nodes, orphans, draw calls,
## primitives, video and texture memory) and what is on screen. Code
## sections timed with `begin`/`end` go to sections.csv (count, total and
## max µs per window), and `mark` notes go to marks.csv. Presentation-side
## tooling only: it never touches the simulation's state.

const SAMPLE_SEC: float = 0.25
const DIR := "user://perf"

static var _active: PerfRecorder

var _dir: String = ""
var _samples: FileAccess
var _sections: FileAccess
var _marks: FileAccess
var _t0: int = 0
var _acc: float = 0.0
var _frames: PackedFloat32Array = PackedFloat32Array()
## Section name -> [count, total µs, max µs] for the current window.
var _sec: Dictionary = {}
## Section name -> start µs (sections do not nest by name).
var _open: Dictionary = {}
## What the game is showing, set by the war room ("overworld", "battle", ...).
var context: String = ""
var _last_orphans: int = 0
var _orphan_samples: int = 0


## Starts the recorder once per run if the game was launched with --perf.
static func start_if_requested(tree: SceneTree) -> void:
	if _active != null or not OS.get_cmdline_user_args().has("--perf"):
		return
	var r := PerfRecorder.new()
	r.name = "PerfRecorder"
	r.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child.call_deferred(r)
	_active = r


static func active() -> bool:
	return _active != null


static func begin(section: StringName) -> void:
	if _active != null:
		_active._open[section] = Time.get_ticks_usec()


static func end(section: StringName) -> void:
	if _active == null or not _active._open.has(section):
		return
	var dt: int = Time.get_ticks_usec() - int(_active._open[section])
	_active._open.erase(section)
	var s: Array = _active._sec.get(section, [0, 0, 0])
	s[0] += 1
	s[1] += dt
	s[2] = maxi(s[2], dt)
	_active._sec[section] = s


static func mark(text: String) -> void:
	if _active != null and _active._marks != null:
		_active._marks.store_line("%.3f,%s" % [_active._now(), text.replace(",", ";")])
		_active._marks.flush()


static func set_context(c: String) -> void:
	if _active != null:
		_active.context = c


func _ready() -> void:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	_dir = "%s/%s" % [DIR, stamp]
	DirAccess.make_dir_recursive_absolute(_dir)
	_samples = FileAccess.open(_dir + "/samples.csv", FileAccess.WRITE)
	_samples.store_line("t,frames,fps,frame_ms_mean,frame_ms_p95,frame_ms_max,process_ms,physics_ms,mem_static_mb,mem_static_max_mb,objects,resources,nodes,orphans,draw_calls,primitives,objects_drawn,video_mb,texture_mb,scene,context")
	_sections = FileAccess.open(_dir + "/sections.csv", FileAccess.WRITE)
	_sections.store_line("t,section,count,total_us,max_us")
	_marks = FileAccess.open(_dir + "/marks.csv", FileAccess.WRITE)
	_marks.store_line("t,mark")
	_t0 = Time.get_ticks_usec()
	var info := FileAccess.open(_dir + "/info.txt", FileAccess.WRITE)
	info.store_line("godot %s" % Engine.get_version_info()["string"])
	info.store_line("debug_build %s" % OS.is_debug_build())
	info.store_line("renderer %s / %s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_method()])
	info.store_line("cpu %s (%d cores)" % [OS.get_processor_name(), OS.get_processor_count()])
	info.store_line("window %s vsync %s max_fps %d" % [get_window().size, DisplayServer.window_get_vsync_mode(), Engine.max_fps])
	info.store_line("pid %d" % OS.get_process_id())
	info.close()
	print("PerfRecorder: writing to ", ProjectSettings.globalize_path(_dir))
	mark("start")


func _now() -> float:
	return float(Time.get_ticks_usec() - _t0) / 1e6


func _process(delta: float) -> void:
	_frames.append(delta * 1000.0)
	_acc += delta
	if _acc >= SAMPLE_SEC:
		_acc = 0.0
		_flush()


## sw-mun: orphans that survive two samples (0.5 s, so not a node just queued
## for freeing) are a leak. Notes them in marks.csv and has Godot list them
## (name, class, path where known) on the console; once per new count.
func _watch_orphans(n: int) -> void:
	if n == 0 or n != _last_orphans:
		_orphan_samples = 0 if n == 0 else 1
		_last_orphans = n
		return
	_orphan_samples += 1
	if _orphan_samples == 2:
		mark("orphans=%d (scene %s)" % [n, get_tree().current_scene.name if get_tree().current_scene != null else ""])
		Node.print_orphan_nodes()


func _flush() -> void:
	var t := _now()
	var n := _frames.size()
	var sorted := _frames.duplicate()
	sorted.sort()
	var mean := 0.0
	for f in _frames:
		mean += f
	mean /= maxf(n, 1)
	var p95: float = sorted[mini(int(n * 0.95), n - 1)] if n > 0 else 0.0
	var mx: float = sorted[n - 1] if n > 0 else 0.0
	var scene: String = String(get_tree().current_scene.name) if get_tree().current_scene != null else ""
	var row := [t, n, Performance.get_monitor(Performance.TIME_FPS), mean, p95, mx,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, Performance.get_monitor(Performance.MEMORY_STATIC_MAX) / 1048576.0,
		Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT), Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0]
	var cells := PackedStringArray()
	for v in row:
		cells.append(("%.3f" % v) if v is float else str(v))
	cells.append(scene)
	cells.append(context)
	_samples.store_line(",".join(cells))
	_watch_orphans(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)))
	for s: StringName in _sec:
		var a: Array = _sec[s]
		_sections.store_line("%.3f,%s,%d,%d,%d" % [t, s, a[0], a[1], a[2]])
	_sec.clear()
	_frames.clear()
	_samples.flush()
	_sections.flush()


func _exit_tree() -> void:
	if _samples != null:
		_flush()
		mark("stop")
	if _active == self:
		_active = null
