class_name EvacuationController
extends RefCounted
## A scripted controller profile (R7Q15) for evacuation battles such as
## Angelfall's spaceport: reads only its player's observation.
##   - The leader's squad (template `lead`) takes the first zone that isn't
##     a hangar (the control console) and stays there, out of the way.
##   - Civilian squads (templates in `civilians`) spread over the hangar
##     zones (zones whose ID starts with "hangar").
##   - Every other squad escorts the civilians: attack-moves to the hangars
##     in turn.

var player: int
var lead: String
var civilians: PackedStringArray


func _init(player_id: int, lead_template: String = "jeff_squad", civilian_templates: PackedStringArray = PackedStringArray(["civilian_group"])) -> void:
	player = player_id
	lead = lead_template
	civilians = civilian_templates


func orders(obs: Dictionary) -> Array:
	var hangars := []
	var console := {}
	var locked := false
	for z: Dictionary in obs["zones"]:
		if String(z["id"]).begins_with("hangar"):
			hangars.append(z)
			locked = locked or z.get("locked", false)
		elif console.is_empty():
			console = z
	var out := []
	if hangars.is_empty():
		return out
	var n := 0
	for s: Dictionary in obs["squads"]:
		if s["player"] != player or s["destroyed"] or s["withdrawn"]:
			continue
		var target: Dictionary
		if s["template"] == lead and not console.is_empty():
			target = console
		elif civilians.has(s["template"]) or s["template"] == lead:
			target = hangars[n % hangars.size()]
			n += 1
		else:
			var to: Dictionary = hangars[n % hangars.size()]
			n += 1
			out.append({"squad": s["id"], "type": "attack_move", "x": to["x"], "y": to["y"]})
			continue
		out.append({"squad": s["id"], "type": "move", "x": target["x"], "y": target["y"], "run": true})
	return out


## No reactions: the profile keeps its plan.
func reactions(_opportunities: Array) -> Array:
	return []
