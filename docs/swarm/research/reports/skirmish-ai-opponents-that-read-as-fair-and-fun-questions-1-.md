# Skirmish AI opponents that read as fair and fun
Date: 2026-11-21. Requested by: games-researcher.

## Questions
1. How do Into the Breach, Advance Wars/Wargroove, Battle for Wesnoth, Frozen Synapse and Total War make AI behaviour legible — difficulty via handicaps vs smarter play, personalities, telegraphed styles?
2. What do players praise or complain about in skirmish AI (fairness, cheating, predictability, cheese)?
3. Which patterns fit a deterministic WeGo sim with controller profiles and an evolution factory, and what should a default skirmish profile expose to the player?

## Short answer (5 lines)
- Fairness reads as "same rules, same information, visible intent": the praised games keep the AI on the player's ruleset and make its next action or style readable.
- Difficulty knobs that read as fair: decision quality (how often the best move is picked), scenario/spawn composition, timers, and *disclosed* economic handicaps — not hidden stat buffs.
- Personality comes from a few named, bounded parameters (Wesnoth's aggression/caution, Advance Wars' CO identity), not secret rule changes.
- Top complaints: AI ignoring fog/rules, unexplained stat bonuses, and exploitable blind spots (ignored objectives, repeated loops). "Stupid" does not read as fair either.
- For Simple War: expose profile name/feel + a few dials + any handicap + seed; telegraph intent at reveal; let the factory evolve decision weights while rules stay symmetric.

## Findings

### Q1 — How five games make AI legible

**Into the Breach (Subset Games).** All enemy attacks are telegraphed, there is no hit/miss chance, and resolution during the player turn is completely deterministic ([GDC 2019 postmortem slides](https://media.gdcvault.com/gdc2019/presentations/Into%20the%20Breach%20Postmortem%20Final.pdf), snippet). Matthew Davis's [AI write-up](https://archive.org/details/into-the-breach-ai) (full text read) describes a deliberately "bordering on dumb" AI: enumerate every move+target, score hits (typically +5 per enemy unit, +5 per building, −2 per friendly hit), drop negative-location moves (danger, map edges), and pick randomly among the best. Crucially, **difficulty is the frequency of picking the optimal vs second-best option** ("having the 'optimal' choice picked more often on harder difficulties"). The AI never plans ahead, never coordinates attacks, and ignores the player's loadout. Real difficulty lives in handmade maps and **spawn management** — one extra spawned unit can flip a puzzle from solvable to unsolvable, and spawns adapt to keep each turn interesting. Davis notes players routinely assume the AI is doing far more than it is.

**Battle for Wesnoth (open source).** The default RCA AI is configured entirely as data: [AiWML aspects](https://wiki.wesnoth.org/AiWML) (full read) with concrete defaults — `aggression=0.4` (scales all negative attack-score terms by `1−aggression`; 1 = ignores own losses, 0 = values own units equally), `caution=0.25` (retreat when `caution × enemy_power > own_power`, i.e. enemy 4× stronger at default; group-advance when `own/their > 0.5 + caution`), `leader_aggression=-4.0`, `grouping=offensive`, `villages_per_scout=4`, `retreat_factor=0.25`. Aspects can be **scheduled by time of day or turn range**, so style shifts are predictable and readable. Difficulty is economic, not statistical: a [Steam discussion](https://steamcommunity.com/app/599390/discussions/0/3802776070756068823/) (full read) ranks the levers gold > income > enemy recruit list > turn limit > items, with a community rule of thumb of ~25% gold/income per difficulty step. Because the game is open source, every AI decision is inspectable — the extreme of pillar-2 transparency.

**Advance Wars / Wargroove.** Personality is carried by the commander: CO Zones and CO Powers give each AI opponent a visible, named style, and players report CO-specific build tendencies (e.g. Isabella "LOVES spamming mechs and Md Tanks"; [GameFAQs DoR thread](https://gamefaqs.gamespot.com/boards/943675-advance-wars-days-of-ruin/57272493), full read — anecdotal). A veteran in that thread claims earlier AW games had "specific coded strategies for the COs" (unverified). Fog of war is the flashpoint: Days of Ruin's AI reportedly respects FoW, while Wargroove's ignores it and never uses transports ([Steam thread](https://steamcommunity.com/app/607050/discussions/0/1778261844039609181/), full read). Difficulty is mostly scenario composition; on balanced skirmish maps the AI is reported trivially exploitable ([r/wargroove](https://www.reddit.com/r/wargroove/comments/assnbe/the_ai_of_war_wargroove/), snippet).

**Frozen Synapse (Mode 7).** The closest structural analogue to Simple War: simultaneous plan-then-execute, no dice, "total player control over what transpires" ([Double Eleven's Prime retrospective](https://www.gamedeveloper.com/business/frozen-synapse-prime-our-recreation-and-some-of-the-challenges), full read). The AI works on the same logical map representation the simulation uses, and players can test plans against predicted enemy behaviour — fairness comes from **symmetric information and rules**, not handicaps. The [postmortem](https://www.gamedeveloper.com/audio/postmortem-mode-7-games-i-frozen-synapse-i-) (full read) says the single-player lesson was "all we actually needed to do was make a fun AI and then create a linear series of levels around it", and praises the heavily parameterised Skirmish Generator. Its warning: because plans can be tested perfectly, players feel they *should* have predicted everything — a constant pressure that turns frustration.

**Total War (Creative Assembly).** Difficulty is handicaps, split into campaign and battle. A [GamersDecide guide](https://www.gamersdecide.com/articles/total-war-warhammer-3-difficulty-levels-explained) (full read) lists WH3 numbers: campaign player line-of-sight 120/100/70/40/0% across Easy→Legendary, public order +1/0/−2/−4/−8, AI replenishment +14% (VH) / +16% (Legendary); battle morale Easy AI −4/player +4, Medium 0/0, Hard AI +2/player −4, Very Hard AI +4/player −8. Community sources dispute the "AI gets smarter" framing: a [TWCenter thread](https://www.twcenter.net/threads/clarification-on-ai-difficulty-levels.815781/) (snippet) says M2TW's battle AI is identical at all difficulties, only stats change (+2 attack/defense/morale Hard, +5 VH). WH3 later **separated the knobs**: a behaviour "Difficulty" setting and an independent "AI Stats Modifiers" slider ([Steam](https://steamcommunity.com/app/1142710/discussions/0/5796774642235112803/), [1d6chan](https://1d6chan.miraheze.org/wiki/Total_War_Warhammer/Tactics), snippets) — an explicit admission that buffing stats and improving play are different axes.

### Q2 — What players praise and complain about

**Praised:** telegraphed, deterministic threats (ITB's whole reputation; [postmortem](https://www.gdcvault.com/play/1025772/-Into-the-Breach-Design)); symmetric rules and depth "from situations and scenarios, not from throwing more units at you" ([r/Games on FS](https://www.reddit.com/r/Games/comments/ow6rz/postmortem_mode_7_games_frozen_synapse/), snippet); inspectable, data-driven AI (Wesnoth); an AI that respects fog like a player (DoR, per the Wargroove thread).

**Complained about:**
- *Hidden information cheats.* Wargroove AI attacking out of fog: "Acting stupid is not the same as playing by the rules. Would anyone play a chess game where the computer opponent was allowed to move a piece 1 extra space every other turn…?" ([Steam](https://steamcommunity.com/app/607050/discussions/0/1778261844039609181/)). The thread also notes fog "is just to cripple you not them" as a genre-wide grievance.
- *Hidden stat cheats.* WH3 players can see +6/+12 leadership on Hard/VH but suspect more: "Is this under the hood stuff, and we cant see what it is" ([Steam](https://steamcommunity.com/app/1142710/discussions/0/3185737967878386431/), snippet). Others explicitly want difficulty to improve the AI, "not a fan of harder settings just resulting in harder to kill/harder hitting units" ([Steam](https://steamcommunity.com/app/1142710/discussions/0/5796774642235112803/), snippet).
- *Cheese and predictability.* Wargroove skirmish: keep the AI busy while capturing every village it ignores; ~4:1 trade ratios; AI "ridiculously lazy" with its commander and fixated on yours ([r/wargroove](https://www.reddit.com/r/wargroove/comments/assnbe/the_ai_of_war_wargroove/), [GameFAQs](https://gamefaqs.gamespot.com/boards/206488-wargroove/77466295), snippets). ITB's Davis pre-empted the equivalent: enemies negatively weight repeated positions/targets so they don't bounce back into the same attack loop.
- *Perfection pressure.* FS's testable plans make every loss feel like a personal failure (postmortem, "Determinism and Difficulties").
- *Undocumented difficulty differences.* Wesnoth players found scenario-specific changes (extra units, terrain) "not mentioned in the campaign description at all" ([Steam](https://steamcommunity.com/app/599390/discussions/0/3802776070756068823/)) — even benign handicaps breed distrust when undisclosed.

### Q3 — Patterns that fit Simple War's deterministic WeGo + factory

- **Wesnoth aspects ≈ controller genomes.** Bounded, named, data-only parameters with documented semantics map one-to-one onto GDD 05's utility parameters and masks. Their formulas (retreat threshold, group-advance odds ratio) are good templates for readable battle-profile params.
- **ITB's optimality frequency ≈ the fuzz gene.** Difficulty as "how often the best-scoring order is chosen" is exactly a deterministic decision-noise strength — already a gene in the factory (A1Q4). This raises difficulty without touching rules or stats.
- **ITB's spawn/map management ≈ skirmish setup.** Army composition and map layout are the strongest difficulty levers; the painted-map MVP already owns them.
- **FS's symmetric planning ≈ sw-ip8.6.** The AI already plans from the same state the player sees, once per phase — keep it that way; the AI must not react to the player's *submitted* plan beyond what the reveal/react rules allow everyone.
- **TW's split sliders ≈ separate "behaviour difficulty" from any handicap**, and disclose both. Pillar 2 permits handicaps only if the displayed calculation is the real one.
- **Masks are fine internally, never as hidden rules.** A mask changes what the AI *thinks it is scored on* (A1Q3) — that is personality, not cheating, as long as the AI's orders still obey the same simulation and the player can see why an order happened.

## Relevance to Simple War
- **GDD 01, pillar 2 (R1Q3/R1Q7):** difficulty from timers and opponents' decisions, never hidden rule information. ITB and Wesnoth are the proof cases; Wargroove/TW are the cautionary tales. The MVP skirmish setup (map, seed, opponent profile) is exactly where disclosure lives.
- **GDD 01, pillar 3:** "conditions, not vague labels" — a profile should say what it does ("attacks at even odds; reinforces strongest-first") rather than only "Hard".
- **GDD 05, Controller profiles (R7Q15) and Shipped AIs (R7Q19):** curated factory outputs "labelled by difficulty and feel (for example Aggressor, Turtle, Opportunist)" with recorded lineage — the research says that label must be backed by visible behaviour and disclosed parameters.
- **GDD 05, Masks (A1Q3), fuzz (A1Q4), MAP-Elites (aggression × expansion, 5×5):** the factory already evolves the two axes players most want to read (aggression, expansion). Surface those archive axes as the profile's public dials.
- **GDD 05, think-time limit and forfeits:** a legitimate, disclosed difficulty lever (faster pulses, less think time) consistent with pillar 2's timers.

## Options and recommendations (ranked by value to the skirmish MVP)
1. **Profile card with disclosed dials (do first).** Name + feel label, 2–3 readable parameters (aggression, caution, expansion — mirroring the factory's MAP-Elites axes), handicap line ("none" or exact numbers), fuzz seed, think-time. Curated profiles read-only; custom profiles editable (pillar 5). Trade-off: exposes tuning knobs; mitigate by showing behaviour sentences, not raw weights, at low verbosity.
2. **Intent telegraph at reveal (ITB pattern).** Show each AI order's target and computed outcome using the real calculation, as the rules allow. Highest pillar-2 payoff; cost is UI work in the war room. Trade-off: perfect information raises FS-style perfection pressure — keep timers and Prowess reactions as the tension source instead of secrecy.
3. **Difficulty ladder = optimality/fuzz + timers + composition, no stat buffs by default.** Easy picks more second-best orders; Hard picks optimal more often and reinforces smarter; army composition and map do the rest. Trade-off: needs playtest tuning; factory fitness must not reward profiles that only win via handicaps.
4. **Anti-cheese guardrails in curated defaults.** Objective/capture awareness (Wargroove's village blindness), negative weight on repeated positions/targets (ITB), bounded commander fixation. Trade-off: more parameters to evolve; hard-code guardrails in shipped profiles rather than hoping evolution finds them.
5. **Optional, fully disclosed handicap slider, separate from behaviour difficulty (TW WH3 pattern).** Only if playtests show decision-quality alone can't span the skill range; every bonus must appear in the displayed calculation. Trade-off: even disclosed buffs read as "cheating" to part of the audience — keep it off by default.
6. **Phase-scheduled style shifts (Wesnoth time_of_day pattern).** E.g. a profile that turtles until a pressure threshold, then attacks — announced as a stance change so it reads as personality, not randomness. The genome's mask schedule already supports this; trade-off is legibility cost if shifts are too frequent.

## Sources
1. https://archive.org/details/into-the-breach-ai — Matthew Davis's ITB AI/difficulty write-up (full text read; primary, community-archived AMA doc).
2. https://media.gdcvault.com/gdc2019/presentations/Into%20the%20Breach%20Postmortem%20Final.pdf — GDC 2019 postmortem slides (snippet only: telegraphed attacks, deterministic).
3. https://wiki.wesnoth.org/AiWML — Wesnoth RCA AI aspects with defaults and formulas (full read; primary).
4. https://steamcommunity.com/app/599390/discussions/0/3802776070756068823/ — Wesnoth difficulty levers, ~25% rule of thumb, undisclosed-differences complaint (full read).
5. https://www.gamedeveloper.com/audio/postmortem-mode-7-games-i-frozen-synapse-i- — Frozen Synapse postmortem, Paul Taylor (full read; primary).
6. https://www.gamedeveloper.com/business/frozen-synapse-prime-our-recreation-and-some-of-the-challenges — Double Eleven on FS Prime: no dice, AI's logical map representation (full read; primary).
7. https://steamcommunity.com/app/607050/discussions/0/1778261844039609181/ — Wargroove "Tell the AI to stop cheating!" FoW thread (full read).
8. https://gamefaqs.gamespot.com/boards/943675-advance-wars-days-of-ruin/57272493 — AW:DoR CO AI difficulty thread; CO build tendencies, FoW claims (full read; anecdotal).
9. https://www.gamersdecide.com/articles/total-war-warhammer-3-difficulty-levels-explained — WH3 campaign/battle difficulty numbers (full read; secondary, patch-sensitive).
10. https://www.twcenter.net/threads/clarification-on-ai-difficulty-levels.815781/ — M2TW battle AI unchanged by difficulty, +2/+5 stats (snippet).
11. https://steamcommunity.com/app/1142710/discussions/0/3185737967878386431/ — WH3 Hard/VH leadership bonuses, "under the hood" complaint (snippet).
12. https://steamcommunity.com/app/1142710/discussions/0/5796774642235112803/ — WH3 difficulty vs AI stats modifier slider; player preference for smarter AI (snippet).
13. https://1d6chan.miraheze.org/wiki/Total_War_Warhammer/Tactics — WH3 behaviour/stat split, auto-resolve criticism (snippet).
14. https://www.reddit.com/r/totalwar/comments/sk33el/ — WH3 VH battle ~+10% melee damage/reload, half WH2 legendary (snippet; fetch blocked).
15. https://www.reddit.com/r/wargroove/comments/assnbe/ — Wargroove skirmish trivially exploitable, villages ignored (snippet).
16. https://www.reddit.com/r/wargroove/comments/aom9xx/ — Wargroove AI ignores FoW, campaign unfairness (snippet).
17. https://gamefaqs.gamespot.com/boards/206488-wargroove/77466295 — Wargroove ~4:1 trades, commander fixation (snippet).
18. https://www.reddit.com/r/Games/comments/ow6rz/ — FS praise: depth from situations, not unit count (snippet).
19. https://www.reddit.com/r/Advance_Wars/comments/55ufr1/ — AW AI perceived quality across entries (snippet).

## Confidence and gaps
- **High:** ITB, Wesnoth, FS mechanics — primary sources read in full.
- **Medium:** Total War numbers. Sources conflict (guide says battle Hard AI +2 morale; a Steam thread says +6 leadership; Reddit says ~+10% melee on VH) — likely patch/version differences. Treat exact values as illustrative, not canonical; the *pattern* (handicaps, later split into behaviour vs stats) is corroborated by four sources.
- **Low:** AW CO-specific coded AI strategies (one forum claim, unverified); DoR respecting FoW (forum consensus, no primary source). Wargroove developer responses were not found; complaints stand as player perception.
- Reddit full pages could not be fetched (blocked); items 14–19 are search-snippet only. GDC video/PDF not directly readable beyond the slide snippet. No source found measuring how disclosure itself changes perceived fairness — that would need our own playtests.
