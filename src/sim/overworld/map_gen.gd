class_name MapGen
extends RefCounted
## Runs a map template's passes in order (R3Q13). Seeds exist only for
## content generation (GDD 02 §2.1): the state's RNG drives scatter, so the
## same template and seed always give the same map.


static func generate(s: OverworldState) -> void:
	var r := s.rules
	for p: Dictionary in r.passes:
		match OverworldRules.PASSES[p["op"]]:
			"fill":
				for plot in r.plot_count():
					s.add_feature(plot, p["feature"], p["owner"])
			"rect":
				for row in range(p["row"], p["row"] + p["h"]):
					for col in range(p["col"], p["col"] + p["w"]):
						s.add_feature(Hex.plot(col, row, r.width), p["feature"], p["owner"])
			"place":
				s.add_feature(Hex.plot(p["col"], p["row"], r.width), p["feature"], p["owner"])
			"line":
				var a := Hex.plot(p["col"], p["row"], r.width)
				var b := Hex.plot(p["to_col"], p["to_row"], r.width)
				for plot in Hex.line(a, b, r.width, r.height):
					if plot >= 0:
						s.add_feature(plot, p["feature"], p["owner"])
			"scatter":
				_scatter(s, p)


static func _scatter(s: OverworldState, p: Dictionary) -> void:
	var r := s.rules
	var f: int = p["feature"]
	var avoid: PackedInt64Array = p["avoid"]
	var candidates := PackedInt64Array()
	for row in range(p["row"], p["row"] + p["h"]):
		for col in range(p["col"], p["col"] + p["w"]):
			var plot := Hex.plot(col, row, r.width)
			if s.feature_row(plot, f) >= 0:
				continue
			var blocked := false
			for fr in s.features_at(plot):
				if avoid.has(s.features.tmpl[fr]):
					blocked = true
					break
			if not blocked:
				candidates.append(plot)
	for _i in p["count"]:
		if candidates.is_empty():
			return
		var plot := candidates[s.rng.next_below(candidates.size())]
		s.add_feature(plot, f, p["owner"])
		var keep := PackedInt64Array()
		for c in candidates:
			if Hex.plot_distance(c, plot, r.width) > p["spacing"]:
				keep.append(c)
		candidates = keep
