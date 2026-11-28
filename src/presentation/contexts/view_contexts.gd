class_name ViewContexts
extends RefCounted
## What the player is looking at: the overworld or one of its battles, plus
## picture-in-picture battle views (GDD 04 §4.8, R2Q19, R3Q20, R4Q15).
## Presentation state only: it reads observations (OverworldSession.observe)
## and never touches the simulation. UI nodes call its methods and redraw on
## `changed`.
##
## Camera rules (R2Q19):
##   - Following a commander: follow it, tab into its battle, swap battles;
##     exiting returns to the followed commander.
##   - Selecting another commander inside a battle (one not fighting in it)
##     exits to that commander.
##   - Deselect-all (allowed anywhere) exits to the current battle's
##     overworld hex.
## Zoom transition (R4Q15): zooming the overworld in past ZOOM_ENTER with a
## battle hex in context (the selected hex, the selected commander's hex,
## else the camera's) enters that battle at the default zoom.
## Battle camera: in a battle `zoom` is the magnification over the whole
## field fitting the view (1, up to BATTLE_ZOOM_MAX) and `battle_centre` the
## field point (metres) at the view's centre, (-1, -1) for the field's
## centre. The view computes moves (it knows the field and its own size)
## and asks for them with set_battle_camera; both reset on entering a battle.
## Several battles at once: the focused battle plus up to MAX_PIPS movable
## picture-in-picture views; the battles menu focuses or pins any of them.

signal changed
## The battle camera moved (set_battle_camera): only the main view redraws.
signal camera_changed

const OVERWORLD: int = -1
## Overworld zoom (GDD 04 §4.8 hex view): a hex is ContextView.HEX_SIZE
## px at 1, 16 px at the floor and 192 at the ceiling.
const ZOOM_MIN: float = 0.25
const ZOOM_MAX: float = 3.0
const ZOOM_DEFAULT: float = 1.0
## Zooming the overworld in to this level enters the battle in context
## (s = 160 px).
const ZOOM_ENTER: float = 2.5
const MAX_PIPS: int = 3
const BATTLE_ZOOM_MAX: float = 6.0
const NO_CENTRE: Vector2 = Vector2(-1, -1)

## Engagement ID of the focused battle, or OVERWORLD.
var focus: int = OVERWORLD
## Commander the camera follows on the overworld (-1 = none).
var followed: int = -1
## Selected commander (-1 = none) and selected hex (-1 = none).
var selected: int = -1
var selected_plot: int = -1
## Selected own detachment (garrison or convoy, sw-kys.8; -1 = none).
var selected_detachment: int = -1
## Selected feature (a site, U1Q23; -1 = none) on selected_plot. It stays
## selected when it leaves sight (the panel shows it as last seen) and
## clears on deselect-all, another selection, or when the player's
## knowledge of its hex no longer holds it (it is gone).
var selected_feature: int = -1
## Whether the selected feature is in sight now (false: last seen).
var feature_in_sight: bool = false
## Overworld camera centre (a plot; -1 = not set yet).
var camera_plot: int = -1
var zoom: float = ZOOM_DEFAULT
## The focused battle's camera centre (metres; NO_CENTRE = the field's).
var battle_centre: Vector2 = NO_CENTRE
## Battles in picture-in-picture views, in order, and where each was moved
## to (engagement ID -> Vector2 offset).
var pips: Array[int] = []
var pip_offsets: Dictionary = {}
## Camera bookmarks (R1Q4): slot -> {"focus", "plot", "zoom", "centre"}.
var bookmarks: Dictionary = {}

var _player: int = 0
## The player's battles: engagement ID -> plot.
var _battles: Dictionary = {}
## Commanders in sight: ID -> {"plot", "engagement", "own"}.
var _commanders: Dictionary = {}


func _init(player: int) -> void:
	_player = player


# --- observations ------------------------------------------------------------

## Reads an overworld observation (OverworldSession.observe). Battles that
## ended leave the view: a focused one exits by the usual rule.
func sync(obs: Dictionary) -> void:
	_commanders = {}
	var mine := {}
	for c: Dictionary in obs.get("commanders", []):
		var own: bool = c["player"] == _player
		_commanders[c["id"]] = {"plot": c["plot"], "engagement": c["engagement"], "own": own}
		if own and c["engagement"] >= 0:
			mine[c["engagement"]] = true
	for d: Dictionary in obs.get("detachments", []):
		if d["player"] == _player and d["engagement"] >= 0:
			mine[d["engagement"]] = true
	var was := _battles
	_battles = {}
	for bt: Dictionary in obs.get("battles", []):
		if bt.get("battle", false) and mine.has(bt["engagement"]):
			_battles[bt["engagement"]] = bt["plot"]
	if not _commanders.has(followed):
		followed = -1
	if not _commanders.has(selected):
		selected = -1
	if selected_feature >= 0:
		_sync_feature(obs)
	for eid in pips.duplicate():
		if not _battles.has(eid):
			unpin(eid)
	if focus != OVERWORLD and not _battles.has(focus):
		_leave_battle(was.get(focus, camera_plot))
	if focus == OVERWORLD and followed >= 0:
		camera_plot = _commanders[followed]["plot"]
	if camera_plot < 0:
		for cid: int in _sorted(_commanders.keys()):
			if _commanders[cid]["own"]:
				camera_plot = _commanders[cid]["plot"]
				break
	changed.emit()


## The player's battles, by engagement ID.
func battles() -> Array[int]:
	var out: Array[int] = []
	out.assign(_sorted(_battles.keys()))
	return out


func battle_plot(eid: int) -> int:
	return _battles.get(eid, -1)


## Battles shown now: the focused one first, then the picture-in-pictures.
func shown() -> Array[int]:
	var out: Array[int] = []
	if focus != OVERWORLD:
		out.append(focus)
	out.append_array(pips)
	return out


## The battles menu: [{"engagement", "plot", "focused", "pinned",
## "commanders" (own ones fighting there)}].
func menu() -> Array:
	var out := []
	for eid in battles():
		var cmds := []
		for cid: int in _sorted(_commanders.keys()):
			if _commanders[cid]["own"] and _commanders[cid]["engagement"] == eid:
				cmds.append(cid)
		out.append({"engagement": eid, "plot": _battles[eid], "focused": focus == eid,
			"pinned": pips.has(eid), "commanders": cmds})
	return out


# --- selection and following -------------------------------------------------

## Selects a commander. Inside a battle, one not fighting in it exits to it.
func select_commander(cid: int) -> void:
	if not _commanders.has(cid):
		return
	selected = cid
	selected_plot = -1
	selected_detachment = -1
	selected_feature = -1
	if focus != OVERWORLD and _commanders[cid]["engagement"] != focus:
		if followed >= 0:
			followed = cid
		_leave_battle(_commanders[cid]["plot"])
	changed.emit()


## Follows a commander (default: the selected one) with the camera.
func follow(cid: int = -2) -> void:
	if cid == -2:
		cid = selected
	if not _commanders.has(cid):
		return
	followed = cid
	selected = cid
	if focus == OVERWORLD:
		camera_plot = _commanders[cid]["plot"]
	changed.emit()


func select_hex(p: int) -> void:
	selected_plot = p
	selected_detachment = -1
	selected_feature = -1
	changed.emit()


## Selects a feature (a site) on plot p, from the map or its panel row
## (U1Q23). Remembered and enemy features are selectable too (inspection;
## what the player may do with one is the panel's business). Clears the
## commander and detachment selection, so the panel shows the site; the
## follow (camera only) stays. `obs` (OverworldSession.observe) says
## whether it is in sight; a feature it doesn't know is not selected.
func select_feature(fid: int, p: int, obs: Dictionary) -> void:
	if fid < 0 or _feature_entry(obs, fid, p).is_empty():
		return
	selected = -1
	selected_detachment = -1
	selected_plot = p
	selected_feature = fid
	feature_in_sight = bool(_feature_entry(obs, fid, p).get("visible", false))
	changed.emit()


## Selects one of the player's detachments to steer it like a commander
## (sw-kys.8). Clears the commander and hex selection.
func select_detachment(did: int) -> void:
	selected = -1
	followed = -1
	selected_plot = -1
	selected_feature = -1
	selected_detachment = did
	changed.emit()


## Clears every selection and the follow; in a battle, exits to its hex.
func deselect_all() -> void:
	selected = -1
	followed = -1
	selected_plot = -1
	selected_detachment = -1
	selected_feature = -1
	if focus != OVERWORLD:
		_leave_battle(_battles.get(focus, camera_plot))
	changed.emit()


# --- moving between contexts -------------------------------------------------

## Tabs into the followed (else selected) commander's battle, else the first
## battle. Returns whether a battle is focused.
func tab_in() -> bool:
	for cid in [followed, selected]:
		if _commanders.has(cid):
			var eid: int = _commanders[cid]["engagement"]
			if _battles.has(eid):
				focus_battle(eid)
				return true
	var all := battles()
	if all.is_empty():
		return false
	focus_battle(all[0])
	return true


## Swaps to the next (dir 1) or previous (-1) battle, wrapping; from the
## overworld it tabs in.
func cycle(dir: int = 1) -> void:
	if focus == OVERWORLD:
		tab_in()
		return
	var all := battles()
	var i := all.find(focus)
	focus_battle(all[posmod(i + dir, all.size())])


## Focuses a battle (the battles menu, a click on its picture-in-picture).
## A pinned battle swaps places with the one it replaces.
func focus_battle(eid: int) -> void:
	if not _battles.has(eid):
		return
	var slot := pips.find(eid)
	if slot >= 0:
		if focus != OVERWORLD:
			pip_offsets[focus] = pip_offsets.get(eid, Vector2.ZERO)
			pips[slot] = focus
		else:
			pips.remove_at(slot)
		pip_offsets.erase(eid)
	focus = eid
	zoom = ZOOM_DEFAULT
	battle_centre = NO_CENTRE
	changed.emit()


## Leaves the focused battle: to the followed commander, else its hex.
func exit() -> void:
	if focus == OVERWORLD:
		return
	_leave_battle(_battles.get(focus, camera_plot))
	changed.emit()


## Moves the focused battle's camera: `z` clamped to 1..BATTLE_ZOOM_MAX,
## `centre` in metres (NO_CENTRE for the field's centre).
func set_battle_camera(z: float, centre: Vector2) -> void:
	if focus == OVERWORLD:
		return
	zoom = clampf(z, ZOOM_DEFAULT, BATTLE_ZOOM_MAX)
	battle_centre = centre if zoom > ZOOM_DEFAULT else NO_CENTRE
	camera_changed.emit()


## Zooms by a factor. On the overworld, reaching ZOOM_ENTER with a battle
## hex in context enters that battle at the default zoom.
func zoom_by(factor: float) -> void:
	var z := clampf(zoom * factor, ZOOM_MIN, ZOOM_MAX)
	if focus == OVERWORLD and z >= ZOOM_ENTER:
		var eid := battle_in_context()
		if eid >= 0:
			focus_battle(eid)
			return
	zoom = z
	changed.emit()


## The battle on the hex in context: the selected hex, else the selected
## commander's, else the camera's. -1 if none.
func battle_in_context() -> int:
	var plots: Array[int] = []
	if selected_plot >= 0:
		plots.append(selected_plot)
	elif _commanders.has(selected):
		plots.append(_commanders[selected]["plot"])
	else:
		plots.append(camera_plot)
	for eid in battles():
		if plots.has(_battles[eid]):
			return eid
	return -1


## Moves the overworld camera (panning stops following).
func look_at(p: int) -> void:
	camera_plot = p
	followed = -1
	changed.emit()


## Saves where the camera is: the focused context, the overworld camera
## and the zoom.
func set_bookmark(slot: int) -> void:
	bookmarks[slot] = {"focus": focus, "plot": camera_plot, "zoom": zoom, "centre": battle_centre}
	changed.emit()


## Jumps back to a bookmark. A bookmarked battle that ended falls back to
## its overworld view.
func recall_bookmark(slot: int) -> void:
	if not bookmarks.has(slot):
		return
	var b: Dictionary = bookmarks[slot]
	followed = -1
	camera_plot = b["plot"]
	if b["focus"] != OVERWORLD and _battles.has(b["focus"]):
		focus_battle(b["focus"])
		set_battle_camera(b["zoom"], b.get("centre", NO_CENTRE))
		return
	focus = OVERWORLD
	zoom = b["zoom"]
	changed.emit()


# --- picture-in-picture ------------------------------------------------------

## Shows a battle in a picture-in-picture view (not the focused one).
func pin(eid: int) -> void:
	if not _battles.has(eid) or pips.has(eid) or eid == focus or pips.size() >= MAX_PIPS:
		return
	pips.append(eid)
	changed.emit()


func unpin(eid: int) -> void:
	if pips.has(eid):
		pips.erase(eid)
		pip_offsets.erase(eid)
		changed.emit()


func toggle_pin(eid: int) -> void:
	if pips.has(eid):
		unpin(eid)
	else:
		pin(eid)


## Remembers where the player moved a picture-in-picture view.
func move_pip(eid: int, offset: Vector2) -> void:
	if pips.has(eid):
		pip_offsets[eid] = offset
		changed.emit()


## Keeps the selected feature while the player's knowledge of its hex
## holds it (in sight or last seen); clears it when it is gone.
func _sync_feature(obs: Dictionary) -> void:
	var entry := _feature_entry(obs, selected_feature, selected_plot)
	if entry.is_empty():
		selected_feature = -1
		return
	feature_in_sight = bool(entry.get("visible", false))


## The known plot entry of obs holding feature fid on plot p, or {}.
static func _feature_entry(obs: Dictionary, fid: int, p: int) -> Dictionary:
	var entry: Dictionary = (obs.get("plots", {}) as Dictionary).get(p, {})
	for f: Dictionary in entry.get("features", []):
		if int(f["id"]) == fid:
			return entry
	return {}


func _leave_battle(p: int) -> void:
	focus = OVERWORLD
	zoom = ZOOM_DEFAULT
	battle_centre = NO_CENTRE
	camera_plot = _commanders[followed]["plot"] if _commanders.has(followed) else p


static func _sorted(keys: Array) -> Array:
	var k := keys.duplicate()
	k.sort()
	return k
