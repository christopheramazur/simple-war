class_name BattleFx
extends RefCounted
## What a played-back battle turn looks like at a moment (sw-aba): shots as
## projectiles, recoil, hit flashes, deaths and floating numbers, all as pure
## functions of the playback frame (a float: ContextView's _play_t times the
## frame count). Built once per OverworldSession.playback entry.
##
## Timing keeps the picture honest: frame i shows the state after the i-th
## tick, so a hit recorded at frame i lowers HP there. Its projectile is
## launched earlier so it lands exactly at frame i, when the flash, the
## number and the HP drop all show. A miss passes the target at frame i and
## flies on behind it, fading; "miss" floats over the shooter then.

## Projectile speed, metres per tick, and its flight-time bounds (ticks).
const SPEED: float = 3.0
const MIN_FLIGHT: float = 4.0
const MAX_FLIGHT: float = 12.0
## A burst's later rounds leave this many ticks after the first.
const BURST_GAP: float = 0.6
## A miss flies on this much of its range past the target, this far aside (m).
const MISS_PAST: float = 0.7
const MISS_ASIDE: float = 1.4
const RECOIL_TICKS: float = 4.0
const RECOIL_ANGLE: float = 0.3
const FLASH_TICKS: float = 4.0
const DEATH_TICKS: float = 8.0
const FLOAT_TICKS: float = 16.0
const MISS_FLOAT_TICKS: float = 10.0

## Per frame: unit ID -> [point (metres), template ID, player].
var _units: Array = []
## [{"launch", "land", "end" (frames), "from", "to", "past" (metres),
## "shooter", "victim", "hit", "player"}]
var shots: Array = []
## [{"at" (frame), "unit", "damage" (fixed), "stack"}]
var hits: Array = []
## [{"at", "unit", "stack"}]: misses, floated over the shooter.
var misses: Array = []
## [{"at", "unit", "pos", "tmpl", "player"}]: units a hit killed.
var deaths: Array = []


static func from_playback(rec: Dictionary) -> BattleFx:
	var fx := BattleFx.new()
	for frame: Dictionary in rec.get("frames", []):
		var m := {}
		for sid: int in frame:
			var d: Dictionary = frame[sid]
			var tmpls: Array = d.get("tmpls", [])
			for j in (d["ids"] as Array).size():
				m[d["ids"][j]] = [d["units"][j], tmpls[j] if j < tmpls.size() else "", d["player"]]
		fx._units.append(m)
	fx._build(rec.get("volleys", []), rec.get("hits", []))
	return fx


func _build(volleys: Array, hit_list: Array) -> void:
	var burst := {}
	var miss_n := {}
	var n := 0
	for v: Array in volleys:
		var land := float(v[0])
		var before := maxi(int(v[0]) - 1, 0)
		var from: Variant = point(v[1], before)
		var to: Variant = point(v[2], before)
		if from == null or to == null:
			continue
		var key := "%d|%d" % [v[0], v[1]]
		var k: int = burst.get(key, 0)
		burst[key] = k + 1
		var dist := (from as Vector2).distance_to(to)
		var flight := maxf(clampf(dist / SPEED, MIN_FLIGHT, MAX_FLIGHT) - k * BURST_GAP, 1.0)
		var s := {"launch": maxf(land - flight, 0.0), "land": land, "end": land, "from": from, "to": to,
			"past": to, "shooter": v[1], "victim": v[2], "hit": bool(v[3]), "player": _player_of(v[1], before)}
		if not s["hit"]:
			# Past the target and a little aside, alternating sides.
			var dir := ((to as Vector2) - (from as Vector2)).normalized()
			var side := 1.0 if n % 2 == 0 else -1.0
			s["past"] = (to as Vector2) + dir * dist * MISS_PAST + dir.orthogonal() * MISS_ASIDE * side
			s["end"] = land + (land - float(s["launch"])) * MISS_PAST
			var mk := "%d|%d" % [v[0], v[1]]
			misses.append({"at": land, "unit": v[1], "stack": miss_n.get(mk, 0)})
			miss_n[mk] = int(miss_n.get(mk, 0)) + 1
		shots.append(s)
		n += 1
	var stack := {}
	for h: Array in hit_list:
		var hk := "%d|%d" % [h[0], h[1]]
		hits.append({"at": float(h[0]), "unit": h[1], "damage": h[2], "stack": stack.get(hk, 0)})
		stack[hk] = int(stack.get(hk, 0)) + 1
		var f := int(h[0])
		var before := maxi(f - 1, 0)
		if stack[hk] == 1 and f < _units.size() and not (_units[f] as Dictionary).has(h[1]) \
				and (_units[before] as Dictionary).has(h[1]):
			var u: Array = _units[before][h[1]]
			deaths.append({"at": float(f), "unit": h[1], "pos": u[0], "tmpl": u[1], "player": u[2]})


func _player_of(uid: int, i: int) -> int:
	for j in [i, mini(i + 1, _units.size() - 1)]:
		var u: Variant = (_units[j] as Dictionary).get(uid)
		if u != null:
			return int(u[2])
	return 0


## A unit's point (metres) at a frame (float), or null if never seen around
## then: between frames it is interpolated; a unit missing on one side is
## taken where it was on the other.
func point(uid: int, f: float) -> Variant:
	if _units.is_empty():
		return null
	var i := clampi(int(floor(f)), 0, _units.size() - 1)
	var j := mini(i + 1, _units.size() - 1)
	var a: Variant = (_units[i] as Dictionary).get(uid)
	var b: Variant = (_units[j] as Dictionary).get(uid)
	if a == null and b == null:
		return null
	if a == null:
		return b[0]
	if b == null:
		return a[0]
	return (a[0] as Vector2).lerp(b[0], clampf(f - i, 0.0, 1.0))


## Projectiles in flight at frame `f`: [{"at", "tail" (metres), "alpha",
## "player", "hit"}]. The tail trails the head toward where it came from.
func projectiles(f: float) -> Array:
	var out := []
	for s: Dictionary in shots:
		if f < s["launch"] or f >= s["end"] or (s["hit"] and f >= s["land"]):
			continue
		var at: Vector2
		var back: Vector2
		var alpha := 1.0
		if f < s["land"]:
			var p := (f - float(s["launch"])) / maxf(float(s["land"]) - float(s["launch"]), 0.001)
			# Aim at where the victim is now, so it lands on the unit.
			var to: Vector2 = s["to"]
			if s["hit"]:
				var now: Variant = point(s["victim"], f)
				if now != null:
					to = now
			at = (s["from"] as Vector2).lerp(to, p)
			back = s["from"]
		else:
			var q := (f - float(s["land"])) / maxf(float(s["end"]) - float(s["land"]), 0.001)
			at = (s["to"] as Vector2).lerp(s["past"], q)
			back = s["to"]
			alpha = 1.0 - q
		var tail := at + (back - at).limit_length(1.6)
		out.append({"at": at, "tail": tail, "alpha": alpha, "player": s["player"], "hit": s["hit"]})
	return out


## Shooters kicked back at frame `f`: unit ID -> signed tilt (radians),
## leaning away from the target (positive is clockwise).
func recoil(f: float) -> Dictionary:
	var out := {}
	for s: Dictionary in shots:
		var age := f - float(s["launch"])
		if age < 0.0 or age >= RECOIL_TICKS:
			continue
		var dx: float = (s["to"] as Vector2).x - (s["from"] as Vector2).x
		var mag := RECOIL_ANGLE * pow(1.0 - age / RECOIL_TICKS, 2.0)
		var a := -mag if dx >= 0.0 else mag
		if absf(a) > absf(float(out.get(s["shooter"], 0.0))):
			out[s["shooter"]] = a
	return out


## Units flashing from a hit at frame `f`: unit ID -> strength (0..1].
func flashes(f: float) -> Dictionary:
	var out := {}
	for h: Dictionary in hits:
		var age := f - float(h["at"])
		if age >= 0.0 and age < FLASH_TICKS:
			out[h["unit"]] = maxf(float(out.get(h["unit"], 0.0)), 1.0 - age / FLASH_TICKS)
	return out


## Units killed shortly before frame `f`, fading: [{"pos", "tmpl",
## "player", "fade" (1..0)}].
func dying(f: float) -> Array:
	var out := []
	for d: Dictionary in deaths:
		var age := f - float(d["at"])
		if age >= 0.0 and age < DEATH_TICKS:
			out.append({"pos": d["pos"], "tmpl": d["tmpl"], "player": d["player"], "fade": 1.0 - age / DEATH_TICKS})
	return out


## Floating text at frame `f`: [{"at" (metres), "text", "miss", "rise"
## (0..1, how far through its float), "stack"}]. Damage floats over the
## unit hit, "miss" over the shooter.
func floaters(f: float) -> Array:
	var out := []
	for h: Dictionary in hits:
		var age := f - float(h["at"])
		if age < 0.0 or age >= FLOAT_TICKS:
			continue
		var at: Variant = point(h["unit"], h["at"])
		if at == null:
			at = point(h["unit"], h["at"] - 1.0)
		if at != null:
			out.append({"at": at, "text": damage_text(h["damage"]), "miss": false, "rise": age / FLOAT_TICKS, "stack": h["stack"]})
	for m: Dictionary in misses:
		var age := f - float(m["at"])
		if age < 0.0 or age >= MISS_FLOAT_TICKS:
			continue
		var at: Variant = point(m["unit"], f)
		if at != null:
			out.append({"at": at, "text": "miss", "miss": true, "rise": age / MISS_FLOAT_TICKS, "stack": m["stack"]})
	return out


## Damage (fixed) as shown: whole points, one decimal below one.
static func damage_text(dmg: int) -> String:
	var v := float(dmg) / float(Fixed.ONE)
	return ("%.1f" % v) if v < 0.95 else str(roundi(v))
