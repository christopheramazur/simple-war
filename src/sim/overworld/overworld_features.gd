class_name OverworldFeatures
extends SoaTable
## One row per feature on a plot (GDD 02 §2.9). Features come from map
## generation, player activity and natural events, so they spawn and despawn
## during play. A plot holds at most one of each feature template.

var plot := PackedInt64Array()   ## plot index (row * width + col)
var tmpl := PackedInt64Array()   ## OverworldRules feature index
var owner := PackedInt64Array()  ## controlling player, 0 = neutral
## 1 = its guard was beaten (the feature stays unguarded).
var cleared := PackedInt64Array()
## Selected production option (index into its `produces`).
var output := PackedInt64Array()
## Turns of production towards the next squad.
var progress := PackedInt64Array()


func _init() -> void:
	super(&"hex_feature")
	declare(&"plot", 0)
	declare(&"tmpl", 0)
	declare(&"owner", 0)
	# 1 = its guard was beaten: the feature is unguarded from then on.
	declare(&"cleared", 0)
	declare(&"output", 0)
	declare(&"progress", 0)
