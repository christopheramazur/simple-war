extends GutTest
## sw-7kr: the squad card and the battle glance summary show one glyph per band.


func test_squad_card_and_summary_share_the_glyph() -> void:
	for band in BandGlyphs.ICONS:
		var glyph := String(BandGlyphs.ICONS[band])
		assert_eq(SquadCard._band_icon(band), glyph, "%s on the squad card" % band)
		var line := EventText.battle_summary({"band": band, "trend": "steady"})
		assert_true(line.begins_with(glyph + " "), "%s in the glance summary: %s" % [band, line])


func test_glyphs_are_distinct() -> void:
	var seen := {}
	for band in BandGlyphs.ICONS:
		assert_false(seen.has(BandGlyphs.ICONS[band]), "%s glyph is unique" % band)
		seen[BandGlyphs.ICONS[band]] = true
