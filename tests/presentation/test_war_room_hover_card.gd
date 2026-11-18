extends GutTest
## The overworld hex hover card (sw-3zs): it belongs to the hex under the
## cursor on the overworld, so it goes away when the view stops being that,
## and it is only as tall as its text.

const ROOM := "res://src/presentation/war_room/war_room.tscn"
const SETTINGS := "user://test_settings_hover.cfg"


func before_each() -> void:
	DirAccess.remove_absolute(SETTINGS)
	GameSettings.path = SETTINGS


func after_all() -> void:
	DirAccess.remove_absolute(SETTINGS)
	GameSettings.path = "user://settings.cfg"


## The demo room (player 1 in two battles), with
## the cursor resting on one of the player's own hexes.
func _hovering() -> WarRoom:
	var w: WarRoom = load(ROOM).instantiate()
	w.record_match = false
	add_child_autofree(w)
	var plot: int = w.session.observe(1)["commanders"].filter(
		func(c: Dictionary) -> bool: return c["player"] == 1)[0]["plot"]
	w._main._hover_plot = plot
	w._main.hex_hovered.emit(plot)
	return w


func test_the_card_fits_its_text() -> void:
	var w := _hovering()
	assert_true(w._hover_card.visible)
	await wait_frames(4)
	assert_almost_eq(w._hover_card.size.y, w._hover_card.get_combined_minimum_size().y, 1.0)
	assert_lt(w._hover_card.size.y, 300.0, "a few lines of text, not a column")


func test_entering_a_battle_with_the_cursor_on_the_map_hides_the_card() -> void:
	var w := _hovering()
	assert_true(w.contexts.tab_in())
	await wait_frames(2)
	assert_false(w._hover_card.visible)
	w.contexts.exit()
	await wait_frames(2)
	assert_false(w._hover_card.visible, "not back until the cursor is on a hex again")


func test_the_cursor_leaving_the_map_hides_the_card() -> void:
	var w := _hovering()
	w._main.notification(Control.NOTIFICATION_MOUSE_EXIT)
	assert_false(w._hover_card.visible)
	assert_eq(w._hover_plot, -1)


func test_turn_playback_hides_the_card_until_it_ends() -> void:
	var w := _hovering()
	w._start_play(w.session.observe(1), 1)
	assert_false(w._hover_card.visible)
	w.skip_playback()
	assert_true(w._hover_card.visible, "the cursor never left the hex")
