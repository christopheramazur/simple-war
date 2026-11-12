extends GutTest
## Glossary tooltips: terms as data in sync with GDD 07, linking terms in
## text, translation keys, and context-aware values from the hovered squad
## (GDD 07, 02 §2.5 defined conditions, R1Q3, R3Q10, R8Q10). Task sw-ip8.4.

const ONE := Fixed.ONE

static var _loader: PackageLoader


func _l() -> PackageLoader:
	if _loader == null:
		_loader = PackageLoader.load_dirs(PackedStringArray(["res://data/packages/core"]))
	return _loader


func _g() -> Glossary:
	return Glossary.from_templates(_l().templates)


## A duel's rifle squad: [session, squad ID].
func _duel() -> Array:
	var s := BattleSession.create(_l().templates, _l().data_hash, "duel_crossroads", 11)
	for q: Dictionary in s.observe(1)["squads"]:
		if q["template"] == "rifle_squad":
			return [s, q["id"]]
	return [s, -1]


func test_every_gdd_term_is_data() -> void:
	var g := _g()
	assert_eq(g.errors, PackedStringArray())
	var md := FileAccess.get_file_as_string("res://Game Design Document/07 Glossary.md")
	var re := RegEx.create_from_string("(?m)^- \\*\\*(.+?)\\*\\*:")
	var names := {}
	for id in g.ids():
		names[g.name_of(id)] = true
	var n := 0
	for m in re.search_all(md):
		n += 1
		assert_true(names.has(m.get_string(1)), "GDD 07 term '%s' is in glossary.json" % m.get_string(1))
	assert_eq(g.ids().size(), n, "and nothing extra")


func test_linking_terms_in_text() -> void:
	var g := _g()
	var spans := g.link("A Bad Hit shakes the squad's Morale; Unitary Squads ignore Mythos.")
	var linked := spans.filter(func(s: Dictionary) -> bool: return s["term"] != "").map(func(s: Dictionary) -> String: return s["term"])
	assert_eq(linked, ["term_bad_hit", "term_squad", "term_morale", "term_squad", "term_legend"],
		"longest match, possessives and plurals, aliases; never inside a word")
	assert_eq(g.term_for("Detachments"), "term_detachment_convoy")
	assert_eq(g.term_for("CR"), "term_capture_rate")
	assert_eq(g.bbcode("[Morale]"), "[lb][url=term:term_morale]Morale[/url]]")


func test_translation_keys() -> void:
	var g := _g()
	var tr := Translation.new()
	tr.locale = "fr"
	tr.add_message("term.term_bad_hit.name", "Coup dur")
	tr.add_message("glossary.value.any_hit", "(Tout coup)")
	TranslationServer.add_translation(tr)
	var was := TranslationServer.get_locale()
	TranslationServer.set_locale("fr")
	assert_eq(g.name_of("term_bad_hit"), "Coup dur")
	assert_eq(g.tooltip("term_bad_hit", {"inspection": {"units": [{"stats": [{"stat": "unit.hp", "value": ONE, "base": ONE}]}]}})["value"],
		"(Tout coup)")
	assert_eq(g.text_of("term_bad_hit"), "A hit greater than 50% of a unit's base HP.", "untranslated keys fall back")
	TranslationServer.set_locale(was)
	TranslationServer.remove_translation(tr)


func test_bad_hit_follows_the_hovered_unit() -> void:
	var g := _g()
	var d := _duel()
	var s: BattleSession = d[0]
	var sid: int = d[1]
	var ctx := {"inspection": s.inspect(1, sid), "unit": 1}
	var tip := g.tooltip("term_bad_hit", ctx)
	assert_eq(tip["value"], "(5 HP)", "half of a trooper's 10 HP")
	assert_eq(tip["change"], 0)
	var st := s.state
	var units := Centroids.units_of(st, st.squads.row_of(sid))
	Effects.apply(st, st.rules.fx.index_of("hardy"), sid, st.units.id_at(units[1]))
	EffectSystem.new().run(st)
	tip = g.tooltip("term_bad_hit", {"inspection": s.inspect(1, sid), "unit": 1})
	assert_eq(tip["value"], "(7.5 HP)", "a base HP buff raises the threshold")
	assert_eq(tip["change"], 1, "shown as better")
	tip = g.tooltip("term_bad_hit", {"inspection": {"units": [{"stats": [{"stat": "unit.hp", "value": ONE, "base": ONE}]}]}})
	assert_eq(tip["value"], "(Any Hit)", "on a 1 HP unit")


func test_stat_pool_and_unit_values() -> void:
	var g := _g()
	var d := _duel()
	var s: BattleSession = d[0]
	var sid: int = d[1]
	var st := s.state
	Effects.apply(st, st.rules.fx.index_of("dug_in"), sid)
	EffectSystem.new().run(st)
	var squad := {}
	for q: Dictionary in s.observe(1)["squads"]:
		if q["id"] == sid:
			squad = q
	var ctx := {"inspection": s.inspect(1, sid), "squad": squad}
	var ev := g.tooltip("term_evasion", ctx)
	assert_string_contains(ev["value"], "base 5")
	assert_eq(ev["change"], 1)
	var mor := g.tooltip("term_morale", ctx)
	assert_string_contains(mor["value"], " / ")
	var bands := g.tooltip("term_bands", ctx)
	assert_string_contains(bands["value"], "Stamina")
	assert_eq(g.tooltip("term_squad", ctx)["value"], "8 of 8 units")
	assert_eq(g.tooltip("term_pulse", ctx)["value"], "", "a term without a context")
	assert_eq(g.tooltip("term_evasion")["value"], "", "no context, no value")


func test_label_and_tooltip() -> void:
	var g := _g()
	var l := GlossaryLabel.new()
	l.glossary = g
	l.context = {"inspection": {"units": [{"stats": [{"stat": "unit.hp", "value": 15 * ONE, "base": 10 * ONE}]}]}}
	add_child_autofree(l)
	l.set_linked("Mind the Bad Hit.")
	assert_eq(l.text, "Mind the [url=term:term_bad_hit]Bad Hit[/url].")
	assert_eq(l.tip_for("term:term_bad_hit")["value"], "(7.5 HP)")
	l._on_hover("term:term_bad_hit")
	assert_true(l._tip.visible)
	assert_eq(l._tip._value.text, "▲ (7.5 HP)", "never colour alone")
	l._on_unhover("term:term_bad_hit")
	assert_false(l._tip.visible)
