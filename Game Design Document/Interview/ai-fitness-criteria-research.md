# AI Fitness Criteria: Research and Library v1

Research for task sw-p2q.7 (follows A1Q6). It covers how comparable strategy-game AIs and research projects score, weight, diversify and tune their decisions. It ends with a proposed criteria library v1 mapped onto `SimMetrics` (`src/api/sim_metrics.gd`). This is reference material: the decisions are in `decision-log.md`, Round B1.

Confidence markers: **[src]** checked against a source this session; **[mem]** from memory of primary docs, not re-checked; verify before relying on the detail.

## 1. What comparable projects score

### Heroes of Might and Magic and VCMI
- **HoMM3 (original AI):**
  - **Strength:** it judges armies by creature **AI Value**, a per-creature strength number. Army strength is the sum of AI Values, scaled by the hero's attack and defence when stacks are compared. **[src]**
  - **Personalities:** Builder, Warrior and Explorer shift priorities between towns, fights and expansion. The Explorer even gets +50 movement a day. **[src]**
  - **Difficulty:** levels change behaviour, not just bonuses. Easy builds every other day, underestimates enemy heroes and hires fewer heroes. Expert is very cautious near enemy heroes. Only Impossible adds resource bonuses. **[src]**
- **VCMI Nullkiller (current adventure AI):**
  - **Planning:** it gathers candidate tasks per hero, then a `PriorityEvaluator` ranks them with fuzzy logic (the fuzzylite library). **[src]**
  - **Inputs:** the evaluation context is a good catalogue of what a HoMM-like AI cares about. **[src]**
    - Cost: `movementCost`, `manaCost`, `goldCost`, `buildingCost`.
    - Risk: `danger`, `armyLossPersentage`, `enemyHeroDangerRatio`, `threat`, `threatTurns`, `fear`.
    - Reward: `armyReward`, `armyGrowth`, `goldReward`, `skillReward`, `strategicalValue`, `conquestValue`, `explorePriority`.
    - Context: `heroRole` (main army vs scout), `turn`, `armyInvolvement`, `closestWayRatio`, `isDefend`, and "gold pressure".
  - **Priority tiers:** INSTAKILL, INSTADEFEND, KILL, UPGRADE, HIGH_PRIO_EXPLORE, HUNTER_GATHER, LOW_PRIO_EXPLORE, FAR_KILL, FAR_HUNTER_GATHER, DEFEND. So exploration has two priority levels, and urgent defence beats everything. **[src]**
  - **Threat map:** a `DangerHitMapAnalyser` estimates which enemy heroes can reach each tile, how soon and with what strength. **[src]**
  - **Hero roles:** one main army hero, the rest scouts. **[src]**
  - **Fuzzy threat terms:** the legacy engine defines threat as LOW / MEDIUM / HIGH over a strength ratio centred on 1.0. **[src]**
- **VCMI development lessons:**
  - **Strong heroes on chores:** a breakthrough came from penalising strong heroes for visiting unguarded objects. Without that, the main army wasted turns on chores. **[src]**
  - **Army demand:** a goal matters more the more army it needs, and less the more army is missing (older VCAI). **[src]**
- **VCMI MMAI** is a machine-learned battle AI. It trained first against the scripted AI, then against older versions of itself, which is the same move as our hall of fame. **[src]**

### Civilization and Freeciv
- **Civilization IV flavours:**
  - Each leader carries `FLAVOR_*` weights (military, gold, science, culture, growth...), conventionally 2 low, 5 medium, 10 high. **[src]**
  - Each tech and building also has flavour values. The AI multiplies them by the leader's weights to bias choices. **[src]**
  - So personality is a weight vector over a shared criteria library: exactly our mask idea.
- **Civilization V grand strategies:**
  - Conquest, Culture, Diplomacy and Spaceship are the long-range goals. The leader's flavours make each one more or less likely to be adopted. **[src]**
  - **Hysteresis:** community tuning raised the minimum time a grand strategy stays active from 10 to 20 turns, to stop the AI flip-flopping. **[src]**
  - **Feasibility:** they also stopped the AI overvaluing culture when it had no realistic chance of winning that way. **[src]**
- **Freeciv:**
  - **Wants:** decisions are "wants", numeric desire scores, often capped. **[src]**
  - **Danger:** danger on a tile is the summed attack strength of potentially hostile units that can reach it. A bodyguard is wanted when danger meets the defence available. **[src]**
  - **Difficulty settings:** each level sets a handicap bitvector, a **fuzziness** value (0–1000, occasional deliberately flipped yes/no decisions), an expansionism percentage and a science cost multiplier. **[src]**
  - **Information handicaps:** handicaps such as `H_FOG` and `H_MAP` limit what the AI may know. **[mem]**
  - **Psychic danger fix:** a later fix (seen in a Civ modding note) stopped the AI reading danger in cities it could not see. **[src]**
  - **Parallel:** Freeciv's fuzziness is the closest analogue to our fuzz seed (A1Q4). Its information handicaps are what our visibility-filtered Game API (R7Q14) gives us for free.

### Battle for Wesnoth (RCA AI)
- **Candidate actions:** the RCA AI evaluates a list of candidate actions (combat, move-to-targets, villages, recruitment, retreat...) every step and runs the best scored. **[src]**
- **Aspects:** personality and difficulty are tunable data, called aspects. **[src]**
  - `aggression` (default 0.4): how much its own losses are discounted against damage dealt. At 0.4 it will attack at about 2:1 odds against it.
  - `caution` (default 0.25): retreat and grouping, and a max-risk value of 1 − caution.
  - `leader_value` (3) and `village_value` (1): target values.
  - `grouping`, `villages_per_scout`, `scout_village_targeting`, `support_villages`.
- **Phase schedules:** aspects can be limited to **turn ranges** (`turns=1-5,10`) or a **time of day**, the last match wins. This is a working, shipped example of state-conditioned weight schedules. **[src]**
- **Lessons:**
  - **Double-counted risk:** feeding `caution` into the attack rating as well made the AI "extremely reluctant to attack anything", per a code comment. **[src]**
  - **Passive defence:** `support_villages` is off by default because it "can make the AI sit around". **[src]**

### Endless Legend (Amplitude)
- **Weights per option:** the AI scores options with heuristic weights per option, with personality files in the game data. A community patch added debug displays of the research and negotiation weights. **[src]**
- **Reproducible choices:** the developers say the same conditions, as its heuristics evaluate them, give the same choices. **[src]**
- No public detail on the weight formulas was found. This is weak evidence, kept for completeness.

### RTS research: MicroRTS, StarCraft, Planet Wars
- **Evaluation functions:**
  - MicroRTS's built-in "Simple" evaluation sums friendly minus enemy unit cost, scaled by remaining HP share, plus carried resources, then squashes the result. **[src]**
  - Combat search work on StarCraft (SparCraft) uses **LTD / LTD2**, "life-time damage": sum over units of HP (or √HP) × damage per frame. It favours keeping high-damage units alive. **[mem]**
  - Both are cousins of our Value-based efficiency. Our `value_lost` is already pro-rated by members lost.
- **Fitness choices in GP-evolved bots:**
  - **StarCraft:** García-Sánchez et al. evolved StarCraft (Zerg) strategies. A **victory-based** fitness (victories first, then the game's final score as tiebreak, over 12 opponents in 3 tiers) beat a **report-based** fitness built from relative destruction, time to loss and relative economy. **[src]**
  - **Planet Wars:** Fernández-Ares et al. compared victory-based fitness with fitnesses built on resources gathered or units made. Victory-based gave better bots on average. **[src]** A related Planet Wars study reportedly found an area-based fitness (area under the strength curve over the match) competitive. **[src: secondary summary, abstract not read]**
  - **Joust selection:** one EvoApplications paper skipped fitness altogether and used head-to-head "jousts" as selection. **[src]**
- **Co-evolution:**
  - Miles and Louis co-evolved influence-map RTS players. Adhikari and Louis co-evolved micro, where an individual's fitness depends on opponents drawn from the other population. **[src]**
  - Co-evolved tactics generalise better to unseen opponents (Oberberger et al.). **[src]**
- **Parameter tuning under noise:** the N-Tuple Bandit EA (Lucas, Liu, Perez-Liebana) was built for noisy, expensive, discrete parameter spaces. It beat grid search and an EDA when tuning game agents (GVGAI, Planet Wars). **[src]** It is a cheap alternative or complement to a GA for low-dimensional genomes such as a mask plus a few schedule knots.
- **AlphaStar league** (not a GA, but the canonical diversity design): **[src]**
  - **Main agents** play everyone, weighted toward opponents they lose to (prioritised fictitious self-play).
  - **Main exploiters** play only the current main agents, to expose their weaknesses.
  - **League exploiters** hunt blind spots of the whole league.
  - Exploiters are periodically reset to keep diversity.

### Quality-diversity (play styles)
- **Tribes:** Pérez-Liébana et al. parameterised a portfolio MCTS agent for the turn-based strategy game Tribes. MAP-Elites then found diverse yet competitive play styles that held on unseen levels. **[src]**
- **How MAP-Elites works:** it keeps the best individual per cell of a grid of behaviour descriptors. **[src]**
  - **Descriptors:** GVGAI agent teams used outcome features (wins, score, % explored, interactions). **[src]**
  - **Sliding boundaries:** Hearthstone work slid cell boundaries so cells don't collapse into a few crowded behaviours. **[src]**
  - **Playtesting:** Rinascimento (Splendor) used the same maps to find degenerate strategies in the game design itself. **[src]**

## 2. How weights change over the game
- **Turn ranges and time of day** (Wesnoth aspects): the simplest form, purely clock-based. **[src]**
- **Long-range goal with hysteresis** (Civ V grand strategy, minimum 20 turns before re-evaluating): stops oscillation. **[src]**
- **Feasibility gating** (Civ V culture fix): drop a goal's weight when it can no longer be achieved. **[src]**
- **Threat-driven** (VCMI threat terms and DEFEND tiers, Freeciv danger): weights follow a strength ratio or reachability, not the clock. **[src]**
- **Triggered milestones** (HoMM3 Grail search starts once a share of the puzzle is revealed): a weight switches on at a state threshold. **[src]**
- **Role split** (VCMI main hero vs scouts): different criteria weights per actor, not just per phase. **[src]**
- **Opening scripts** (VCMI `StartupBehavior` on day 1): a scripted first turn before scoring takes over. **[src]**

## 3. How projects get difficulty and diversity
| Lever | Seen in | Fits Simple War? |
|---|---|---|
| Resource or science cheats | Freeciv science cost, HoMM Impossible, Civ bonuses | No: R1Q3 says difficulty comes from timers and opponent decisions |
| Information handicaps | Freeciv `H_FOG`/`H_MAP` [mem], the Civ psychic-danger fix | Already given: the Game API is visibility-filtered for every client (R7Q14) |
| Decision noise | Freeciv fuzziness | Yes: the fuzz seed and fuzz strength gene (A1Q4) |
| Behaviour throttles | HoMM Easy builds every other day, hero caps | Possible: as profile parameters, not hidden rules |
| Personality weight vectors | Civ IV flavours, HoMM3 personalities, Wesnoth aspects | Yes: masks (A1Q3) |
| Exploiters and league roles | AlphaStar | Partly: a few profile slots could be exploiters |
| Behaviour archive | MAP-Elites (Tribes, GVGAI, Hearthstone) | Yes: the source of curated "feels" (R7Q19) |

## 4. Pitfalls found
1. **Proxy fitness loses to outcome fitness.** In both StarCraft and Planet Wars GP work, fitness built from economy, units or destruction produced weaker bots than counting wins. Shaping terms help early but must not dominate selection.
2. **Specification gaming.** DeepMind and Krakovna's list collects agents that satisfy the letter of the objective. **[src]** Classic game cases **[mem]**:
   - looping to farm score pickups instead of finishing a race;
   - pausing Tetris forever to avoid losing.

   For us that means exploration loops, Value farmed off neutrals or civilians, and stalling or quitting to dodge a loss.
3. **Stalling.** Defensive criteria make AIs sit still: Wesnoth's `support_villages`, and our own `stalemate` trope. A turn-limit draw that scores like a half-win rewards turtling.
4. **Double-counted risk.** Feeding the same caution into several places makes the AI never attack (Wesnoth).
5. **Chores for the main army.** A strong unit spends turns on cheap objectives unless opportunity cost is priced in (VCMI).
6. **Flip-flopping goals.** Weights that change every turn oscillate. Needs hysteresis (Civ V).
7. **Infeasible goals.** The AI keeps chasing a goal it can no longer reach (Civ V culture).
8. **Co-evolution pathologies** (Watson and Pollack; Ficici and Pollack; the Bucci and Ficici tutorial): **[src]**
   - **cycling:** rock-paper-scissors loops, countered by a hall of fame (Rosin and Belew 1997);
   - **disengagement:** one side always wins, so no gradient remains; worse with asymmetric setups such as side 1 vs side 2 maps; remedy: substitution of the fittest;
   - **forgetting:** old skills are lost once nobody tests them;
   - **overspecialisation:** more likely with many objectives.
9. **Noisy, or too little noise.** Fitness from few matches is noisy. Our duel is currently deterministic per seed with no outcome variance (sw-884.5), so seeds alone don't sample anything.
10. **Perverse pressure incentives.** R4Q4 already untied Morale from damage to avoid these. A "pressure health" criterion would reward avoiding fights, unless it is set against pressure inflicted on the enemy.

## 5. What `SimMetrics` records today, and the gaps
- **Recorded today:**
  - Battles: `vp`, `value_destroyed`, `value_lost`, `units_lost`, `squads_lost`, `band.<pool>.<band>`, `surges/breaks/band_changes.<pool>`, `ledger.<pool>`, `first_break_tick`, `turns`, `first_contact_tick`, `first_casualty_tick`, `first_capture_turn`, `perf.*`. The report also gives the `winner`.
  - Overworld: `value`, `value_earned`, `hexes_explored`, `fog_revealed_pct`, `features_owned`, `commanders_alive`, `turns`, `battles`, `first_battle_turn`, `first_capture_turn`. The report also gives the `outcome` string.
- **Gaps for the factory:**
  - **G1 `result` per player:** win, draw, loss, forfeit (overworld gives only an outcome string per run).
  - **G2 Battle metrics inside overworld runs:** summed per player (GDD 05 §5.2 already lists this as "not yet").
  - **G3 Per-turn series:** a few metrics sampled every turn (own Value, visible enemy Value, features owned, hexes explored, VP), for area-under-curve criteria and for schedule conditions.
  - **G4 Per-player milestones:** first contact, first battle, first capture. Today they are per run.
  - **G5 Objective hold time:** zone-owned ticks per player in battles, feature-turns held per player on the overworld.
  - **G6 Value split by victim:** enemy player vs neutral garrison vs civilian/scripted forces, so neutrals can't be farmed.
  - **G7 Idle turns:** turns in which a player issued no order that changed anything, as a stall guard.
  - **G8 Forfeit and leave events:** quitting the game, kept apart from withdrawing a battleforce (`leave_battle`).
- **Decision-time forms:** a utility AI needs each criterion as a **state value** it can estimate from `observe()`, to score a candidate action by its predicted change. `SimMetrics` only gives the end-of-game form, so each criterion below names both.

## 6. Proposed criteria library v1
Fitness is what the GA selects on (per training run, with a schedule). The decision side is what a profile's utility process weighs (through its mask). Same library, two uses (see B1Q1).

**Outcome (fitness core, always on):**
| # | Criterion | End-of-game form (fitness) | Decision-time form | Source metrics |
|---|---|---|---|---|
| O1 | Result | win 1, draw 0, loss 0, forfeit −1 (B1Q3, B1Q4) | n/a (decisions use the criteria below) | report `winner`/`outcome`; **G1** |
| O2 | Speed | on a win: 1 − T_end / T_cap | n/a | `turns` (battle or overworld) |
| O3 | Margin | battle: (VP_own − VP_opp) / VP target, clamped to ±1; overworld: (Value_own − Value_opp) / (sum), tiebreak only | own VP lead, own Value lead | `vp`, `value` |

**Strategic criteria (decision weights; optional annealed shaping in fitness):**
| # | Criterion | End-of-game form | Decision-time form | Source metrics | Guard |
|---|---|---|---|---|---|
| S1 | Value efficiency | destroyed / (destroyed + lost) over all battles, weighted by volume; 0/0 = 0.5 | predicted exchange of a battle (forecast) | `value_destroyed`, `value_lost`; **G2, G6** | count only enemy-player Value; neutrals are a separate criterion or excluded |
| S2 | Force ratio | area under (own Value / (own + visible enemy Value)) per turn | own vs reachable enemy strength at the target (VCMI danger, Freeciv danger) | `value`; **G3** | ratio of what is visible only |
| S3 | Objective control | battle: zone-held ticks share plus VP; overworld: feature-turns held | Value of holding or capturing a zone or feature, minus travel cost | `vp`, `features_owned`, `first_capture_turn`; **G4, G5** | |
| S4 | Economy | `value_earned` (earned, not banked) | income change from a feature, discounted by turns to reach it | `value_earned`, `features_owned` | banked Value counts only in O3, so hoarding doesn't pay |
| S5 | Exploration | min(fog revealed / target %, 1) | new hexes revealed by a route | `hexes_explored`, `fog_revealed_pct` | saturates at the target; schedule gate (below) |
| S6 | Commander safety | commanders alive at the end / at the start | threat at a commander's hex vs its army (VCMI hit map) | `commanders_alive`; **G3** for threat | stronger in story rulesets (R2Q13) |
| S7 | Tempo / initiative | share of battles you started; your first capture turn vs the run's | turns until first contact or capture on this plan | `first_battle_turn`, `first_capture_turn`, `battles`; **G4** | low weight; also a schedule condition |
| S8 | Pressure differential | (enemy Morale Fraying+Broken share) − (own share) and enemy minus own Morale breaks | forecast pool vacuums of a planned engagement | `band.morale.*`, `breaks.morale` | always own **vs** enemy, never own alone (R4Q4) |

**Guards (fitness penalties, always on):**
| # | Guard | Form | Source |
|---|---|---|---|
| P1 | Forfeit | O1 = −1 (below a loss) | **G8** |
| P2 | Stall | a turn-limit draw scores as a loss for both sides (B1Q3); optional idle-turn penalty | `turns`, report; **G7** |
| P3 | Think budget | not a criterion: a hard per-decision time limit in the harness, so slow genomes don't win by thinking longer | `perf.*` |

**Proposed fitness formula** (B1Q2): F = O1 + 0.25·O2 (wins only) + 0.1·O3 + λ_g·Σ wᵢ(state)·Sᵢ. Shaping weight λ_g starts at 0.3 and decays to 0 over the first ~50 generations, or once the population beats the hall of fame more than 60% of the time.

**Schedule conditions** (B1Q6): each criterion's weight = base × Π gates. A gate is a piecewise-linear curve over one condition, with a minimum hold of k turns (hysteresis).
| Condition | From | Example gate |
|---|---|---|
| Overworld turn / battle turn | clock | Wesnoth-style ranges; the battle arc of R2Q1 (scout T1, main fight T3–5, rout T6+) |
| First contact made | **G4** / `first_contact_tick` | S5 Exploration ×1 before, decaying to ×0 over 3 turns after |
| Fog revealed % | `fog_revealed_pct` | S5 off above the target % |
| Force ratio | **G3** | S6 and S3-defend up when the ratio < 0.8; S1 risk-taking up when > 1.2 (VCMI threat terms) |
| Commander threatened | threat at a commander's hex | S6 overrides (an INSTADEFEND analogue) |
| Bank level | current Value | S4 down, spending up, when the bank is high (VCMI gold pressure) |
| Ahead / behind | O3 margin so far | when behind: S3/S7 up (comeback); when ahead: S6 up (close out); feasibility gating as in Civ V |

**Behaviour descriptors for diversity** (B1Q8): aggression = battles started per turn (or 1 / first battle turn); expansion = features owned × fog revealed; caution = Value lost / Value fielded. They are computed from the same metrics, so they cost nothing extra.

## Sources
- VCMI Nullkiller `PriorityEvaluator.h` (1.6.5): https://sources.debian.org/src/vcmi/1.6.5%2Bdfsg-2/AI/Nullkiller/Engine/PriorityEvaluator.h
- VCMI fuzzy engines (threat terms): https://sources.debian.org/src/vcmi/1.6.5%2Bdfsg-2/AI/Nullkiller/Engine/FuzzyEngines.cpp
- VCMI AI developer docs: https://vcmi.eu/developers/AI/
- VCMI forum, AI improvement threads: https://forum.vcmi.eu/t/ai-improvement/4604
- VCAI `FuzzyHelper.cpp` (older): https://sources.debian.org/src/vcmi/1.1.0%2Bdfsg-1/AI/VCAI/FuzzyHelper.cpp
- vcmi-gym / MMAI: https://smanolloff.github.io/projects/vcmi-gym and https://vcmi.eu/Mod%20Repository/AI/MMAI
- HoMM3 AI behaviour (Builder / Warrior / Explorer, difficulty): https://heroes3wog.net/homm-3-ai-behavior-builder-warrior-explorer
- HoMM3 wandering stacks and AI Value: https://heroes.thelazy.net/index.php/Wandering_stacks
- Freeciv AI docs (Longturn): https://longturn.readthedocs.io/en/latest/Coding/ai.html
- Freeciv `difficulty.c` (doxygen): https://files.freeciv.org/nightly/weekly/S3_2/doxygen/html/dd/d03/difficulty_8c.html
- Freeciv want-value patches: https://mirrors.sunsite.dk/osdn/ticket/g/f/fr/freeciv/47823/12557/0031-AI-Adjust-max-want-domestic-advisor-might-assign.patch
- Civ V grand strategies (modiki): https://modiki.civfanatics.com/index.php/CIV5AIGrandStrategies
- Civ V AI tuning changelog (grand strategy duration, culture feasibility): https://steamcommunity.com/sharedfiles/filedetails/changelog/312060464?p=2
- Civ IV leader flavours: https://modiki.civfanatics.com/index.php/Civ4LeaderHeadInfos and https://forums.civfanatics.com/threads/what-does-flavors-mean.283758
- Wesnoth RCA AI: https://wiki.wesnoth.org/RCA_AI ; aspects: https://wiki.wesnoth.org/AiWML ; `ca.cpp`: https://devdocs.wesnoth.org/ca_8cpp_source.html
- Endless Legend AI weights (community patch thread): https://community.amplitude-studios.com/amplitude-studios/endless-legend/forums/15-modding/threads/30618-endless-legend-community-patch?page=12
- García-Sánchez et al., StarCraft strategy generation with GP: https://human-competitive.org/sites/default/files/garcia-sanchez-merelo-mora-squillero-tonda-paper.pdf
- Fernández-Ares et al. 2017, fitness function influence (Planet Wars): https://gpbib.cs.ucl.ac.uk/gp-html/FernandezAres_2017_EC.html
- Co-evolving RTS micro (Adhikari, Louis): https://ar5iv.arxiv.org/html/1803.10314 ; Oberberger et al. CEC 2011: https://www.cse.unr.edu/~moberberger/oberberger_et_al_cec2011.pdf
- Experiments with game tree search in RTS (MicroRTS evaluation): https://arxiv.org/pdf/1208.1940 ; Lanchester-based prediction (Stanescu, Barriga, Buro): https://ojs.aaai.org/index.php/AIIDE/article/download/12780/12628
- NTBEA: https://ar5iv.labs.arxiv.org/html/1802.05991
- AlphaStar: https://deepmind.google/research/breakthroughs/alphastar/ ; league summary in TStarBot-X: https://arxiv.org/pdf/2011.13729
- MAP-Elites play styles in Tribes: https://arxiv.org/abs/2104.08641
- Co-evolution pathologies, substitution of the fittest: https://arxiv.org/pdf/2108.03156 ; Bucci and Ficici GECCO 2006 tutorial: https://gpbib.cs.ucl.ac.uk/gecco2006etc/papers/tut124.pdf
- Specification gaming (DeepMind): https://deepmind.google/discover/blog/specification-gaming-the-flip-side-of-ai-ingenuity/
