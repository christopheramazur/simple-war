class_name SimSystem
extends RefCounted
## A system is a function over one context's state: it reads tables and
## events, writes columns of the tables it owns, queues structural changes in
## the command buffer, and pushes events. It holds no simulation state of its
## own (configuration only), so the same system object can run any context.
## GDD 04 §4.2, R5Q17.


## Stable name for logs and ordering checks.
func system_name() -> StringName:
	return &"system"


func run(_ctx: SimContext) -> void:
	pass
