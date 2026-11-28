class_name OverworldOwnerActions
extends RefCounted
## Owner actions resolved (U1Q24, GDD 02 §2.9): remote buys planned with
## OverworldOrders.set_owner_action, after activities and before
## production. Players in seat order (ascending), each player's features
## by ascending ID, each feature's buys in planned order; Value is paid as
## each buy resolves, so later buys may find it spent.
## A buy is cancelled, with nothing paid, when the feature is gone or no
## longer the player's, its hex is engaged, its hex is contested (a hostile
## commander, or a hostile detachment with squads, stands on it), the
## option is no longer offered, the feature's limit is reached, or the
## player lacks the Value. Reasons never name what contests the hex: an
## enemy the player does not see stays unseen ("contested").
## What is bought is made like produced output (Convoys.output_detachment):
## into the owner's garrison on the hex, or a caravan leaving on the
## feature's supply line.

const NOT_YOURS := "not your feature"
const GONE := "the feature is gone"
const ENGAGED := "engaged"
const CONTESTED := "contested"
const NOT_OFFERED := "no longer offered here"
const LIMIT := "the limit for this turn is reached"
const NO_VALUE := "not enough Value"


static func resolve(s: OverworldState) -> void:
	var by_player := {}
	for fid: int in s.owner_orders:
		var player: int = s.owner_orders[fid]["player"]
		if not by_player.has(player):
			by_player[player] = []
		by_player[player].append(fid)
	var players: Array = by_player.keys()
	players.sort()
	for player: int in players:
		var fids: Array = by_player[player]
		fids.sort()
		for fid: int in fids:
			var made := 0
			for option: String in s.owner_orders[fid]["buys"]:
				if _buy(s, player, fid, option, made):
					made += 1
	s.owner_orders = {}


## One buy; whether it went through.
static func _buy(s: OverworldState, player: int, fid: int, option: String, made: int) -> bool:
	var f := s.features
	var row := f.row_of(fid)
	var p := f.plot[row] if row >= 0 else -1
	var why := ""
	var buy := PackedInt64Array()
	if row < 0:
		why = GONE
	elif f.owner[row] != player:
		why = NOT_YOURS
	elif s.engagement_at(p) >= 0:
		why = ENGAGED
	elif contested(s, player, p):
		why = CONTESTED
	else:
		var t := f.tmpl[row]
		buy = s.rules.buy_option(t, option) if s.rules.has_owner_action(t, "buy") else PackedInt64Array()
		if buy.is_empty():
			why = NOT_OFFERED
		elif made >= s.rules.hf_buys[t]:
			why = LIMIT
		elif s.value_of(player) < buy[3]:
			why = NO_VALUE
	if not why.is_empty():
		s.events.push(&"owner_action_cancelled", {"player": player, "feature": fid, "plot": p, "action": "buy",
			"option": option, "reason": why}, s.tick)
		return false
	s.add_value(player, -buy[3], &"owner_action")
	var did := Convoys.output_detachment(s, fid, player, p)
	if buy[0] >= 0:
		var sq := buy[0]
		var size := s.rules.sq_size[sq]
		var id := s.squads.spawn({&"holder": -1, &"detachment": did, &"tmpl": sq, &"alive": size, &"size": size})
		s.events.push(&"squad_bought", {"feature": fid, "player": player, "plot": p, "squad": id, "tmpl": sq,
			"detachment": did, "cost": buy[3]}, s.tick)
	else:
		WarChest.add(s, buy[1], buy[2], -1, did, -1)
		s.events.push(&"item_bought", {"feature": fid, "player": player, "plot": p, "item": buy[1],
			"count": buy[2], "detachment": did, "cost": buy[3]}, s.tick)
	return true


## Whether a hostile commander, or a hostile detachment holding squads,
## stands on plot p.
static func contested(s: OverworldState, player: int, p: int) -> bool:
	for cid in Commanders.at(s, p):
		if s.hostile(player, s.commanders.player[s.commanders.row_of(cid)]):
			return true
	for did in Detachments.at(s, p):
		if s.hostile(player, s.detachments.player[s.detachments.row_of(did)]) and not Detachments.squads_of(s, did).is_empty():
			return true
	return false
