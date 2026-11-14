class_name SimMetrics
extends RefCounted
## The metrics library (GDD 05 §5.2, R7Q17, B1Q10): what a harness run
## measures, for balance, feel and performance analysis and the AI
## factory's scoring (SimCriteria). Read-only: it watches through the battle
## sim's tick hook and reads states, events and input logs; it never changes
## them (the state hash is unchanged by measuring).
##
## Rows: {"metric", "player" (0 = the whole run), "value"}.
## Every run: won, drew, lost, forfeited (per player, 0 or 1); idle_turns
##   (turns with no order but "ready"); forfeit_turn (-1 = none); turn_cap
##   (the turn limit, set by the runner).
## Battles: vp (influence), value_destroyed, value_destroyed.<victim>
##   (player / neutral / civilian, B1Q7), value_lost, units_lost,
##   squads_lost, force_start; zone_ticks (ticks holding an unlocked zone);
##   band.<pool>.<band>: squad-ticks spent in each pressure band;
##   surges.<pool>, breaks.<pool>, band_changes.<pool>: band crossings
##   (Pressure Lab, GDD 05 §5.3); first_break_tick (any Morale break);
##   ledger.<pool>: net SIMPL flow (the per-battle ledger, R6Q3);
##   first_contact_tick, first_casualty_tick, first_capture_turn
##   (milestones, -1 = never; player 0 for the run, and per player);
##   perf.<system>_usec (per-system time).
## Overworld runs: value, value_earned, hexes_explored, fog_revealed_pct,
##   features_owned, feature_turns (features held, summed over turns),
##   commanders_start, commanders_alive, force (Value of squads held);
##   battles (run and per player), first_battle_turn, first_capture_turn,
##   first_contact_turn (run and per player); every battle's metrics summed
##   per player under
##   "battle." (battle.vp, battle.value_destroyed.player, battle.band...).
## Series (`series`, {"metric", "player", "turn", "value"}), sampled at the
##   end of every turn: battles vp, force, zones, contact (0/1); overworld
##   value, force, enemy_force_seen, features_owned, hexes_explored,
##   fog_pct, contact (0/1), threat (the worst ratio of hostile Value within
##   THREAT_RANGE hexes of an own commander to that commander's army
##   Value). The schedule gates (SimCriteria, hx fitness) read these.

const NEUTRAL := 30  # OverworldBattles.NEUTRAL: guards and Angels
const VICTIMS := ["player", "neutral", "civilian"]
const THREAT_RANGE := 2

var rows: Array = []
## Per-turn series rows: {"metric", "player", "turn", "value"}.
var series: Array = []
var _watch: _BattleWatch = null
var _forfeits: Dictionary = {}  # player -> turn
# Overworld runs.
var _x: OverworldSession = null
var _sim: BattleSim = null
var _watches: Dictionary = {}  # BattleState instance ID -> _BattleWatch
var _ow_battles: Dictionary = {}  # engagement ID -> [OverworldBattle, _BattleWatch]
var _events: Array = []
var _first: Dictionary = {}  # "kind|player" -> turn (player 0 = the run)
var _feature_turns: Dictionary = {}
var _commanders_start: Dictionary = {}
var _battles_of: Dictionary = {}  # player -> battles fought


## Records that a player left the game (forfeit, B1Q4): kept apart from
## withdrawing a battleforce (leave_battle), which is a legitimate move.
func forfeit(player: int, turn: int) -> void:
	if not _forfeits.has(player):
		_forfeits[player] = turn


## Starts watching a battle: samples bands every tick.
func watch_battle(state: BattleState, sim: BattleSim) -> void:
	_profile(sim)
	_watch = _BattleWatch.new(state, true)
	sim.tick_hook = func(st: BattleState) -> void: _watch.sample(st, series)


func _profile(sim: BattleSim) -> void:
	sim.runner.profiling = true
	sim.runner.profile = {}


## Battle metrics once it has ended (or stopped). `input_log` is the
## session's (BattleSession.input_log), for idle turns.
func battle(state: BattleState, sim: BattleSim, prefix: String = "", input_log: Array = []) -> Array:
	var acc := {}
	if _watch == null:
		_watch = _BattleWatch.new(state, true)
	_watch.finish(state, series)
	_watch.add_rows(state, acc)
	var out := _flush(acc, prefix)
	var w := _watch
	out.append(_row(prefix + "first_break_tick", 0, w.first_break))
	out.append(_row(prefix + "turns", 0, state.turn))
	out.append(_row(prefix + "first_contact_tick", 0, w.first_contact))
	out.append(_row(prefix + "first_casualty_tick", 0, w.first_casualty))
	out.append(_row(prefix + "first_capture_turn", 0, w.first_capture))
	for p in state.players:
		out.append(_row(prefix + "first_contact_tick", p, w.contact.get(p, -1)))
		out.append(_row(prefix + "first_capture_turn", p, w.capture.get(p, -1)))
	var winner := int(state.result.get("winner", 0)) if state.is_over() else 0
	out.append_array(_results(state.players, winner, state.turn))
	out.append_array(_idle(input_log, state.players, state.turn))
	out.append_array(_perf(sim, prefix))
	return out


## Starts watching an overworld session: its battles are measured through
## the battle sim they run on. Call after_turn() after every resolved turn.
func watch_overworld(x: OverworldSession) -> void:
	_x = x
	_sim = x.battle_sim()
	_profile(_sim)
	_sim.tick_hook = _overworld_tick
	for p in x.players():
		_commanders_start[p] = _commanders(x.state, p)
	_pick_up_battles()


func _overworld_tick(st: BattleState) -> void:
	var id := st.get_instance_id()
	if not _watches.has(id):
		_watches[id] = _BattleWatch.new(st, false)
	(_watches[id] as _BattleWatch).sample(st, series)


func _pick_up_battles() -> void:
	for eid: int in _x.battles:
		if _ow_battles.has(eid):
			continue
		var b: OverworldBattle = _x.battles[eid]
		var id := b.state.get_instance_id()
		if not _watches.has(id):
			_watches[id] = _BattleWatch.new(b.state, false)
		_ow_battles[eid] = [b, _watches[id]]
		for p in b.state.players:
			_battles_of[p] = int(_battles_of.get(p, 0)) + 1
			_mark("battle", p, _x.turns_resolved())
			_mark("contact", p, _x.turns_resolved())


func _mark(kind: String, player: int, turn: int) -> void:
	for k in ["%s|%d" % [kind, player], "%s|0" % kind]:
		if not _first.has(k):
			_first[k] = turn


## After each resolved overworld turn: events, series and new battles.
func after_turn(x: OverworldSession) -> void:
	var turn := x.turns_resolved()
	for e in x.last_events:
		var d := e.to_dict()
		d["turn"] = turn
		_events.append(d)
		if e.type == &"feature_captured":
			_mark("capture", int(e.data["player"]), turn)
	var s := x.state
	_pick_up_battles()
	var plots := maxi(s.rules.plot_count(), 1)
	for p in x.players():
		var owned := _features(s, p)
		_feature_turns[p] = int(_feature_turns.get(p, 0)) + owned
		var seen := _enemy_force_seen(s, p)
		if seen > 0:
			_mark("contact", p, turn)
		var explored := (s.memory.get(p, {}) as Dictionary).size()
		for kv: Array in [["value", s.value_of(p)], ["force", force_of(s, p)], ["enemy_force_seen", seen],
				["features_owned", owned], ["hexes_explored", explored], ["fog_pct", 100.0 * explored / plots],
				["contact", 1 if _first.has("contact|%d" % p) else 0], ["threat", threat(s, p)]]:
			series.append({"metric": kv[0], "player": p, "turn": turn, "value": float(kv[1])})


## Overworld metrics for a played session. `events` is only needed when
## the session was not watched turn by turn (after_turn).
func overworld(x: OverworldSession, events: Array = []) -> Array:
	var s := x.state
	var out := []
	var earned := {}
	var battles := 0
	var all := _events if _x != null else events
	for e: Dictionary in all:
		match StringName(e["type"]):
			&"value_changed":
				if int(e["data"]["amount"]) > 0:
					var p := int(e["data"]["player"])
					earned[p] = int(earned.get(p, 0)) + int(e["data"]["amount"])
			&"battle_started":
				battles += 1
				if _x == null:
					_mark("battle", 0, int(e["turn"]))
			&"feature_captured":
				_mark("capture", int(e["data"]["player"]), int(e["turn"]))
	var plots := s.rules.plot_count()
	for p in x.players():
		var explored: int = (s.memory.get(p, {}) as Dictionary).size()
		out.append(_row("value", p, s.value_of(p)))
		out.append(_row("value_earned", p, earned.get(p, 0)))
		out.append(_row("hexes_explored", p, explored))
		out.append(_row("fog_revealed_pct", p, 100.0 * explored / maxi(plots, 1)))
		out.append(_row("features_owned", p, _features(s, p)))
		out.append(_row("feature_turns", p, _feature_turns.get(p, 0)))
		out.append(_row("commanders_start", p, _commanders_start.get(p, _commanders(s, p))))
		out.append(_row("commanders_alive", p, _commanders(s, p)))
		out.append(_row("force", p, force_of(s, p)))
		out.append(_row("battles", p, _battles_of.get(p, 0)))
		for k in ["battle", "capture", "contact"]:
			out.append(_row("first_%s_turn" % k, p, _first.get("%s|%d" % [k, p], -1)))
	out.append(_row("turns", 0, s.turn))
	out.append(_row("battles", 0, battles))
	for k in ["battle", "capture", "contact"]:
		out.append(_row("first_%s_turn" % k, 0, _first.get("%s|0" % k, -1)))
	# Every battle fought, summed per player (G2).
	var acc := {}
	for eid: int in _ow_battles:
		var pair: Array = _ow_battles[eid]
		(pair[1] as _BattleWatch).add_rows((pair[0] as OverworldBattle).state, acc)
	out.append_array(_flush(acc, "battle."))
	out.append_array(_results(x.players(), _overworld_winner(x), s.turn))
	out.append_array(_idle(x.input_log, x.players(), s.turn))
	if _sim != null:
		out.append_array(_perf(_sim, "battle."))
	return out


## The winner of an overworld run, 0 = none (yet) or a draw. A built-in
## win condition names its winner; a story mission's outcome is the
## campaign player's (player 1): won or lost.
static func _overworld_winner(x: OverworldSession) -> int:
	if x.state.outcome.has("winner"):
		return int(x.state.outcome["winner"])
	var o := String(x.state.outcome.get("outcome", ""))
	var ps := x.players()
	if o == "won":
		return 1
	if o == "lost":
		for p in ps:
			if p != 1:
				return p
		return -1  # lost with nobody else to win
	return 0


## won / drew / lost / forfeited per player. A forfeit is a loss below a
## loss (B1Q4): its player forfeited, every other player won.
func _results(players: Variant, winner: int, _turns: int) -> Array:
	var out := []
	var quitter := -1
	for p in players:
		if _forfeits.has(p):
			quitter = p
			break
	for p in players:
		var r := {"won": 0, "drew": 0, "lost": 0, "forfeited": 0}
		if quitter >= 0:
			r["forfeited" if p == quitter else "won"] = 1
		elif winner == 0:
			r["drew"] = 1
		else:
			r["won" if p == winner else "lost"] = 1
		for k: String in r:
			out.append(_row(k, p, r[k]))
	out.append(_row("forfeit_turn", 0, _forfeits.get(quitter, -1) if quitter >= 0 else -1))
	return out


## Turns in which a player gave no order but "ready" (G7, a stall guard).
static func _idle(input_log: Array, players: Variant, turns: int) -> Array:
	var active := {}
	for i: Dictionary in input_log:
		var kind := String(i["kind"])
		if kind in ["ready", "advance"]:
			continue
		var pl: Variant = i["payload"]
		if kind in ["orders", "battle_orders"]:
			var list: Array = pl if pl is Array else (pl as Dictionary).get("orders", [])
			if list.is_empty():
				continue
		active["%d|%d" % [int(i["player"]), int(i["turn"])]] = true
	var out := []
	for p in players:
		var n := 0
		for t in range(1, turns + 1):
			if not active.has("%d|%d" % [p, t]):
				n += 1
		out.append(_row("idle_turns", p, n))
	return out


static func _perf(sim: BattleSim, prefix: String) -> Array:
	var out := []
	var keys: Array = sim.runner.profile.keys()
	keys.sort()
	for k: String in keys:
		out.append(_row(prefix + "perf.%s_usec" % k, 0, sim.runner.profile[k]))
	return out


## Summed "metric|player" -> value as rows, in a stable order.
static func _flush(acc: Dictionary, prefix: String) -> Array:
	var keys: Array = acc.keys()
	keys.sort()
	var out := []
	for k: String in keys:
		out.append(_row(prefix + k.get_slice("|", 0), int(k.get_slice("|", 1)), acc[k]))
	return out


static func _features(s: OverworldState, p: int) -> int:
	var n := 0
	for row in s.features.count():
		if s.features.owner[row] == p:
			n += 1
	return n


static func _commanders(s: OverworldState, p: int) -> int:
	var n := 0
	for row in s.commanders.count():
		if s.commanders.player[row] == p:
			n += 1
	return n


## The owner of an overworld squad row: its commander's or detachment's.
static func squad_owner(s: OverworldState, row: int) -> int:
	var sq := s.squads
	if sq.holder[row] >= 0:
		var c := s.commanders.row_of(sq.holder[row])
		return s.commanders.player[c] if c >= 0 else 0
	var d := s.detachments.row_of(sq.detachment[row])
	return s.detachments.player[d] if d >= 0 else 0


## Where an overworld squad row is: its commander's or detachment's plot.
static func squad_plot(s: OverworldState, row: int) -> int:
	var sq := s.squads
	if sq.holder[row] >= 0:
		var c := s.commanders.row_of(sq.holder[row])
		return s.commanders.plot[c] if c >= 0 else -1
	var d := s.detachments.row_of(sq.detachment[row])
	return s.detachments.plot[d] if d >= 0 else -1


static func _squad_value(s: OverworldState, row: int) -> int:
	var sq := s.squads
	return s.rules.sq_value[sq.tmpl[row]] * sq.alive[row] / maxi(sq.size[row], 1)


## Value of the squads a player holds (armies and detachments).
static func force_of(s: OverworldState, p: int) -> int:
	var v := 0
	for row in s.squads.count():
		if squad_owner(s, row) == p:
			v += _squad_value(s, row)
	return v


## The worst threat to a player's commanders: hostile Value within
## THREAT_RANGE hexes of an own commander over that commander's army Value
## (0 = none; > 1 = outmatched). Omniscient: a harness measure.
static func threat(s: OverworldState, p: int) -> float:
	var r := s.rules
	var worst := 0.0
	for c in s.commanders.count():
		if s.commanders.player[c] != p:
			continue
		var at := s.commanders.plot[c]
		var cid := s.commanders.id_at(c)
		var own := 0
		var foe := 0
		for row in s.squads.count():
			if s.squads.holder[row] == cid:
				own += _squad_value(s, row)
				continue
			var o := squad_owner(s, row)
			var there := squad_plot(s, row)
			if o > 0 and s.hostile(p, o) and there >= 0 and Hex.plot_distance(at, there, r.width) <= THREAT_RANGE:
				foe += _squad_value(s, row)
		worst = maxf(worst, float(foe) / maxi(own, 1))
	return worst


## Value of hostile squads on plots the player sees now.
static func _enemy_force_seen(s: OverworldState, p: int) -> int:
	var sight := OverworldVision.sight(s, p)
	var v := 0
	for row in s.squads.count():
		var o := squad_owner(s, row)
		var at := squad_plot(s, row)
		if o > 0 and s.hostile(p, o) and at >= 0 and sight[at] != 0:
			v += _squad_value(s, row)
	return v


static func _row(metric: String, player: int, value: Variant) -> Dictionary:
	return {"metric": metric, "player": player, "value": float(value)}


## One battle's tick-by-tick observations.
class _BattleWatch extends RefCounted:
	var band_ticks: Dictionary = {}  # "player|pool|band" -> squad-ticks
	var crossings: Dictionary = {}  # "player|kind|pool" -> count
	var zone_ticks: Dictionary = {}  # player -> ticks holding unlocked zones
	var victim: Dictionary = {}  # "player|class" -> Value destroyed
	var contact: Dictionary = {}  # player -> first engagement tick
	var capture: Dictionary = {}  # player -> first capture turn
	var force_start: Dictionary = {}
	var first_contact := -1
	var first_casualty := -1
	var first_capture := -1
	var first_break := -1
	var log_seen := 0
	var turn_seen := 0
	var with_series := false

	func _init(state: BattleState, series_on: bool) -> void:
		with_series = series_on
		turn_seen = state.turn
		for p in state.players:
			force_start[p] = SimMetrics.battle_force(state, p)

	func sample(state: BattleState, series: Array) -> void:
		if with_series and state.turn > turn_seen:
			_series(state, series, turn_seen)
		turn_seen = state.turn
		var sq := state.squads
		for row in sq.count():
			if not sq.is_active(row) or sq.alive[row] <= 0:
				continue
			for p in 5:
				var key := "%d|%s|%s" % [sq.player[row], DataSchema.SIMPL[p], DataSchema.BANDS[Pools.band(state, row, p)]]
				band_ticks[key] = int(band_ticks.get(key, 0)) + 1
		if state.turn_log.size() < log_seen:
			log_seen = 0  # a new turn's log
		for i in range(log_seen, state.turn_log.size()):
			_event(state, state.turn_log[i])
		log_seen = state.turn_log.size()
		for z in state.zone_owner.size():
			var o := state.zone_owner[z]
			if o == 0 or (state.zone_locked.size() > z and state.zone_locked[z] != 0):
				continue
			zone_ticks[o] = int(zone_ticks.get(o, 0)) + 1
			if first_capture < 0:
				first_capture = state.turn
			if not capture.has(o):
				capture[o] = state.turn

	func _event(state: BattleState, e: SimEvent) -> void:
		var sq := state.squads
		match e.type:
			&"engagement":
				if first_contact < 0:
					first_contact = e.tick
				for k in ["squad", "target"]:
					var row := sq.row_of(int(e.data.get(k, -1)))
					if row >= 0 and not contact.has(sq.player[row]):
						contact[sq.player[row]] = e.tick
			&"unit_killed":
				if first_casualty < 0:
					first_casualty = e.tick
				var vrow := sq.row_of(int(e.data["squad"]))
				var krow := sq.row_of(int(e.data.get("by", -1)))
				if vrow >= 0 and krow >= 0 and sq.player[krow] != sq.player[vrow]:
					var st := sq.tmpl[vrow]
					var cls := "player"
					if state.rules.sq_keywords[st].has("civilian"):
						cls = "civilian"
					elif sq.player[vrow] == SimMetrics.NEUTRAL:
						cls = "neutral"
					var key := "%d|%s" % [sq.player[krow], cls]
					victim[key] = int(victim.get(key, 0)) + Fixed.round_div(state.rules.sq_value[st], state.rules.sq_members[st].size())
			&"pool_surge", &"pool_break", &"pool_band":
				var row := sq.row_of(int(e.data["squad"]))
				var p := sq.player[row] if row >= 0 else 0
				var kind := {&"pool_surge": "surges", &"pool_break": "breaks", &"pool_band": "band_changes"}[e.type] as String
				var key := "%d|%s|%s" % [p, kind, e.data["pool"]]
				crossings[key] = int(crossings.get(key, 0)) + 1
				if e.type == &"pool_break" and e.data["pool"] == "morale" and first_break < 0:
					first_break = e.tick

	func _series(state: BattleState, series: Array, turn: int) -> void:
		var zones := {}
		for z in state.zone_owner.size():
			if state.zone_owner[z] != 0:
				zones[state.zone_owner[z]] = int(zones.get(state.zone_owner[z], 0)) + 1
		for p in state.players:
			for kv: Array in [["vp", state.influence[p]], ["force", SimMetrics.battle_force(state, p)], ["zones", zones.get(p, 0)],
					["contact", 1 if contact.has(p) else 0]]:
				series.append({"metric": kv[0], "player": p, "turn": turn, "value": float(kv[1])})

	## The last turn's series point (a battle can end mid-turn).
	func finish(state: BattleState, series: Array) -> void:
		if with_series:
			_series(state, series, state.turn)
			with_series = false

	## Adds this battle's per-player totals to `acc` ("metric|player").
	func add_rows(state: BattleState, acc: Dictionary) -> void:
		var r := state.rules
		var sq := state.squads
		var put := func(m: String, p: int, v: float) -> void: acc["%s|%d" % [m, p]] = float(acc.get("%s|%d" % [m, p], 0.0)) + v
		for row in sq.count():
			var p := sq.player[row]
			var st := sq.tmpl[row]
			var start := r.sq_members[st].size()
			var gone := start - sq.alive[row]
			put.call("units_lost", p, gone)
			put.call("value_lost", p, r.sq_value[st] * gone / maxi(start, 1))
			if sq.destroyed[row] == 1:
				put.call("squads_lost", p, 1)
		for p in state.players:
			put.call("vp", p, state.influence[p])
			put.call("value_destroyed", p, state.value_score[p])
			put.call("force_start", p, force_start.get(p, 0))
			put.call("zone_ticks", p, zone_ticks.get(p, 0))
			for c: String in SimMetrics.VICTIMS:
				put.call("value_destroyed." + c, p, victim.get("%d|%s" % [p, c], 0))
		for k: String in band_ticks:
			var parts := k.split("|")
			put.call("band.%s.%s" % [parts[1], parts[2]], int(parts[0]), band_ticks[k])
		for k: String in state.ledger:
			var parts := k.split("|")
			var row := sq.row_of(int(parts[0]))
			put.call("ledger." + DataSchema.SIMPL[int(parts[1])], sq.player[row] if row >= 0 else 0,
				Fixed.to_display(int(state.ledger[k])).to_float())
		for k: String in crossings:
			var parts := k.split("|")
			put.call("%s.%s" % [parts[1], parts[2]], int(parts[0]), crossings[k])


## Value of a side's living units in a battle.
static func battle_force(state: BattleState, p: int) -> int:
	var r := state.rules
	var sq := state.squads
	var v := 0
	for row in sq.count():
		if sq.player[row] == p and sq.alive[row] > 0:
			v += r.sq_value[sq.tmpl[row]] * sq.alive[row] / maxi(r.sq_members[sq.tmpl[row]].size(), 1)
	return v
