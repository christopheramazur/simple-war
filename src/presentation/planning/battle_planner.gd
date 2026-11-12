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

signal changed

## Spacing between squads in a new formation (fixed, metres).
const FORMATION_SPACING: int = 12 * Fixed.ONE
const GROUPS: int = 10

## Selected own squad IDs, in selection order.
var selection: Array[int] = []
## Control group n -> squad IDs.
var groups: Dictionary = {}
## Drafted orders: squad ID -> order dict (BattleOrders format).
var drafts: Dictionary = {}

var _player: int = 0
var _width: int = 0
var _height: int = 0
## Own active squads: ID -> {"template", "x", "y", "abilities"}.
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
	_own = {}
	_enemy = {}
	for sq: Dictionary in obs.get("squads", []):
		if sq.get("destroyed", false) or sq.get("withdrawn", false):
			continue
		if sq["player"] == _player:
			_own[sq["id"]] = {"template": sq["template"], "x": sq["x"], "y": sq["y"], "abilities": sq.get("abilities", [])}
		else:
			_enemy[sq["id"]] = {"x": sq["x"], "y": sq["y"]}
	selection = selection.filter(func(id: int) -> bool: return _own.has(id))
	for g: int in groups.keys():
		groups[g] = (groups[g] as Array).filter(func(id: int) -> bool: return _own.has(id))
	for id: int in drafts.keys():
		if not _own.has(id):
			drafts.erase(id)


## Own squads in sight of the planner, by ID.
func own_squads() -> Array[int]:
	var out: Array[int] = []
	out.assign(_sorted(_own.keys()))
	return out


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
	changed.emit()


func deselect() -> void:
	selection = []
	changed.emit()


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
	if selection.is_empty():
		return
	var centre := selection_centre()
	var dir := (at - centre).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var side := Vector2(-dir.y, dir.x)
	var spacing := float(FORMATION_SPACING) / Fixed.ONE
	var ordered := selection.duplicate()
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
	for id in selection:
		_draft(id, {"type": "attack", "target": target})
	changed.emit()


## hold, fall_back or withdraw for the whole selection.
func order(type: String) -> void:
	if not type in ["hold", "fall_back", "withdraw"]:
		return
	for id in selection:
		_draft(id, {"type": type})
	changed.emit()


## Toggles running for the selection's move orders.
func toggle_run() -> void:
	var all_run := true
	for id in selection:
		all_run = all_run and bool((drafts.get(id, {}) as Dictionary).get("run", false))
	for id in selection:
		var o: Dictionary = drafts.get(id, {"squad": id, "type": "hold"})
		o["run"] = not all_run
		drafts[id] = o
	changed.emit()


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

## Replaces a squad's order, keeping its run flag and planned abilities.
func _draft(id: int, o: Dictionary) -> void:
	var old: Dictionary = drafts.get(id, {})
	o["squad"] = id
	if old.has("run"):
		o["run"] = old["run"]
	if old.has("abilities"):
		o["abilities"] = old["abilities"]
	drafts[id] = o


func _pos(id: int) -> Vector2:
	var d: Dictionary = _own[id] if _own.has(id) else _enemy[id]
	return Vector2(float(d["x"]) / Fixed.ONE, float(d["y"]) / Fixed.ONE)


## Metres to a fixed coordinate, kept on the battlefield.
static func _fx(m: float, limit: int) -> int:
	return clampi(int(round(m * Fixed.ONE)), 0, Fixed.from_int(limit) if limit > 0 else 1 << 40)


static func _sorted(keys: Array) -> Array:
	var k := keys.duplicate()
	k.sort()
	return k
