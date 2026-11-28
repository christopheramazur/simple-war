class_name OverworldSession
extends RefCounted
## The Game API for the overworld (GDD 04 §4.4, R7Q14): the one interface
## the human UI, AI controllers, the network layer, tests and the AI factory
## use. Mirrors BattleSession.
##
## Inputs:   set_route, set_drop_off, set_activity, transfer_squad (also picks up
##           from a detachment), set_battleforce, set_output,
##           set_supply_line, rally, equip, unequip, give_item,
##           take_items, answer_offer
##           (Planning only), save_preset, ready, advance(ms);
##           submit_reaction (Reaction only).
## Queries:  observe(player) - fog-filtered state plus last turn's visible
##           events (OverworldVision); path(player, commander, to) - the
##           cheapest affordable route as the player knows the map.
## Battles:  every engagement becomes a battle at the start of the next
##           turn (OverworldBattles) and runs one battle turn per overworld
##           turn on the same pulse: submit_battle_orders, reinforce,
##           submit_battle_deployment (while the battle is deploying),
##           submit_arrival (placing squads that arrive at the next Reveal,
##           a joining side's included; arrival shows that player its area)
##           and leave_battle in Planning; observe_battle shows one;
##           forecast_battle previews drafted orders (intent ghosts).
## Clock:    the shared PulseClock (R2Q3). Reveal sends reinforcements in
##           and applies every battle's orders. While any battle runs (and
##           the clock config allows it), a reaction window follows: each
##           battle's coming turn is forecast (Reactions), players react
##           through submit_reaction, and a player with nothing to react to
##           is ready at once (GDD 02 §2.2). Each player's battle count sets
##           its bonus time. Execute runs the battle turns, applies finished
##           battles, resolves the overworld turn, then starts new battles.
## Records:  every input is logged with its turn and phase, and the state
##           hash after every resolved turn is kept, so a replay (initial
##           state + inputs) is checked turn by turn (R8Q5, R6Q20).

const SAVE_VERSION: int = 1

## Why the last load_save / rebuild returned null (empty on success).
static var last_error: String = ""

var map_id: String
var templates: TemplateTable
var seed_value: int
var data_hash: String
var rules: OverworldRules
var state: OverworldState
var clock: PulseClock
var bus: PulseBus
## [{"turn", "phase", "player", "kind", "payload"}]
var input_log: Array = []
## State hash (hex) after each resolved turn; [i] is after turn i + 1.
var turn_hashes: PackedStringArray = PackedStringArray()
## Every event of the last resolved turn (unfiltered; observe filters).
var last_events: Array[SimEvent] = []
## Battles in progress: engagement ID -> OverworldBattle.
var battles: Dictionary = {}
## Problems building battles (bad battlefield data); such engagements end.
var errors: PackedStringArray = PackedStringArray()
var _next_context: int = 100
## One sim runs every battle (it holds no per-battle state).
var _battle_sim := BattleSim.new()

var _players: PackedInt64Array = PackedInt64Array()
var _execute_pending: bool = false
## The clock config's own reaction_enabled: the window opens only on turns
## with battles, and only if this allows it.
var _reactions_allowed: bool = true
## Reaction window: engagement ID -> Reactions.forecast opportunities.
var _opportunities: Dictionary = {}
## Reaction window: engagement ID -> Reactions.forecast_all telegraphs (sw-7o7).
var _telegraphs: Dictionary = {}
## Set on entering the reaction window: ready the players with nothing to
## react to (done in _pump, outside the clock's call stack).
var _auto_ready: bool = false
## A replay (MatchReplay): the session takes no orders, readies or time
## from outside; only replay_inputs moves it.
var locked: bool = false
## Presentation opt-in: keep every battle's last turn tick by tick
## (`playback`). Read-only; it never changes a result.
var keep_playback: bool = false
## Whether the reaction window forecasts enemy attack telegraphs (UI only).
## Off for headless runs: a battle with no reaction ability then skips the
## forecast's scratch turn (sw-kd5).
var want_telegraphs: bool = true
## Engagement ID -> {"rules", "players", "frames", "shots", "volleys",
## "hits", "start" (BattleCursor.capture)} of the last turn.
var _playback: Dictionary = {}
## Engagement ID -> player -> worst own SIMPL band index last recorded (at
## the battle's start and after each of its turns): the glance summary's
## backward-looking trend reference. Only the session records it; saved
## with the game, it never feeds back into the simulation.
var _band_history: Dictionary = {}
## Set while rebuilding: the hashes the replay must reproduce.
var _expected: PackedStringArray = PackedStringArray()
var _diverged: int = -1


## Creates a session at turn 1, Planning, with the map's starting
## commanders. Returns null (and sets last_error) if the data is invalid.
static func create(templates: TemplateTable, hash_hex: String, map: String, seed_in: int, clock_config: ClockConfig = null) -> OverworldSession:
	last_error = ""
	var r := OverworldRules.compile(templates, map, hash_hex)
	if not r.is_valid():
		last_error = "; ".join(r.errors)
		return null
	if r.players().is_empty():
		last_error = "map '%s' has no players" % map
		return null
	var s := OverworldSession.new()
	s._setup(templates, r, map, seed_in, hash_hex, clock_config)
	s.clock.start()
	return s


func _setup(t: TemplateTable, r: OverworldRules, map: String, seed_in: int, hash_hex: String, clock_config: ClockConfig) -> void:
	templates = t
	rules = r
	map_id = map
	seed_value = seed_in
	data_hash = hash_hex
	state = OverworldState.create(1, rules, seed_in)
	for st in rules.starts:
		Commanders.spawn_index(state, st["player"], st["commander"], st["plot"])
	OverworldVision.update(state)
	_players = rules.players()
	bus = PulseBus.new()
	bus.register_context(state)
	var cfg := _config_from(_config_dict(clock_config if clock_config != null else ClockConfig.new()))
	_reactions_allowed = cfg.reaction_enabled
	cfg.reaction_enabled = false
	clock = PulseClock.new(cfg)
	for p in _players:
		clock.add_player(p)
		clock.set_battles(p, 0)
	clock.phase_changed.connect(_on_phase)
	clock.pulse_point.connect(_on_pulse)


## The battle simulator every battle runs on (harness profiling and
## SimMetrics hook into it; it holds no per-battle state).
func battle_sim() -> BattleSim:
	return _battle_sim


func players() -> PackedInt64Array:
	return _players.duplicate()


func phase_name() -> String:
	return PulseClock.Phase.keys()[clock.phase]


## Overworld turns resolved so far.
func turns_resolved() -> int:
	return state.turn


# --- inputs ----------------------------------------------------------------

## Where a dialogue stands (sw-62i): {"dialogue", "node", "speaker", "key",
## "text", "choices" [{"index", "key", "text"} of the available ones], "ended"}.
## {} for an
## unknown dialogue. A dialogue not yet begun shows its start node. Progress
## lives in the state, so it is saved and hashed.
func dialogue_view(id: String) -> Dictionary:
	if not templates.has(id) or templates.kind_of(id) != "dialogue":
		return {}
	var v := templates.values_of(id)
	var at: String = state.dialogues.get(id, String(v["start"]))
	var out := {"dialogue": id, "node": at, "ended": at == Dialogue.END, "speaker": "", "key": "", "text": "", "choices": []}
	if out["ended"]:
		return out
	var node: Dictionary = (v["nodes"] as Dictionary)[at]
	out["speaker"] = String(node.get("speaker", ""))
	out["key"] = String(node.get("key", ""))
	out["text"] = String(node.get("text", ""))
	var list: Array = node.get("choices", [])
	for i in Dialogue.available(state, v, at):
		var c: Dictionary = list[i]
		out["choices"].append({"index": i, "key": String(c.get("key", "")), "text": String(c.get("text", ""))})
	return out


## Begins a dialogue at its start node (its `do` runs). A no-op once begun.
## "" or why not.
func dialogue_begin(player: int, id: String) -> String:
	var err := _planning(player)
	if not err.is_empty():
		return err
	if not templates.has(id) or templates.kind_of(id) != "dialogue":
		return "unknown dialogue"
	if not state.dialogues.has(id):
		var v := templates.values_of(id)
		state.dialogues[id] = String(v["start"])
		Dialogue.enter(state, v, String(v["start"]))
		_log(player, "dialogue_begin", id)
	return ""


## Moves a dialogue on: picks choice `choice` of its node, or (-1) follows a
## node without choices. "" or why not.
func dialogue_pick(player: int, id: String, choice: int) -> String:
	var err := _planning(player)
	if not err.is_empty():
		return err
	var view := dialogue_view(id)
	if view.is_empty():
		return "unknown dialogue"
	if not state.dialogues.has(id):
		return "the dialogue has not begun"
	if view["ended"]:
		return "the dialogue has ended"
	var v := templates.values_of(id)
	var node: Dictionary = (v["nodes"] as Dictionary)[view["node"]]
	var nxt := ""
	if node.has("choices"):
		if choice < 0 or not view["choices"].any(func(c: Dictionary) -> bool: return c["index"] == choice):
			return "that choice is not available"
		nxt = Dialogue.choose(state, v, view["node"], choice)
	elif choice != -1:
		return "this line has no choices"
	else:
		nxt = String(node.get("next", ""))
	if nxt.is_empty():
		state.dialogues[id] = Dialogue.END
	else:
		state.dialogues[id] = nxt
		Dialogue.enter(state, v, nxt)
	_log(player, "dialogue", {"dialogue": id, "choice": choice})
	return ""


## Sets (or, with an empty route, clears) a commander's route. "" or why not.
func set_route(player: int, commander_id: int, plots: PackedInt64Array) -> String:
	var err := _planning(player)
	if err.is_empty():
		err = OverworldOrders.set_route(state, player, commander_id, plots)
	if err.is_empty():
		_log(player, "route", {"commander": commander_id, "plots": plots.duplicate()})
	return err


## Plans (or, with plot -1, clears) a commander's drop-off: after route step
## `step` (-1 = before moving), its battleforce without its own squad is
## dropped on that hex or one next to it. "" or why not.
func set_drop_off(player: int, commander_id: int, step: int, plot: int) -> String:
	var err := _planning(player)
	if err.is_empty():
		err = OverworldOrders.set_drop_off(state, player, commander_id, step, plot)
	if err.is_empty():
		_log(player, "drop", {"commander": commander_id, "step": step, "plot": plot})
	return err


## Selects which production option an owned feature makes. "" or why not.
func set_output(player: int, feature_id: int, option: int) -> String:
	var err := _planning(player)
	if err.is_empty():
		err = Convoys.set_output(state, player, feature_id, option)
	if err.is_empty():
		_log(player, "output", {"feature": feature_id, "option": option})
	return err


## Sends an owned feature's output along a supply line to a plot or one of
## the player's commanders (both -1 clears it). "" or why not.
func set_supply_line(player: int, feature_id: int, plot: int, commander: int = -1) -> String:
	var err := _planning(player)
	if err.is_empty():
		err = Convoys.set_line(state, player, feature_id, plot, commander)
	if err.is_empty():
		_log(player, "supply", {"feature": feature_id, "plot": plot, "commander": commander})
	return err


## Steers a detachment by hand along `plots` (sw-kys.8; Convoys.set_route):
## a chain of neighbouring hexes, possibly several turns long. Empty halts
## it. "" or why not.
func set_convoy_route(player: int, detachment_id: int, plots: PackedInt64Array) -> String:
	var err := _planning(player)
	if err.is_empty():
		err = Convoys.set_route(state, player, detachment_id, plots)
	if err.is_empty():
		_log(player, "convoy_route", {"detachment": detachment_id, "plots": plots.duplicate()})
	return err


## What a detachment of `player` can enter this turn: {"budget" (its
## movement points as a caravan, which sending it makes it), "reach"
## (plot -> cost)}; {} if not its own or in a battle.
func convoy_reach(player: int, detachment_id: int) -> Dictionary:
	var row := state.detachments.row_of(detachment_id)
	if row < 0 or state.detachments.player[row] != player or state.detachments.engagement[row] >= 0:
		return {}
	var mp := OverworldStats.movement_of(state, OverworldStats.BAND, detachment_id, rules.band_caravan)
	return {"budget": mp, "reach": OverworldPath.reach(state, state.detachments.plot[row], mp, player)}


## The cheapest way for a detachment to plot `to`, as the player knows the
## map, whole (a convoy keeps walking on later turns). With `via` (the route
## it already has), the way continues from its end and the result is the
## whole route: waypoints. Empty if none.
func convoy_path(player: int, detachment_id: int, to: int, via: PackedInt64Array = PackedInt64Array()) -> PackedInt64Array:
	var row := state.detachments.row_of(detachment_id)
	if row < 0 or state.detachments.player[row] != player:
		return PackedInt64Array()
	var from := state.detachments.plot[row] if via.is_empty() else via[via.size() - 1]
	var way := OverworldPath.find(state, from, to, player)
	if way.is_empty():
		return PackedInt64Array()
	var out := via.duplicate()
	out.append_array(way)
	return out


## Sends a detachment as a convoy to a plot or one of the player's
## commanders (both -1 halts it). "" or why not.
func rally(player: int, detachment_id: int, plot: int, commander: int = -1) -> String:
	var err := _planning(player)
	if err.is_empty():
		err = Convoys.rally(state, player, detachment_id, plot, commander)
	if err.is_empty():
		_log(player, "rally", {"detachment": detachment_id, "plot": plot, "commander": commander})
	return err


## Equips `count` items of a stack in a commander's War Chest to a squad
## of its army (R4Q10). "" or why not.
func equip(player: int, commander_id: int, item_id: int, squad_id: int, count: int) -> String:
	var err := _planning(player)
	if err.is_empty():
		err = WarChest.equip(state, player, commander_id, item_id, squad_id, count)
	if err.is_empty():
		_log(player, "equip", {"commander": commander_id, "item": item_id, "squad": squad_id, "count": count})
	return err


## Returns `count` equipped items to the commander's War Chest.
func unequip(player: int, commander_id: int, item_id: int, count: int) -> String:
	var err := _planning(player)
	if err.is_empty():
		err = WarChest.unequip(state, player, commander_id, item_id, count)
	if err.is_empty():
		_log(player, "unequip", {"commander": commander_id, "item": item_id, "count": count})
	return err


## Hands items between friendly commanders sharing a hex (R7Q9).
func give_item(player: int, from_commander: int, item_id: int, count: int, to_commander: int) -> String:
	var err := _planning(player)
	if err.is_empty():
		err = WarChest.give(state, player, from_commander, item_id, count, to_commander)
	if err.is_empty():
		_log(player, "give", {"from": from_commander, "item": item_id, "count": count, "to": to_commander})
	return err


## A commander takes the War Chest of the player's detachment on its hex.
func take_items(player: int, commander_id: int, detachment_id: int) -> String:
	var err := _planning(player)
	if err.is_empty():
		err = WarChest.take(state, player, commander_id, detachment_id)
	if err.is_empty():
		_log(player, "take", {"commander": commander_id, "detachment": detachment_id})
	return err


## Answers an offer made to the player this turn (an uncertain feature,
## R6Q14) with one of its choices; the map's triggers decide what it does.
func answer_offer(player: int, feature_id: int, choice: String) -> String:
	var err := _planning(player)
	if err.is_empty():
		err = OverworldTurn.answer(state, player, feature_id, choice)
	if err.is_empty():
		_log(player, "answer", {"feature": feature_id, "choice": choice})
	return err


## Plans (or, with "", clears) a commander's activity; recruit names the
## squad in `option`. "" or why not.
func set_activity(player: int, commander_id: int, activity: String, option: String = "") -> String:
	var err := _planning(player)
	if err.is_empty():
		err = OverworldOrders.set_activity(state, player, commander_id, activity, option)
	if err.is_empty():
		_log(player, "activity", {"commander": commander_id, "activity": activity, "option": option})
	return err


## Sets a commander's battleforce plan: a preset name ("" = strongest) or
## hand-picked squads, and whether the commander's own squad leads it.
func set_battleforce(player: int, commander_id: int, preset: String, squads: PackedInt64Array = PackedInt64Array(), lead: bool = true) -> String:
	var err := _planning(player)
	if err.is_empty():
		err = OverworldBattleforce.set_plan(state, player, commander_id, preset, squads, lead)
	if err.is_empty():
		_log(player, "battleforce", {"commander": commander_id, "preset": preset, "squads": squads.duplicate(), "lead": lead})
	return err


## Saves one of the player's own battleforce presets (any phase).
func save_preset(player: int, name: String, prefer: PackedStringArray, avoid: PackedStringArray = PackedStringArray()) -> String:
	if not _players.has(player):
		return "unknown player"
	var err := OverworldBattleforce.save_preset(state, player, name, prefer, avoid)
	if err.is_empty():
		_log(player, "preset", {"name": name, "prefer": prefer.duplicate(), "avoid": avoid.duplicate()})
	return err


## Orders for the player's squads in one battle this turn (BattleOrders).
## Replaces earlier ones; returns errors, keeping the valid orders.
func submit_battle_orders(player: int, engagement_id: int, orders: Array) -> PackedStringArray:
	var errs := PackedStringArray()
	var err := _planning(player)
	var b: OverworldBattle = battles.get(engagement_id)
	if err.is_empty() and (b == null or not b.state.players.has(player)):
		err = "not in that battle"
	if not err.is_empty():
		errs.append(err)
		return errs
	var kept := []
	for i in orders.size():
		var e := BattleOrders.validate(b.state, player, orders[i])
		if e.is_empty():
			kept.append((orders[i] as Dictionary).duplicate(true))
		else:
			errs.append("order %d: %s" % [i, e])
	b.orders[player] = kept
	_log(player, "battle_orders", {"engagement": engagement_id, "orders": kept})
	return errs


## Deployment placements for one of the player's battles while it is
## deploying (BattleDeploy): [{squad, x, y, facing}]. Replaces the player's
## earlier draft for that battle; valid placements are kept and apply at the
## Reveal (squads not placed keep their automatic places, so an empty draft
## at the timeout is automatic deployment). Returns errors. Planning only.
func submit_battle_deployment(player: int, engagement_id: int, placements: Array) -> PackedStringArray:
	var errs := PackedStringArray()
	var err := _planning(player)
	var b: OverworldBattle = battles.get(engagement_id)
	if err.is_empty() and (b == null or not b.state.players.has(player)):
		err = "not in that battle"
	if err.is_empty() and not b.state.deploying:
		err = "the battle is not deploying"
	if not err.is_empty():
		errs.append(err)
		return errs
	var c := BattleDeploy.check(b.state, player, placements)
	b.deploys[player] = c["kept"]
	_deploy_draft_changed(engagement_id)
	_sync_deploying()
	_log(player, "battle_deploy", {"engagement": engagement_id, "placements": c["kept"]})
	return c["errors"]


## Tells the clock how many battles each player deploys in this Planning
## (a non-empty draft), for the deployment bonus (GDD 02 §2.2 Time).
func _sync_deploying() -> void:
	for p in _players:
		var n := 0
		for eid: int in battles:
			var b: OverworldBattle = battles[eid]
			if b.state.players.has(p) and not (b.deploys.get(p, []) as Array).is_empty():
				n += 1
		clock.set_deploying(p, n)


## A deployment draft changed: the battle's cached reaction-window forecasts
## are stale. (C4's forecast_battle cache clears here too once it lands.)
func _deploy_draft_changed(engagement_id: int) -> void:
	_opportunities.erase(engagement_id)
	_telegraphs.erase(engagement_id)


## The planning forecast for one of the player's battles (IntentForecast):
## the coming battle turn with these drafted orders, as the player knows
## it. Nothing is submitted or changed. Planning only ({} otherwise).
func forecast_battle(player: int, engagement_id: int, orders: Array) -> Dictionary:
	var b: OverworldBattle = battles.get(engagement_id)
	if clock.phase != PulseClock.Phase.PLANNING or b == null or not b.state.players.has(player):
		return {}
	return IntentForecast.run(b.state, _battle_sim, player, orders, b.deploys.get(player, []))


## forecast_battle as a job for a worker thread (IntentForecast.job): an
## invalid Callable when there is nothing to forecast. Callers must let it
## finish before the turn resolves.
func forecast_job(player: int, engagement_id: int, orders: Array) -> Callable:
	var b: OverworldBattle = battles.get(engagement_id)
	if clock.phase != PulseClock.Phase.PLANNING or b == null or not b.state.players.has(player):
		return Callable()
	return IntentForecast.job(b.state, player, orders, b.deploys.get(player, []))


## Sends a squad from a staying commander's army into its battle. `place`
## ({x, y, facing}, optional) is where it arrives, inside the player's area
## (OverworldBattles.place_error); without one it arrives at the automatic
## place. A bad place refuses the whole order.
func reinforce(player: int, commander_id: int, squad_id: int, place: Dictionary = {}) -> String:
	var err := _planning(player)
	var b: OverworldBattle = null
	if err.is_empty():
		var eid := state.commanders.get_value(commander_id, &"engagement") if state.commanders.is_alive(commander_id) else -1
		b = battles.get(eid)
		if b == null:
			err = "is not in a battle"
		elif not place.is_empty():
			err = OverworldBattles.place_error(state, b, player, squad_id, place)
		if err.is_empty():
			err = OverworldOrders.reinforce(state, player, commander_id, squad_id, _in_field(b, commander_id))
	if err.is_empty():
		var payload := {"commander": commander_id, "squad": squad_id}
		if not place.is_empty():
			b.places[squad_id] = {"x": place["x"], "y": place["y"], "facing": place["facing"]}
			payload["place"] = b.places[squad_id].duplicate()
		_log(player, "reinforce", payload)
	return err


## Places the player's squads arriving in a battle at the next Reveal (a
## joining side's battleforce, reinforcements on the way):
## [{squad (overworld ID), x, y, facing}], inside the player's area
## (arrival). Replaces the player's earlier placements there; valid ones
## are kept and squads not placed arrive at their automatic places. Returns
## errors. Planning only.
func submit_arrival(player: int, engagement_id: int, placements: Array) -> PackedStringArray:
	var errs := PackedStringArray()
	var err := _planning(player)
	var b: OverworldBattle = battles.get(engagement_id)
	var mine := {}
	if err.is_empty() and b != null:
		for id: int in OverworldBattles.arriving(state, b):
			if OverworldArmies.player_of(state, id) == player:
				mine[id] = true
	if err.is_empty() and mine.is_empty():
		err = "nothing of yours arrives in that battle"
	if not err.is_empty():
		errs.append(err)
		return errs
	for id: int in mine:
		b.places.erase(id)
	var kept := []
	for i in placements.size():
		var pc: Variant = placements[i]
		var e := ""
		if typeof(pc) != TYPE_DICTIONARY or typeof((pc as Dictionary).get("squad")) != TYPE_INT:
			e = "squad must be an int"
		elif not mine.has(pc["squad"]):
			e = "not a squad of yours arriving there"
		elif b.places.has(pc["squad"]):
			e = "squad placed twice"
		else:
			e = OverworldBattles.place_error(state, b, player, pc["squad"], pc)
		if not e.is_empty():
			errs.append("placement %d: %s" % [i, e])
			continue
		var d := {"x": pc["x"], "y": pc["y"], "facing": pc["facing"]}
		b.places[pc["squad"]] = d
		var k := d.duplicate()
		k["squad"] = pc["squad"]
		kept.append(k)
	_log(player, "arrival", {"engagement": engagement_id, "placements": kept})
	return errs


## Where the player's squads arrive in a battle at the next Reveal, for that
## player only ({} if nothing of theirs arrives): {"facing", "area" [x, y,
## w, h] (fixed), "joining" (the player becomes a new side), "squads":
## [{"squad" (overworld ID), "tmpl" (battle squad template), "x", "y",
## "facing", "placed"}]} with each squad's placement or automatic place.
func arrival(player: int, engagement_id: int) -> Dictionary:
	var b: OverworldBattle = battles.get(engagement_id)
	if b == null or player <= 0:
		return {}
	var ids := []
	for id: int in OverworldBattles.arriving(state, b):
		if OverworldArmies.player_of(state, id) == player:
			ids.append(id)
	if ids.is_empty():
		return {}
	var a := OverworldBattles.arrival_area_of(state, b, player)
	var d: PackedInt64Array = a["deploy"]
	var joining := not b.state.players.has(player)
	var squads := []
	for i in ids.size():
		var id: int = ids[i]
		var st := b.rules.squad_index(rules.squad_ids[state.squads.get_value(id, &"tmpl")])
		var spot := OverworldBattles.default_spot(d, i, ids.size() if joining else 0)
		var e := {"squad": id, "tmpl": st, "x": spot[0], "y": spot[1], "facing": a["facing"], "placed": false}
		var pc: Dictionary = b.places.get(id, {})
		if not pc.is_empty():
			e.merge({"x": pc["x"], "y": pc["y"], "facing": pc["facing"], "placed": true}, true)
		squads.append(e)
	return {"facing": a["facing"], "area": Array(d), "joining": joining, "squads": squads}


## Reaction opportunities for the player during the reaction window, across
## its battles: [{"engagement", "squad", "player", "trigger", "tick",
## "reactions"}], by engagement then forecast order.
func reaction_opportunities(player: int) -> Array:
	if clock.phase != PulseClock.Phase.REACTION:
		return []
	var out := []
	var eids: Array = _opportunities.keys()
	eids.sort()
	for eid: int in eids:
		for o: Dictionary in _opportunities[eid]:
			if o["player"] == player:
				var x := o.duplicate()
				x["engagement"] = eid
				out.append(x)
	return out


## Enemy attack telegraphs in one battle during the reaction window
## (BattleSession.telegraphs): [{"attacker", "target", "damage" (fixed),
## "kills", "tick"}] on the player's squads; [] outside REACTION.
func telegraphs(player: int, engagement_id: int) -> Array:
	if clock.phase != PulseClock.Phase.REACTION:
		return []
	if want_telegraphs and not _telegraphs.has(engagement_id) and battles.has(engagement_id):
		# Lazy (sw-pcl): the scratch turn runs only for a battle someone asks about
		# (the focused one), not for every battle at REACTION.
		_telegraphs[engagement_id] = Reactions.forecast_all((battles[engagement_id] as OverworldBattle).state, _battle_sim)["telegraphs"]
	return (_telegraphs.get(engagement_id, []) as Array).filter(
		func(t: Dictionary) -> bool: return t["player"] == player)


## Queues a reaction for one of the player's squads in a battle (Reaction
## phase only). "" or why not.
func submit_reaction(player: int, engagement_id: int, squad: int, reaction: String, trigger: int) -> String:
	if clock.phase != PulseClock.Phase.REACTION:
		return "reactions are only accepted in the reaction window"
	var b: OverworldBattle = battles.get(engagement_id)
	var ok := false
	for o: Dictionary in _opportunities.get(engagement_id, []):
		if o["player"] == player and o["squad"] == squad and o["trigger"] == trigger and reaction in o["reactions"]:
			ok = true
			break
	if b == null or not ok:
		return "no such reaction opportunity"
	var err := Reactions.queue(b.state, squad, reaction, trigger)
	if err.is_empty():
		_log(player, "reaction", {"engagement": engagement_id, "squad": squad, "reaction": reaction, "trigger": trigger})
	return err


## A commander whose own squad is not fighting leaves its battle.
func leave_battle(player: int, commander_id: int) -> String:
	var err := _planning(player)
	if err.is_empty():
		err = OverworldOrders.leave_battle(state, player, commander_id)
	if err.is_empty():
		_log(player, "leave", {"commander": commander_id})
	return err


## What the player can still bring into battle `eid`, per commander of its
## there (sw-dek): [{"commander", "open" (battleforce slots free), "squads":
## [{"squad", "tmpl", "alive", "size", "sent" (joins at the next Reveal),
## "why" (why it can't be sent now, "" if it can)}]}]. Commanders with nothing
## in reserve are left out.
func reserves(player: int, eid: int) -> Array:
	var out := []
	var b: OverworldBattle = battles.get(eid)
	if b == null:
		return out
	var c := state.commanders
	var q := state.squads
	var joined := {}
	for bid: int in b.links:
		joined[b.links[bid]] = true
	var phase_err := _planning(player)
	for row in c.count():
		if c.player[row] != player or c.engagement[row] != eid:
			continue
		var cid := c.id_at(row)
		var in_field := _in_field(b, cid)
		var squads := []
		for id in OverworldArmies.of(state, cid):
			var r := q.row_of(id)
			var sent := q.deployed[r] == eid and not joined.has(id)
			if q.own[r] == 1 or q.alive[r] <= 0 or (q.deployed[r] >= 0 and not sent):
				continue
			var why := ""
			if not sent:
				why = phase_err if not phase_err.is_empty() else OverworldOrders.reinforce_error(state, player, cid, id, in_field)
			squads.append({"squad": id, "tmpl": q.tmpl[r], "alive": q.alive[r], "size": q.size[r], "sent": sent, "why": why})
		if not squads.is_empty():
			out.append({"commander": cid, "open": maxi(rules.bf_cap_squads - in_field, 0), "squads": squads})
	return out


## The commander's squads still fighting in battle b, plus those on the way.
func _in_field(b: OverworldBattle, cid: int) -> int:
	var n := 0
	var linked := {}
	for bid: int in b.links:
		var id: int = b.links[bid]
		linked[id] = true
		if id < 0 or not state.squads.is_alive(id) or state.squads.get_value(id, &"holder") != cid:
			continue
		var row := b.state.squads.row_of(bid)
		if row >= 0 and b.state.squads.is_active(row):
			n += 1
	for id in OverworldBattleforce.deployed_in(state, b.engagement):
		if not linked.has(id) and state.squads.get_value(id, &"holder") == cid:
			n += 1
	return n


## Moves a squad between two of the player's commanders on one hex (R7Q9).
func transfer_squad(player: int, squad_id: int, to_commander: int) -> String:
	var err := _planning(player)
	if err.is_empty():
		err = OverworldOrders.transfer_squad(state, player, squad_id, to_commander)
	if err.is_empty():
		_log(player, "transfer", {"squad": squad_id, "to": to_commander})
	return err


func ready(player: int) -> void:
	if locked or not _players.has(player):
		return
	_log(player, "ready", null)
	clock.mark_ready(player)
	_pump()


## Feeds elapsed time (ms). Headless drivers may skip it and rely on ready.
func advance(ms: int) -> void:
	if locked or ms <= 0:
		return
	_log(0, "advance", ms)
	clock.advance(ms)
	_pump()


func _planning(player: int) -> String:
	if locked:
		return "this is a replay: it takes no orders"
	if clock.phase != PulseClock.Phase.PLANNING:
		return "orders are only accepted during planning"
	if not _players.has(player):
		return "unknown player"
	return ""


# --- clock -----------------------------------------------------------------

func _on_pulse(point: StringName, _turn: int) -> void:
	bus.flush(point)


func _on_phase(phase: PulseClock.Phase, _turn: int) -> void:
	match phase:
		PulseClock.Phase.REVEAL:
			_reveal_battles()
			clock.config.reaction_enabled = _reactions_allowed and not battles.is_empty()
		PulseClock.Phase.REACTION:
			_opportunities = {}
			_telegraphs = {}
			var ids: Array = battles.keys()
			ids.sort()
			for eid: int in ids:
				var bstate := (battles[eid] as OverworldBattle).state
				var fc := Reactions.forecast_all(bstate, _battle_sim, false)
				_opportunities[eid] = fc["opportunities"]
				if Reactions.any_reactions(bstate):
					_telegraphs[eid] = fc["telegraphs"]  # the scratch turn ran anyway
				# else: telegraphs() computes them lazily for a battle that is looked at (sw-pcl)
			_auto_ready = true
		PulseClock.Phase.EXECUTE:
			_execute_pending = true


## Runs work the clock asked for, outside the clock's own call stack.
func _pump() -> void:
	while _execute_pending or _auto_ready:
		if _auto_ready:
			_auto_ready = false
			for p in _players:
				if clock.phase == PulseClock.Phase.REACTION and reaction_opportunities(p).is_empty():
					clock.mark_ready(p)
			continue
		_execute_pending = false
		_opportunities = {}
		_telegraphs = {}
		PerfRecorder.begin(&"sim_battles")
		_run_battles()
		PerfRecorder.end(&"sim_battles")
		PerfRecorder.begin(&"sim_overworld")
		last_events = OverworldTurn.resolve(state)
		PerfRecorder.end(&"sim_overworld")
		_start_battles()
		_plan_arrivals()
		if rules.triggers != null:
			rules.triggers.run(state, state.events.all(), false)  # battles starting, guards dispersed
		_count_battles()
		last_events.append_array(state.events.drain())
		var h := state_hash_hex()
		var i := turn_hashes.size()
		turn_hashes.append(h)
		if _diverged < 0 and i < _expected.size() and _expected[i] != h:
			_diverged = i + 1
		clock.execute_finished()


## Reveal: reinforcements join every battle, the neutral side (guards,
## Angels) gets its orders from GuardController, and every side's orders
## apply.
func _reveal_battles() -> void:
	var ids: Array = battles.keys()
	ids.sort()
	for eid: int in ids:
		var b: OverworldBattle = battles[eid]
		BattleDeploy.reveal(b.state, b.deploys)
		b.deploys = {}
		OverworldBattles.reinforce(state, b)
		var n := OverworldBattles.NEUTRAL
		if b.state.players.has(n):
			b.orders[n] = GuardController.orders(BattleSession.observe_state(b.state, n), b.rules, n)
		for p in b.state.players:
			BattleOrders.apply(b.state, p, b.orders.get(p, []))
		b.orders = {}


## Planning starts: fix where each joining side arrives (C12).
func _plan_arrivals() -> void:
	var ids: Array = battles.keys()
	ids.sort()
	for eid: int in ids:
		OverworldBattles.plan_arrivals(state, battles[eid])


## Each player's battle count drives its bonus time (R3Q1).
func _count_battles() -> void:
	for p in _players:
		var n := 0
		for eid: int in battles:
			if (battles[eid] as OverworldBattle).state.players.has(p):
				n += 1
		clock.set_battles(p, n)


## One battle turn in every battle, then finished battles are applied.
func _run_battles() -> void:
	var ids: Array = battles.keys()
	ids.sort()
	var done := []
	_playback = {}
	for eid: int in ids:
		var b: OverworldBattle = battles[eid]
		if keep_playback:
			_record_turn(eid, b)
		else:
			_battle_sim.execute_turn(b.state)
		_record_bands(eid, b)
		if b.state.is_over():
			done.append(eid)
	for eid: int in done:
		var b: OverworldBattle = battles[eid]
		OverworldBattles.finish(state, b)
		bus.unregister_context(b.context_id)
		battles.erase(eid)
		_band_history.erase(eid)


## Runs one battle turn, keeping a frame per tick (and one before the
## first): PLAYBACK_STRIDE ints per unit, and the turn's shot and hit traces
## (BattleState.trace_shots). Whatever hook the sim already has still runs.
func _record_turn(eid: int, b: OverworldBattle) -> void:
	var frames: Array[PackedInt64Array] = []
	var first_tick := b.state.tick
	var was := _battle_sim.tick_hook
	# The turn's start, orders applied, and keyframes, for BattleCursor
	# (sw-tho3.7).
	var start := BattleCursor.capture(b.state)
	var capture := func(st: BattleState) -> void:
		if was.is_valid():
			was.call(st)
		if frames.size() <= b.rules.ticks_per_turn:
			frames.append(_frame(st))
			BattleCursor.keyframe(start, st, frames.size() - 1)
	frames.append(_frame(b.state))
	_battle_sim.tick_hook = capture
	b.state.trace_shots = true
	b.state.shot_trace = PackedInt64Array()
	b.state.hit_trace = PackedInt64Array()
	_battle_sim.execute_turn(b.state)
	b.state.trace_shots = false
	_battle_sim.tick_hook = was
	BattleCursor.seal(start, b.state)
	var last := frames.size() - 1
	var shots := []
	for e in b.state.turn_log:
		if e.type == &"squad_fired":
			shots.append([clampi(e.tick - first_tick + 1, 0, last), int(e.data["squad"]), int(e.data["target"])])
	# Frame i holds the state after tick first_tick + i - 1, so what happened
	# in a tick shows from the frame after it.
	var volleys := []
	var st := b.state.shot_trace
	for o in range(0, st.size(), BattleState.SHOT_STRIDE):
		volleys.append([clampi(st[o] - first_tick + 1, 0, last), st[o + 1], st[o + 2], st[o + 3] == 1])
	var hits := []
	var ht := b.state.hit_trace
	for o in range(0, ht.size(), BattleState.HIT_STRIDE):
		hits.append([clampi(ht[o] - first_tick + 1, 0, last), ht[o + 1], ht[o + 2], ht[o + 3]])
	b.state.shot_trace = PackedInt64Array()
	b.state.hit_trace = PackedInt64Array()
	_playback[eid] = {"rules": b.rules, "players": b.state.players.duplicate(), "frames": frames,
		"shots": shots, "volleys": volleys, "hits": hits, "start": start}


## A BattleCursor over the last recorded turn of battle `eid` (needs
## keep_playback): the full, all-seeing state at any tick of that turn. Its
## seek(i) matches playback frame i. Unavailable (never null) when nothing
## was recorded. Tooling and the all-seeing replay only: it shows hidden
## squads, so callers filter by what a player saw. One cursor per recorded
## turn, kept with the record (so it is dropped when the playback is).
func turn_cursor(eid: int) -> BattleCursor:
	var rec: Dictionary = _playback.get(eid, {})
	if not rec.has("cursor"):
		rec["cursor"] = BattleCursor.new(rec.get("start", {}), rec.get("rules"))
	return rec["cursor"]


## The battle tick a playback frame shows (sw-bafi.5). Frame i is the state
## after i ticks of the turn, before the turn resolves (frame 0 the turn's
## start, frame `ticks` the last tick): the recorder's tick hook captures.
## Frames index the playback, so any pacing of it (sw-ll4.26.6) reaches the
## same tick.
static func tick_of_frame(frame: int, ticks: int) -> int:
	return clampi(frame, 0, ticks)


## SquadRelation.facts(a, b) at playback frame `frame` of battle `eid`'s last
## turn, as `player` sees it (0 or less: all-seeing). The state is the
## turn's BattleCursor at that frame's tick, so it is exactly the state the
## live battle had then. [] when the battle has no playback this turn, the
## player did not fight in it, the frame is out of range, or the turn has no
## usable snapshot (an old record): never an error.
func playback_relation(player: int, eid: int, frame: int, a: int, b: int) -> Array:
	var rec: Dictionary = _playback.get(eid, {})
	if rec.is_empty():
		return []
	var viewer := maxi(player, 0)
	if viewer != 0 and not (rec["players"] as PackedInt64Array).has(viewer):
		return []
	if frame < 0 or frame >= (rec["frames"] as Array).size():
		return []
	var c := turn_cursor(eid)
	var st := c.seek_unresolved(tick_of_frame(frame, c.ticks))
	if st == null:
		return []
	return SquadRelation.facts(st, viewer, a, b)


## Ints per unit in a playback frame: ID, squad, player, x, y, squad facing,
## seen_by, template, HP, max HP, activity (BattleSession.ACT_* bits),
## hold-fire reason (BattleActivity.Hold), squad activity (BattleActivity.
## Squad, raw), reload left, cooldown left, ammo (sw-ll4.27.2).
const PLAYBACK_STRIDE: int = 16
## One playback frame of `state` (PLAYBACK_STRIDE ints per unit); read-only.
static func playback_frame(st: BattleState) -> PackedInt64Array:
	return _frame(st)


static func _frame(st: BattleState) -> PackedInt64Array:
	var u := st.units
	var sq := st.squads
	var f := PackedInt64Array()
	for row in u.count():
		var srow := sq.row_of(u.squad[row])
		if srow < 0 or not sq.is_active(srow):
			continue
		f.append_array(PackedInt64Array([u.id_at(row), u.squad[row], sq.player[srow], u.x[row], u.y[row], sq.facing[srow], sq.seen_by[srow],
			u.tmpl[row], u.hp[row], u.hp_max[row], BattleSession.activity(st, row),
			BattleActivity.hold(st, row), BattleActivity.squad(st, srow), u.reload[row], u.cooldown[row], u.ammo[row]]))
	return f


## The last resolved turn of every battle `player` fought in, tick by tick
## and as the player saw it (needs keep_playback): engagement ID ->
## {"rules" (BattleRules), "width", "height", "frames": one Dictionary per
## tick (the first is the turn's start), squad ID -> {"player", "facing",
## "ids": unit IDs, "units": their points in metres, "tmpls": unit template
## IDs, "hp": HP fractions (0..1), "acts": activity bits (ACT_*), "activity":
## BattleActivity.Squad code (enemy squads: behaviour only)}, own squads
## also per unit "holds" (BattleActivity.Hold), "reload", "cooldown", "ammo"
## (sw-ll4.27.2), "shots":
## [[frame, squad, target]] where the player saw both ends, "volleys":
## [[frame, shooter unit, victim unit, hit]] every shot where the player saw
## both units, landing (or passing) at that frame, and "hits": [[frame,
## victim unit, damage (fixed), by unit]] every hit on a unit the player saw}.
## A battle that ended this turn is still here.
func playback(player: int) -> Dictionary:
	PerfRecorder.begin(&"playback_build")
	var out := {}
	for eid: int in _playback:
		var rec: Dictionary = _playback[eid]
		if player > 0 and not (rec["players"] as PackedInt64Array).has(player):
			continue
		out[eid] = playback_entry(rec, player)
	PerfRecorder.end(&"playback_build")
	return out


## One recorded battle as `player` saw it (0 or less: all-seeing), in
## playback's entry format. `rec` holds "rules", "frames" (playback_frame
## per tick), "shots", "volleys" and "hits" as _record_turn keeps them; the
## behaviour workshop (WorkshopRun.playback) builds one for a whole run.
static func playback_entry(rec: Dictionary, player: int) -> Dictionary:
	var all_seeing := player <= 0  # the replay's all-seeing view
	var me := 0 if all_seeing else BattleSquads.bit(player)
	var r: BattleRules = rec["rules"]
	var frames := []
	# Per frame, the unit IDs the player saw.
	var seen := []
	for f: PackedInt64Array in rec["frames"]:
		var squads := {}
		var units := {}
		for o in range(0, f.size(), PLAYBACK_STRIDE):
			if f[o + 2] != player and not all_seeing and f[o + 6] & me == 0:
				continue
			var own_unit := f[o + 2] == player
			if not squads.has(f[o + 1]):
				squads[f[o + 1]] = {"player": f[o + 2], "facing": f[o + 5], "ids": [], "units": [], "tmpls": [], "hp": [], "acts": [],
					"activity": f[o + 12] if own_unit else BattleActivity.squad_public(f[o + 12], f[o + 10] & BattleSession.ACT_MOVING != 0)}
				if own_unit:
					squads[f[o + 1]]["holds"] = []
					squads[f[o + 1]]["reload"] = []
					squads[f[o + 1]]["cooldown"] = []
					squads[f[o + 1]]["ammo"] = []
			var d: Dictionary = squads[f[o + 1]]
			(d["ids"] as Array).append(f[o])
			(d["units"] as Array).append(Vector2(f[o + 3], f[o + 4]) / float(Fixed.ONE))
			var t := f[o + 7]
			(d["tmpls"] as Array).append(r.unit_ids[t] if t >= 0 and t < r.unit_ids.size() else "")
			(d["hp"] as Array).append(clampf(float(f[o + 8]) / maxf(float(f[o + 9]), 1.0), 0.0, 1.0))
			(d["acts"] as Array).append(f[o + 10])
			if own_unit:
				(d["holds"] as Array).append(f[o + 11])
				(d["reload"] as Array).append(f[o + 13])
				(d["cooldown"] as Array).append(f[o + 14])
				(d["ammo"] as Array).append(f[o + 15])
			units[f[o]] = true
		frames.append(squads)
		seen.append(units)
	var shots := []
	for sh: Array in rec["shots"]:
		var at: Dictionary = frames[sh[0]]
		if at.has(sh[1]) and at.has(sh[2]):
			shots.append(sh)
	# A shot is shown when the player saw both units the tick before it
	# (a victim it killed is gone from the frame it lands in).
	var volleys := []
	for v: Array in rec.get("volleys", []):
		var at: Dictionary = seen[maxi(v[0] - 1, 0)]
		if at.has(v[1]) and at.has(v[2]):
			volleys.append(v)
	var hits := []
	for h: Array in rec.get("hits", []):
		if (seen[maxi(h[0] - 1, 0)] as Dictionary).has(h[1]):
			hits.append(h)
	return {"rules": r, "width": r.width, "height": r.height, "frames": frames, "shots": shots,
		"volleys": volleys, "hits": hits}


## Battles begin at the start of a turn (R2Q1): every engagement without one
## gets it now, or ends at once if nobody opposes.
func _start_battles() -> void:
	for eid in state.engagements.ids():
		if battles.has(eid) or not state.engagements.is_alive(eid):
			continue
		var before := errors.size()
		var b := OverworldBattles.build(templates, data_hash, state, eid, _next_context,
			(seed_value * 7919 + _next_context) & 0x7fffffff, errors)
		if b == null:
			if errors.size() > before:
				push_warning("OverworldSession: %s" % errors[errors.size() - 1])
			OverworldBattles.finish_unopposed(state, eid)
			continue
		_next_context += 1
		battles[eid] = b
		bus.register_context(b.state)
		_record_bands(eid, b)


## The overworld's hash combined with every battle's (desync checks).
func state_hash_hex() -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(state.state_hash())
	var ids: Array = battles.keys()
	ids.sort()
	for eid: int in ids:
		h.update(PackedInt64Array([eid, _next_context]).to_byte_array())
		h.update((battles[eid] as OverworldBattle).state.state_hash())
	return h.finish().hex_encode()


# --- queries ---------------------------------------------------------------

## What `player` may know (OverworldVision.observe), plus the clock, the map
## size and the visible events of the last resolved turn.
func observe(player: int) -> Dictionary:
	var o := OverworldVision.observe(state, player)
	o["phase"] = phase_name()
	o["remaining_ms"] = clock.remaining_ms(player)
	o["width"] = rules.width
	o["height"] = rules.height
	var evs := []
	for e in OverworldVision.filter_events(state, player, last_events):
		evs.append(e.to_dict())
	o["events"] = evs
	for bt: Dictionary in o["battles"]:
		bt["battle"] = battles.has(bt["engagement"])
	o["reactions"] = reaction_opportunities(player)
	o["outcome"] = state.outcome.duplicate()
	return o


## One battle as `player` sees it ({} unless the player fights in it): the
## battle observation, plus "engagement" and "links" (battle squad ID ->
## overworld squad ID, own squads only).
func observe_battle(player: int, engagement_id: int) -> Dictionary:
	var b: OverworldBattle = battles.get(engagement_id)
	if b == null or (player > 0 and not b.state.players.has(player)):
		return {}
	var o := BattleSession.observe_state(b.state, player, _allies(b, player))
	o["engagement"] = engagement_id
	o["phase"] = phase_name()
	var mine := {}
	for bid: int in b.links:
		var id: int = b.links[bid]
		if id >= 0 and b.state.squads.row_of(bid) >= 0 and b.state.squads.player[b.state.squads.row_of(bid)] == player:
			mine[bid] = id
	o["links"] = mine
	return o


## The glance summary of one battle for `player` ({} unless it fights in
## it): the worst SIMPL band across its OWN squads still fighting, as
## {"band" (name), "pool" (its SIMPL pool), "squad" (battle squad ID),
## "trend", "prev_band" (the last recorded worst band, "" before any
## record)}. The trend is backward-looking — the current worst band against
## the one recorded after the battle's previous turn (or its start):
## "worsening", "improving", "steady", or "new" with no record yet. Never a
## forecast of pending orders (GDD 02 §2.2 Vacuum stays "Not yet").
## Read-only, any phase; enemy pools are never read (fog-safe).
func battle_summary(player: int, engagement_id: int) -> Dictionary:
	var b: OverworldBattle = battles.get(engagement_id)
	if b == null or not b.state.players.has(player):
		return {}
	var worst := _worst_own_band(b, player)
	if worst.is_empty():
		return {}
	var prev: int = (_band_history.get(engagement_id, {}) as Dictionary).get(player, -1)
	var trend := "new"
	if prev >= 0:
		trend = "worsening" if worst["band"] < prev else ("improving" if worst["band"] > prev else "steady")
	return {"band": DataSchema.BANDS[worst["band"]], "pool": DataSchema.SIMPL[worst["pool"]], "squad": worst["squad"],
		"trend": trend, "prev_band": DataSchema.BANDS[prev] if prev >= 0 else ""}


## The lowest band across the player's own active squads and all five SIMPL
## pools, by the sim's own mapping (Pools.band): {"band", "pool", "squad"}
## of the first worst entry (store order breaks ties), or {} with no own
## squad fighting.
static func _worst_own_band(b: OverworldBattle, player: int) -> Dictionary:
	var out := {}
	var sq := b.state.squads
	for row in sq.count():
		if sq.player[row] != player or not sq.is_active(row):
			continue
		for p in DataSchema.SIMPL.size():
			var band := Pools.band(b.state, row, p)
			if out.is_empty() or band < int(out["band"]):
				out = {"band": band, "pool": p, "squad": sq.id_at(row)}
	return out


## Records every side's worst own band: the trend's reference point.
func _record_bands(eid: int, b: OverworldBattle) -> void:
	var h: Dictionary = _band_history.get(eid, {})
	for p in b.state.players:
		var w := _worst_own_band(b, p)
		if not w.is_empty():
			h[p] = w["band"]
	_band_history[eid] = h


## The inspection window's data for one squad of a battle (Inspection), as
## BattleSession.inspect: own squads always, enemy squads only while seen.
func inspect_battle(player: int, engagement_id: int, squad_id: int) -> Dictionary:
	var b: OverworldBattle = battles.get(engagement_id)
	if b == null or not b.state.players.has(player):
		return {}
	var row := b.state.squads.row_of(squad_id)
	if row < 0:
		return {}
	var own := b.state.squads.player[row] == player
	if not own and (b.state.squads.seen_by[row] & BattleSquads.bit(player) == 0 or not b.state.squads.is_active(row)
			or BattleDeploy.hides(b.state, player, row, _allies(b, player))):
		return {}
	return Inspection.squad(b.state, squad_id, player)


## The other players in battle b on the player's team (OverworldState.teams).
func _allies(b: OverworldBattle, player: int) -> PackedInt64Array:
	var out := PackedInt64Array()
	for p in b.state.players:
		if p != player and not state.hostile(p, player):
			out.append(p)
	return out


## What `player` knows about one hex, for inspecting it (hover cards, the
## selection panel): {"plot", "known" (ever seen), "visible" (in sight
## now), "cost" (movement points to enter, -1 impassable), "features":
## [{"id", "name", "owner", "controllable", "guard": squad names,
## "value_per_turn", "cache_value", "activities": names, "recruits":
## [{"id", "name", "cost"}], "hires": [{"id", "name", "cost"}], "produces": [{"name", "turns", "cost", "selected",
## "progress" (own, selected option only; else -1)}], "line" (own: where
## its output goes: {"plot", "commander"} or {})}], "commanders": [{"id",
## "player", "squads" (own: army size, else -1), "engagement"}],
## "detachments": [{"id", "player", "convoy", "squads" (own: names)}],
## "battle" (an engagement there)}. Read-only, any phase. Each feature is
## inspect_feature's facts without its plot, visible and turn keys.
func inspect_plot(player: int, plot: int) -> Dictionary:
	var out := {"plot": plot, "known": false, "visible": false, "cost": -1, "features": [], "commanders": [], "detachments": [], "battle": false}
	if plot < 0 or plot >= rules.plot_count() or not _players.has(player):
		return out
	var obs := OverworldVision.observe(state, player)
	var entry: Dictionary = (obs["plots"] as Dictionary).get(plot, {})
	if entry.is_empty():
		return out
	out["known"] = true
	out["visible"] = bool(entry.get("visible", false))
	out["cost"] = OverworldVision.known_costs(state, player)[plot]
	for f: Dictionary in entry.get("features", []):
		var fact := _feature_facts(obs, int(f["id"]), int(f["tmpl"]), int(f.get("owner", 0)))
		if not fact.is_empty():
			out["features"].append(fact)
	for c: Dictionary in obs.get("commanders", []):
		if int(c["plot"]) == plot:
			out["commanders"].append({"id": c["id"], "player": c["player"], "engagement": c["engagement"],
				"squads": (c["army"] as Array).size() if c.has("army") else -1})
	for d: Dictionary in obs.get("detachments", []):
		if int(d["plot"]) == plot:
			var names := PackedStringArray()
			for q: Dictionary in d.get("squads", []):
				names.append(rules.sq_names[int(q["tmpl"])])
			out["detachments"].append({"id": d["id"], "player": d["player"], "convoy": d.get("convoy", false), "squads": names})
	for b: Dictionary in obs.get("battles", []):
		if int(b["plot"]) == plot:
			out["battle"] = true
	return out


## One feature as `player` knows it (feature_id, from its observation `obs`):
## the facts inspect_plot lists, plus "plot", "visible" (in sight now) and
## "turn" (now if visible, else the turn it was last seen, from memory).
## Dead features (despawned), unknown IDs and features the player never saw
## give {}. Enemy features carry no progress, selected output or supply line:
## those come only from the owner's own production and lines.
func inspect_feature(player: int, feature_id: int) -> Dictionary:
	if not _players.has(player):
		return {}
	var row := state.features.row_of(feature_id)
	if row < 0:
		return {}
	var plot := state.features.plot[row]
	var obs := OverworldVision.observe(state, player)
	var entry: Dictionary = (obs["plots"] as Dictionary).get(plot, {})
	for f: Dictionary in entry.get("features", []):
		if int(f["id"]) != feature_id:
			continue
		var out := _feature_facts(obs, feature_id, int(f["tmpl"]), int(f.get("owner", 0)))
		if out.is_empty():
			return {}
		out["plot"] = plot
		out["visible"] = bool(entry.get("visible", false))
		out["turn"] = int(entry.get("turn", -1))
		return out
	return {}


## One feature's facts (see inspect_plot), from the observation `obs` of the
## player: its template `t` and the owner it is known to have. {} if the
## template is unknown.
func _feature_facts(obs: Dictionary, fid: int, t: int, owner: int) -> Dictionary:
	if t < 0 or t >= rules.hf_names.size():
		return {}
	var production: Dictionary = obs.get("production", {})
	var lines: Dictionary = obs.get("supply_lines", {})
	var guard := PackedStringArray()
	for g in rules.hf_guard[t]:
		var gi := rules.squad_index(g)
		guard.append(rules.sq_names[gi] if gi >= 0 else g)
	var acts := PackedStringArray()
	for i in OverworldRules.ACTIVITIES.size():
		if rules.hf_activities[t] & (1 << i) != 0:
			acts.append(OverworldRules.ACTIVITIES[i])
	var recruits := []
	for i in range(0, rules.hf_recruits[t].size(), 2):
		recruits.append({"id": rules.squad_ids[rules.hf_recruits[t][i]], "name": rules.sq_names[rules.hf_recruits[t][i]], "cost": rules.hf_recruits[t][i + 1]})
	var hires := []
	for i in range(0, rules.hf_hires[t].size(), 2):
		var cm := rules.hf_hires[t][i]
		hires.append({"id": rules.commander_ids[cm], "name": rules.cm_names[cm], "cost": rules.hf_hires[t][i + 1]})
	var produces := []
	var opts := rules.hf_produces[t]
	var made: Dictionary = production.get(fid, {})
	@warning_ignore("integer_division")
	for i in opts.size() / OverworldRules.PRODUCTION_STRIDE:
		var o := i * OverworldRules.PRODUCTION_STRIDE
		var what := rules.sq_names[opts[o]] if opts[o] >= 0 else "%d × %s" % [opts[o + 4], rules.it_names[opts[o + 3]] if opts[o + 3] >= 0 else "item"]
		var chosen: bool = not made.is_empty() and int(made["output"]) == i
		produces.append({"name": what, "turns": opts[o + 1], "cost": opts[o + 2], "selected": chosen,
			"progress": int(made["progress"]) if chosen else -1})
	return {"id": fid, "name": rules.hf_names[t], "owner": owner,
		"controllable": rules.hf_controllable[t] == 1, "guard": guard, "value_per_turn": rules.hf_value_per_turn[t],
		"cache_value": rules.hf_cache_value[t], "activities": acts, "recruits": recruits, "hires": hires, "produces": produces,
		"line": (lines.get(fid, {}) as Dictionary).duplicate()}


## A commander's movement this turn, as the player knows the map:
## {"budget", "spent" (by its planned route), "reach": plot -> cheapest cost
## from where it stands}. {} if it is not the player's.
func reach(player: int, commander_id: int) -> Dictionary:
	var row := state.commanders.row_of(commander_id)
	if row < 0 or state.commanders.player[row] != player:
		return {}
	var budget := Commanders.budget(state, row)
	var costs := OverworldVision.known_costs(state, player)
	var spent := 0
	for p: int in state.routes.get(commander_id, PackedInt64Array()):
		spent += maxi(costs[p], 0)
	var held := state.commanders.engagement[row] >= 0
	return {"budget": budget, "spent": spent,
		"reach": {} if held else OverworldPath.reach(state, state.commanders.plot[row], budget, player)}


## The cheapest route for a commander to plot `to`, as the player knows the
## map, cut to what it can afford this turn. Empty if none. With `via` (a
## route it already plans), the way continues from that route's end and the
## result is the whole route: waypoints.
func path(player: int, commander_id: int, to: int, via: PackedInt64Array = PackedInt64Array()) -> PackedInt64Array:
	var row := state.commanders.row_of(commander_id)
	if row < 0 or state.commanders.player[row] != player:
		return PackedInt64Array()
	var from := state.commanders.plot[row] if via.is_empty() else via[via.size() - 1]
	var full := OverworldPath.find(state, from, to, player)
	var costs := OverworldVision.known_costs(state, player)
	var budget := Commanders.budget(state, row)
	var out := via.duplicate()
	var spent := 0
	for p in via:
		spent += maxi(costs[p], 0)
	if full.is_empty():
		return PackedInt64Array()
	for p in full:
		spent += costs[p]
		if spent > budget:
			break
		out.append(p)
	return out


# --- persistence and replays (R8Q5) ----------------------------------------

## A save: the input log, per-turn hashes and data identity, plus a
## snapshot at a phase boundary to resume from.
func save() -> PackedByteArray:
	assert(clock.phase != PulseClock.Phase.EXECUTE, "OverworldSession.save: not during execute")
	var events := []
	for e in last_events:
		events.append(e.to_dict())
	var data := {
		"version": SAVE_VERSION, "map": map_id, "seed": seed_value, "data_hash": data_hash,
		"clock_config": _saved_config(), "inputs": input_log.duplicate(true),
		"hashes": turn_hashes.duplicate(), "state": state.snapshot(), "clock": clock.snapshot(),
		"last_events": events, "hash": state_hash_hex(),
		"battles": _battles_dict(), "next_context": _next_context,
		"opportunities": _opportunities.duplicate(true), "telegraphs": _telegraphs.duplicate(true), "band_history": _band_history.duplicate(true),
	}
	return var_to_bytes(data).compress(FileAccess.COMPRESSION_GZIP)


## Loads a save from its snapshot. Null if the content differs.
static func load_save(bytes: PackedByteArray, templates: TemplateTable, hash_hex: String) -> OverworldSession:
	last_error = ""
	var data: Variant = _decode(bytes)
	if typeof(data) != TYPE_DICTIONARY or data.get("version") != SAVE_VERSION:
		last_error = "unreadable save"
		return null
	if data["data_hash"] != hash_hex:
		last_error = "content differs from the save's (different mods or version)"
		return null
	var r := OverworldRules.compile(templates, data["map"], hash_hex)
	var s := OverworldSession.new()
	s._setup(templates, r, data["map"], data["seed"], hash_hex, _config_from(data["clock_config"]))
	s.state.restore(data["state"])
	s.clock.restore(data["clock"])
	s.input_log = data["inputs"]
	s.turn_hashes = data["hashes"]
	for e: Dictionary in data["last_events"]:
		var ev := SimEvent.new(e["type"], e["data"])
		ev.source = e["source"]
		ev.seq = e["seq"]
		ev.tick = e["tick"]
		s.last_events.append(ev)
	var bd: Dictionary = data.get("battles", {})
	for eid: int in bd:
		var b := OverworldBattles.from_dict(templates, hash_hex, bd[eid])
		if not (bd[eid] as Dictionary).has("arrivals") and s.clock.phase == PulseClock.Phase.PLANNING:
			OverworldBattles.plan_arrivals(s.state, b)  # a save from before C12
		s.battles[eid] = b
		s.bus.register_context(b.state)
	s._next_context = data.get("next_context", 100)
	s._opportunities = data.get("opportunities", {})
	s._telegraphs = data.get("telegraphs", {})
	s._band_history = data.get("band_history", {})
	if s.state_hash_hex() != data["hash"]:
		last_error = "the saved state does not match its hash"
		return null
	return s


## The clock config as created (reaction_enabled as allowed, not as this
## turn has it).
func _saved_config() -> Dictionary:
	var d := _config_dict(clock.config)
	d["reaction_enabled"] = _reactions_allowed
	return d


func _battles_dict() -> Dictionary:
	var out := {}
	for eid: int in battles:
		out[eid] = OverworldBattles.to_dict(battles[eid])
	return out


## Replays a save's inputs from the start without trusting its snapshot,
## checking the state hash after every turn. Null on the first turn that
## differs (last_error names it) or if the end state differs.
static func rebuild(bytes: PackedByteArray, templates: TemplateTable, hash_hex: String) -> OverworldSession:
	last_error = ""
	var data: Variant = _decode(bytes)
	if typeof(data) != TYPE_DICTIONARY or data.get("data_hash") != hash_hex:
		last_error = "unreadable save or different content"
		return null
	var s := create(templates, hash_hex, data["map"], data["seed"], _config_from(data["clock_config"]))
	if s == null:
		return null
	s._expected = data["hashes"]
	s.replay_inputs(data["inputs"])
	s._expected = PackedStringArray()
	if s._diverged > 0:
		last_error = "turn %d did not reproduce its recorded hash" % s._diverged
		return null
	if s.turn_hashes.size() != (data["hashes"] as PackedStringArray).size() or s.state_hash_hex() != data["hash"]:
		last_error = "inputs did not reproduce the saved state"
		return null
	return s


## Re-applies logged inputs in order.
func replay_inputs(inputs: Array) -> void:
	var was := locked
	locked = false
	_replay(inputs)
	locked = was


func _replay(inputs: Array) -> void:
	for i: Dictionary in inputs:
		var p: Variant = i["payload"]
		match i["kind"]:
			"route":
				set_route(i["player"], p["commander"], p["plots"])
			"activity":
				set_activity(i["player"], p["commander"], p["activity"], p.get("option", ""))
			"answer":
				answer_offer(i["player"], p["feature"], p["choice"])
			"drop":
				set_drop_off(i["player"], p["commander"], p["step"], p["plot"])
			"output":
				set_output(i["player"], p["feature"], p["option"])
			"supply":
				set_supply_line(i["player"], p["feature"], p["plot"], p["commander"])
			"rally":
				rally(i["player"], p["detachment"], p["plot"], p["commander"])
			"convoy_route":
				set_convoy_route(i["player"], p["detachment"], p["plots"])
			"equip":
				equip(i["player"], p["commander"], p["item"], p["squad"], p["count"])
			"unequip":
				unequip(i["player"], p["commander"], p["item"], p["count"])
			"give":
				give_item(i["player"], p["from"], p["item"], p["count"], p["to"])
			"take":
				take_items(i["player"], p["commander"], p["detachment"])
			"transfer":
				transfer_squad(i["player"], p["squad"], p["to"])
			"battleforce":
				set_battleforce(i["player"], p["commander"], p["preset"], p["squads"], p["lead"])
			"battle_orders":
				submit_battle_orders(i["player"], p["engagement"], p["orders"])
			"battle_deploy":
				# A draft for a battle that is gone by now is refused here and
				# never logged, so it leaves no effect on replay.
				submit_battle_deployment(i["player"], p["engagement"], p["placements"])
			"reinforce":
				reinforce(i["player"], p["commander"], p["squad"], p.get("place", {}))
			"arrival":
				submit_arrival(i["player"], p["engagement"], p["placements"])
			"leave":
				leave_battle(i["player"], p["commander"])
			"reaction":
				submit_reaction(i["player"], p["engagement"], p["squad"], p["reaction"], p["trigger"])
			"preset":
				save_preset(i["player"], p["name"], p["prefer"], p["avoid"])
			"dialogue_begin":
				dialogue_begin(i["player"], p)
			"dialogue":
				dialogue_pick(i["player"], p["dialogue"], p["choice"])
			"ready":
				ready(i["player"])
			"advance":
				advance(p)


func _log(player: int, kind: String, payload: Variant) -> void:
	input_log.append({"turn": state.turn + 1, "phase": clock.phase, "player": player, "kind": kind,
		"payload": payload.duplicate(true) if payload is Dictionary else payload})


static func _decode(bytes: PackedByteArray) -> Variant:
	var raw := bytes.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	if raw.is_empty():
		return null
	return bytes_to_var(raw)


static func _config_dict(c: ClockConfig) -> Dictionary:
	return BattleSession._config_dict(c)


static func _config_from(d: Dictionary) -> ClockConfig:
	return BattleSession._config_from(d)
