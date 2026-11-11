class_name AbilitySystem
extends SimSystem
## Runs first every tick, before EffectSystem: readying, lose_on move and
## attack, expiry of held states, toggle upkeep and auto-off (Abilities).


func system_name() -> StringName:
	return &"abilities"


func run(ctx: SimContext) -> void:
	var state := ctx as BattleState
	if state.abilities.count() > 0:
		Abilities.tick(state)
