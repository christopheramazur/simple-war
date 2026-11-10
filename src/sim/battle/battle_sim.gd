class_name BattleSim
extends RefCounted
## The battle's fixed system order (R5Q17). Same state + same orders =>
## same result. One BattleSim can run any number of battles.

var runner := SystemRunner.new()
## Optional read-only observer called after every tick with the state, e.g.
## the replay recorder. It must never write to the state.
var tick_hook: Callable = Callable()


func _init() -> void:
	runner.add_phase(&"move", [Centroids.new(), MovementSystem.new()] as Array[SimSystem])
	runner.add_phase(&"sense", [Centroids.new(), VisionSystem.new(), Reactions.new()] as Array[SimSystem])
	runner.add_phase(&"fight", [CombatSystem.new()] as Array[SimSystem])
	runner.add_phase(&"pressure", [Centroids.new(), PoolsSystem.new()] as Array[SimSystem])


## Runs one full Execute (ticks_per_turn ticks) and resolves the turn.
func execute_turn(state: BattleState) -> void:
	state.begin_turn()
	for _t in state.rules.ticks_per_turn:
		runner.step(state)
		if tick_hook.is_valid():
			tick_hook.call(state)
	Centroids.update(state)
	TurnResolution.resolve(state)
	Reactions.clear_all(state)
	if tick_hook.is_valid():
		tick_hook.call(state)
