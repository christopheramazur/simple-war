# A) Live relationship readout during execution

**Fog rule (non‑negotiable).** Every relation is derived only from *player‑observable* state: your own orders, observed enemy position/facing, observed muzzle flashes/tracers, effects applied to your squads, and your team's spot graph. Never render enemy planned orders, pre‑fire target locks, waypoints, or morale values. Enemy "intent" appears only after it manifests (first tracer, observed movement over ≥0.6 s). Frozen Synapse shows *your* ghost plan only — copy that asymmetry.

**Vocabulary (directional, closed enum — reuse it in UI, API, and tests).**

- Contact: `SPOTTED_DIRECT`, `SPOTTED_BY_ALLY`, `LAST_KNOWN` (ghost + age), `NO_CONTACT`
- Fire feasibility (you→them): `IN_RANGE`, `OUT_OF_RANGE (Δ 34 m)`, `LOF_CLEAR`, `LOF_BLOCKED (wall/smoke/friendly)`, `COVER_HALF/FULL` (directional, XCOM‑style)
- Active: `TARGETING`, `UNDER_FIRE_FROM`, `SUPPRESSING`, `SUPPRESSED_BY`
- Trend (observed velocity, 1.5 s window): `CLOSING`, `FLEEING`, `HOLDING`, `LATERAL`
- Meta: `TARGET_OF_OPPORTUNITY` (your squad's current auto‑target), `NO_SOLUTION`

**Priority when several apply.** One primary label + max two chips, ordered by *decision urgency*:

1. Contact gate — `LAST_KNOWN`/`NO_CONTACT` suppresses everything else (grey ghost card, "last seen 4 s ago").
2. Inbound threat — `UNDER_FIRE_FROM` > `SUPPRESSED_BY`.
3. Your outbound action — `TARGETING` > `SUPPRESSING`.
4. Feasibility blocker — `LOF_BLOCKED` > `OUT_OF_RANGE` > `IN_RANGE` (blocker beats distance because it's actionable by moving *sideways*, not forward).
5. Trend — `CLOSING`/`FLEEING`.
6. Provenance — `SPOTTED_BY_ALLY` (always a chip, never primary).

Multi‑select aggregates: "3/5 can fire · 2 blocked (wall) · 1 out of range".

**Hover vs. context menu.**
*Hover* (120 ms delay, transient, no click): target‑anchored card, primary + 2 chips, one connector line, distance number. Cheap, spammable, disappears on exit. Dwell >400 ms adds the range ring and LoF ray.
*Right‑click* (pinned): full **Relationship panel** — both directions side by side, numeric range/cover %, blocker identity, 5 s event sparkline (first contact → first shot → pinned), and orders (focus fire, hold fire, fall back, mark). Right‑click on empty ground = order menu, not relations (Door Kickers / Frozen Synapse convention). `Tab` cycles pinned panels; `Esc` unpins.

**Visual language, with sources.**

- **Connector lines** — XCOM targeting line + badge; taper own→enemy lines, animate flow direction. White solid = firing solution; amber dashed = LoF blocked with an ✕ at the blocker; grey dotted = out of range, extended to the range boundary tick.
- **Inbound threat** — Company of Heroes tracer/pin language: red chevrons animating *toward* your squad, drawn only from observed fire. Suppression = CoH "pinned" icon over your squad, plus a desaturation pulse.
- **Rings/arcs** — CoH weapon arcs / Total War range bands: filled inner band = effective range, dashed outer = max. Enemy rings only for *known* weapon class; otherwise dashed + "est." label.
- **Cones** — Door Kickers vision cone for the selected squad; clip it against walls so the player sees the actual shadow.
- **Badges** — Into the Breach intent tiles, but only for *manifested* enemy actions; eye‑with‑link for ally‑spot; white flag arrow for observed rout.
- **Budget** — max 3 simultaneous connectors; everything else behind "show all threats" (`H`). Encode with shape + dash, not hue alone. Playback scrubber carries event ticks (contact, first shot, pin, rout) à la Frozen Synapse's turn timeline.

# B) Hidden simultaneous deployment

**What the references do.** Total War: bounded deployment zone, drag cards, formation + facing, terrain read, auto‑deploy button, enemy hidden until scouts. CoH: no free placement — entry points/sectors, which removes the coin‑flip but also the expression. Frozen Synapse: deployment *is* turn 0 of the same simultaneous plan/commit loop. Battle Brothers: tile slots on your half, roster‑limited, reserve rows.

**Placeable:** squad position (snap to 1 m grid, free rotation), facing, formation (line/column/wedge/loose), stance (advance/hold/defend), hold‑fire toggle, off‑map reserve. **Not** placeable: individual troopers, loadouts — the squad stays atomic.

**Defaults / auto‑deploy.** Deterministic role‑aware solver: support/heavy on high ground with long LoF lanes, recon forward in cover, line infantry center, ≥12 m spacing to defeat AoE clumping. It produces a *reviewable* layout, never auto‑commits. Provide per‑squad lock pins, "reset unlocked to auto", and a diff highlight of manual edits. Auto‑deploy must be a decent floor, not the optimum — otherwise manual play is dead.

**Time limits.** Soft 75 s, commit‑early ready flag, resolve immediately when both ready; hard cap commits the *current* layout (never random). Show "enemy ready" without any positional hint.

**Pitfalls & fixes.**
- Battle decided before turn 1 → make the no‑man's‑land buffer ≥ max weapon range so turn 1 can't be a point‑blank ambush.
- Double blindness (hidden deploy + fog) → give a deployment‑time LoF/coverage preview from the candidate position (Door Kickers), and a "known enemy doctrine" card, not positions.
- Asymmetric terrain advantage → mirrored zones with equal cover budget, or rotate sides across a series.
- Leaks via heatmaps/terrain hints/"enemy likely here" overlays — audit them.
- Drag precision and snap‑fighting on top‑down 2D → magnetic snap with visible ghost, arrow‑key nudge, undo stack (`Ctrl+Z`), and the *same* planning UI as turn 0.

# C) Automatic readability regression

**Capture harness.** Deterministic replays (seed + order log) → fixed stages: `deploy`, `first_contact`, `first_shot`, `t=5s`, `first_suppression`, `first_rout`, `t=15s`, plus event‑triggered captures. Each stage × 3 camera presets (default player cam, 0.5×, 2×) × 2 resolutions (1080p, 720p) × HUD‑on/off. Lossless PNG. Frame strips: 5 frames at 250 ms around an event, tiled with visible time labels.

**Ground truth.** Sim dumps per‑capture JSON: squad IDs, screen‑space bbox, `visible_to_player`, firing pairs, in‑range booleans, LoF blocker, suppression, observed movement label. **Only ask about player‑visible truth** — otherwise you score the model down for correctly refusing to leak fog.

**Annotations (this is what makes a 27B usable).**
- Overlay letter IDs (A, B, C…) at ≥24 px with a 2 px dark halo and leader lines, collision‑avoided.
- Chess‑style grid overlay (A1–H8) so spatial answers are *categorical*, not pixel regression.
- Legend strip baked into the image (faction colors, icon meanings).
- Ship **two variants**: `raw` (measures real readability) and `annotated` (measures reasoning ceiling). The gap is your **legibility deficit** — the number you actually optimize.

**Prompt design.** One question per call, temperature 0, JSON schema out, forced choice over enumerated IDs, ≤6 options, and **always include `CANNOT_TELL`**. Targeting = pick from an enumerated pair list, not free text. Never "how many" (VLMs count badly) — ask "which ID is suppressed, or none". Never fine metric distance — discretize to grid cells or ring bands. Tile 2×2 with 15% overlap for small text; ask per tile, merge by ID. Keep prompts versioned in the repo.

**Rubric categories** (macro‑averaged, each 0–1): targeting pair exact‑match; range status 3‑way; action label 5‑way closed set; threat direction; occlusion/blocker identity. Plus two meta‑metrics: **abstention calibration** (abstains when truth is ambiguous) and **hallucination rate** (confident wrong on deliberately unanswerable items). Normalize against a **null renderer** (plain circles, no VFX) as floor and an **ideal diagram** as ceiling.

**Regression signal.** ~40 scenarios × 7 stages × 3 cameras, nightly, 3‑sample majority vote. Alert on total drop >3 pts or any category drop >5 pts; attach per‑scene image diffs.

**VLM pitfalls to engineer around.** Small text and thin 1 px lines vanish at downscale; counting is unreliable; left/right and relative‑distance judgments are weak; quantization and batching introduce non‑determinism; models drift with runtime version — pin weights, quant, and runtime hash. Prompt overfitting is real: hold out 20% of scenarios. Score gaming is real: adding giant labels raises the annotated score — guard with the HUD‑off/raw variant and periodic human panels (5 raters × 30 scenes) to re‑anchor correlation with actual comprehension.

**Behaviour workshop sandbox.** One scenario schema (YAML) consumed by the game renderer, the headless sim, and the rubric generator: units, terrain, seed, orders, start states, camera, duration. Canonical isolates: 1v1 at range boundary ±10%; LoF clipped by a wall corner; smoke occlusion; 1v2 suppression; morale rout; ally‑only spot relay; two squads crossing; overwatch trigger.

Each scenario carries three assertion sets: **sim** (state invariants), **render** (VLM rubric), **API** (`GET /relations?from=A&to=B` returns the same enum the tooltip shows). Sharing one enum across UI, API, and rubric is what prevents vocabulary drift.

Controls: scrub, single‑frame step, freeze, layer toggles (rings / LoF / tracers / labels / cones), camera presets, A/B split of two renderer builds on the same seed, and "export capture bundle" that CI can replay byte‑identically.
