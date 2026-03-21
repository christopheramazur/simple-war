extends GutTest

func test_start_quickplay_emits_audit_and_projection() -> void:
	CampaignRuntime.start_quickplay()
	assert_true(CampaignRuntime.get_event_count() >= 1)
	var p: Dictionary = CampaignRuntime.get_sector_projection()
	assert_true(p.has("route_target"))
	assert_true(str(p.get("current_plot_id", "")).length() > 0)

func test_sector_move_requires_army() -> void:
	CampaignRuntime.start_quickplay()
	var r: Dictionary = CampaignRuntime.submit_intent("sector.move_to_battle")
	assert_false(r.get("ok", true))

func test_army_then_move_ok() -> void:
	CampaignRuntime.start_quickplay()
	assert_true(CampaignRuntime.submit_intent("armybuilding.select", {"army_name": "Militia"}).get("ok", false))
	var r: Dictionary = CampaignRuntime.submit_intent("sector.move_to_battle")
	assert_true(r.get("ok", false))
