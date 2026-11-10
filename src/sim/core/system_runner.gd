class_name SystemRunner
extends RefCounted
## Runs systems in a fixed, caller-owned order: phases in order, systems in
## order within a phase, and the command buffer applied at the end of every
## phase. Same state + same inputs => same result. GDD 04 §4.2, R5Q17.

## When true, `step()` records the state hash after every tick.
var hash_every_tick: bool = false
## Per-tick hashes (hex) recorded while `hash_every_tick` is on.
var tick_hashes: PackedStringArray = PackedStringArray()

var _phase_names: Array[StringName] = []
var _phases: Array[Array] = []


func add_phase(phase_name: StringName, systems: Array[SimSystem]) -> void:
	assert(not _phase_names.has(phase_name), "SystemRunner: duplicate phase %s" % phase_name)
	_phase_names.append(phase_name)
	_phases.append(systems)


## Phase and system names in execution order, for audits.
func order() -> PackedStringArray:
	var out := PackedStringArray()
	for i in _phases.size():
		for s: SimSystem in _phases[i]:
			out.append("%s/%s" % [_phase_names[i], s.system_name()])
	return out


## Advances `ctx` by one tick.
func step(ctx: SimContext) -> void:
	for systems: Array in _phases:
		for s: SimSystem in systems:
			s.run(ctx)
		ctx.commands.apply(ctx)
	ctx.end_tick()
	if hash_every_tick:
		tick_hashes.append(ctx.state_hash_hex())


func step_n(ctx: SimContext, ticks: int) -> void:
	for _i in ticks:
		step(ctx)
