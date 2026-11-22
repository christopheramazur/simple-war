extends GutTest
## The skirmish profile card shows what ProfileController uses (sw-kif).


func test_omitted_keys_show_the_defaults_used() -> void:
	var d := ProfileCard.describe({"name": "X", "text": "Feel."})
	var pc := ProfileController.new(2, {})
	assert_eq(d["fuzz_pct"], pc.fuzz_pct)
	assert_eq(d["think_ms"], pc.think_ms)
	assert_eq(d["think_ms"], ProfileController.DEFAULT_THINK_MS)
	assert_eq(d["difficulty"], ProfileCard.DEFAULT_DIFFICULTY)
	assert_string_contains(d["think"], "2 s")
	assert_string_contains(d["fuzz"], "0%")


func test_set_keys_are_shown() -> void:
	var v := {"text": "t", "difficulty": "Hard", "fuzz": 30, "think_ms": 500}
	var d := ProfileCard.describe(v)
	var pc := ProfileController.new(2, v)
	assert_eq(d["fuzz_pct"], 30)
	assert_eq(d["fuzz_pct"], pc.fuzz_pct)
	assert_eq(d["think_ms"], 500)
	assert_string_contains(d["fuzz"], "30%")
	assert_string_contains(d["think"], "0.5 s")
	assert_string_contains(ProfileCard.text(v), "Hard")


func test_every_shipped_profile_matches_its_controller() -> void:
	var l := PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	assert_true(l.is_valid())
	var n := 0
	for id in l.templates.ids():
		if l.templates.kind_of(id) != "controller_profile":
			continue
		var v: Dictionary = l.templates.values_of(id)
		var pc := ProfileController.new(2, v)
		var d := ProfileCard.describe(v)
		assert_eq(d["fuzz_pct"], pc.fuzz_pct, id)
		assert_eq(d["think_ms"], pc.think_ms, id)
		n += 1
	assert_gt(n, 0)
