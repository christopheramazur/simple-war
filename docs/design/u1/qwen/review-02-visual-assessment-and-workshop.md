# 1. Fidelity to the brief

- Scope is honest (U1Q2/U1Q3 only), but the draft **over-reaches into governance**: §1.4 recommends closing sw-68h, §3.4 rewrites DESIGN.md §7/§8, §3.5 edits canonical AGENTS.md, V9 writes `config/routing.toml`, V13 auto-files beads and schedules weekly GPU sweeps. None of that is in the brief; it's harness policy the owner didn't ask to change.
- Owner asked for a workshop for "working through individual components… visually and through api". §3.7 delivers a **read-only replay viewer** ("a tweak makes a new run", reload-only). No authoring, no parameter sweep, no side-by-side variant playback in the scene — the "workshop" is a scenario runner plus a viewer. Defensible for determinism, but say so and ask.
- Owner called the visual framework **a priority**; §5 puts capture (V8) and judging (V10) at P2 behind workshop P1s, and V8's strip sizing waits on V1. Inverted.
- §3.1 says captures must use the game's own view, but V1's go/no-go is measured on **mocks with hand-written truth**. The verdict won't transfer to real battle frames.
- Brief's DPS opacity (paragraph 1) is only touched by V4, and V4 never asks whether order-dependent DPS is *intended*. Measuring a number isn't answering the owner.

# 2. Design risks

- **Clarity score (§3.1) is broken.** Control renders draw lines of fire, victims and large labels — they contain the answers. Control accuracy ≈ 1 by construction, so game÷control ≈ game accuracy; the ratio adds nothing and the 0.9 judge-limited cutoff is arbitrary.
- **The rubric asks exactly what §2 says VLMs fail at**: `vis_fire_pairs`, `vis_range`, `vis_count` are line-crossing/counting tasks. Citing "VLMs are blind" and then building the suite on geometry is self-contradictory.
- **Fog leak in V2.** "Fog-safe" only covers `squad_seen` and enemy holds. The all-pairs `fire` matrix, shots/hits, victims, pool bands and casualties all expose unseen enemy state. Acceptance "leaks no orders" is far too narrow.
- **Capture determinism is asserted, not designed.** V8 claims identical PNGs, but `BattleFx` (projectiles, recoil, floating numbers) is almost certainly delta/time-driven; setting playback `t` won't reproduce FX state. `SETTLE_FRAMES` is a wall-clock heuristic. Nothing makes FX a function of tick.
- **Fixed-point ignored.** V3's `at [x,y] in metres`, `patch` values and `compare.factor` are JSON floats with no quantization rule. That's a determinism hole in a fixed-point sim.
- **Pending-scenario spec laundering (OQ4/V4).** Agents write the acceptance criteria for their own later behaviour work, and "unexpected pass" only prints. Nothing forces promotion or owner sign-off; pending files rot.
- **Cost.** V3 records a full probe snapshot *plus* frame every tick; V2's LoF matrix is O(units²) per tick. Gate suite and sweeps will crawl. V7's SquadCard re-simulates per click; backward stepping re-simulates from 0.
- V13 auto-filing from model answers contradicts §3.1's "evidence, never a verdict" — filing *is* an action, and it will be noisy given the blindness problem.

# 3. Missing cases

- Deployment phase (owner explicitly wants one) has no representation in the scenario schema; planning vs execution orders unmodelled.
- Variant override merge semantics (`script` vs `patch`) undefined; deep vs replace matters.
- `--all` exit-code semantics with pending failures; CI behaviour.
- Zero squads / all dead / no contact / turn limit; stage ties ("most squads ENGAGED" — which tick on a tie?).
- Manifest lacks **rules-package hash and engine/build version**; truth and goldens aren't comparable across builds.
- V11 needs pixel sampling under antialiased labels and reuses GDScript `cvd_sim` luminance from Python — cross-language duplication unaddressed.
- V12 introduces an SSIM dependency (budget/dep rules) and, with local-only goldens (OQ5), never runs in CI — it's not a regression gate at all.
- V1 measures projector-on-GPU at 128k with 7.6 GB free: OOM/driver reset risk, and it runs Godot capture beside the model despite its own one-GPU rule.
- V5 acceptance (≤1 line/scenario) contradicts §3.3's "one line per probe".

# 4. Bead review

**Swarm beads:**
- **V5** — ~2h and right runner *if* V3's CLI JSON is frozen first. Sharpen: pin the exact `workshop_cli --json` schema in the bead, test against a fixture only, no Godot dependency.
- **V12 — too vague/cross-cutting.** Metric choice (SSIM vs banded delta), new dependency, tolerance calibration, diff PNGs, `--accept` flow, golden layout. Split: **V12a** exact per-pixel diff + over-tolerance listing with numeric thresholds and synthetic fixtures (swarm, 90 min); **V12b** perceptual metric + calibration (autopilot).
- **V14 — too cross-cutting.** Five files, canonical AGENTS.md, decision-log numbering, gated on *ten* owner answers including a GPU spike. Split per file: GDD 05 §5.6/§5.7 (autopilot), harness README rows (swarm, mechanical), DESIGN.md (autopilot-large, after V1), AGENTS.md (owner approval, separate). Land workshop docs now; don't block on vision.

**Others:**
- **V2** (autopilot/Haiku): four-system aggregation + fog contract + tests is too much for Haiku. Make it autopilot-large, or split core snapshot / fog filter.
- **V3**: schema + loader + runner + CLI + gate test + helper refactor + 2 scenarios = 3–4 days. Split V3a schema/validation, V3b WorkshopRun+tick_hook, V3c CLI+gate, V3d shared builder.
- **V4**: authoring six files is swarm-able once V3a lands; the DPS analysis is autopilot-large. Also fix the measurement (see §5).
- **V6**: split frame data (autopilot) from overlay drawing (autopilot-large). "Test that greps for writes" is a lint, not acceptance.
- **V7**: transport + pickers + probe panel + SquadCard + GUIDE + tests > 1 day. Split shell/transport from panels.
- **V8**: four sources + stage finding + strip compositing + CVD + truth + manifest + label rects — the biggest bead here, 3+ days. Split per source; label/footprint rect export is a `ContextView` change and its own bead (V11 depends on it).
- **V9**: adapter content-parts change touches the shared bench adapter used by the frozen text suite — needs its own small bead with a text-suite regression test. Also duplicates V1's manual questioning.
- **V10**: gateway + grading + DuckDB + queue + rubric is autopilot-large, not Haiku; split ask/report from storage/queue.
- **Dependencies:** V6 only needs the frame format, not all of V8/V3; V8's game-kind capture needs neither V6 nor V1 — decouple so V1 can spike on real frames.
- **Untestable acceptance:** V8 "same PNGs on one machine" (not CI), V11 "clean or findings listed" (unfalsifiable), V12 tolerances (no numbers), V1 "go/no-go" (no threshold; specify ≥0.9 on n≥10 per class).

# 5. Open questions

Should have asked:
- What *specific* readability failures the owner sees, and whether human review is the authority over any model score.
- Must the workshop support live tweaking/authoring, or is read-only replay acceptable?
- Is order-dependent DPS a bug to remove or a rule to specify? V4 assumes "measure", not "decide".
- Image-judging spend/quota ceiling, and whether screenshots may leave the machine at all (broader than OQ2).
- How deployment interacts with scenarios.

Could have decided itself: **OQ3, OQ5, OQ6, OQ7, OQ8, OQ9, OQ10** — all have obvious defaults consistent with existing convention. **OQ1** isn't a question, it's the spike's output. Only OQ2 and OQ4 genuinely need the owner. Ten questions gating V14 is self-inflicted blocking.

# 6. Top 5 changes

1. **Rewrite V2's fog contract** and add leak tests covering LoF, shots, victims, pools; make the probe windowed/strided, not all-pairs every tick.
2. **Split V3, V8, V10 into ≤1-day beads and freeze the JSON contracts first**, so V5, scenario authoring and doc rows can run as swarm work in parallel; re-run V1 on real game captures.
3. **Replace the clarity ratio** with absolute per-class accuracy plus human spot-checks; drop or redesign the geometry questions; give V1 numeric go/no-go thresholds.
4. **Fix V4's measurement**: normalize for approach time, isolate retarget cost within a turn, use killable targets for overkill, and specify fixed-point quantization for all JSON positions/patches.
5. **Land model-free workshop docs immediately** (split V14, self-decide the seven OQs); demote V13 auto-filing and V12 goldens until FX are tick-driven and manifests carry rules/engine hashes.
