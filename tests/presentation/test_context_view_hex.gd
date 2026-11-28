extends GutTest
## ContextView's hex view (sw-63wt.5, GDD 04 §4.8): plot_at and feature_at
## at the floor, default and ceiling zooms, the layout cache and the zoom
## constants.

const NAMES := ["hex_plains", "hex_road", "hex_village", "hex_depot", "hex_mine", "hex_forest"]
const VALUES := {
	"hex_plains": {"layer": "ground", "draw_order": 0, "color": "5d6b4c", "name": "Plains"},
	"hex_forest": {"layer": "ground", "draw_order": 2, "color": "3f5a40", "name": "Forest"},
	"hex_road": {"layer": "path", "color": "8b8476", "name": "Road"},
	"hex_village": {"layout_priority": 3, "color": "b9a46a", "name": "Village"},
	"hex_depot": {"layout_priority": 2, "color": "8f8a6c", "name": "Supply depot",
		"produces": [{"squad": "x", "turns": 2}]},
	"hex_mine": {"layout_priority": 2, "color": "6f6a64", "name": "Mine"},
}
const W := 4
const H := 3
const VIEW := Vector2(900, 700)
## Plot 5 (col 1, row 1): three sites. Plot 6: a village on a road running
## east into plot 7. Plot 9: forest over plains, no sites.
const THREE := 5
const ROADED := 6


func _plots() -> Dictionary:
	var plots := {}
	var fid := 100
	for p in W * H:
		plots[p] = {"visible": true, "turn": 0, "features": [{"id": fid, "tmpl": 0, "owner": 0}]}
		fid += 1
	var f5: Array = plots[THREE]["features"]
	f5.append({"id": 51, "tmpl": 4, "owner": 0})
	f5.append({"id": 52, "tmpl": 2, "owner": 1})
	f5.append({"id": 53, "tmpl": 3, "owner": 1})
	(plots[ROADED]["features"] as Array).append_array([{"id": 61, "tmpl": 1, "owner": 0}, {"id": 62, "tmpl": 2, "owner": 2}])
	(plots[7]["features"] as Array).append({"id": 71, "tmpl": 1, "owner": 0})
	(plots[9]["features"] as Array).append({"id": 91, "tmpl": 5, "owner": 0})
	return plots


func _info() -> Dictionary:
	var out := {}
	for id: String in VALUES:
		out[id] = ContextView.hex_info(id, VALUES[id])
	return out


func _view(zoom: float, obs: Dictionary = {}) -> ContextView:
	var v: ContextView = autofree(ContextView.new())
	v.size = VIEW
	v.feature_info = _info()
	var ctx := ViewContexts.new(1)
	ctx.camera_plot = THREE
	ctx.zoom = zoom
	if obs.is_empty():
		obs = {"width": W, "height": H, "plots": _plots()}
	v.show_overworld(obs, PackedStringArray(NAMES), ctx)
	return v


## A plot's centre on screen (the camera's plot sits at the view's centre).
func _at(p: int, zoom: float) -> Vector2:
	return VIEW / 2.0 + _raw(p, zoom) - _raw(THREE, zoom)


func _raw(p: int, zoom: float) -> Vector2:
	var s := ContextView.HEX_SIZE * zoom
	var col := p % W
	var row := p / W
	return Vector2(sqrt(3.0) * s * (col + 0.5 * (row & 1)), 1.5 * s * row)


## Where a site of plot p is drawn: HexLayout's point, scaled.
func _site(p: int, zoom: float, sites: Array, roads: PackedInt32Array, i: int) -> Vector2:
	var lay := HexLayout.compute(sites, roads)
	return _at(p, zoom) + Vector2(lay["points"][i]) * (ContextView.HEX_SIZE * zoom / 1000.0)


func test_plot_at_three_zooms() -> void:
	for z: float in [ViewContexts.ZOOM_MIN, ViewContexts.ZOOM_DEFAULT, ViewContexts.ZOOM_MAX]:
		var v := _view(z)
		for p in W * H:
			var c := _at(p, z)
			if Rect2(Vector2.ZERO, VIEW).has_point(c):
				assert_eq(v.plot_at(c), p, "zoom %s: centre of plot %d" % [z, p])
		var s := ContextView.HEX_SIZE * z
		assert_eq(v.plot_at(_at(THREE, z) + Vector2(s * 0.8, 0)), THREE, "zoom %s: inside near the east side" % z)
		assert_eq(v.plot_at(_at(THREE, z) + Vector2(s * 0.9, 0)), THREE + 1, "zoom %s: past the east side" % z)


func test_feature_at_three_sites() -> void:
	# Slot order: village (priority 3) first, then depot and mine (2, by ID).
	var sites := [{"id": "hex_mine", "priority": 2}, {"id": "hex_village", "priority": 3}, {"id": "hex_depot", "priority": 2}]
	for z: float in [ViewContexts.ZOOM_DEFAULT, ViewContexts.ZOOM_MAX]:
		var v := _view(z)
		assert_eq(v.feature_at(_site(THREE, z, sites, PackedInt32Array(), 0)), 51, "zoom %s: the mine" % z)
		assert_eq(v.feature_at(_site(THREE, z, sites, PackedInt32Array(), 1)), 52, "zoom %s: the village" % z)
		assert_eq(v.feature_at(_site(THREE, z, sites, PackedInt32Array(), 2)), 53, "zoom %s: the depot" % z)
		var s := ContextView.HEX_SIZE * z
		assert_eq(v.feature_at(_at(THREE, z) + Vector2(0, s * 0.62)), -1, "zoom %s: the lane is open ground" % z)
		assert_eq(v.feature_at(_at(9, z)), -1, "zoom %s: ground only" % z)
	# Floor zoom (s = 16, below the glyph band): one glyph per hex, its first site.
	var lo := _view(ViewContexts.ZOOM_MIN)
	assert_eq(lo.feature_at(_at(THREE, ViewContexts.ZOOM_MIN)), 52, "glyph: the first site (village)")
	assert_eq(lo.feature_at(_at(THREE, ViewContexts.ZOOM_MIN) + Vector2(0, 10)), -1, "outside the glyph")
	assert_eq(lo.feature_at(_at(9, ViewContexts.ZOOM_MIN)), -1, "no glyph on a ground-only hex")


func test_village_on_a_road_stands_off_it() -> void:
	var sites := [{"id": "hex_village", "priority": 3}]
	var roads := PackedInt32Array([0])  # east, into plot 7
	for z: float in [ViewContexts.ZOOM_DEFAULT, ViewContexts.ZOOM_MAX]:
		var v := _view(z)
		var at := _site(ROADED, z, sites, roads, 0)
		assert_eq(v.feature_at(at), 62, "zoom %s: the village where HexLayout put it" % z)
		assert_eq(v.feature_at(_at(ROADED, z)), -1, "zoom %s: the road through the centre is not a site" % z)
		assert_true(at.distance_to(_at(ROADED, z)) > 0.25 * ContextView.HEX_SIZE * z, "offset off the road")


func test_off_view_and_unknown() -> void:
	var v := _view(1.0)
	assert_eq(v.plot_at(Vector2(-5000, -5000)), -1)
	assert_eq(v.feature_at(Vector2(-5000, -5000)), -1)
	var plots := _plots()
	plots.erase(THREE)  # fogged: nothing known there
	var fog := _view(1.0, {"width": W, "height": H, "plots": plots})
	assert_eq(fog.feature_at(_at(THREE, 1.0)), -1, "an unknown hex has no sites")


func test_layout_cache_keeps_unchanged_plots_and_redoes_changed_ones() -> void:
	var obs := {"width": W, "height": H, "plots": _plots()}
	var v := _view(1.0, obs)
	var before: Dictionary = v._layouts[THREE]
	var road_before: Dictionary = v._layouts[ROADED]
	var ctx := ViewContexts.new(1)
	ctx.camera_plot = THREE
	# A new observation: plot 7 loses its road (fog or capture), plot 5 only
	# changes owner.
	var plots := _plots()
	(plots[7]["features"] as Array).resize(1)
	(plots[THREE]["features"] as Array)[2]["owner"] = 2
	v.show_overworld({"width": W, "height": H, "plots": plots}, PackedStringArray(NAMES), ctx)
	assert_true(is_same(v._layouts[THREE], before), "an owner change keeps the layout")
	assert_false(is_same(v._layouts[ROADED], road_before), "a neighbour's road change lays the hex out again")
	assert_eq(int(v._layouts[ROADED]["lay"]["open"]), -1, "no road side left")


func test_ground_by_draw_order_and_paths() -> void:
	var v := _view(1.0)
	assert_eq(int(v._layouts[9]["ground"]), 5, "forest (draw_order 2) over plains")
	assert_eq(int(v._layouts[THREE]["ground"]), 0)
	var paths: Array = v._layouts[ROADED]["paths"]
	assert_eq(paths.size(), 1)
	assert_eq(Array(paths[0][1]), [0], "the road strip runs east")


func test_zoom_constants() -> void:
	assert_eq(ContextView.HEX_SIZE, 64.0)
	assert_eq(ViewContexts.ZOOM_MIN, 0.25)
	assert_eq(ViewContexts.ZOOM_MAX, 3.0)
	assert_eq(ViewContexts.ZOOM_ENTER, 2.5)
