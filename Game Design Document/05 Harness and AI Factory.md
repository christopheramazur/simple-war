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
  - **Results:** runs and metrics go to DuckDB (`harness/data/sim.duckdb`: `sim_batch`, `sim_run`, `sim_metric`). The verbs `hx sim report`, `list` and `variants` read them.
  - **Replays:** every run leaves its JSON report and its replay save in `harness/data/sim/runs/<batch>/`. Battle replays open in the replay viewer with `--replay=<path>`, plus `--variant=<file>` for a run under a variant.
  - **Variants** (`SimVariant`, `data/sim/variants/*.json`): `patches` merge into template values, so a variant has its own data hash; `controllers` set each player's profile (`zone`, `expand`, `evacuation`, `idle`, with params); `turns` caps overworld runs. Examples: `cautious`, `idle_defender`, `tough_angels`.
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
- **Not yet:** metrics for the battles inside an overworld run.

## 5.3 Pressure Lab (R6Q6)
A harness mode for tuning SIMPL parameters (drift, distribution, bands, sensitivity) against scenarios. It is used to find which tropes emerge (R5Q3).

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
