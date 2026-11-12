class_name Commanders
extends RefCounted
## Commander lifecycle and queries on the overworld (GDD 02 §2.3, §2.9).


## Places a commander. Setup and campaign scripts only (structural change).
static func spawn(s: OverworldState, player: int, commander: String, p: int) -> int:
	var t := s.rules.commander_index(commander)
	assert(t >= 0, "Commanders.spawn: unknown commander '%s'" % commander)
	return spawn_index(s, player, t, p)


## Spawns commander template t with its own squad and starting army.
static func spawn_index(s: OverworldState, player: int, t: int, p: int) -> int:
	var cid := s.commanders.spawn({&"player": player, &"tmpl": t, &"plot": p})
	OverworldArmies.muster(s, cid)
	return cid


## Movement points available this turn: the template's per-turn points plus
## whatever was banked last turn.
static func budget(s: OverworldState, row: int) -> int:
	return s.rules.cm_mp[s.commanders.tmpl[row]] + s.commanders.banked[row]


static func name_of(s: OverworldState, row: int) -> String:
	return s.rules.cm_names[s.commanders.tmpl[row]]


## Commander IDs on a plot, ascending.
static func at(s: OverworldState, p: int) -> PackedInt64Array:
	var out := PackedInt64Array()
	for row in s.commanders.count():
		if s.commanders.plot[row] == p:
			out.append(s.commanders.id_at(row))
	out.sort()
	return out
