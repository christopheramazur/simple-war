## 1. Fidelity to the brief

- Scope is legitimate (Battles ¶3–4), but the draft ignores that ¶2 calls a **visual assessment framework a priority**. E1/E2/E6/D3 acceptance is "a mock PNG (`hx godot mock`)" — a file, not an assessment. Either hook these into the bonsai/workshop loop or state the dependency; as written the beads produce artefacts nobody reads.
- **U1Q3c over-narrowed.** Owner says "hover-tooltip **or** right-click comparison". Q4/E7 demote right-click comparison to playback-only and invent key `C` for Planning. That's a silent drop of the owner's stated interaction. Decide it, don't bury it in a non-blocking question.
- **Over-reach from one sentence** ("A start of battle deployment step is still desired"): hidden/simultaneous placement, `deployment_bonus` with ranked variants (D5), `locked` placed squads, scenario `open|fixed`, vanguard/ambush hooks, and an AI deployment heuristic (D7). None are owner words. D7 and D5-ranked are pure invention.
- **U1Q3d mis-served.** The owner's underlying complaint (¶1) is "why is my damage low". §3.2's fact list leads with targeting/under-fire and caps at 3 lines (E6), so `MIN_RANGE`/`NO_LOS`/`RELOADING` — the actual answer — can be truncated away.
- E2's "selection carries into the next Planning" is proposed, not requested; harmless but unlabelled as a feel change.

## 2. Design risks

- **§3.2 Fleeing contradicts §3.2 Fog.** Fall-back threat is derived from an *order* plus the fall-back runner's own visible-enemy set (`battle_orders.gd:96-100`). Showing "fleeing from X" about an enemy exposes exactly the order-derived state the fog paragraph forbids. Either drop enemy fleeing, or define it behaviourally (velocity away + recent fire) and say so.
- **E5 shadow re-sim is an unbounded cost and a determinism hazard.** Backward seek restarts from snapshot → O(N²) scrubbing; hover-driven re-sim on a 200×100 fixture with many concurrent battles is a frame-time bomb. Snapshot must capture RNG, gear overrides and content-package version or the probe silently diverges from what was shown. Old replays have no snapshot (no version gate mentioned). Option (a) widen frames is cheaper, replay-safe, and was dismissed without a cost comparison.
- **`would_engage` reads as a promise.** Nearest-visible-in-reach changes next tick; players will treat it as committed intent. Needs "likely" framing distinct from `engaged`.
- **Right-click in Planning** (E7) currently *is* the attack order. Putting a menu on it adds a click to every attack. Don't do this; keep right-click = order, comparison on hover + a bound key, and say so as a decision.
- **Deployment stacking exploit.** §3.3 "squads may share ground" + hidden placement = stack the whole force on one enterable cell at the area edge for maximal focus fire. Also snap-then-validate ordering is unspecified: `open_point` can snap an anchor *outside* the deploy rect (D1 validate vs `BattleSetup.open_point`).
- **Blind turn 1.** Hidden deployment + shared Planning (Q1) means no attack orders, only attack-move — the exact command whose DPS the owner already can't read. Turn 1 becomes an unreadable slugfest.
- **D1 acceptance is self-contradictory**: `deploying` is "saved, hashed" *and* "with no placement input, golden hashes equal main". Adding a hashed field changes every hash. Pick one.
- **D3 vs D1**: D3 clamps an out-of-area drop to the edge; D1 refuses it. Two behaviours, one rule.

## 3. Missing cases

- Squads that die mid-turn: hover/selection/relations at frame *i* where a or b is dead; selection of a dead squad carried into Planning (E2).
- Allies and neutral guards: D1 hides "non-own, non-allied" — do allies share deployment sight? Do relations exist for friendly pairs?
- Multiple battles deploying in one Planning: draft switching, per-battle bonus stacking (D5), abandonment, battle cancelled before Reveal → orphan `battle_deploy` inputs in saves/replays.
- Ranked "skip to results" (R3Q2) and timeout with zero placements; disconnect mid-deployment.
- E4 forecast cache must invalidate on **deployment** draft changes, not just orders.
- Multiple late joiners in one Reveal: `_join` picks farthest-from-fighting-squads; computing at Planning start (D4) can differ from Reveal if another join/reinforcement lands first.
- sw-ll4.26.6 pacing: frames may be held/interpolated; probe indexing "by frame" needs a defined frame→tick map.
- Fixed-point → metres conversion and localisation for the range gap; tooltip for a squad vs itself.

## 4. Bead review

**Too vague / cross-cutting for a Qwen4 worker (<2h, alone, one worktree):**

- **E1 (swarm)** — three files, a blocker-architecture decision ("panel regions only" vs `MOUSE_FILTER_IGNORE`), hover plumbing, card refresh, plus a dependency on an *expired-lease* bead. Split: **E1a** blocker hit-region only (wheel + middle-drag reach `ContextView`, panels still blocked, GUT); **E1b** `squad_hovered` during playback + card refresh keyed on (id, frame). Pre-decide the blocker approach in the bead text; don't make the worker choose.
- **E2 (swarm)** — selection semantics + ring drawing + cross-phase persistence + box-select. Box-select conflicts with drag-pan and is unspecified. Split **E2a** click/shift/ctrl + `next_squad` selection and persistence; **E2b** rings in `show_playback`. Drop box-select.
- **E6 (swarm)** — five deps, two data sources, glossary JSON, translation keys, glyph design, clamping, three mocks. Split **E6a** pure `RelationText.lines(facts)` + keys + GUT against a fixture (no deps beyond E3's schema — unblocks parallelism); **E6b** wire to hover via .6's lookup; **E6c** glossary terms/glyphs.
- **E7 (swarm)** — new UiWindow + input bindings + controls help + planner order actions + focus walk + pad. Not a swarm bead. Split **E7a** read-only playback menu (right-click, Esc, focus); **E7b** Planning binding + order actions → autopilot, after the right-click decision.
- **D5, D6 (swarm)** are correctly sized; D6 should not own the scenario `deployment` field (D1 already adds it) — duplicate ownership, guaranteed conflict.

**Others:** E0 deps should be *all* answered questions, not just Q1, since §3 embeds Q2–Q11. E3 is >1 day: split the pure `pick_target`/`nearest_visible_enemy` extraction (hash-gated) from the facts module. E4's dep sw-abk is labelled autopilot-failed — verify before relying on it. E5's "worst case recorded in notes" is not an acceptance criterion; give a ms budget and a fallback. D1 is 2–3 days: split sim module/flag/apply from Reveal ordering + fog suppression across observe/inspect/forecast. **D3 on Haiku is wrong** — drag placement, facing handle, group drag, pad nudge, banner is autopilot-large or three specified swarm beads. D4 mixes two features; split. D7 acceptance ("recorded in notes") is untestable; cut or give a threshold. E1/E2/E6/E7/D3 all edit `war_room.gd`/`context_view.gd` — assign file ownership or expect worktree merge pain.

## 5. Open questions

**Should have asked:** Is deployment hidden at all (assumed, never asked)? Does it apply to AI-only/overworld auto-battles and quick battle? Is widening the playback frame format (save/replay version bump) acceptable vs re-sim, and what's the perf budget? Does free-camera + relation info create a ranked fairness problem? What does "select squads" mean for *enemy* squads?

**Could have decided:** Q3, Q4, Q6, Q8, Q9, Q10, Q11 — seven of eleven are self-answerable with a provisional number and a decision-log line. Only Q1, Q2, Q5, Q7 need the owner. Trim to those.

## 6. Top 5 changes

1. **Kill the D1 hash contradiction and settle E5's approach** (widen frames vs re-sim) with a perf budget and replay-version gate before any code lands.
2. **Re-cut E1/E2/E6/E7 into ~2h file-scoped swarm beads; move D3 off Haiku; split D1 and E3.**
3. **Fix the fleeing/fog contradiction and the right-click conflict**; reorder fact priority so hold-fire reason and range lead, and make the 3-line cap configurable.
4. **Cut invented scope** (D7, ranked timer values, vanguard/ambush, controller hook) and reduce §4 to four real owner questions.
5. **Route all visual acceptance through the ¶2 assessment framework** and make relation facts answer the owner's actual question — why damage is low — not just label relationships.
