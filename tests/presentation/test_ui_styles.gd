extends GutTest
## Named UI styles (sw-ijp.1): screens name a style from data/ui/styles.json,
## every theme builds all of them, and panels no longer pick their own colours.

const SCREENS: Array[String] = [
	"res://src/presentation/glossary/glossary_tooltip.gd",
	"res://src/presentation/main_menu/main_menu.gd",
	"res://src/presentation/options/options_screen.gd",
	"res://src/presentation/war_room/battle_panel.gd",
	"res://src/presentation/war_room/command_panel.gd",
	"res://src/presentation/war_room/controls_help.gd",
	"res://src/presentation/war_room/hex_card.gd",
	"res://src/presentation/war_room/pip_panel.gd",
	"res://src/presentation/war_room/results_screen.gd",
	"res://src/presentation/war_room/squad_card.gd",
	"res://src/presentation/war_room/war_room.gd",
]


func before_all() -> void:
	UiTheme.reload()


func _source(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func test_every_style_a_screen_names_exists_in_every_theme() -> void:
	var re := RegEx.create_from_string("\"([A-Z][A-Za-z]+(?:Label|Panel|Gap|Bar))\"")
	var named := {}
	for path in SCREENS:
		for m in re.search_all(_source(path)):
			named[m.get_string(1)] = path
	assert_gt(named.size(), 20, "the scan found the screens' styles")
	for id in UiTheme.ids():
		var t := UiTheme.build(UiTheme.profile(id))
		var known := t.get_type_variation_list("Label") + t.get_type_variation_list("PanelContainer") + t.get_type_variation_list("Container")
		for style: String in named:
			assert_has(known, style, "%s in %s (used by %s)" % [style, id, named[style]])


func test_screens_do_not_pick_their_own_colours_or_sizes() -> void:
	var banned := RegEx.create_from_string("Color\\(\"|StyleBoxFlat\\.new|add_theme_font_size_override|add_theme_stylebox_override")
	for path in SCREENS:
		var hit := banned.search(_source(path))
		assert_null(hit, "%s: %s" % [path, hit.get_string() if hit != null else ""])


func test_a_theme_reaches_the_named_styles() -> void:
	var normal := UiTheme.build(UiTheme.profile("default"))
	var contrast := UiTheme.build(UiTheme.profile("high_contrast"))
	var large := UiTheme.build(UiTheme.profile("large"))
	assert_eq(normal.get_font_size("font_size", "SmallDimLabel"), 13)
	assert_eq(large.get_font_size("font_size", "SmallDimLabel"), 16, "text grows with the theme")
	assert_eq(normal.get_color("font_color", "DimLabel"), Color("8a93a3"))
	assert_eq(contrast.get_color("font_color", "DimLabel"), Color("c8c8c8"))
	assert_eq(contrast.get_color("default_color", "DimLabel"), Color("c8c8c8"), "rich text follows too")
	var card := contrast.get_stylebox("panel", "HoverCardPanel") as StyleBoxFlat
	assert_eq(card.border_width_left, 2, "the theme's border width applies")
	assert_eq(card.border_color, Color("ffd400"))


func test_a_control_takes_its_look_from_the_style() -> void:
	var holder := Control.new()
	holder.theme = UiTheme.build(UiTheme.profile("high_contrast"))
	add_child_autofree(holder)
	var l := UiTheme.label("x", "SmallGoodLabel")
	holder.add_child(l)
	assert_eq(l.get_theme_color("font_color"), Color("00ff7f"))
	assert_eq(l.get_theme_font_size("font_size"), 14)
	var box := VBoxContainer.new()
	box.theme_type_variation = &"ModalGap"
	holder.add_child(box)
	assert_eq(box.get_theme_constant("separation"), 10)
