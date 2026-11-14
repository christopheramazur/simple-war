# 5. Harness and AI Factory

The game is built to be played very fast without graphics (R6Q24). That makes the harness and the AI factory first-class citizens. This document covers the game-testing side. The agent tooling harness (`harness/`, `hx`) is documented in `harness/README.md`.

## 5.1 Headless runs (R4Q11, R5Q19, R5Q20, R5Q21)
- **Scenario × variant runs:** the harness runs scenario × configuration-variant matrices through the Game API in fast-forward mode, as parallel Godot processes.
- **Results:** each run's outputs go into **DuckDB**.
- **Replays:** every run produces a replay for visual inspection.
- **Verbs:** `hx sim` verbs drive the runs.
- **Later:** QA extends to testing against map templates (R5Q20).
- **In play (sw-884.1):** `hx sim run <scenario>... --variant <name>... --seeds N --jobs J`.
  - **Runs:** each run is one headless Godot process (`res://src/api/sim_runner.gd`) playing a battle scenario or an overworld map through the Game API.
  - **Results:** runs and metrics go to DuckDB (`harness/data/sim.duckdb`: `sim_batch`, `sim_run`, `sim_metric`, `sim_series`). The verbs `hx sim report`, `list` and `variants` read them.
  - **Replays:** every run leaves its JSON report and its replay save in `harness/data/sim/runs/<batch>/`. Battle replays open in the replay viewer with `--replay=<path>`, plus `--variant=<file>` for a run under a variant.
  - **Variants** (`SimVariant`, `data/sim/variants/*.json`): `patches` merge into template values, so a variant has its own data hash; `controllers` set each player's profile (`zone`, `expand`, `evacuation`, `idle`, with params); `turns` caps overworld runs. Examples: `cautious`, `idle_defender`, `tough_angels`, `quitter`.
  - **Determinism:** measuring is read-only. A run's state hash is the same with or without metrics, and the hash is stored with each run.

## 5.2 Metrics library (R7Q17)
These metrics serve balance, feel and performance analysis, and the AI factory's scoring:
- Victory Points
- Value destroyed and lost
- hexes explored and fog revealed
- economy
- time to milestones
- time spent in each pressure band
- per-system performance

The per-battle SIMPL ledger (R6Q3) is a primary input.

**In play (sw-884.1):** `SimMetrics` produces rows of (metric, player, value), where player 0 means the whole run.
- **Battles:**
  - `vp`, `value_destroyed`, `value_lost`, `units_lost`, `squads_lost`;
  - `band.<pool>.<band>`: squad-ticks spent in each pressure band;
  - `ledger.<pool>`: net SIMPL flow;
  - milestones `first_contact_tick`, `first_casualty_tick`, `first_capture_turn`;
  - `turns`;
  - `perf.<System>_usec`: per-system wall time, from profiling in `SystemRunner`.
- **Overworld runs:**
  - `value`, `value_earned`, `hexes_explored`, `fog_revealed_pct`, `features_owned`, `commanders_alive`;
  - `turns`, `battles`, `first_battle_turn`, `first_capture_turn`, and the mission outcome.
- **Factory metrics (sw-884.6, B1Q10):**
  - **Every run:** per-player result flags `won`, `drew`, `lost`, `forfeited`; `idle_turns` (turns with no order but "ready"); `forfeit_turn`; `turn_cap`.
  - **Forfeits** (leaving the game) are kept apart from withdrawing a battleforce, which is a legitimate move. A variant's controller can set `forfeit_turn` (the `quitter` variant), and the report then names the player who stayed as the winner.
  - **Battles:** `value_destroyed.<victim>` split by `player`, `neutral` and `civilian` victims, so neutrals can't be farmed (B1Q7); `zone_ticks` (ticks holding an unlocked zone); `force_start`; milestones per player as well as per run.
  - **Overworld:** every battle inside the run is measured and summed per player under `battle.` (for example `battle.value_destroyed.player`, `battle.band.morale.broken`). Also `force` (Value of squads held), `feature_turns`, `commanders_start`, `battles` per player, and per-player `first_contact_turn`, `first_battle_turn` and `first_capture_turn`.
  - **Per-turn series** (DuckDB `sim_series`: run, metric, player, turn, value), sampled at the end of each turn:
    - battles: `vp`, `force`, `zones`, `contact`;
    - overworld: `value`, `force`, `enemy_force_seen`, `features_owned`, `hexes_explored`, `fog_pct`, `contact`, `threat` (the worst ratio of hostile Value within 2 hexes of an own commander to that commander's army).
  - These are harness measures and see everything; decision-time estimates use only what a player observes (§5.4).

## 5.3 Pressure Lab (R6Q6)
A harness mode for tuning SIMPL parameters (drift, distribution, bands, sensitivity) against scenarios. It is used to find which tropes emerge (R5Q3).

**In play (sw-884.2):** `hx sim lab <lab>`.
- **Lab files** (`data/sim/labs/*.json`) name scenarios, seeds and axes: `"<template>.<field>[.<key>...]": [values]`, e.g. `standard.pool_defaults.morale.drift_pct_per_s`, plus a `base` every setting shares (controllers, other patches).
- **Settings:** every combination of axis values becomes a generated variant (v1, v2, ...), run through `hx sim`. Settings are recorded per batch.
- **Pressure metrics:** besides the time spent in each band, `SimMetrics` counts `surges.<pool>`, `breaks.<pool>`, `band_changes.<pool>` and the first Morale break.
- **Tropes** (`data/sim/tropes.json`) are rules over a run's features: the share of squad-ticks per pool band (and at the extremes), crossing counts, turns, whether a side won before the turn limit, the VP gap, and the Value-lost ratio. The set:
  - **flatline:** Morale barely moves.
  - **pressure cooker:** Morale lives at the extremes.
  - **rout cascade:** squads break one after another.
  - **seesaw:** Morale swings back and forth across bands.
  - **death spiral:** one side breaks and collapses.
  - **stalemate:** nobody gets ahead before the turn limit.
  - **surge rush:** squads surge often.
- **The table:** per setting, win rate, turns, Morale's neutral share, Morale breaks, and how often each trope showed. `hx sim tropes [--batch]` re-evaluates a batch after the rules change.
- **Labs shipped:** `morale_drift` and `band_floors`.
- **First finding** (`morale_drift` on the duel): slow drift with a fast Morale exchange turns into a pressure cooker with no breaks; a slow exchange gives rout cascades at any drift.
- **Caveat:** duel outcomes don't vary with the seed (sw-884.5), so seeds don't diversify runs yet.

## 5.4 AI factory
- **Controller profiles** (R7Q15): data made of a decision process (scripted, utility, rule-based, later search), parameters and a deterministic **fuzz seed**. Profiles are composable.
- **Evolution** (R7Q16): a genetic algorithm (selection, crossover, mutation) with **competitive co-evolution** between populations, and a **hall of fame** to prevent cycling. No neural networks initially.
- **Scoring** (R6Q24, R7Q17):
  - Each training run defines a **weight schedule** per criterion, conditioned on game state. For example, exploration counts until N hexes are explored or first contact is made, without outweighing fighting or building.
  - A **mask** sets which criteria the process can see. Masks create difficulties and "feels", and filter decision noise.
- **Lineage:** every result records the profile, criteria set, mask, schedule and parent profiles.
- **Throughput target** (R7Q18): the target is **how quickly scoring gains are achieved**, not a match count. It measures both run speed and how nuanced the metrics are.
  1. Benchmark what this machine achieves once the API, metric library and test scenarios exist.
  2. If throughput is low, investigate optimisation.
  3. Move to native code only after optimisations and scoring tweaks run out.
- **Shipped AIs** (R7Q19): curated factory outputs, labelled by difficulty and feel (for example Aggressor, Turtle, Opportunist). They are deterministic with recorded lineage, and the Story and Competitive rulesets get separate sets.

## 5.5 Build order (R8Q6)
1. Sim core: stores, systems, fixed-point maths, state hash.
2. Game API, plus a headless Duel-sized battle scenario.
3. Minimum presentation to watch replays.
4. Angelfall overworld and battles, with editor-plugin authoring tools (R8Q7).
5. Metric library and harness runs (DuckDB, replays).
6. First AI factory loop.

The rest of the testing framework is designed in the AI factory interview wave (R8Q16).
