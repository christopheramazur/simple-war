extends GutTest
## Layout records (sw-tho3.12, U1 B12): ContextView.drawn lists each squad's
## label and footprint for hx visual lint. A label records its text colour;
## a squad that is not selected is dimmed, and its text keeps WCAG AA over the field.

const FIRE_CUES := "res://src/presentation/mocks/fire_cues_mock.gd"


func _view() -> ContextView:
	var root: Control = load(FIRE_CUES).build()
	add_child_autofree(root)
	await get_tree().process_frame
	await get_tree().process_frame
	return root.find_children("*", "ContextView", true, false)[0] as ContextView


func test_labels_record_their_text_colour() -> void:
	var v := await _view()
	var labels := v.drawn.filter(func(d: Dictionary) -> bool: return d["kind"] == "label")
	assert_gt(labels.size(), 0, "the view drew labels")
	for d: Dictionary in labels:
		assert_true(d.has("fg"), "label of squad %s carries its text colour" % d["squad"])
		var fg: Color = d["fg"]
		assert_gte(fg.a, 0.9, "even a dimmed label stays near full strength")
	var footprints := v.drawn.filter(func(d: Dictionary) -> bool: return d["kind"] == "footprint")
	for d: Dictionary in footprints:
		assert_false(d.has("fg"), "footprints have no text")


func test_selected_label_is_full_strength_and_others_are_dimmed() -> void:
	var v := await _view()
	var alphas := []
	for d: Dictionary in v.drawn:
		if d["kind"] == "label":
			alphas.append(snappedf((d["fg"] as Color).a, 0.001))
	assert_has(alphas, 1.0, "the selected mortar team's label")
	assert_has(alphas, 0.92, "the dimmed labels")
