# Research Note: Composable Hexes, Remote Actions, Caravan ECS

## 1. Prior art — what made it readable

**HoMM 3** — 32px tile grid; objects have a *footprint mask* plus exactly one **entrance/active tile**. Art overflows the footprint, but logic never does. Owner flag sits at a fixed offset on every mine/town; guards render as a stack sprite *on* the entrance tile. Lessons: one interaction point per object; ownership marker in a constant screen-relative slot; art may be big, the anchor may not move. **HoMM 5/7** kept tile-anchored footprints under a 3D camera and added hover outline + tooltip; 7's larger art hurt readability precisely where silhouettes overlapped neighbours — the failure mode our keep-out logic must avoid.

**Civ V** — one improvement *or* one unit *or* one city per tile; sight is a per-entity radius (≈2 military, 3 scout, cities ≈2). **Civ VI** — districts spread a city across tiles, one dominant structure per tile, yields as small badges, routes as a separate layer painted between/over tiles. Lesson: separate **terrain / route / occupant / actor / overlay** layers; never let two "dominant" objects share a tile.

**Humankind / Old World** — district sprawl and urban tiles, one unit per tile, ownership borders tinted, numeric badges at consistent size. Readability came from *uniform icon grammar*, not from art detail.

**Endless Legend** — ownership at **region** granularity, districts and villages composed inside it; armies are one map entity holding many units. This is the closest analogue to our fat hex: the region is the composability boundary, the map entity is the thing you select and tooltip.

**Battle Brothers / Bannerlord** — caravans are ordinary world parties with a distinct banner, a size number, and a tooltip that *explains* speed (terrain, cargo, herd, riding, night). Vision is party-derived and scout-modifiable. Lesson: slow entities need legible *why-am-I-slow* breakdowns or players read them as bugs.

## 2. Deterministic in-hex layout

Normalize to hex circumradius 1, pointy-top, y-up. Usable inner radius `r_in = 0.78` (outer ring reserved for ownership border + road entry).

**Slot sets** (ring layout, start angle 90°, step 360/n, index order fixed):
`n=1: r=0` · `n=2: r=0.30` · `n=3: 0.36` · `n=4: 0.40` · `n=5: 0.43` · `n=6: 0.45`.

**Priority sort** (kind first, then feature id ascending — stable, no RNG): village/town > barracks > mine > shrine/special > guard/lair > decor. Footprint radii: village .26, barracks .20, mine .18, guard .14, decor .10. If ring capacity is exceeded, scale all footprints uniformly (floor 0.75).

**Road-aware offsets:**
1. Roads enter/exit via edge indices; build polyline edge-midpoint → center → edge-midpoint.
2. Keep-out half-width `w = 0.16 + roadWidth/2`.
3. Per slot, signed perpendicular distance `d` to nearest segment. If `|d| < w + r_feature`, translate along the segment normal by `(w + r_feature − |d|) · sign(d)`; `d == 0` → pick left-of-travel (lower edge index → higher), deterministic.
4. Clamp into inset hex via hex SDF projection.
5. Two relaxation passes: for pairs closer than `r_i + r_j + 0.04`, push apart equally, iterate in slot-index order.
6. Cap net displacement at 0.22; if still infeasible, shrink scale ≤15% and flag the hex `crowded` for the editor.

**Slots are never reordered — only translated.** That is what "keeps the arrangement" means.

**Editor override, compact:** sparse map `hexId → LayoutOverride{ u8 layoutVersion, u8 slotSetId(0=auto), u8 count, per feature: u8 slotIndex, i8 dx, i8 dy (1/128 hex units), u8 scale(128=1.0), u8 rot }` ≈ 5 B/feature, ~34 B/hex, stored only for touched hexes. Deltas are *relative to the auto slot*, so algorithm tweaks still propagate. On `layoutVersion` mismatch, re-bake unless the override is pinned. Bake once at load into a SoA of world positions + hit circles; **play never writes layout**. Selection is a single `selectedFeatureId` (id = index+generation) shared by map ring and sidebar row — both highlight from the same source, no duplicate state.

## 3. Remote owner actions vs commander-only

Rule: **money flows remotely, matter flows physically.**

*Remote (owner, no commander):* buy squads/items into a feature's production queue; set rally point; set garrison stance/auto-defend; queue upgrades; change production recipe; set convoy route endpoints.

*Commander-only:* pick up produced squads/items; claim neutral or guarded features; capture/siege enemy features; excavate artifacts; transfer troops between armies; recruit heroes; anything contested.

**Consequences.** Commanders stop being couriers and become agents of *contest, escort and tempo*. Their value drops in the safe rear and rises on the frontier — which is the intended shape. The economy no longer stalls because one hero is walking home.

**Exploit risks and mitigations:**
- *Instant defence*: buying must never materialize units. Purchases enter a timed queue; only **delivered** garrison squads auto-defend.
- *Rally teleport*: rally is a destination hint for convoys, never a spawn point.
- *Arbitrage*: one faction price table, or price = f(local stock) with per-turn budget cap and cooldown.
- *Simultaneous-turn double spend*: one owner action per feature per turn, resolved in a fixed phase with per-feature locks; orders carry timestamps.
- *Remote actions under raid*: disable them when an enemy commander is adjacent or the hex is interdicted. This makes raiding supply lines strategically real and gives caravans a job.
- Remote actions require **ownership**, not visibility — fog must not gate your own economy.

## 4. Data-only entity/component model

Entity = `u32` id (index + generation). Components live in dense packed arrays (SoA) with `entityId ↔ row` maps, grouped by archetype. Systems query by component presence, never by "kind".

```json
"caravan_light": { "components": {
  "Position": {}, "Owner": {},
  "Movement": { "speed": 1536, "terrain": "road_favoring" },
  "Vision":   { "radius": 3, "modifiers": [] },
  "Payload":  { "capacity": 12, "contents": [] },
  "Route":    { "mode": "supply_line" },
  "Stock":    { "capacity": 400 }
}}
```

A scout item in `Payload` appends `{source:"scout", add:1}` to `Vision.modifiers`; vision is recomputed each turn as `base + Σ modifiers`, sorted by source id. **Capability = component presence**, so a modded "armed caravan" just adds `Combat` and existing systems pick it up. Features use the same model: `Position + Owner + Produces + Stock + RemoteActions + Vision + LayoutSlot`. Guards: `Position + Guard{armyRef}`.

**Determinism:** fixed-point `i32` at 1/1024 hex for positions/speeds; no floats in sim; stable sorts everywhere; content hash shared by all clients.

**Pitfalls:**
- *Save versioning*: serialize by stable component name + per-component schema version with explicit up-migrations. Never save derived data (baked layout, computed vision, path caches) — rebuild on load.
- *Component explosion*: ban `CaravanScoutVisionBonus`. Use modifier lists inside ~25–35 component types. Add a component only when a system needs to *query* by it.
- *Archetype churn*: toggling vision by add/remove reshuffles arrays every turn. Use `enabled`/zero values; restrict structural changes to turn boundaries.
- *Mod loading*: unknown component = hard error naming the def, not a silent skip.
- *Stale ids*: generation counters, so UI selection of a destroyed caravan fails cleanly.

## 5. Movement / vision tuning

**Core inequality:** `R_vision ≥ v_enemy_max · T_turn + margin`, or defenders get ambushed from fog every single turn. Aim for ~1 turn of warning for static assets, ~1 turn of surprise for scouts, ~2 turns for caravans (they see far but cannot react — that's what escorts are for).

Because hexes got bigger, **scale speeds down proportionally**: if a hex is 2× wider, halve hexes/turn so travel time in minutes is unchanged. Target 3–5 hexes/turn for a decisive move.

Suggested defaults (all JSON-configurable):

| Entity | Speed (hex/turn) | Vision (hexes) |
|---|---|---|
| Commander | 3 road / 2 off-road | 3 (4 with scouting) |
| Cavalry commander | 4 road / 2 off-road | 3 |
| Caravan | 1.5 road / 1 off-road | 3, +1 per scout, cap 5 |
| Siege caravan | 0.75 | 2 |
| Owned hex | — | self only (r=0) |
| Mine | — | 1 |
| Barracks | — | 2 |
| Village | — | 3 |
| Watchtower | — | 4 |

Vision/speed ratios: static features ≈1.2–1.5, commanders ≈1.0, caravans ≈2.0. Cavalry at 4 outruns village vision 3 — fix this with a cheap **border-watch tripwire** (owned hexes adjacent to a visible hex report entry events) rather than inflating every radius. That preserves scouting as a skill and keeps the map dark.

**Fog memory:** explored-but-unseen shows terrain and *last-known* static features with a stale badge; never live armies.

**Simultaneous turns:** snapshot vision at turn start, resolve movement, recompute vision, publish only the post-resolution state. Mid-resolution reveals must not leak, or order timing becomes an information exploit.
