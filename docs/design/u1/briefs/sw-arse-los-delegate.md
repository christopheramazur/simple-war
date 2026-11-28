# Brief: line-of-sight at scale for firing positions (sw-arse)

Written 2026-11-28 for an Opus 5.5 (high effort) delegate, at the owner's request. The owner's words:
"walks won't work if we go bigger or have multiple large battles going. Raycasting techniques and better caching
may be initial investigation directions but don't let me limit solution-finding."

## 1. Your job

1. Find a line-of-sight (LoS) approach for the battle sim that scales well past today's 40 squads, and to several
   large battles running at once, then **implement it**. Either finish it inside sw-arse, or land it as a follow-up
   bead that closes sw-arse (your call; say which and why).
2. When it has landed, write a **human-readable report** on how the game does unit firing positions, line of sight,
   pathfinding and attacking (§6).

You have standing autonomy (AGENTS.md §6): decide, record the decision in the bead notes, keep going. Stop and ask
only for what §6 lists (billing, guardrails, a blocking design decision the GDD doesn't settle).

## 2. Start here

- `AGENTS.md` (repo root): environment (Windows 11, Git Bash, Godot 4.7.2 via `harness/bin/hx godot ...`), rules,
  build and test commands (§7). Do this first: `bd update sw-arse --claim`.
- `bd show sw-arse`: the bead and the autopilot's findings (read them closely; summary in §3).
- `GD-Agentic-Skills/godot-skill-distillation.md` §1, §9, §10, §14 (architecture, performance, the NEVER list).
  §12 names the skill module for performance; load only that one.
- GDD `Game Design Document/02 Rules Spec.md`: §2.6 (range, vision, line of fire, attack orders), §2.14 (battle
  space, routing, separation, coherency and their budgets), §2.15 (orders, firing positions, "Built (sw-txnj.5)").
  `04 Systems Architecture.md` for determinism and the state hash.
- Code: `src/sim/battle/battle_rules.gd` (`los()` ~l.371, `_walk_los()` ~l.393, `clear_los_memo()` ~l.367, and
  `point_shot`), `src/sim/battle/firing_positions.gd` (ring search, `SEARCH_CAP`), and every other caller of
  `los` / `point_shot` (grep: the fire pass, LineOfFire marks, `src/api/workshop/workshop_run.gd`, relations).
- Measurement scripts: `docs/design/u1/scripts/fp/` (`fp_cost.gd` cost per tick, `fp_dps.gd` shots and DPS at
  12/24/40 squads, `los_cost.gd` cost per walk, `trace_*.gd`). Run with `harness/bin/hx godot run <script>`.
- Prior decisions: `docs/design/u1/00-synthesis.md`, `docs/design/u1/answers.md` (U1Q28, U1Q29).

## 3. What's known (from sw-0jm5 and the sw-arse Haiku run, 40 squads, Crossroads, 300 ticks)

- `FiringPositions.update` costs about 0.61 ms per tick. Ring searches are about 1.8 per tick with about 15
  candidates each; that's about 20k `point_shot` and 50k `los` calls over 300 ticks, 55% memo hits, about 22k
  real walks at about 1.4 µs each. So today walks are only about 0.10 ms per tick (about 17% of the firing-position
  cost).
- A per-cell blocker mask was tried: exact, but the walk got only about 1% faster, so it was reverted.
- The remaining ~0.5 ms per tick is GDScript overhead per candidate and per unit (`slot_point` allocations,
  `units_of` dictionary lookups, `pick_mode` and `_min_range` per candidate, trig).
- `SEARCH_CAP=1` saves 0.18 ms per tick but costs 7% of shots at 40 squads.

**Don't stop at "walks are only 17% today."** The owner's point is growth: candidates times targets grows with
squads, and several battles multiply it. So measure how cost grows (per tick, and per battle-second) as you go
from 40 to 80 to 160 squads, and with 2 to 4 battles stepped in one process. Then show your approach bends that
curve. Both the LoS share and the per-candidate overhead are in scope, if fixing one exposes the other.

## 4. Directions (starting points, not limits)

Treat these as prompts. Measure, and find what actually works for this sim.

- **Invert the query.** Many candidates test LoS to the same few enemy units. Compute a visibility field *from the
  target* once (shadowcasting / FOV over the cell grid, limited to weapon range), then each candidate is one array
  lookup. Share it across squads engaging the same enemy, and keep it while the target stays in its cell.
- **Precomputation on static terrain.** If blockers never change during a battle (check: what calls
  `clear_los_memo`, and can terrain or smoke change?), precompute per map: coarse cell-to-cell visibility,
  per-region visibility sets, horizon or sector tables, or a hierarchical blocker grid (mip pyramid or quadtree) so
  rays skip open ground in big steps.
- **Faster rays:** grid DDA (Amanatides–Woo) on packed bitsets, early exit on known-open or known-blocked
  rectangles, and batching many rays per call over PackedArrays.
- **Better caching:** keys that actually hit (memo hit rate is about 55% now; candidates land on distinct cells),
  cell-pair or cell-to-region caches, results carried across ticks while both ends stay in their cells, and
  invalidation tied to real terrain changes.
- **Do less:** amortise searches over ticks, search fewer candidates when coarse visibility says they're hopeless,
  and reuse a squad-mate's result.
- **Native code** (GDExtension) or other engine-level options, if the numbers justify the build pipeline it needs.
  A GDExtension build is a large addition: record the reasoning, and make sure exported and test builds still work.
- Anything else you find better.

## 5. Constraints (non-negotiable)

- **Determinism** (AGENTS.md §5.5): same inputs and seed give the same result. Fixed-point / integer math in the
  sim, no floats where results feed the state. Any cache must be derived state: not hashed, not saved, and rebuilt
  identically after a load or a forecast copy (see how `clear_los_memo` handles forecasts).
- **Exact first.** An approach that gives bit-identical LoS answers (same state hash on every existing battle test
  and on `fp_dps` 12/24/40) can merge on its own. Prove it: compare against `_walk_los` over large random and
  scenario cell pairs, in a GUT test.
- **Behaviour changes** (different shots, positions, or a search budget like option (a)) need the owner's sign-off.
  Put them behind a data flag that defaults to today's behaviour. Report `fp_dps` 12/24/40 numbers (shots, DPS,
  survivors) for both settings, file a bead labelled `needs-human` for the sign-off, and don't flip the default.
- Layering: logic in `src/sim`, data in `data/` packages, presentation never mutates. `RefCounted` for logic. Every
  scene runs standalone (F6).
- Keep the memory per battle bounded and state it (cell count times bytes), since several battles run at once.
- Don't break the other LoS users: the fire pass, LineOfFire marks, relations, the workshop and the capture runner.

## 6. The report

When the work has landed, write `docs/design/u1/firing-positions-los.md` for a human reader (the owner):

- How a unit gets from an order to a shot: attack orders, the anchor and coherency, firing-position search, line
  of sight, routing (pathfinding) and separation, the volley phase and the fire pass. Explain it in prose first,
  then the details.
- Point to the code for each step (`path:line`) and to the tests that cover it (file and test name).
- Diagrams in Mermaid: at least a flow from order to shot per tick, the firing-position ring search, and the LoS
  structure you built (what's precomputed, cached, invalidated, and when).
- The costs: measured numbers before and after, the scaling curve (squads, battles), the budget, and what
  dominates now.
- Known limits, open questions, and the follow-up beads you filed.
- Update GDD §2.14 and §2.15 "Built" / "Measured" lines where your work changes them. Proposed terms go in the
  glossary's proposed table (`07 Glossary.md`).

## 7. Process

- Work on a branch in your worktree. Commit often, with messages that start with the bead id.
- Gate: `harness/bin/hx godot check` (with import after adding a `class_name`), then `harness/bin/hx godot test`
  (the full GUT suite, about 10 minutes; a subset while iterating, e.g. `--dir tests/sim`). If you touch `harness/`,
  run `uv run --project harness pytest -q` too.
- **Land through the merge gate** that autopilot uses, which keeps main green while autopilot merges too. From the
  main checkout (`C:/Users/chris/Documents/simple-war`):
  `uv run --project harness python -c "from pathlib import Path; from hx import swarm; print(swarm.merge_branch('<your branch>', Path(r'<your worktree path>'), 1800))"`
  It merges main into your branch, runs the tests there, then fast-forwards and pushes main. If main moved or a
  conflict comes up, resolve it on your branch and run it again. Never force-push or rewrite history.
- Then close or update the beads (`bd close sw-arse --reason=...`, or close it from the follow-up), with
  `--append-notes` only (never `--notes`, which replaces the notes).
- Pitfalls: the Bash tool truncates commands over about 7K chars (write scripts to files); Python on Windows writes
  CRLF unless `newline=""`; the repo is eol=lf; run `hx godot check` with import after adding a `class_name`.
- Timing tests are noisy under load (autopilot may be running a Godot suite at the same time). Measure with
  repeated runs and report medians.

## 8. What to send back when you finish

A short summary: the approach chosen and why (with the alternatives you measured and their numbers), what merged
(commits), the before-and-after scaling numbers, the beads closed and filed, anything that needs the owner, and the
path to the report.
