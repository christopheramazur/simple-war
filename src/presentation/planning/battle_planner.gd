class_name BattlePlanner
extends RefCounted
## The player's planning state for one battle (GDD 01 Input and UI, 02 §2.2,
## R1Q4, R3Q4, R4Q3): selection, control groups and the drafted orders, plus the RTS command set that edits them. Presentation
## state only: it reads battle observations (observe_battle) and produces an
## order list in the BattleOrders format; the owner submits it and asks for
## the forecast. Nothing here reaches the simulation.
##
## Commands: select (click, add/toggle), box select, select by type (all,
## or on screen), control groups (assign, add, recall), move / attack-move
## keeping the formation or into a new line formation, attack, hold, fall
## back, withdraw, run toggle, and one ability menu across the selection.
##
## Deployment (U1 C11, GDD 02 §2.4): while the battle deploys (turn-1
## Planning), own squads can be placed anywhere in the player's area: drag
## one or a selected group (offsets kept), turn them (facing snaps to eight
## directions), nudge them, or reset to the automatic places. A point outside
## the area is clamped to its edge here; the simulation still refuses
## anything outside (BattleDeploy). Placements are their own draft
## (`deploy_changed`, `deployment()`), submitted through
## submit_battle_deployment only; orders drafted meanwhile start from the
## placed positions.
##
## Arrival (U1 C12, sw-bafi.18, sw-bafi.19): squads arriving at the next
## Reveal (a joining side's battleforce, or reinforcements of a side already
## fighting) are placed the same way, inside the player's arrival area. The
## owner merges them into the observation as own squads marked "arriving"
## (under IDs of its choosing that no battle squad uses) with the area as
## "arrival_area"; they take placements only, never orders, and their
## placements come out of `arrival()`, not `deployment()`, for submit_arrival.
## Battle squads and arriving squads can be selected together: a drag places
## only the arriving ones (or, while the battle deploys, both, each in its
## own area) and orders reach only the battle squads.

## The orders or groups changed (a draft to submit).
signal changed
## The selection changed. Separate from `changed`, so a selection never
## counts as a draft: it is information, allowed during playback (sw-bafi.2).
signal selection_changed
## The deployment placements changed (a draft for submit_battle_deployment).
signal deploy_changed

## Spacing between squads in a new formation (fixed, metres).
const FORMATION_SPACING: int = 12 * Fixed.ONE
const GROUPS: int = 10
## One eighth of a turn (binary angle): deployment facings snap to it.
const FACING_STEP: int = Fixed.ANGLE_FULL >> 3
## How far one nudge moves the deploying selection (metres).
const NUDGE: float = 2.0

## Selected own squad IDs, in selection order.
var selection: Array[int] = []
## Control group n -> squad IDs.
var groups: Dictionary = {}
## Drafted orders: squad ID -> order dict (BattleOrders format).
var drafts: Dictionary = {}
## Whether the battle is deploying (the last observation said so).
var deploying: bool = false
## The player's deployment area (metres; Rect2() if none).
var area: Rect2 = Rect2()
## The player's arrival area (metres; Rect2() if nothing of its arrives).
var arrival_area: Rect2 = Rect2()
## Every side's area: [{"player", "rect": Rect2 (metres)}], plus the
## player's arrival area marked "arrival": true.
var areas: Array = []
## Deployment placements: squad ID -> {squad, x, y, facing} (BattleDeploy).
var placements: Dictionary = {}
## The battle's rules, when the owner has them: placements snap to a cell
## the squad can enter (BattleDeploy.open_point_in). Read only.
var rules: BattleRules

var _player: int = 0
var _width: int = 0
var _height: int = 0
## Own active squads: ID -> {"template", "x", "y", "facing", "abilities",
## "arriving"}.
var _own: Dictionary = {}
## Visible enemy squads: ID -> {"x", "y"}.
var _enemy: Dictionary = {}


func _init(player: int) -> void:
	_player = player


## Reads a battle observation (BattleSession.observe_state shape). Squads
## that left the battle leave the selection, groups and drafts. Silent: it
## never emits `changed` (only the player's edits do).
func sync(obs: Dictionary) -> void:
	_width = obs.get("width", 0)
	_height = obs.get("height", 0)
	deploying = obs.get("deploying", false)
	var a: Array = obs.get("area", [])
	area = _rect(a) if a.size() == 4 else Rect2()
	areas = []
	for d: Dictionary in obs.get("areas", []):
		areas.append({"player": int(d["player"]), "rect": _rect(d["deploy"])})
	var aa: Array = obs.get("arrival_area", [])
	arrival_area = _rect(aa) if aa.size() == 4 else Rect2()
	if arrival_area.size != Vector2.ZERO:
		areas.append({"player": _player, "rect": arrival_area, "arrival": true})
	_own = {}
	_enemy = {}
	for sq: Dictionary in obs.get("squads", []):
		if sq.get("destroyed", false) or sq.get("withdrawn", false):
			continue
		if sq["player"] == _player:
			_own[sq["id"]] = {"template": sq["template"], "x": sq["x"], "y": sq["y"], "facing": sq.get("facing", 0),
				"abilities": sq.get("abilities", []), "arriving": sq.get("arriving", false)}
		else:
			_enemy[sq["id"]] = {"x": sq["x"], "y": sq["y"]}
	selection = selection.filter(func(id: int) -> bool: return _own.has(id))
	for g: int in groups.keys():
		groups[g] = (groups[g] as Array).filter(func(id: int) -> bool: return _own.has(id))
	for id: int in drafts.keys():
		if not _own.has(id) or arriving(id):
			drafts.erase(id)
	for id: int in placements.keys():
		if not can_place(id):
			placements.erase(id)


## Own squads in sight of the planner, by ID.
func own_squads() -> Array[int]:
	var out: Array[int] = []
	out.assign(_sorted(_own.keys()))
	return out


## Whether own squad `id` arrives at the next Reveal (placements only).
func arriving(id: int) -> bool:
	return bool((_own.get(id, {}) as Dictionary).get("arriving", false))


## The order list to submit (submit_battle_orders / submit_orders).
func orders() -> Array:
	var out := []
	for id: int in _sorted(drafts.keys()):
		out.append((drafts[id] as Dictionary).duplicate(true))
	return out


func clear_drafts() -> void:
	drafts = {}
	changed.emit()


# --- selection ---------------------------------------------------------------

## Selects squads; `add` keeps the current selection (shift), `toggle`
## flips each (ctrl). Only own squads can be selected.
func select(ids: Array, add: bool = false, toggle: bool = false) -> void:
	if not add and not toggle:
		selection = []
	for id: int in ids:
		if not _own.has(id):
			continue
		if toggle and selection.has(id):
			selection.erase(id)
		elif not selection.has(id):
			selection.append(id)
	selection_changed.emit()


func deselect() -> void:
	selection = []
	selection_changed.emit()


## Own squads whose position is inside a battlefield rect (metres).
func in_rect(rect: Rect2) -> Array[int]:
	var out: Array[int] = []
	for id in own_squads():
		if rect.abs().has_point(_pos(id)):
			out.append(id)
	return out


## Box select (drag).
func select_box(rect: Rect2, add: bool = false) -> void:
	select(in_rect(rect), add)


## Selects every own squad of the same template as the clicked one; with
## `on_screen`, only those inside it (double click / ctrl+click).
func select_type(id: int, on_screen: Rect2 = Rect2(), add: bool = false) -> void:
	if not _own.has(id):
		return
	var t: String = _own[id]["template"]
	var pool := own_squads() if on_screen.size == Vector2.ZERO else in_rect(on_screen)
	select(pool.filter(func(x: int) -> bool: return _own[x]["template"] == t), add)


## Control groups: assign replaces (ctrl+n), add appends (shift+n), recall
## selects (n).
func assign_group(n: int, add: bool = false) -> void:
	var g: Array = groups.get(n, []) if add else []
	for id in selection:
		if not g.has(id):
			g.append(id)
	groups[n] = g
	changed.emit()


func recall_group(n: int, add: bool = false) -> void:
	select(groups.get(n, []), add)


## The selection's centre (metres), for camera jumps to a recalled group.
func selection_centre() -> Vector2:
	if selection.is_empty():
		return Vector2.ZERO
	var c := Vector2.ZERO
	for id in selection:
		c += _pos(id)
	return c / selection.size()


# --- orders ------------------------------------------------------------------

## Moves the selection to a point (metres). `new_formation` lines the
## squads up across the direction of travel; otherwise they keep their
## places around the centre. `attack` makes it an attack-move.
func move_to(at: Vector2, new_formation: bool = false, attack: bool = false) -> void:
	var sel := _orderable()
	if sel.is_empty():
		return
	var centre := Vector2.ZERO
	for id in sel:
		centre += _pos(id)
	centre /= sel.size()
	var dir := (at - centre).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var side := Vector2(-dir.y, dir.x)
	var spacing := float(FORMATION_SPACING) / Fixed.ONE
	var ordered := sel.duplicate()
	if new_formation:
		ordered.sort_custom(func(a: int, b: int) -> bool: return _pos(a).dot(side) < _pos(b).dot(side))
	for i in ordered.size():
		var id: int = ordered[i]
		var p := at + (_pos(id) - centre)
		if new_formation:
			p = at + side * spacing * (i - (ordered.size() - 1) / 2.0)
		_draft(id, {"type": "attack_move" if attack else "move", "x": _fx(p.x, _width), "y": _fx(p.y, _height)})
	changed.emit()


## Orders the selection to attack a visible enemy squad.
func attack(target: int) -> void:
	if not _enemy.has(target):
		return
	for id in _orderable():
		_draft(id, {"type": "attack", "target": target})
	changed.emit()


## hold, fall_back or withdraw for the whole selection.
func order(type: String) -> void:
	if not type in ["hold", "fall_back", "withdraw"]:
		return
	for id in _orderable():
		_draft(id, {"type": type})
	changed.emit()


## Toggles running for the selection's move orders.
func toggle_run() -> void:
	var all_run := true
	for id in _orderable():
		all_run = all_run and bool((drafts.get(id, {}) as Dictionary).get("run", false))
	for id in _orderable():
		var o: Dictionary = drafts.get(id, {"squad": id, "type": "hold"})
		o["run"] = not all_run
		drafts[id] = o
	changed.emit()


# --- deployment --------------------------------------------------------------

## Whether placements can be drafted now: the battle deploys and the player
## has an area, or squads of its arrive and it has an arrival area.
func can_deploy() -> bool:
	return not placeable().is_empty()


## Whether own squad `id` can be placed now: an arriving squad inside the
## arrival area, a battle squad while the battle deploys.
func can_place(id: int) -> bool:
	if not _own.has(id):
		return false
	return area_of(id).size != Vector2.ZERO and (arriving(id) or deploying)


## Own squads that can be placed now, by ID.
func placeable() -> Array[int]:
	var out: Array[int] = []
	for id in own_squads():
		if can_place(id):
			out.append(id)
	return out


## The area squad `id` is placed in: the arrival area for an arriving squad,
## else the deployment area.
func area_of(id: int) -> Rect2:
	return arrival_area if arriving(id) else area


## The battle squads' placement list to submit (submit_battle_deployment),
## by squad ID.
func deployment() -> Array:
	return _placements_where(false)


## The arriving squads' placement list to submit (submit_arrival), by the IDs
## they were synced under (the owner maps them back to overworld IDs).
func arrival() -> Array:
	return _placements_where(true)


func _placements_where(arrive: bool) -> Array:
	var out := []
	for id: int in _sorted(placements.keys()):
		if arriving(id) == arrive:
			out.append((placements[id] as Dictionary).duplicate())
	return out


## A point (metres) kept inside squad `id`'s area (the deployment area when
## `id` is -1): a drop outside lands on the nearest edge.
func clamp_to_area(m: Vector2, id: int = -1) -> Vector2:
	var r := area_of(id) if id >= 0 else area
	if r.size == Vector2.ZERO:
		return m
	return Vector2(clampf(m.x, r.position.x, r.end.x), clampf(m.y, r.position.y, r.end.y))


## Where squad `id` would be placed for a drop at `m` (metres): clamped to
## the area, then snapped to a cell the squad can enter, as the simulation
## will (BattleDeploy.open_point_in). Without rules, only the clamp.
func snap(id: int, m: Vector2) -> Vector2:
	var c := clamp_to_area(m, id)
	if rules == null or not _own.has(id):
		return c
	var st := rules.squad_index(String(_own[id]["template"]))
	var r := area_of(id)
	var a := PackedInt64Array([_fx(r.position.x, 0), _fx(r.position.y, 0), _fx(r.size.x, 0), _fx(r.size.y, 0)])
	var at := BattleDeploy.open_point_in(rules, st, _fx(c.x, _width), _fx(c.y, _height), a)
	if at.is_empty():
		return c
	return Vector2(float(at[0]) / Fixed.ONE, float(at[1]) / Fixed.ONE)


## Whether a drop at `m` lands where squad `id` can stand (inside the area,
## on a cell it can enter); the drag ghost marks a refused cell otherwise.
func drop_ok(id: int, m: Vector2) -> bool:
	return snap(id, m).distance_to(m) < 0.01


## Places squads by dragging `anchor` to `to` (metres); the others keep
## their offsets from it. Each lands clamped and snapped (`snap`).
func place_group(ids: Array, anchor: int, to: Vector2) -> void:
	if not _own.has(anchor) or not can_deploy():
		return
	var delta := to - _pos(anchor)
	for id: int in ids:
		if can_place(id):
			_place(id, _pos(id) + delta, facing_of(id))
	deploy_changed.emit()


## A drag in the battle view: `anchor` (and the rest of `ids`) moved by
## `delta` metres from where they stand now.
func drag(ids: Array, anchor: int, delta: Vector2) -> void:
	if _own.has(anchor):
		place_group(ids, anchor, _pos(anchor) + delta)


## Places one squad (a drag of an unselected squad).
func place(id: int, to: Vector2) -> void:
	place_group([id], id, to)


## Turns squads to face `toward` (metres), snapped to eight directions (the
## facing handle).
func face(ids: Array, toward: Vector2) -> void:
	if not can_deploy():
		return
	for id: int in ids:
		var d := toward - _pos(id) if can_place(id) else Vector2.ZERO
		if d != Vector2.ZERO:
			_place(id, _pos(id), snap_facing(roundi(d.angle() / TAU * Fixed.ANGLE_FULL)))
	deploy_changed.emit()


## Turns squads by `steps` eighths of a turn (the rotate key; + turns
## clockwise on screen), from their facing snapped to eight directions.
func rotate(ids: Array, steps: int) -> void:
	if not can_deploy():
		return
	for id: int in ids:
		if can_place(id):
			_place(id, _pos(id), snap_facing(snap_facing(facing_of(id)) + steps * FACING_STEP))
	deploy_changed.emit()


## Moves the deploying selection by `dir` nudges (pad stick, arrow keys).
## Only the selected squads that can be placed move.
func nudge(dir: Vector2) -> void:
	var ids := selection.filter(can_place)
	if ids.is_empty():
		return
	place_group(ids, ids[0], _pos(ids[0]) + dir * NUDGE)


## Back to the automatic places: every placement dropped.
func reset_deployment() -> void:
	placements = {}
	deploy_changed.emit()


## A squad's facing (binary angle): its placement's, else the observed one.
func facing_of(id: int) -> int:
	if placements.has(id):
		return placements[id]["facing"]
	return int((_own.get(id, {}) as Dictionary).get("facing", 0))


## A binary angle snapped to the nearest of eight directions.
static func snap_facing(a: int) -> int:
	return (roundi(float(a) / FACING_STEP) * FACING_STEP) & Fixed.ANGLE_MASK


## The observation as it will look with the placements applied, for
## drawing: each placed own squad (and its units) moved by its offset and
## turned to its facing, marked "placed". Presentation only; the units' own
## snapping at the Reveal may differ by a cell.
func deploy_view(obs: Dictionary) -> Dictionary:
	if placements.is_empty():
		return obs
	var out := obs.duplicate()
	var shift := {}
	var squads := []
	for sq: Dictionary in obs.get("squads", []):
		var id: int = sq["id"]
		if not placements.has(id):
			squads.append(sq)
			continue
		var p: Dictionary = placements[id]
		var d := sq.duplicate()
		d.merge({"x": p["x"], "y": p["y"], "facing": p["facing"], "placed": true}, true)
		shift[id] = {"from": Vector2(sq["x"], sq["y"]), "to": Vector2(p["x"], p["y"]),
			"turn": float(int(p["facing"]) - int(sq.get("facing", 0))) / Fixed.ANGLE_FULL * TAU}
		squads.append(d)
	out["squads"] = squads
	var units := []
	for u: Dictionary in obs.get("units", []):
		if not shift.has(u["squad"]):
			units.append(u)
			continue
		var t: Dictionary = shift[u["squad"]]
		var to: Vector2 = t["to"]
		var off := (Vector2(u["x"], u["y"]) - (t["from"] as Vector2)).rotated(t["turn"])
		var d := u.duplicate()
		d["x"] = clampi(roundi(to.x + off.x), 0, Fixed.from_int(_width) - 1)
		d["y"] = clampi(roundi(to.y + off.y), 0, Fixed.from_int(_height) - 1)
		units.append(d)
	out["units"] = units
	return out


func _place(id: int, m: Vector2, facing: int) -> void:
	var at := snap(id, m)
	placements[id] = {"squad": id, "x": _fx(at.x, _width), "y": _fx(at.y, _height), "facing": facing & Fixed.ANGLE_MASK}


static func _rect(a: Array) -> Rect2:
	return Rect2(float(a[0]) / Fixed.ONE, float(a[1]) / Fixed.ONE, float(a[2]) / Fixed.ONE, float(a[3]) / Fixed.ONE)


# --- abilities ---------------------------------------------------------------

## One menu across the selection: [{"id", "name", "squads" (selected
## squads that have it), "toggle", "on" (all of them on)}], reactions left
## out (they belong to the reaction window).
func ability_menu() -> Array:
	var by_id := {}
	var order_ids := []
	for id in selection:
		for ab: Dictionary in _own[id]["abilities"]:
			if ab.get("reaction", false):
				continue
			if not by_id.has(ab["id"]):
				by_id[ab["id"]] = {"id": ab["id"], "name": ab["name"], "squads": [], "toggle": ab.get("toggle", false), "on": true}
				order_ids.append(ab["id"])
			var m: Dictionary = by_id[ab["id"]]
			(m["squads"] as Array).append(id)
			m["on"] = m["on"] and _ability_on(id, ab)
	var out := []
	for k: String in order_ids:
		out.append(by_id[k])
	return out


## Uses an ability on every selected squad that has it: a toggle flips
## (all on -> off, else on); others are used (with `target` if given).
func use_ability(ability: String, target: int = -1) -> void:
	for m: Dictionary in ability_menu():
		if m["id"] != ability:
			continue
		for id: int in m["squads"]:
			var o: Dictionary = drafts.get(id, {"squad": id, "type": "hold"})
			var list: Array = (o.get("abilities", []) as Array).filter(func(a: Dictionary) -> bool: return a["id"] != ability)
			var use := {"id": ability}
			if m["toggle"]:
				use["on"] = not m["on"]
			elif target >= 0:
				use["target"] = target
			list.append(use)
			o["abilities"] = list
			drafts[id] = o
	changed.emit()


func _ability_on(id: int, ab: Dictionary) -> bool:
	for u: Dictionary in (drafts.get(id, {}) as Dictionary).get("abilities", []):
		if u["id"] == ab["id"] and u.has("on"):
			return u["on"]
	return ab.get("on", false)


# --- helpers -----------------------------------------------------------------

## The selection that takes orders: arriving squads take none.
func _orderable() -> Array[int]:
	var out: Array[int] = []
	for id in selection:
		if not arriving(id):
			out.append(id)
	return out


## Replaces a squad's order, keeping its run flag and planned abilities.
## Arriving squads take none.
func _draft(id: int, o: Dictionary) -> void:
	if arriving(id):
		return
	var old: Dictionary = drafts.get(id, {})
	o["squad"] = id
	if old.has("run"):
		o["run"] = old["run"]
	if old.has("abilities"):
		o["abilities"] = old["abilities"]
	drafts[id] = o


## A squad's position (metres): own squads at their placement while one is
## drafted.
func _pos(id: int) -> Vector2:
	var d: Dictionary = placements[id] if placements.has(id) else (_own[id] if _own.has(id) else _enemy[id])
	return Vector2(float(d["x"]) / Fixed.ONE, float(d["y"]) / Fixed.ONE)


## Metres to a fixed coordinate, kept on the battlefield.
static func _fx(m: float, limit: int) -> int:
	return clampi(int(round(m * Fixed.ONE)), 0, Fixed.from_int(limit) if limit > 0 else 1 << 40)


static func _sorted(keys: Array) -> Array:
	var k := keys.duplicate()
	k.sort()
	return k
