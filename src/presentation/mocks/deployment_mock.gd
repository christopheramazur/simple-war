extends RefCounted
## Mock (sw-bafi.12): battle deployment on turn 1. The scenario's own squads
## stand in the player's area; the first one is placed 10 m forward and
## turned, two are selected, and a group drag is in progress: the anchor's
## ghost sits in the area, the other ghost is pushed to the area's edge
## with a cross where its drop point was refused. Both sides' areas show:
## the player's lit, the enemy's hatched and labelled.
## Render with `hx godot mock res://src/presentation/mocks/deployment_mock.gd`.

const ONE := Fixed.ONE


static func build() -> Control:
	var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	var r := BattleRules.compile(l.templates, "duel_crossroads", l.data_hash)
	var s := BattleSetup.create(1, r, 5)
	s.deploying = r.deployment_open
	var obs := BattleSession.observe_state(s, 1)
	var pl := BattlePlanner.new(1)
	pl.rules = r
	pl.sync(obs)
	var ids := pl.own_squads()
	var pos := {}
	for sq: Dictionary in obs.get("squads", []):
		pos[sq["id"]] = Vector2(float(sq["x"]) / ONE, float(sq["y"]) / ONE)
	if ids.size() > 0:
		pl.place(ids[0], pos[ids[0]] + Vector2(10, 0))
		pl.rotate([ids[0]], 1)
	if ids.size() >= 2:
		pl.select([ids[0], ids[1]])
	var root := Control.new()
	root.custom_minimum_size = Vector2(1280, 800)
	var v := ContextView.new()
	v.art = ArtSet.core()
	v.terrain_colors = ContextView.feature_colors(l.templates)
	v.custom_minimum_size = Vector2(1280, 800)
	v.size = Vector2(1280, 800)
	v.title = "Turn 1 deployment: two squads selected, one dragged to a refused spot"
	root.add_child(v)
	v.set_meta(&"planner", pl)  # the overlay's snap Callable needs it alive
	v.show_battle(pl.deploy_view(obs), {"deploy": {"player": 1, "areas": pl.areas, "own": pl.own_squads(), "snap": pl.snap}, "selected": pl.selection, "drafts": {}, "terrain": r})
	# A group drag in progress: the view needs a size before points map to metres.
	v.size = Vector2(1280, 800)
	var anchor_at: Vector2 = pos[ids[0]] + Vector2(10, 0)
	var far := Vector2(pl.area.end.x + 30, pl.area.get_center().y)
	v._drag_kind = "squad"
	v._drag_ids = pl.selection.duplicate()
	v._drag_anchor = ids[0] if ids.size() > 0 else -1
	v._press_at = v.to_view(anchor_at)
	v._drag_at = v.to_view(far)
	v.queue_redraw()
	return root
