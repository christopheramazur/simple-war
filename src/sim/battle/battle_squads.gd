class_name BattleSquads
extends SoaTable
## One row per squad, the command unit. GDD 02 §2.3-2.8, 03 §3.3.
## Squads stay in the table after destruction (destroyed = 1) so IDs held by
## events, orders and scores stay meaningful for the whole battle.

enum Order { HOLD, MOVE, ATTACK_MOVE, ATTACK, FALL_BACK, WITHDRAW }

## Pool columns in DataSchema.SIMPL order.
const POOLS: Array[StringName] = [&"p_stamina", &"p_instinct", &"p_morale", &"p_prowess", &"p_legend"]
const STAMINA: int = 0
const INSTINCT: int = 1
const MORALE: int = 2
const PROWESS: int = 3
const LEGEND: int = 4

var player := PackedInt64Array()
var tmpl := PackedInt64Array()          ## BattleRules squad template index
var order := PackedInt64Array()         ## Order
var tx := PackedInt64Array()            ## order target point, fixed
var ty := PackedInt64Array()
var target := PackedInt64Array()        ## order target squad ID, -1 none
var run := PackedByteArray()            ## running (sinks Stamina)
var facing := PackedInt64Array()        ## squad facing, binary angle
var ax := PackedInt64Array()            ## formation anchor, fixed
var ay := PackedInt64Array()
var cx := PackedInt64Array()            ## centroid of living units, fixed
var cy := PackedInt64Array()
var alive := PackedInt64Array()         ## living units
var hp_max := PackedInt64Array()        ## total starting HP
var hp_lost := PackedInt64Array()
var destroyed := PackedByteArray()
var withdrawn := PackedByteArray()
var engaged := PackedInt64Array()       ## squad ID it is firing at, -1 none
var detect_on := PackedByteArray()
var conceal_on := PackedByteArray()
var seen_by := PackedInt64Array()       ## bitmask of players that see it (bit = player)
var fired_tick := PackedInt64Array()
var moving := PackedByteArray()
var reaction := PackedInt64Array()      ## queued reaction index, -1 none
var reaction_trigger := PackedInt64Array()  ## enemy squad ID that triggers it
var dmg_dealt := PackedInt64Array()     ## remainder accumulators for "per 10" Legend floats
var dmg_taken := PackedInt64Array()
var p_stamina := PackedInt64Array()
var p_instinct := PackedInt64Array()
var p_morale := PackedInt64Array()
var p_prowess := PackedInt64Array()
var p_legend := PackedInt64Array()


func _init() -> void:
	super(&"squad")
	for c: StringName in [&"player", &"tmpl", &"order", &"tx", &"ty", &"run", &"facing", &"ax", &"ay",
			&"cx", &"cy", &"alive", &"hp_max", &"hp_lost", &"destroyed", &"withdrawn",
			&"detect_on", &"conceal_on", &"seen_by", &"moving", &"dmg_dealt", &"dmg_taken",
			&"p_stamina", &"p_instinct", &"p_morale", &"p_prowess", &"p_legend"]:
		declare(c, 0)
	for c: StringName in [&"target", &"engaged", &"fired_tick", &"reaction", &"reaction_trigger"]:
		declare(c, -1)


func is_active(row: int) -> bool:
	return destroyed[row] == 0 and withdrawn[row] == 0


## Player bit for seen_by masks.
static func bit(player_id: int) -> int:
	return 1 << player_id
