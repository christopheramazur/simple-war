extends SceneTree
## Bench (sw-63wt.5): mean µs per ContextView overworld draw on the war room
## demo map (WarRoom.demo_session, player 1), a fixed 1230 x 680 view and
## camera. Run with
## `hx godot run res://src/tools/bench_overworld_draw.gd -- <zoom> [frames]`.

const VIEW := Vector2(1230, 680)


class TimedView extends ContextView:
	var total_us: int = 0
	var draws: int = 0

	func _draw() -> void:
		var t := Time.get_ticks_usec()
		super()
		total_us += Time.get_ticks_usec() - t
		draws += 1


var _view: TimedView
var _frames: int = 0
var _want: int = 300
var _zoom: float = 1.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var zoom := float(args[0]) if args.size() > 0 else 1.0
	_zoom = zoom
	if args.size() > 1:
		_want = int(args[1])
	var session := WarRoom.demo_session()
	var obs := session.observe(1)
	var ctx := ViewContexts.new(1)
	ctx.sync(obs)
	ctx.zoom = zoom
	_view = TimedView.new()
	_view.size = VIEW
	_view.art = ArtSet.core()
	_view.commander_ids = session.rules.commander_ids
	_view.feature_info = ContextView.hex_feature_info(session.templates)
	root.add_child(_view)
	_view.size = VIEW
	_view.show_overworld(obs, session.rules.feature_ids, ctx)


func _process(_delta: float) -> bool:
	_frames += 1
	_view.queue_redraw()
	if _frames < _want:
		return false
	print("BENCH draw_overworld zoom=%.3f draws=%d mean_us=%.1f" % [
		_zoom, _view.draws, float(_view.total_us) / maxf(_view.draws, 1)])
	return true
