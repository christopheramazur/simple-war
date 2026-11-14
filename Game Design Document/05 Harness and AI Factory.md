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
  - **In play (sw-884.3):** `ProfileController` (`src/api/profile_controller.gd`) composes an overworld process and a battle process with the mask, fuzz and think-time limit. Every built-in variant profile (`zone`, `expand`, `evacuation`, `idle`) is now a two-layer profile, so a battle profile also plays the overworld.
  - **Utility processes** (`UtilityOverworld`, `UtilityBattle`; A2Q6) score candidate orders (take, convert, recruit, attack, explore; capture, attack, fall back) with SimCriteria values adjusted by a quick estimate: Lanchester's square law for fights, using the battleforce on the overworld. They weigh the scores through the mask and pick the best gain per turn of travel.
  - **Leader squads:** a commander's own squad stays back unless its side clearly outweighs the enemies in sight, and falls back from stronger ones, since losing it loses the commander.
  - **Shipped profiles:** `profile_utility`, `profile_aggressor`, `profile_turtle`; variants `utility` and `aggressor_vs_turtle`.
  - **Faults** (A2Q1, B1Q11): a decision that overruns `think_ms` or returns no order list (a script error) forfeits. Run reports carry `fault` and `think_ms_max`.
- **Evolution** (R7Q16): a genetic algorithm (selection, crossover, mutation) with **competitive co-evolution** between populations, and a **hall of fame** to prevent cycling. No neural networks initially.
  - **In play (sw-884.4):** `hx factory run` (`harness/src/hx/factory.py`).
  - **Genome:** a controller profile as plain data: the utility parameters of both layers, mask bases over the default spec's gates, and fuzz.
  - **Each generation is one harness batch:**
    1. Draw age-weighted pairings; side B comes from the hall of fame 20% of the time.
    2. Play each pairing on both sides × 3 match seeds.
    3. Score it, with λ fed from the generation and the hall-of-fame win rate.
    4. Average fitness per profile and update the MAP-Elites archive (aggression × expansion, 5 × 5).
    5. Retire the oldest profile that reached `max_age` (8) into the hall of fame if it ranked in the top half.
    6. Replace it and the worst 2 with children: uniform crossover of tournament winners, then mutation. Mask genes mutate at 5% against 25% for other genes.
  - **Storage:** lineage, members, generations and the archive go to DuckDB (`factory_*` tables). Every random choice is seeded from the run seed.
  - **Benchmark:** every `bench_every` generations the champion plays `profile_utility` on both sides. `hx factory report` turns those results into the scoring-gain rate (benchmark fitness per wall-clock hour, R7Q18).
- **Scoring** (R6Q24, R7Q17):
  - Each training run defines a **weight schedule** per criterion, conditioned on game state. For example, exploration counts until N hexes are explored or first contact is made, without outweighing fighting or building.
  - A **mask** sets which criteria the process can see. Masks create difficulties and "feels", and filter decision noise.
- **First loop** (A1Q1, A1Q2): the AI learns to win a game. Faster wins score more, and leaving the game is penalised. It plays overworld and battles together, on an open overworld of about 10 by 20 hexes. Balance and test-campaign work come later.
  - **Win condition** (A2Q2): a side wins a duel-style skirmish when every enemy commander is defeated. The run's turn cap ends an undecided game as a draw, which scores as a loss for both sides. A Victory Point target from held features is not used for now. **In play (sw-884.8):** an `overworld_map`'s `elimination` flag (`OverworldVictory`); `test_vale` has it on.
  - **Maps** (A2Q3): one authored mirror map first, for debugging. Then a 10×20 template generates a map from each match seed, with mirrored starts and seed-scattered features, so profiles can't overfit one layout. **In play (sw-884.9):** `skirmish_mirror` (authored) and `skirmish_seeded` (scatter passes, a new layout per seed), both 20 wide by 10 high, built with the map's `mirror` flag.
  - **Forces and economy** (A2Q4): each side starts with one commander and a fixed battleforce. Production features are on, so gathering and spending resources are AI actions from the first loop.
  - **Leaving the game** (A2Q1): the game API keeps every player action, resign included, with no carve-outs for AIs. The framework discourages leaving instead: a forfeit scores −1, and in the factory a profile that crashes or goes over its think-time limit also forfeits. Battle withdrawal stays a legal move.
- **Genome** (A2Q5, A2Q8): one profile spans both layers, with an overworld section and a battle section; the profile that moves a commander fights that commander's battles. The mask is part of the genome, random at birth and rarely mutated. It only changes what the AI thinks it is scored on; selection always uses the real fitness.
- **Order choice** (A2Q6): a profile generates candidate orders and scores each with a quick estimate of its masked, weighted criteria (`SimCriteria`). There is no simulated lookahead; it is added only if the AIs plateau.
- **Generation** (A2Q7): about 20 age-weighted pairings. A profile's fitness is averaged over the matches it played. The worst 2–3 profiles are replaced by mutated or crossbred children of the best. Age is the number of generations survived. Retired top profiles join the hall of fame and are sometimes drawn as opponents.
- **Masks** (A1Q3): a profile's mask limits what the AI thinks it is scored against. It can hide criteria, reweight them, or both, and it can change over the game. Masks set strength and also make decision-making diverse against one scenario. The fuzz seed adds deterministic decision noise, and its strength is a gene (A1Q4).
- **Pairings** (A1Q5): faction doesn't separate populations. The pool starts with 10 profiles; each generation draws 2 (duplicates allowed, older profiles more likely) as side 1 and side 2.
- **Criteria library v1** (B1Q1, B1Q5; `data/sim/criteria.json`; research in `Interview/ai-fitness-criteria-research.md`). One library has two uses:
  - **Fitness:** what the GA selects on. The harness computes each criterion's end-of-game form from the run's metrics (`hx sim fitness`, `harness/src/hx/fitness.py`).
  - **Decisions:** what a profile's utility process weighs through its mask. `SimCriteria` (`src/api/sim_criteria.gd`) computes decision-time forms from the player's own observation only.
  - **Outcome criteria:** result, speed and margin.
  - **Strategic criteria:**
    - value efficiency;
    - force ratio;
    - objective control;
    - economy (Value earned, not banked);
    - exploration (saturating at a target %);
    - commander safety;
    - tempo (low weight);
    - pressure differential (own versus enemy, never own alone, R4Q4).
- **Fitness** (B1Q2-B1Q4; `data/sim/fitness/default.json`):
  - The formula: F = result + 0.25 × speed (wins only) + 0.1 × margin + λ × shaping.
  - Result scores a win 1, a draw or a loss 0 (a turn-limit draw is a loss for both sides), and a forfeit −1.
  - Shaping is the weighted mean of the strategic criteria, each weighted by its schedule and averaged over the run's turns.
  - λ starts at 0.3 and anneals to 0 over 50 generations, or drops to 0 once the population beats the hall of fame more than 60% of the time.
  - `hx sim run` and `hx sim lab` score each batch under the default spec into DuckDB `sim_fitness`; `hx sim fitness` re-scores a batch under any spec.
- **Schedules and gates** (B1Q6):
  - A criterion's weight is base × the product of its gates.
  - A gate is a piecewise-linear curve over one condition. Once its value changes, it holds for at least 3 turns (hysteresis).
  - Conditions: `turn`, `contact`, `since_contact`, `fog_pct`, `force_ratio`, `threat`, `bank`, `ahead`.
  - The fitness spec's `shaping` and a profile's mask share this format. `SimCriteria.Mask` evaluates it in the game; `data/sim/fitness/gate_cases.json` checks that the game and the harness agree.
- **Guards** (B1Q7):
  - Value destroyed counts only enemy-player victims; neutral and civilian kills are measured separately.
  - Exploration saturates.
  - Economy rewards Value earned.
  - With no fighting, Value efficiency is a neutral 0.5.
- **Diversity** (B1Q8): a hall of fame plus a MAP-Elites-style behaviour archive.
  - Archive axes: aggression × expansion, with caution optional.
  - The descriptors are computed with fitness (`desc.*`).
  - Curated "feels" come from archive cells.
  - AlphaStar-style exploiter slots are an option to revisit later.
- **Difficulty** (B1Q9) comes from masks, fuzz strength and visible behaviour limits (commander caps, think budget), never from resource or information cheats.
- **Evaluation protocol** (B1Q11):
  - Every pairing plays both sides on at least 3 seeds or map variants.
  - Each decision has a hard think-time limit.
  - NTBEA is an optional tuner for small genomes (masks, schedule knots).
  - Until sw-884.5 makes seeds vary outcomes, map variation carries the variance.
- **Runs** (A1Q7, A2Q9, A2Q10): set by resource allocation plus a number of iterations, at selectable intensities. An interrupted run saves its results and stops cleanly between iterations.
  - `hx factory run --intensity background|normal|max --generations N`. `background` is 1–2 Godot processes at below-normal priority; `max` uses about 90% of the cores.
  - Ctrl+C or `hx factory stop` lets running matches finish, saves the generation and exits. `hx factory resume` continues from the saved generation.
  - A whole run is reproducible from its run seed: pairings, mutations and map seeds.
  - **In play (sw-884.10):**
    - `hx factory run --intensity background|normal|max`: background is 1–2 processes at below-normal priority, normal is half the cores, max is about 90%.
    - Ctrl+C or `hx factory stop` stops starting new matches. Running matches finish and are saved, and the run exits; a second Ctrl+C aborts.
    - `hx factory resume` plays only the interrupted generation's missing matches and continues to the run's target.
    - A stopped-and-resumed run gives the same results as an uninterrupted one (checked).
    - The database is open only between matches, so `hx factory report` works during a run.
- **Storage** (A1Q8): curated profiles are package data (a moddable `controller_profile` kind). Every evaluated genome, with its lineage, scores, criteria, mask and schedule, goes to DuckDB. An export promotes a genome to package data.
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

**Testing framework** (A1Q9-A1Q11):
- Regression metric baselines run on demand only for now.
- Per-system performance trends are recorded; budgets are set later.
- Feel testing is human playtests for the foreseeable future.
