# U1 draft 02: Visual assessment of battles and the behaviour workshop

Traces to `docs/design/u1/brief.md`, Battles, second paragraph:

> Creating a framework for visually assessing battles at various stages for clarity -- especially if the local bonsai model can be used for assessing still images or short recordings, as there will likely be a lot of visual work -- is a priority. A workshop of some sort for working through individual components of unit behavior both visually and through api is desirable.

Status: research draft for the owner. Nothing in the GDD, `src/`, `harness/`, config or data was changed. No beads were created.

**Tagging.** Owner statements from the brief are tagged `U1Qn`, numbered by their order in the brief. The numbers are provisional until the decision log records Round U1.
- **U1Q2:** a visual clarity framework for battles at several stages is a priority. Local Bonsai should judge stills or short recordings if it can, because there will be a lot of visual work.
- **U1Q3:** a workshop for single components of unit behaviour is wanted, usable both visually and through the API.

Everything else here is **proposed**.

---

## 1 Findings

### 1.1 What already exists and can be reused

| Capability | Where | What it gives this design |
|---|---|---|
| Per-squad activity and per-unit hold-fire reasons | `src/sim/battle/battle_activity.gd` (`squad`, `squad_seen`, `hold`, `victim`, `unit_report`) | Ground truth for "what is each squad doing / why isn't it firing / who is it aiming at". It is read-only and built from the combat systems' own gates, so it can't disagree with the sim. |
| Shot rule | `src/sim/battle/line_of_fire.gd` (`OUT_OF_RANGE`, `SHOT`, `BLOCKED`) | Ground truth for "is A in range of / has a line to B". It is already shared by attack-order movement and the UI cues. |
| Inspection data | `src/sim/battle/inspection.gd`, `BattleSession.inspect` | Stats with traces, the weapon report, effects. It is the squad card's data. |
| Planning forecast | `src/sim/battle/intent_forecast.gd` | Ghost positions and contacts on a scratch copy. It shows that a read-only scratch run is an accepted pattern. |
| Battle Game API | `src/api/battle_session.gd` | `submit_orders`, `ready`, `observe` (fog-safe, with `activity`, `target`, `fire`, `sees` and per-unit weapon reports for own squads), `save`, `load_save`, `rebuild`. Orders are documented in `src/sim/battle/battle_orders.gd`: `hold`, `move`, `attack_move`, `attack`, `fall_back`, `withdraw`, plus `run` and abilities. |
| Exact placement | `BattleSetup.spawn_squad(state, player, st, x, y, facing)` (`src/sim/battle/battle_setup.gd`) | Micro-scenarios can place squads by hand. |
| Micro-battle construction in code | `src/presentation/mocks/fire_cues_mock.gd`; helpers `_place`, `_target` (disarmed, unkillable dummy) and `_move_squad` in `tests/sim/test_battle_activity.gd` | A workshop scenario is this pattern turned into data. The helpers are copy-pasted per test today. |
| Frozen rules package | `tests/fixtures/rules/` (`rules-fixture`) | Gated workshop scenarios can assert exact numbers without breaking on rebalances. |
| Tick-by-tick playback with rich frames | `OverworldSession.playback`, `_frame` (`PLAYBACK_STRIDE` 16: position, facing, `seen_by`, HP, ACT bits, hold reason, squad activity, reload, cooldown, ammo) plus `shots`, `volleys`, `hits` (`src/api/overworld_session.gd`) | Ground truth per tick for clips. `ContextView.show_playback(rec, t)` already draws it with `BattleFx` (projectiles, recoil, hit flashes, floating numbers). |
| Battle drawing | `src/presentation/war_room/context_view.gd` (`show_battle(obs, overlay)` with `selected`, `ghosts`, `contacts`, `drafts`, `telegraphs`, `terrain`; range and sight rings; names and `7/8` strengths), `battle_fx.gd` | The game's own picture. Captures must use it, not a separate renderer, or they would assess the wrong thing. |
| Replay viewer (F6) | `src/presentation/replay_viewer/replay_viewer.gd`, driven by `src/api/replay_recorder.gd` | Space to pause, +/- for speed, Left/Right by turn, Home to restart, `seek_frame`, `--replay=<sav> --variant=<json>`. Its frames are thin (`STRIDE` 6: id, player, x, y, HP, squad), so they carry no activity or hold truth. Its re-simulate-with-a-tick-hook pattern (`session.sim.tick_hook = _capture`) is what capture and the workshop need. |
| War room demo (F6) | `src/presentation/war_room/war_room.gd` (`demo_session()`, `demo_view` export) | Full UI context: panels, squad card, playback. Too heavy for isolating one behaviour. |
| Match replays | `src/api/match_replay.gd`, `user://matches/<…>/match.sav` and `log.md` | Real playtests as a capture source (hash-checked per turn). |
| Harness runs | `src/api/sim_runner.gd`, `hx sim run` (`harness/data/sim/runs/<batch>/<run>.sav` plus JSON) | Deterministic battles by scenario × variant × seed. Stage milestones are already measured in `src/api/sim_metrics.gd`: `first_contact_tick`, `first_casualty_tick`, `first_break_tick` (first Morale `pool_break`). |
| PNG rendering | `src/presentation/mocks/mock_runner.gd`, `hx godot mock` | A SceneTree script that opens a window briefly (`--headless` renders nothing), waits `SETTLE_FRAMES`, then saves PNG plus greyscale, protan and deutan variants (`cvd_sim.gd`). The capture runner is this, generalised. |
| Benchmark ladder | `harness/src/hx/bench/` (`adapters.py` `_openai` sends `content` as a plain string; `checks.py` has `_set_equal` and `_labels`), `harness/bench/tasks/L1–L3`, `config/bench_targets.toml` (`bonsai`, `gateway-bonsai`, `bonsai-nothink`, `haiku` via `claude -p`) | Checking is mechanical and the verdicts are auto ≥ 90% and review ≥ 70%. There is no image support yet. |
| Worker | `hx worker` (SQLite queue, starts Bonsai only when its measured footprint fits) | Vision judging can be a queued job that runs when the GPU is free. |

### 1.2 Gaps
- **No single truth snapshot.** Activity, hold reasons, line-of-fire matrix, victims, pool bands and recent shots each come from a different function. Tests, mocks and the squad card each assemble their own subset.
- **No data format for micro-scenarios.** Each test and mock builds its battle in GDScript, so it can't be opened in a viewer.
- **No tick-level stepping in a viewer.** The replay viewer scrubs frames that lack truth. The war room plays turns. Neither steps backwards with overlays.
- **No debug overlays.** There are no lines of fire, chosen victims, route legs or spacing violations. `ContextView` draws only player-facing cues.
- **No separation or collision rule.** Units sit at `Formation.offset` slots (`formation.gd`, `movement_system.gd:226`). The workshop must be able to hold *pending* scenarios for behaviour that doesn't exist yet.
- **No image capture of battles at chosen ticks.** There is no image input in the bench or the gateway, and Bonsai is started without its vision projector.

### 1.3 Bonsai vision: facts
| Fact | Source |
|---|---|
| Bonsai 2 27B is a vision-language model built on the `qwen35` architecture. It runs only on the PrismML llama.cpp fork (the PQ2_0 rotated basis). | `C:/Users/chris/llmstuff/Bonsai-demo/VISION.md`, `MODEL-FORMATS.md` |
| The projector file is `Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf`, 629,246,976 bytes. The demo budgets about 0.9 GiB of extra memory for it. | directory listing; `VISION.md` |
| To enable it: `--mmproj <file>` (`-mm`, env `LLAMA_ARG_MMPROJ`). `--no-mmproj-offload` keeps the projector in system RAM (the demo's `BONSAI_MMPROJ_CPU=1`), which costs tens of ms to a few seconds of CPU per image during prefill and leaves text speed unchanged. Also `--image-max-tokens N`, `--image-min-tokens N`, `--mtmd-batch-max-tokens N`, and `--media-path PATH` for local media files. | `bin/cuda/llama-server.exe --help` (build 10777, commit e3de71522); `scripts/common.sh` 280–330; `scripts/start_llama_server.ps1` 225–229 |
| `hx bonsai start` passes neither `--mmproj` nor the image flags today. | `harness/config/providers.toml` `[provider.bonsai.server]` |
| Image cost is about 1 vision token per 32×32 px patch, capped near 4,096 tokens (about 4.2 MP). The demo's tested sweet spot is 1,024 tokens for screenshots. Small print degrades under the cap, so crop instead. CUDA is uncapped by default. Follow-up questions about the same image hit the prompt cache. | `VISION.md` |
| Speed on this card: text prefill about 470 tok/s, generation about 34.5 tok/s. So a 1280×720 still (about 900 tokens) costs roughly 2–4 s to encode plus the answer, before projector overhead, which is unmeasured. | `harness/data/bonsai/server.log`; DESIGN.md §7 |
| **VRAM is the blocker.** The text-only footprint at 128k is 9,381 MiB (`harness/data/bonsai/footprint.json`). Measured free VRAM was 7,595–7,632 MiB, about 2.3 GB short (sw-hbz), and local Bonsai never served a delegate call. The projector on the GPU adds about 0.9 GiB more. The weights alone are 7.2 GB, so vision use needs a small context (a vision job needs about 8–16k), the CPU projector, or a freed GPU. Godot's capture window also uses the GPU, so capture and judging must run one after the other. | footprint.json; `bd show sw-hbz`; DESIGN.md §7 |
| API: llama-server's OpenAI-compatible `/v1/chat/completions` accepts `image_url` content parts. Base64 `data:` URLs are the portable choice. | `VISION.md`; [llama.cpp multimodal docs](https://github.com/ggml-org/llama.cpp/blob/master/docs/multimodal.md) |
| Through LiteLLM: the `openai/` prefix passes OpenAI-format content parts through. `model_info: {supports_vision: true}` on the model entry makes `/model/info` report vision. LiteLLM converts image URLs to base64 for back ends that need it. An end-to-end check through *our* gateway is unverified, and is part of the spike. | [LiteLLM vision](https://docs.litellm.ai/docs/completion/vision), [LiteLLM image handling](https://docs.litellm.ai/docs/proxy/image_handling) |
| **Video:** upstream llama.cpp merged mtmd video input on 2026-06-08 (PR #24269). Video is decoded by an FFmpeg subprocess (FFmpeg on PATH), only image frames are used, and fps and frame controls are still future work. Our fork's `--help` lists no video flags, so support in build 10777 is unverified. **Recommendation:** sample frames ourselves as labelled frame strips. Our own frame choice is deterministic, tick-labelled, cheaper and tied to ground truth. Revisit native video later. | [PR #24269](https://github.com/ggml-org/llama.cpp/pull/24269); `--help` output |
| Cloud fallbacks: Gemini Flash is multimodal but `trains_on_data = true` in `providers.toml`. Haiku through `claude -p` can view an image file via its Read tool, using subscription quota. | `harness/config/providers.toml`, `config/bench_targets.toml` |

### 1.4 Relation to sw-68h
On 2026-11-23, sw-68h decided (recorded in DESIGN.md §7):
- retire the `.mcp.json` `hx` entry;
- keep `hx delegate`, the gateway and the bench;
- don't repair Bonsai now;
- revisit only if a local model would save spend, and qualify any local model through the ladder.

This proposal:
- **Doesn't touch** the MCP entry or `hx delegate`. It needs `hx bonsai`, the gateway and the bench, all of which sw-68h keeps.
- **Is the concrete reason to revisit** that sw-68h anticipated:
  - high-volume image judging, hundreds of images per sweep, would burn subscription quota on Haiku;
  - the free multimodal tier (Gemini) trains on the data.
- **Follows sw-68h's rule:** Bonsai is qualified first by a spike and then by a vision bench suite before anything routes to it.
- **Doesn't depend on Bonsai succeeding.** The judge is pluggable. Truth-based checks, layout lint and golden-image diffs work with no model at all. If the spike fails on VRAM, judging falls back to sampled Haiku or is skipped.

**Recommendation:** close sw-68h once the user empties `.mcp.json`; nothing here reopens it. The spike (bead V1 below) cites sw-68h and sw-hbz in its description.

---

## 2 Prior art (short)
- **Vision-language models for game QA.** Two benchmarks:
  - [GlitchBench](https://arxiv.org/abs/2312.05291) (CVPR 2024): 593 glitch images; the best model then was about 43% accurate.
  - [VideoGameQA-Bench](https://arxiv.org/abs/2505.15952) (NeurIPS 2025 D&B): visual unit tests, regression tests, needle-in-a-haystack and glitch detection on images and video. Frontier models wrote useful bug reports for at most about half of real glitches.

  Lesson: closed, checkable questions ("visual unit tests") work far better than open "is this OK?" prompts. Answers must be graded against truth.
- **Known blind spots.** ["Vision language models are blind"](https://arxiv.org/abs/2407.06581) (2024): VLMs fail at simple geometry such as line crossings, overlapping circles and counting. That is exactly "is this line from A to B" and "does the ring reach the enemy". Expect to calibrate per question type, not trust a single global score.
- **Golden-image and visual regression.** Examples: Unreal's Automation screenshot comparison, Unity's Graphics Test Framework (`ImageAssert`), Playwright `toHaveScreenshot`. All need deterministic captures, per-machine baselines and a perceptual tolerance, because GPU and driver output differs.
- **Deterministic capture in Godot.** [Movie Maker mode](https://docs.godotengine.org/en/stable/tutorials/animation/creating_movies.html): `--write-movie out.png|.avi`, `--fixed-fps N`, `--quit-after N`. It renders non-real-time with fixed frame pacing and needs a real renderer. It suits human-viewable clips. For judged strips, setting the playback `t` explicitly per frame is simpler and exact.
- **Isolated micro-scenarios for unit behaviour.** [SMAC](https://arxiv.org/abs/1902.04043) (StarCraft Multi-Agent Challenge) builds micromanagement scenarios (for example 3 marines against 3 marines) as small maps. Unreal's Functional Tests are levels with assertions.
- **RTS and AI debug overlays.**
  - The StarCraft II API's debug draw (`DebugDraw` lines, spheres and text in world space).
  - BWAPI's `drawLineMap` and `drawCircleMap`, which bot authors use for targets and ranges.
  - Unreal's Gameplay Debugger.
  - Godot's own Debug menu (visible collision shapes, navigation).

  Common pattern: overlays are drawn from the AI's own decision data, never re-derived by the renderer.

---

## 3 Proposed text for the GDD and harness docs

### 3.1 GDD `05 Harness and AI Factory.md`: append two sections after §5.5

````markdown
## 5.6 Visual assessment (U1Q2; proposed)
Battles must read clearly at every stage. The harness captures what the player would see at chosen moments and checks it against what the simulation knows.
- **Stages** (proposed), found from a run's events, so every capture is deterministic for a scenario, variant and seed:
  - **deploy:** turn 1, tick 0.
  - **first contact:** `first_contact_tick`.
  - **first blood:** `first_casualty_tick`.
  - **mid-fight:** the tick with the most squads `ENGAGED` between first contact and the end.
  - **rout:** `first_break_tick`, or else the first squad falling back.
  - **end:** the last tick.

  A stage that never happened is skipped and reported.
- **Sources** (proposed): a harness run's replay (`hx sim run`), a match log's `match.sav`, a workshop scenario (§5.7), or a scenario plus seed played on the spot. The capture re-simulates through the Game API and checks the state hash, so the picture is always of the recorded battle.
- **What is captured** (proposed):
  - **Stills and frame strips:** a strip is 4–6 frames over a short window, each labelled with its tick.
  - **Views:** a player's fog view, or omniscient.
  - **Kinds:** the game render (what the player sees), a control render (the same frame with debug overlays and large labels: the most legible the frame can be), and colour-vision variants (greyscale, protan, deutan, as `hx godot mock` makes).

  Drawing always goes through the game's own battle view, never a separate renderer.
- **Ground truth** (proposed): one read-only truth snapshot per captured tick (`BattleProbe`):
  - each squad's activity and target;
  - each unit's hold reason and victim;
  - the line-of-fire matrix;
  - shots in the strip's window;
  - pool bands and casualties.

  It comes from the same functions the simulation uses, so it can't disagree with it.
- **Rubric** (proposed): closed questions with checkable answers, asked per capture:
  - who is shooting whom;
  - which squads are out of range of their target;
  - what each squad is doing;
  - which squad is taking the most damage;
  - which squads are breaking;
  - which squad is selected and what its ring shows.

  Answers are JSON over the squad labels drawn on screen. Open-ended remarks are recorded but never scored.
- **Judges** (U1Q2: local Bonsai where it can be trusted; proposed otherwise): a vision model answers the rubric with the game's legend as its only briefing, as a player would have it.
  - A question class is graded automatically only for a judge the vision bench rates `auto` on it (harness `hx bench`, vision suite).
  - Classes rated `review` go to a stronger judge on a sample.
  - Classes rated `no` aren't asked.
- **Clarity score** (proposed): per question and stage, the judge's accuracy on the game render divided by its accuracy on the control render. A low score on a question the judge answers well on control frames means the picture is unclear, not the judge. Control accuracy under 0.9 marks the question judge-limited, and it is left out of the score.
- **Checks without a model** (proposed):
  - **Layout lint:** overlapping labels, labels over squads, text contrast against the ground.
  - **Golden-image diffs:** against per-machine baselines with a perceptual tolerance.

  These run without any model.
- **Trust** (proposed): a judge's answers are evidence, never a verdict. They never gate a merge or close a task. They feed reports and filed proposals that name the capture, the truth and the answer.
- **Not built:** everything in this section. See the harness `hx visual` verb.

## 5.7 Behaviour workshop (U1Q3; proposed)
One place to work through a single component of unit behaviour, such as targeting, attack-move positioning, separation, fire modes or retargeting, both by watching it and through the API.
- **Scenarios are data** (proposed): `data/sim/workshop/<id>.json`. Each scenario holds:
  - the rules package (`rules-fixture` for gated scenarios, `core` for feel work);
  - a battle map, or open ground;
  - squads placed exactly, each optionally a dummy (unarmed, unkillable, or stationary), with optional stat patches;
  - scripted orders per turn;
  - named variants (other orders or patches);
  - probes: expectations at a tick or over a window, read from the truth snapshot (§5.6);
  - comparisons between variants.

  One file serves both the visual check and the API check.
- **Status per scenario** (proposed):
  - `gate`: its probes run in the game test suite and must pass.
  - `pending`: describes behaviour the owner wants but the game doesn't do yet. It is reported, and never fails the suite; when it starts passing the report says so.
  - `explore`: no probes; for watching only.
- **Headless** (proposed): every scenario runs through the Game API at full speed. The game tests run every `gate` scenario. The harness verb `hx workshop` prints probe results and traces.
- **The workshop scene** (proposed): a standalone (F6) scene.
  - **Opening and controls:** it opens a scenario and variant. Play, pause, step one tick either way, step a turn and scrub; it re-simulates from the start, so every tick is exact.
  - **Overlays** can be switched on and off: weapon ranges, lines of fire (shot, blocked, out of range), each unit's chosen victim, route legs, spacing violations, hold-fire reasons.
  - **Probes** are listed with pass or fail; clicking one jumps to its tick.
  - **Squad card:** the squad card of a clicked squad at the current tick.
  - **Reload** re-reads the file after an edit.

  The scene only reads a run's recorded frames. It never changes the battle; a tweak makes a new run.
- **Determinism:** same file, same variant, same result. The run's state hash is reported, so a visual check and an API check are provably of the same battle.
- **Not built:** everything in this section.
````

Also amend §5.5's last bullet:

````markdown
- Feel testing is human playtests for the foreseeable future, supported by the behaviour workshop (§5.7) and visual assessment (§5.6) (proposed).
````

### 3.2 GDD `04 Systems Architecture.md` §4.9 Tools: add a bullet

````markdown
- **Behaviour workshop** (U1Q3; proposed): `src/presentation/workshop/behaviour_workshop.tscn`, F6. It plays one workshop scenario (Harness and AI Factory §5.7) with debug overlays, stepping and scrubbing. It reads `WorkshopRun` frames from the API layer (`src/api/workshop/`). The truth behind its overlays and probes is `BattleProbe` (`src/sim/battle/battle_probe.gd`), a read-only snapshot that combines `BattleActivity`, `LineOfFire` and the recent shots.
````

### 3.3 `harness/README.md`: rows for the Verbs table

````markdown
| `visual` | Visual assessment of battles (GDD 05 §5.6; proposed).<br>• `capture <scenario\|--replay PATH\|--match DIR\|--workshop ID> [--seed N] [--variant V] [--stages deploy,contact,blood,mid,rout,end] [--strip N] [--view p1\|p2\|omni] [--kinds game,control,cvd]` renders stills and frame strips with Godot (a window opens briefly, as with `godot mock`) and writes PNGs, per-shot truth JSON and `manifest.json` to `data/visual/<capture>/`.<br>• `ask <capture> [--judge NAME] [--rubric default]` asks each shot the rubric's applicable questions (`data/sim/visual/rubric.json`) through the gateway and grades the answers against the truth. Only question classes the vision suite rates `auto` for that judge are graded; `review` classes are sampled to the next judge.<br>• `report [<capture>\|--batch ID] [--file]`: accuracy per question × stage × kind, clarity (game ÷ control), judge-limited questions, the worst shots with their paths. `--file` files up to 3 proposals as bd tasks labelled `visual` (evidence: shot paths, truth, answers; deduplicated like `mine`).<br>• `lint <capture>`: model-free layout checks (label overlap, labels over squads, text contrast).<br>• `diff <capture> --golden NAME [--accept]`: perceptual diff against a local baseline in `data/visual/golden/`.<br>• Results go to DuckDB `data/sim.duckdb` (`vis_capture`, `vis_shot`, `vis_answer`). Judging runs after capture, never beside it (one GPU). `--queue` hands it to `hx worker` to run when VRAM is free. |
| `workshop` | Behaviour workshop scenarios (GDD 05 §5.7; proposed). `list` (id, component, status, last result); `run <id>\|--all [--variant V] [--trace]` plays them headless (`src/api/workshop/workshop_cli.gd`) and prints probe results (pass, fail, pending, unexpected pass) and the state hash; `--trace` adds the per-tick table of the probed values. `gate` scenarios also run in `hx godot test` (`tests/sim/test_workshop_scenarios.gd`). |
````

Also add to `bonsai`:

````markdown
`start --vision` adds the projector and image flags from `[provider.bonsai.server]` (`mmproj`, `mmproj_offload`, `image_max_tokens`, `vision_ctx`) and records the footprint separately per (ctx, vision), so text-only starts are unchanged (proposed).
````

Under "Benchmark suite", add:

````markdown
- **Vision suite** (proposed): `bench/vision/` is a separate suite with its own version, so text suite v1 stays frozen. It holds frozen battle stills and strips rendered from workshop scenarios, each with truth JSON and closed questions in classes `vis_activity`, `vis_fire_pairs`, `vis_range`, `vis_breaking`, `vis_count`, `vis_selected`, plus negative controls whose truthful answer is "none". Checking is mechanical (`set_equal`, `labels`). The openai adapter sends `image_url` parts as base64; `claude-cli` passes file paths for Haiku to Read. `hx bench run --suite vision --target bonsai-vision`.
````

### 3.4 `harness/DESIGN.md`: §7 and §8 additions (proposals, per DESIGN.md's own rule)

````markdown
- **Vision (U1Q2, proposed, after spike V1):** Bonsai 2 27B accepts images through its projector (`--mmproj`, `VISION.md` in the Bonsai demo). It is served as `bonsai/vision` (no-think, `model_info.supports_vision`), started by `hx bonsai start --vision` with the context and projector placement the spike measured to fit. Its uses:
  - battle stills and frame strips for `hx visual`;
  - never authoritative: answers are graded against sim truth, and only question classes the vision suite rates `auto` are graded without review.
  - Native video input is not used: frames are sampled by the game, tick-labelled.
  - Free tiers that train on data (`trains_on_data = true`) get no game screenshots unless the user allows it.
  - Relation to sw-68h: this is the "revisit local Bonsai" trigger it named, qualified through the ladder; it does not restore the MCP entry.
````

````markdown
| V | Vision: closed questions on battle stills and strips | Set or label agreement with sim truth |
````

### 3.5 `AGENTS.md` §7: two rows (the owner's call, since AGENTS.md is canonical)

````markdown
| Behaviour workshop scenarios | `harness/bin/hx workshop run <id>\|--all [--trace]` (`data/sim/workshop/`; scene `src/presentation/workshop/behaviour_workshop.tscn`, F6) |
| Visual clarity of a battle | `harness/bin/hx visual capture <scenario> --seed N` then `hx visual ask <capture>` and `hx visual report <capture>` |
````

---

## 4 Open questions for the owner

| # | Question | Blocking? | Recommended default |
|---|---|---|---|
| OQ1 | Bonsai vision doesn't fit the VRAM normally free (about 7.6 GB free; the text-only footprint is already 9.4 GB at 128k). Pick one: (a) vision jobs use a small context (16k) with the projector on the CPU, (b) you close GPU-heavy apps before scheduled sweeps, (c) skip local and judge a sample with Haiku. | No: the spike measures (a). | (a), with (c) as the automatic fallback if (a) doesn't start. |
| OQ2 | May game screenshots go to free cloud models that train on data (Gemini Flash)? | No | No. Use only Bonsai and the Claude subscription. |
| OQ3 | Workshop scenarios: `data/sim/workshop/`, with gated ones on the frozen `rules-fixture` package and feel ones on `core`? | No | Yes. |
| OQ4 | May agents write **pending** scenarios that state behaviour you want (for example "an attack-moving infantry squad with an enemy seen but not in range uses its remaining movement to reach a firing position", from the brief's movement paragraph), and should these count as the spec you review in the workshop scene? | Yes, for bead V4. | Yes: agents draft them from the brief, the status stays `pending`, and you accept or edit them in the scene. |
| OQ5 | Golden images: committed, or local per machine? | No | Local only (`harness/data/visual/golden/`, git-ignored). GPU and driver output differs. |
| OQ6 | May visual reports file beads on their own? | No | Proposals only: at most 3 per run, labelled `visual`, deduplicated, like `mine` and `reflect`. |
| OQ7 | Should the debug overlays also be a developer toggle in the war room? (The player-facing hover and context-menu interactions from the brief's third paragraph are a separate draft, but can read the same `BattleProbe`.) | No | Later, as a dev-only toggle once the workshop overlays are stable. |
| OQ8 | Frame strips instead of native video? | No | Yes. Revisit when the fork exposes video flags. |
| OQ9 | Verb names: top-level `hx visual` and `hx workshop`, or `hx sim visual` and `hx sim workshop`? | No | Top level. They are used often and named in AGENTS.md. |
| OQ10 | Stage definitions (§3.1: deploy, contact, blood, mid, rout, end): are these the moments you care about? | No | As listed. Add any stage as a named event rule later. |

---

## 5 Bead breakdown (ordered)

The runners:
- `swarm`: small, well-specified, safe for Qwen4.
- `autopilot`: Haiku-sized.
- `autopilot-large`: needs Opus.

Rules for every bead:
- Harness beads follow `harness/DESIGN.md` and `harness/README.md` "Adding a verb": `src/hx/commands/<verb>.py` plus `VERBS`, a pytest, compact output and `--json`. Data goes under git-ignored `harness/data/`. Never edit frozen bench task files. Never raise budgets.
- Game beads follow AGENTS.md §5: presentation never mutates the sim, F6, determinism. Every bead updates its own "In play" line in the GDD.

### V1 Spike: Bonsai vision on battle stills
- **Type and priority:** task, P1. **Runner:** autopilot-large. **Depends on:** none (cites sw-68h and sw-hbz).
- **Why:** U1Q2 asks for local Bonsai if it can do the job. Its projector is unused, and VRAM is already short for text (sw-hbz). Measure before building anything that relies on it.
- **What:**
  1. Add optional `mmproj`, `mmproj_offload` (default false), `image_max_tokens` and `vision_ctx` keys under `[provider.bonsai.server]`, and `hx bonsai start --vision`. Text starts stay unchanged. Files: `harness/config/providers.toml`, `harness/src/hx/localmodel.py`, `harness/src/hx/commands/bonsai.py`.
  2. Measure the footprint with the projector on GPU and on CPU, at 16k, 32k and 128k context. Record each in `data/bonsai/footprint.json` keyed by (ctx, vision).
  3. Render 10–12 stills with existing mocks (`fire_cues_mock`, `combat_fx_mock`, `war_room_readability_mock`, `telegraph_mock`) or small new ones. Hand-write truth: which squads fire at which, out of range, activity, a count, a selected squad's ring, and 2 negative controls.
  4. Ask the questions as JSON both direct (`:8080`) and through the gateway, with a `bonsai/vision` alias (`model_info.supports_vision`) via `hx gateway config`. Also ask Haiku via `claude -p` with Read as the baseline.
  5. Record per question: accuracy, image tokens, encode and answer latency, at image caps of 1024 tokens and uncapped.
  6. Check whether the fork accepts a video content part. Report only; don't build on it.
- **Acceptance:**
  - `data/bonsai/vision-<date>.json` holds the footprint, latency and accuracy table.
  - The bead notes give a go or no-go per question class, and the start configuration that fits, or "doesn't fit: fallback (c)".
  - A short "Vision" entry is in DESIGN.md §7.
  - The harness pytest passes.
  - No budget or provider-training setting is changed.

### V2 BattleProbe: one read-only truth snapshot
- **Type and priority:** feature, P1. **Runner:** autopilot. **Depends on:** none.
- **Why:** visual grading, workshop probes and overlays all need the same truth. Today it is spread across `BattleActivity`, `LineOfFire`, `Inspection` and events.
- **What:** `src/sim/battle/battle_probe.gd` (RefCounted, static). `snapshot(state, viewer := 0) -> Dictionary` returns, per squad:
  - label, player, activity, target, alive and start, pool bands, centroid, range, sight;
  - per unit: hold reason, victim and distance, position, HP;
  - a `fire` matrix of LineOfFire results for every enemy pair;
  - shots and hits of the last N ticks from `turn_log`.

  With `viewer > 0` it is fog-safe: `squad_seen` for enemies, and no enemy holds.
- **Files:** that file, `tests/sim/test_battle_probe.gd`.
- **Acceptance:**
  - On a hand-placed battle, it equals `BattleActivity` and `LineOfFire` called directly.
  - The state hash is unchanged after a snapshot.
  - The fog view leaks no orders (mirror the existing `observe` test).
  - `hx godot test` is green.

### V3 Workshop scenario format, headless runner, test gate
- **Type and priority:** feature, P1. **Runner:** autopilot-large. **Depends on:** V2.
- **Why:** U1Q3 asks for the API half of the workshop. One data file must drive both the visual and the API checks.
- **What:**
  - **Schema:**
    - `id`, `component`, `doc`, `status` (gate, pending or explore), `package`, `map` (or `open`), `seed`;
    - `squads`: `key`, `player`, `squad`, `at` [x, y] in metres, `facing`, `dummy` {`armed`, `hp`, `stationary`}, `patch` {stat: value};
    - `script`: per turn `orders`, using squad keys, in `BattleOrders` format;
    - `turns`, `variants` {name: {script or patch overrides}};
    - `probes`: `id`, `at` (`t1:40`, `end`) or `over` (`t1`, `t1:0-50`), and one of `activity`, `hold`, `fire`, `distance`, `within`, `damage`, `shots`, `duty` (share of armed unit-ticks that fired), `victims` (distinct victims, maximum shots per victim, overkill), `kills`, `spacing` (minimum unit distance), `moved`;
    - `compare` [{`metric`, `lhs`, `rhs` variants, `rel`, `factor`}].
  - **Classes:** `WorkshopScenario` (load and validate with errors) and `WorkshopRun` (builds the state with `BattleSetup.create` plus `spawn_squad`, submits orders through the same validation as `BattleSession`, and records a per-tick frame in playback format plus a `BattleProbe` snapshot through the sim's `tick_hook`).
  - **Files:** `src/api/workshop/workshop_scenario.gd`, `src/api/workshop/workshop_run.gd`, `src/api/workshop/workshop_cli.gd` (SceneTree: `--scenario id|all --variant --json`), `tests/sim/test_workshop_scenarios.gd` (runs every `gate` file), `data/sim/workshop/README.md` (the schema), and 2 example scenarios.
  - Move `_place`, `_target` and `_move_squad` from the tests into a shared builder.
- **Acceptance:**
  - Two runs of a scenario give the same hash.
  - A bad file gives readable errors.
  - A `pending` probe that fails doesn't fail GUT; one that passes prints "unexpected pass".
  - The gate test is in `hx godot test`, which is green.

### V4 Seed workshop scenarios from the brief
- **Type and priority:** task, P1. **Runner:** autopilot. **Depends on:** V3, OQ4.
- **Why:** the brief's first paragraph says it is hard to confirm whether attack-move, run, hold, targeting and retargeting lower damage output. The movement paragraph wants SC2-like attack-move. These scenarios make both measurable. Coordinate with the U1 draft on orders and damage output: scenarios here, rule changes there.
- **What:** scenarios in `data/sim/workshop/`:
  - `dps_orders`: a rifle squad against a dummy, with variants `attack`, `attack_move`, `move_then_attack`, `run`, `hold`; probes `duty`, `damage`; `compare` against `attack`.
  - `dps_retarget`: switch targets each turn, compared with a constant target.
  - `fire_modes_moving`: moving fire against standing fire.
  - `attack_move_firing_position` (pending): enemy seen, out of range, movement left; expect `fire` = shot by the turn's end and `within` reach.
  - `separation_clump` (explore): two squads converging; `spacing` reported.
  - `focus_fire_spread` (explore): `victims` and overkill, for the later Prowess idea.
- **Acceptance:**
  - Every file loads and runs in `hx workshop run --all`.
  - The bead notes give the measured DPS table per order, the first hard answer to the brief's question.
  - Gate scenarios pass. Pending ones are reported.

### V5 `hx workshop` verb
- **Type and priority:** task, P2. **Runner:** swarm. **Depends on:** V3.
- **What:** `harness/src/hx/commands/workshop.py`: `list` and `run <id>|--all [--variant] [--trace] [--json]`. It calls `workshop_cli.gd` through the existing `hx godot run` plumbing. Output is compact (one line per probe; failures first). Add a pytest with a fake Godot output fixture and a README row.
- **Acceptance:** pytest is green. `hx workshop run --all` prints at most 1 line per scenario when everything passes.

### V6 Debug frames and overlay layer
- **Type and priority:** feature, P2. **Runner:** autopilot-large. **Depends on:** V3.
- **Why:** the visual half of the workshop, and the control renders for V8.
- **What:**
  - Per-tick debug data in `WorkshopRun`: ranges, the LoF matrix, per-unit victim, route legs (the sequence of `BattleRoute.next_waypoint` from the squad's cell), spacing violations, hold glyphs.
  - `src/presentation/workshop/debug_overlay.gd`: a Control drawn over `ContextView` that uses `ContextView`'s camera transform and reads only frame data. Toggles: ranges, lines of fire (green shot, amber blocked, grey out of range), victim lines unit to unit, route legs, spacing, holds, large labels.
  - A mock `src/presentation/mocks/debug_overlay_mock.gd`.
- **Acceptance:**
  - The mock renders with `hx godot mock`.
  - The overlay never imports sim classes beyond reading frame dictionaries (checked by a test that greps for writes).
  - `godot check` is clean.

### V7 Behaviour workshop F6 scene
- **Type and priority:** feature, P2. **Runner:** autopilot-large. **Depends on:** V6.
- **What:** `src/presentation/workshop/behaviour_workshop.tscn` and `.gd`:
  - Scenario and variant pickers (`data/sim/workshop`), `--scenario=` argument, the first scenario by default.
  - Transport reusing the replay viewer's keys: Space, +/-, comma and period for a tick, Left/Right for a turn, Home, plus a scrub slider.
  - `ContextView.show_playback` for the picture with `BattleFx`, plus `DebugOverlay`.
  - A probe list (pass, fail, pending), where a click seeks to the probe's tick.
  - `SquadCard` for the clicked squad, from `Inspection` on a re-simulation to that tick.
  - F5 reloads the file. All keys go through GUIDE (AGENTS / GDD 04 §4.1: none hard-coded).
- **Files:** those two, plus `tests/presentation/test_behaviour_workshop.gd`.
- **Acceptance:**
  - Runs with F6 and `hx godot run`.
  - Seeking to tick N shows the same positions as the headless frame N.
  - No orphans.
  - The GDD 04 §4.9 bullet is added.

### V8 Capture runner: stills and frame strips with truth
- **Type and priority:** feature, P2. **Runner:** autopilot-large. **Depends on:** V2, V6, and a go from V1 for strip sizing (capture is useful even on a no-go).
- **What:**
  - `src/presentation/capture/capture_runner.gd` (SceneTree, opens a window like `mock_runner.gd`).
  - **Sources:** a battle `.sav` (`BattleSession.load_save` or rebuild, then re-execution with `tick_hook`, hash-checked), a `match.sav` (`MatchReplay` with `keep_playback`), a workshop id, or a scenario plus seed (`HeadlessDuel` controllers).
  - Finds the stages (§3.1).
  - For each stage, view and kind, it sets up `ContextView` (`show_playback` at an exact `t` for strips, so `BattleFx` shows the shots) and saves a PNG. A strip is N frames composited into one image with tick captions, kept to about 1,024 vision tokens or cropped.
  - Control kind adds `DebugOverlay` and large labels. CVD kinds use `CvdSim`.
  - Writes `truth/<shot>.json` (`BattleProbe` with the viewer's fog) and `manifest.json` (source, data hash, state hash, stage to tick, paths).
  - Also writes the label and footprint rectangles that `ContextView` drew, for V11.
- **Acceptance:**
  - Two captures of the same source give identical truth and manifests, and the same PNGs on one machine.
  - A missing stage is reported, not an error.
  - The runner never writes to the session (test).

### V9 Vision bench suite
- **Type and priority:** task, P2. **Runner:** autopilot. **Depends on:** V1, V8.
- **What:**
  - `harness/bench/vision/` with its own version: about 24 stills and strips captured from V4 scenarios and a harness duel, frozen with truth.
  - Question classes `vis_activity`, `vis_fire_pairs`, `vis_range`, `vis_breaking`, `vis_count`, `vis_selected`, plus negative controls.
  - `adapters._openai` sends content parts (text plus `image_url` data URLs). `claude-cli` passes paths for Read.
  - Targets `bonsai-vision` (and `gateway-bonsai-vision`), and `haiku`.
  - `hx bench run --suite vision`. `hx bench route` writes vision routes.
  - Generator and freeze test, as for suite v1.
- **Acceptance:**
  - Pytest is green.
  - A report per class and target.
  - `config/routing.toml` gains vision routes only via `hx bench route --write`.

### V10 `hx visual capture | ask | report`
- **Type and priority:** feature, P2. **Runner:** autopilot. **Depends on:** V8, V9.
- **What:**
  - `harness/src/hx/visual.py` and `commands/visual.py`.
  - `capture` wraps V8.
  - `ask` builds per-question prompts with the game's legend text: the controls help and the terrain and glyph legend, nothing more. It requests JSON over the squad labels and grades against truth with `checks.py` functions. It uses only `auto` classes for the judge; `review` classes are sampled to the next routed judge.
  - `report` gives accuracy per question × stage × kind, clarity = game ÷ control, judge-limited flags and the worst shots.
  - DuckDB tables `vis_capture`, `vis_shot`, `vis_answer` in `data/sim.duckdb`.
  - `--queue` runs as an `hx worker` job, so judging waits for free VRAM, after capture.
  - `data/sim/visual/rubric.json` holds the questions, their applicability (for example `vis_range` only when a squad is engaged) and the answer schemas.
- **Acceptance:**
  - An end-to-end run on a V4 scenario with a fake judge fixture passes in pytest.
  - With a real judge, the report lists every shot with its truth and answer.
  - Output stays compact by default.

### V11 Layout lint (model-free clarity checks)
- **Type and priority:** task, P3. **Runner:** autopilot. **Depends on:** V8.
- **What:** `hx visual lint`, using the rectangles from V8: label against label overlap, a label over another squad's footprint, label text contrast against the ground under it (WCAG ratio, using the luminance from `cvd_sim.gd`), and squads whose footprints overlap beyond a threshold.
- **Acceptance:** a constructed mock with two overlapping labels is flagged. The `fire_cues` mock is clean or its findings are listed.

### V12 Golden-image diff
- **Type and priority:** task, P3. **Runner:** swarm. **Depends on:** V8.
- **What:** `hx visual diff <capture> --golden NAME [--accept]`. Per-pixel and perceptual (SSIM or a tolerance-banded delta) diff against `data/visual/golden/NAME/`. It writes diff PNGs and lists the shots over tolerance.
- **Acceptance:** identical captures diff to 0. A 1-pixel shift is under tolerance. A moved label is over it. Pytest is green.

### V13 Visual proposals and the scheduled sweep
- **Type and priority:** task, P3. **Runner:** autopilot. **Depends on:** V10, OQ6.
- **What:**
  - `hx visual report --file` files at most 3 proposals labelled `visual`. Each cites shot paths, truth and answers, and is deduplicated against open tasks (reuse the reflection probe).
  - An optional worker job runs a sweep over the duel's stages and the workshop scenarios at most weekly.
- **Acceptance:** a dry run prints the proposals. Filing respects the cap and dedup. No proposal is filed without evidence.

### V14 Land the documentation
- **Type and priority:** task, P2. **Runner:** swarm. **Depends on:** owner answers to OQ1–OQ10.
- **What:** apply §3's text to GDD 05 §5.6 and §5.7, GDD 04 §4.9, `harness/README.md`, `harness/DESIGN.md` §7 and §8, and AGENTS.md §7 (only if the owner approves). Record U1Q2 and U1Q3 in the decision log once numbered.
- **Acceptance:** the docs match the decisions. "Proposed" tags are removed only where settled.

**Suggested order:** V1 ∥ V2 → V3 → V4 ∥ V5 ∥ V6 → V7 ∥ V8 → V9 → V10 → V11 ∥ V12 → V13. V14 lands after the owner answers. V2 through V7 deliver the workshop with no model at all. Only V9, V10 and V13 depend on V1's verdict.
