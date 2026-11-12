class_name WarChest
extends RefCounted
## The War Chest: an army's item inventory (GDD 02 §2.9, R3Q7, R4Q10).
##   - Items are per-unit gear (OverworldRules items): one item equips one
##     unit and fills one of its slots (weapon, defense or kit). No generic
##     +1 upgrades: 5 rifles from a cache arm 5 units (R3Q7).
##   - Places: each commander and each detachment (convoys included) has a
##     War Chest; equipped items belong to their squad and travel with it.
##     Identical items in one place form one stack (OverworldItems).
##   - Equipping: a commander outside battle equips items from its chest to
##     squads of its army, as many as the squad has units that fit and have
##     the slot free at full strength, and unequips them back.
##   - Casualties: a squad keeps its items; in battle they go to its first
##     surviving members that fit (leaders first, then template order), so
##     a refitted squad re-equips them (R4Q10). A destroyed squad's items
##     are scavenged into its commander's or detachment's chest (R3Q7).
##   - Trading: friendly commanders sharing a hex trade items during
##     planning (R7Q9); a commander takes the chest of its player's
##     detachment on its hex. A convoy delivering to its commander hands
##     over its chest; merging convoys merge chests (R6Q13).
##   - Pickups: a feature with `items` is a cache the first commander
##     through picks up into its chest, then the feature is removed.
##   - Unguarded chests: a detachment with no squads cannot fight. A hostile
##     commander (or, failing one, a hostile detachment with squads) on its
##     hex seizes its chest; guards destroy it.
##   - Lost: a defeated commander's chest and a destroyed or defeated
##     detachment's chest are lost with them.


# --- queries -----------------------------------------------------------------

## Stack IDs at a place (one of the three >= 0), ascending.
static func stacks(s: OverworldState, holder: int, did: int, squad: int) -> PackedInt64Array:
	var it := s.items
	var out := PackedInt64Array()
	for row in it.count():
		if it.holder[row] == holder and it.detachment[row] == did and it.squad[row] == squad:
			out.append(it.id_at(row))
	out.sort()
	return out


## A commander's War Chest.
static func chest(s: OverworldState, cid: int) -> PackedInt64Array:
	return stacks(s, cid, -1, -1)


## A detachment's (or convoy's) War Chest.
static func of_detachment(s: OverworldState, did: int) -> PackedInt64Array:
	return stacks(s, -1, did, -1)


## Stacks equipped to a squad.
static func on_squad(s: OverworldState, sid: int) -> PackedInt64Array:
	return stacks(s, -1, -1, sid)


## Items of template t at a place (0 if none).
static func count_of(s: OverworldState, t: int, holder: int, did: int, squad: int) -> int:
	var id := _find(s, t, holder, did, squad)
	return s.items.get_value(id, &"qty") if id >= 0 else 0


# --- moving items ------------------------------------------------------------

## Adds `count` items of template t at a place, merging into the stack
## there. Returns the stack ID.
static func add(s: OverworldState, t: int, count: int, holder: int, did: int, squad: int) -> int:
	var id := _find(s, t, holder, did, squad)
	if id >= 0:
		s.items.set_value(id, &"qty", s.items.get_value(id, &"qty") + count)
		return id
	return s.items.spawn({&"tmpl": t, &"qty": count, &"holder": holder, &"detachment": did, &"squad": squad})


## Moves `count` items of a stack to a place (all of them when count is at
## least the stack's). Returns the receiving stack's ID.
static func move(s: OverworldState, id: int, count: int, holder: int, did: int, squad: int) -> int:
	var it := s.items
	var row := it.row_of(id)
	var n := it.qty[row]
	var t := it.tmpl[row]
	if count < n:
		it.set_value(id, &"qty", n - count)
		return add(s, t, count, holder, did, squad)
	var into := _find(s, t, holder, did, squad)
	if into >= 0:
		it.set_value(into, &"qty", it.get_value(into, &"qty") + n)
		it.despawn(id)
		return into
	it.set_value(id, &"holder", holder)
	it.set_value(id, &"detachment", did)
	it.set_value(id, &"squad", squad)
	return id


## Moves a detachment's whole chest to a commander's chest (cid >= 0) or
## another detachment's (to_did).
static func hand_over(s: OverworldState, did: int, cid: int, to_did: int = -1) -> int:
	var n := 0
	for id in of_detachment(s, did):
		n += s.items.get_value(id, &"qty")
		move(s, id, 1 << 30, cid, -1 if cid >= 0 else to_did, -1)
	return n


## A squad about to be destroyed: survivors scavenge its items into its
## commander's or detachment's chest (R3Q7); with neither, they are lost.
static func scavenge(s: OverworldState, sid: int) -> void:
	var q := s.squads
	var row := q.row_of(sid)
	var holder := q.holder[row] if row >= 0 else -1
	var did := q.detachment[row] if row >= 0 else -1
	for id in on_squad(s, sid):
		if s.commanders.is_alive(holder):
			move(s, id, 1 << 30, holder, -1, -1)
		elif s.detachments.is_alive(did):
			move(s, id, 1 << 30, -1, did, -1)
		else:
			s.items.despawn(id)


## Removes stacks whose place is gone (a defeated commander, a disbanded
## detachment, a destroyed squad).
static func tidy(s: OverworldState) -> void:
	var it := s.items
	for id in it.ids():
		var row := it.row_of(id)
		if not (s.commanders.is_alive(it.holder[row]) or s.detachments.is_alive(it.detachment[row])
				or s.squads.is_alive(it.squad[row])):
			it.despawn(id)


# --- orders (planning) -------------------------------------------------------

## Equips `count` items of a stack in commander cid's chest to a squad of
## its army. "" or why not.
static func equip(s: OverworldState, player: int, cid: int, item_id: int, sid: int, count: int) -> String:
	var err := _free_commander(s, player, cid)
	if not err.is_empty():
		return err
	var it := s.items
	var row := it.row_of(item_id)
	if row < 0:
		return "no such item"
	if it.holder[row] != cid:
		return "not in this commander's War Chest"
	err = _own_squad(s, cid, sid)
	if not err.is_empty():
		return err
	if count < 1 or count > it.qty[row]:
		return "the War Chest holds %d" % it.qty[row]
	var t := it.tmpl[row]
	var room := room_for(s, t, sid)
	if room == 0:
		return "no unit in that squad can carry it"
	if count > room:
		return "only %d more units can carry it" % room
	move(s, item_id, count, -1, -1, sid)
	s.events.push(&"item_equipped", {"commander": cid, "player": player, "squad": sid, "item": t, "count": count}, s.tick)
	return ""


## Returns `count` items equipped to a squad of commander cid's army to its
## chest. "" or why not.
static func unequip(s: OverworldState, player: int, cid: int, item_id: int, count: int) -> String:
	var err := _free_commander(s, player, cid)
	if not err.is_empty():
		return err
	var it := s.items
	var row := it.row_of(item_id)
	if row < 0:
		return "no such item"
	var sid := it.squad[row]
	if sid < 0 or s.squads.get_value(sid, &"holder") != cid:
		return "not equipped in this commander's army"
	err = _own_squad(s, cid, sid)
	if not err.is_empty():
		return err
	if count < 1 or count > it.qty[row]:
		return "the squad carries %d" % it.qty[row]
	var t := it.tmpl[row]
	move(s, item_id, count, cid, -1, -1)
	s.events.push(&"item_unequipped", {"commander": cid, "player": player, "squad": sid, "item": t, "count": count}, s.tick)
	return ""


## Friendly commanders sharing a hex trade items during planning (R7Q9).
static func give(s: OverworldState, player: int, from_cid: int, item_id: int, count: int, to_cid: int) -> String:
	var err := _free_commander(s, player, from_cid)
	if err.is_empty():
		err = _free_commander(s, player, to_cid)
	if not err.is_empty():
		return err
	var it := s.items
	var row := it.row_of(item_id)
	if row < 0:
		return "no such item"
	if it.holder[row] != from_cid:
		return "not in this commander's War Chest"
	if from_cid == to_cid:
		return "already in that War Chest"
	if s.commanders.get_value(from_cid, &"plot") != s.commanders.get_value(to_cid, &"plot"):
		return "the commanders must share a hex"
	if count < 1 or count > it.qty[row]:
		return "the War Chest holds %d" % it.qty[row]
	var t := it.tmpl[row]
	move(s, item_id, count, to_cid, -1, -1)
	s.events.push(&"item_given", {"from": from_cid, "to": to_cid, "player": player, "item": t, "count": count}, s.tick)
	return ""


## A commander takes the whole chest of its player's detachment on its hex;
## a detachment left with no squads and no items is disbanded.
static func take(s: OverworldState, player: int, cid: int, did: int) -> String:
	var err := _free_commander(s, player, cid)
	if not err.is_empty():
		return err
	var d := s.detachments
	var dr := d.row_of(did)
	if dr < 0:
		return "no such detachment"
	if d.player[dr] != player:
		return "not your detachment"
	if d.plot[dr] != s.commanders.get_value(cid, &"plot"):
		return "the commander must be on the detachment's hex"
	if d.engagement[dr] >= 0:
		return "a detachment in a battle cannot be picked up"
	if of_detachment(s, did).is_empty():
		return "its War Chest is empty"
	var p := d.plot[dr]
	var n := hand_over(s, did, cid)
	s.events.push(&"items_taken", {"commander": cid, "detachment": did, "player": player, "plot": p, "count": n}, s.tick)
	if Detachments.squads_of(s, did).is_empty():
		Detachments.disband(s, did, "picked_up")
	return ""


static func _free_commander(s: OverworldState, player: int, cid: int) -> String:
	var cr := s.commanders.row_of(cid)
	if cr < 0:
		return "no such commander"
	if s.commanders.player[cr] != player:
		return "not your commander"
	if s.commanders.engagement[cr] >= 0:
		return "a commander in a battle cannot manage its War Chest"
	return ""


static func _own_squad(s: OverworldState, cid: int, sid: int) -> String:
	var qr := s.squads.row_of(sid)
	if qr < 0:
		return "no such squad"
	if s.squads.holder[qr] != cid:
		return "not in this commander's army"
	if s.squads.deployed[qr] >= 0:
		return "a squad in a battle cannot change gear"
	return ""


# --- fitting items to units --------------------------------------------------

## How many more items of template t squad sid can carry at full strength,
## keeping everything it already carries.
static func room_for(s: OverworldState, t: int, sid: int) -> int:
	var q := s.squads
	var row := q.row_of(sid)
	var size := q.size[row]
	var have := _equipped(s, sid)
	var base: int = have.get(t, 0)
	var n := 0
	while n < size:
		have[t] = base + n + 1
		if not _assign(s, q.tmpl[row], size, have)[1]:
			break
		n += 1
	return n


## Which item each member slot carries when `units` members are alive:
## [slots (per member: PackedInt64Array [weapon, defense, kit] item
## templates, -1 = none), every item placed]. Stacks go in item template
## order to the first members that fit and have the slot free.
static func _assign(s: OverworldState, sq: int, units: int, have: Dictionary) -> Array:
	var r := s.rules
	var slots := []
	for i in units:
		slots.append(PackedInt64Array([-1, -1, -1]))
	var all := true
	var ts: Array = have.keys()
	ts.sort()
	for t: int in ts:
		var k := r.it_slot[t]
		var left: int = have[t]
		for i in units:
			if left == 0:
				break
			var sl: PackedInt64Array = slots[i]
			if sl[k] < 0 and r.item_fits(t, sq, i):
				sl[k] = t
				slots[i] = sl
				left -= 1
		if left > 0:
			all = false
	return [slots, all]


## Item template -> count equipped to squad sid.
static func _equipped(s: OverworldState, sid: int) -> Dictionary:
	var out := {}
	for id in on_squad(s, sid):
		out[s.items.get_value(id, &"tmpl")] = s.items.get_value(id, &"qty")
	return out


## The squad's gear for a battle with `units` members alive: per member
## slot, {"weapon", "defense" (template IDs, "" = its own), "bundles"}.
## Empty when it carries nothing.
static func gear(s: OverworldState, sid: int, units: int) -> Array:
	var have := _equipped(s, sid)
	if have.is_empty():
		return []
	var r := s.rules
	var slots: Array = _assign(s, s.squads.get_value(sid, &"tmpl"), units, have)[0]
	var out := []
	for sl: PackedInt64Array in slots:
		var g := {"weapon": "", "defense": "", "bundles": PackedStringArray()}
		for t in sl:
			if t < 0:
				continue
			if r.it_weapon[t] != "":
				g["weapon"] = r.it_weapon[t]
			if r.it_defense[t] != "":
				g["defense"] = r.it_defense[t]
			(g["bundles"] as PackedStringArray).append_array(r.it_bundles[t])
		out.append(g)
	return out


# --- pickups, production and seizure ----------------------------------------

## A commander picks up feature fid's item cache.
static func pick_up(s: OverworldState, cid: int, fid: int) -> void:
	var r := s.rules
	var grants := r.hf_items[s.features.get_value(fid, &"tmpl")]
	var got := []
	for i in range(0, grants.size(), 2):
		var id := add(s, grants[i], grants[i + 1], cid, -1, -1)
		got.append({"stack": id, "item": grants[i], "count": grants[i + 1]})
	s.events.push(&"items_picked", {"commander": cid, "player": s.commanders.get_value(cid, &"player"),
		"plot": s.features.get_value(fid, &"plot"), "feature": fid, "items": got}, s.tick)


## A detachment with no squads on plot p is seized by a hostile commander
## there (lowest ID), else a hostile detachment with squads; guards destroy
## its chest. Returns whether it was taken.
static func seize(s: OverworldState, did: int, p: int) -> bool:
	var d := s.detachments
	var row := d.row_of(did)
	if row < 0 or not Detachments.squads_of(s, did).is_empty():
		return false
	var player := d.player[row]
	var by_cid := -1
	for cid in Commanders.at(s, p):
		if s.hostile(player, s.commanders.get_value(cid, &"player")):
			by_cid = cid
			break
	var by_did := -1
	if by_cid < 0:
		for other in Detachments.at(s, p):
			if s.hostile(player, d.get_value(other, &"player")) and not Detachments.squads_of(s, other).is_empty():
				by_did = other
				break
	var guarded := not s.guard_at(p).is_empty()
	if by_cid < 0 and by_did < 0 and not guarded:
		return false
	var by := 0
	if by_cid >= 0:
		by = s.commanders.get_value(by_cid, &"player")
	elif by_did >= 0:
		by = d.get_value(by_did, &"player")
	var n := 0
	for id in of_detachment(s, did):
		n += s.items.get_value(id, &"qty")
	if by_cid >= 0 or by_did >= 0:
		hand_over(s, did, by_cid, by_did)
	s.events.push(&"items_seized", {"detachment": did, "player": player, "plot": p, "by": by,
		"commander": by_cid, "count": n}, s.tick)
	Detachments.disband(s, did, "seized")
	return true


## Seizes every unguarded chest sharing a hex with hostile forces.
static func seize_all(s: OverworldState) -> void:
	var d := s.detachments
	var all := d.ids()
	all.sort()
	for did in all:
		var row := d.row_of(did)
		if row >= 0 and d.engagement[row] < 0:
			seize(s, did, d.plot[row])


# --- views -------------------------------------------------------------------

## Stacks as plain data: [{"id", "item" (template ID), "name", "icon",
## "tags", "value", "slot", "count"}]; sort and filter on any field.
static func view(s: OverworldState, ids: PackedInt64Array) -> Array:
	var r := s.rules
	var out := []
	for id in ids:
		var row := s.items.row_of(id)
		var t := s.items.tmpl[row]
		out.append({"id": id, "item": r.item_ids[t], "name": r.it_names[t], "icon": r.it_icons[t],
			"tags": r.it_tags[t], "value": r.it_value[t], "slot": ["weapon", "defense", "kit"][r.it_slot[t]],
			"count": s.items.qty[row]})
	return out


## A commander's War Chest with, per stack, the army's squads that can
## take more of it: "squads": [{"squad", "room"}] (the detail view).
static func chest_view(s: OverworldState, cid: int) -> Array:
	var out := view(s, chest(s, cid))
	var army := OverworldArmies.of(s, cid)
	for x: Dictionary in out:
		var t := s.items.get_value(x["id"], &"tmpl")
		var fits := []
		for sid in army:
			var n := room_for(s, t, sid)
			if n > 0:
				fits.append({"squad": sid, "room": n})
		x["squads"] = fits
	return out


static func _find(s: OverworldState, t: int, holder: int, did: int, squad: int) -> int:
	var it := s.items
	for row in it.count():
		if it.tmpl[row] == t and it.holder[row] == holder and it.detachment[row] == did and it.squad[row] == squad:
			return it.id_at(row)
	return -1
