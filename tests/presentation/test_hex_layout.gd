extends GutTest
## HexLayout (sw-63wt.4, U1Q20-U1Q22): slots, road offsets, mover lane.

const E := 0
const NE := 1
const NW := 2
const W := 3
const SW := 4
const SE := 5


func _sites(count: int) -> Array:
	var out: Array = []
	for i in count:
		out.append({"id": "site_%d" % i, "priority": 0})
	return out


func _clearance() -> float:
	return float(HexLayout.table().road.clearance)


## Distance from p to the road segment of side k.
func _road_dist(p: Vector2, k: int) -> float:
	var d := HexLayout.side_dir(k)
	var t := clampf(p.dot(d), 0.0, float(HexLayout.APOTHEM))
	return p.distance_to(d * t)


## Every invariant the bead asks for, on one layout without overrides.
func _assert_sound(lay: Dictionary, roads: PackedInt32Array, label: String) -> void:
	var r := float(lay.radius)
	var lr := float(lay.lane_radius)
	for p in lay.points:
		var v := Vector2(p)
		for k in HexLayout.SIDES:
			assert_true(v.dot(HexLayout.side_dir(k)) + r <= HexLayout.APOTHEM + 0.5,
				"%s: site %s inside the hex (side %d)" % [label, p, k])
		for q in lay.lane:
			assert_true(v.distance_to(Vector2(q)) >= r + lr,
				"%s: site %s clear of mover %s" % [label, p, q])
		for k in HexLayout.clean_sides(roads):
			assert_true(_road_dist(v, k) >= _clearance(),
				"%s: site %s outside the clearance of road %d" % [label, p, k])
	for q in lay.lane:
		for k in HexLayout.SIDES:
			assert_true(Vector2(q).dot(HexLayout.side_dir(k)) + lr <= HexLayout.APOTHEM,
				"%s: mover %s inside the hex" % [label, q])


func test_each_count_uses_its_slot_table() -> void:
	var slots: Array = HexLayout.table().slots
	assert_eq(slots.size(), 7)
	for count in range(1, 8):
		var lay := HexLayout.compute(_sites(count), PackedInt32Array())
		assert_eq(lay.points.size(), count)
		assert_eq(lay.scale, 100)
		assert_eq(lay.radius, 180)
		assert_eq(lay.overflow, 0)
		assert_eq(lay.open, -1)
		for i in count:
			var slot: Array = slots[count - 1][i]
			assert_eq(lay.points[lay.order[i]], Vector2i(slot[0], slot[1]), "count %d slot %d" % [count, i])
		_assert_sound(lay, PackedInt32Array(), "count %d" % count)
		for i in count:
			for j in range(i + 1, count):
				assert_true(Vector2(lay.points[i]).distance_to(Vector2(lay.points[j])) >= 2 * lay.radius,
					"count %d: sites %d and %d apart" % [count, i, j])


func test_open_ground_lane_runs_along_the_lower_edge() -> void:
	var lay := HexLayout.compute(_sites(2), PackedInt32Array())
	assert_eq(lay.lane, [Vector2i(-260, 620), Vector2i(0, 620), Vector2i(260, 620)])


func test_order_by_priority_then_template_id() -> void:
	var sites := [{"id": "hex_mine", "priority": 2}, {"id": "hex_village", "priority": 3},
		{"id": "hex_depot", "priority": 2}, {"id": "hex_supply_cache"}]
	assert_eq(HexLayout.order(sites), PackedInt32Array([1, 2, 0, 3]))


func test_an_eighth_site_shares_the_last_slot() -> void:
	var lay := HexLayout.compute(_sites(9), PackedInt32Array())
	assert_eq(lay.overflow, 2)
	var last: Vector2i = lay.points[lay.order[6]]
	assert_eq(lay.points[lay.order[7]], last)
	assert_eq(lay.points[lay.order[8]], last)


func test_open_direction() -> void:
	# E-W: gaps up and down tie; down wins.
	assert_eq(HexLayout.open_angle(PackedInt32Array([E, W])), 90)
	# NE-SW: the two gaps bisect at 30 (down-right) and 210 (up-left).
	assert_eq(HexLayout.open_angle(PackedInt32Array([NE, SW])), 30)
	# A dead end east: opposite it.
	assert_eq(HexLayout.open_angle(PackedInt32Array([E])), 180)
	# Three-way E, NW, SW: three equal gaps bisected at 60 (down-right), 180
	# (west) and 300 (up-right); the most downward wins.
	assert_eq(HexLayout.open_angle(PackedInt32Array([E, NW, SW])), 60)
	# A wide gap beats a downward one: E, NE, NW leave W..SE open.
	assert_eq(HexLayout.open_angle(PackedInt32Array([E, NE, NW])), 120)
	assert_eq(HexLayout.open_angle(PackedInt32Array()), -1)


func test_straight_east_west_road() -> void:
	var roads := PackedInt32Array([E, W])
	for count in range(1, 8):
		var lay := HexLayout.compute(_sites(count), roads)
		assert_eq(lay.open, 90)
		assert_true(lay.scale <= 85 and lay.scale >= 60)
		_assert_sound(lay, roads, "E-W %d" % count)
		var sum := 0
		for p in lay.points:
			sum += p.y
		assert_true(sum > 0, "E-W %d: the group moved to the open (lower) side" % count)
	# Movers stand on the road.
	assert_eq(HexLayout.compute(_sites(1), roads).lane,
		[Vector2i(-520, 0), Vector2i(0, 0), Vector2i(520, 0)])


func test_straight_northeast_southwest_road() -> void:
	var roads := PackedInt32Array([NE, SW])
	for count in range(1, 8):
		_assert_sound(HexLayout.compute(_sites(count), roads), roads, "NE-SW %d" % count)
	var one := HexLayout.compute(_sites(1), roads)
	assert_eq(one.open, 30)
	assert_true(one.points[0].x > 0 and one.points[0].y > -80, "pushed towards the down-right gap")


func test_dead_end() -> void:
	var roads := PackedInt32Array([E])
	for count in range(1, 8):
		_assert_sound(HexLayout.compute(_sites(count), roads), roads, "dead end %d" % count)
	var lay := HexLayout.compute(_sites(1), roads)
	assert_eq(lay.open, 180)
	assert_true(lay.points[0].x < 0, "a single site moves west, away from the road")
	assert_eq(lay.lane, [Vector2i(0, 0), Vector2i(260, 0), Vector2i(520, 0)])


func test_three_way_junction() -> void:
	var roads := PackedInt32Array([E, NW, SW])
	for count in range(1, 8):
		_assert_sound(HexLayout.compute(_sites(count), roads), roads, "junction %d" % count)
	assert_eq(HexLayout.compute(_sites(3), roads).open, 60)


func test_every_road_shape_keeps_sites_sound() -> void:
	for mask in range(1, 64):
		var roads := PackedInt32Array()
		for k in HexLayout.SIDES:
			if mask & (1 << k):
				roads.append(k)
		for count in range(1, 8):
			_assert_sound(HexLayout.compute(_sites(count), roads), roads, "mask %d count %d" % [mask, count])


func test_an_override_wins_and_leaves_the_rest() -> void:
	var sites := _sites(3)
	var plain := HexLayout.compute(sites, PackedInt32Array([E, W]))
	sites[1]["at"] = Vector2i(-500, -300)
	var lay := HexLayout.compute(sites, PackedInt32Array([E, W]))
	assert_eq(lay.points[1], Vector2i(-500, -300))
	assert_eq(lay.points[0], plain.points[0])
	assert_eq(lay.points[2], plain.points[2])


func test_same_inputs_same_points() -> void:
	var sites := [{"id": "hex_village", "priority": 3}, {"id": "hex_mine", "priority": 2},
		{"id": "hex_shrine", "priority": 1}, {"id": "hex_supply_cache"}]
	var roads := PackedInt32Array([SW, E, NE])
	var a := HexLayout.compute(sites, roads)
	var b := HexLayout.compute(sites.duplicate(true), PackedInt32Array([NE, SW, E]))
	assert_eq(a, b)
	assert_eq(HexLayout.cache_key(sites, roads), HexLayout.cache_key(sites.duplicate(true), PackedInt32Array([E, NE, SW])))
	for p in a.points:
		assert_typeof(p, TYPE_VECTOR2I)


func test_a_newly_seen_road_changes_the_layout_only_through_its_inputs() -> void:
	var sites := [{"id": "hex_village", "priority": 3}, {"id": "hex_mine", "priority": 2}]
	var before := PackedInt32Array([W])
	var after := PackedInt32Array([W, E])
	assert_ne(HexLayout.cache_key(sites, before), HexLayout.cache_key(sites, after))
	assert_ne(HexLayout.compute(sites, before).points, HexLayout.compute(sites, after).points)
	# A newly seen site is an input too.
	var more := sites.duplicate(true)
	more.append({"id": "hex_shrine", "priority": 1})
	assert_ne(HexLayout.cache_key(sites, before), HexLayout.cache_key(more, before))
	assert_eq(HexLayout.compute(sites, after), HexLayout.compute(sites.duplicate(true), after))


func test_road_sides_from_known_neighbours() -> void:
	var info := {
		"hex_road": {"layer": "path"},
		"hex_rail": {"layer": "path", "connects": ["hex_depot"]},
		"hex_village": {},
		"hex_depot": {},
	}
	var nb: Array = [["hex_road"], ["hex_village"], [], ["hex_road", "hex_forest"], ["hex_depot"], []]
	assert_eq(HexLayout.road_sides(PackedStringArray(["hex_road", "hex_village"]), nb, info), PackedInt32Array([E, W]))
	assert_eq(HexLayout.road_sides(PackedStringArray(["hex_rail"]), nb, info), PackedInt32Array([SW]))
	# A hex without a path reaches nothing.
	assert_eq(HexLayout.road_sides(PackedStringArray(["hex_village"]), nb, info), PackedInt32Array())


func test_core_features_carry_drawing_fields() -> void:
	var loader := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	assert_true(loader.is_valid(), "packages load: %s" % [loader.errors])
	var t := loader.templates
	assert_eq(t.values_of("hex_plains").get("layer"), "ground")
	assert_eq(t.values_of("hex_forest").get("layer"), "ground")
	assert_eq(t.values_of("hex_hills").get("layer"), "ground")
	assert_eq(t.values_of("hex_lake").get("layer"), "ground")
	assert_eq(t.values_of("hex_road").get("layer"), "path")
	assert_eq(t.values_of("hex_village").get("layer", "site"), "site")
	for fid in ["hex_plains", "hex_road", "hex_village", "hex_mine"]:
		var c := String(t.values_of(fid).get("color", ""))
		assert_true(c.is_valid_html_color() and c.length() == 6, "%s colour %s" % [fid, c])
	var info := {"hex_road": t.values_of("hex_road")}
	assert_eq(HexLayout.road_sides(PackedStringArray(["hex_road"]),
		[["hex_road"], [], [], [], [], []], info), PackedInt32Array([E]))
