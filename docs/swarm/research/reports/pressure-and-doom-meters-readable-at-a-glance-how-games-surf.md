# Pressure and doom meters readable at a glance: how games surface accumulating pressure, stress and doom

Date: 2026-11-21 (UTC). Requested by: games-researcher. Prep for GDD Open topic 5 (Legend deep dive); this report prepares options and decides nothing.

## Questions

1. How do Darkest Dungeon (stress), Frostpunk (hope/discontent), XCOM 2 (Avatar project), Into the Breach (threat tiles), Battle Brothers (morale) and This War of Mine (sadness) display accumulating pressure — granularity, named states, thresholds, visible triggers, concrete numbers?
2. What did players praise as readable and criticise as opaque, with sources?
3. Which UI patterns say "one bad hit from breaking" without vague labels, and which forecast/threshold displays let players plan around the meter?

## Short answer (5 lines)

- The most readable systems use **discrete named states with icons** (Battle Brothers' five morale flags) or **countable pips with a marked threshold** (DD1's 100-stress line, XCOM 2's 12 blocks), not bare percentages.
- Battle Brothers' devs explicitly reworked morale *from* an abstract number *to* named states so players can "see at a glance how everyone is doing" and act before someone breaks — the closest documented precedent for Simple War's pillar 3.
- Players praise meters whose **causes are visible and countable** (XCOM facility pips, Frostpunk complaint modifiers) and criticise **vague magnitude words** ("slight/major change"), **hidden accumulators** (TWoM sympathy) and **opaque relational triggers** (DD2 relationships).
- The best planning aids are **forecasts of the future state** (Into the Breach's telegraphed attacks) and **grace-period countdowns after a threshold** (Frostpunk's ultimatum, XCOM's doom clock), which turn "about to break" into a solvable puzzle instead of a surprise.
- For Legend: band-first display + threshold ticks + pending-flow forecast + a source-tagged ledger tooltip map directly onto SIMPL's existing contract; a doom-clock-style consequence window is the main open option for the user.

## Findings

### Q1. How six titles display accumulating pressure

**Darkest Dungeon 1 — per hero, 0–200 bar with a marked threshold at 100.** Stress is a gauge from 0 to 200; crossing 100 forces a resolve test: usually an Affliction (named state with stat penalties and disobedience), rarely a Virtue (buff; stress resets to 40–45). At 200, a heart attack drops HP to 0 (Death's Door) or kills, and stress falls to 170 ([1], [2]). Triggers are concrete events: enemy crits and stress attacks, witnessing an ally hit Death's Door or die, traps, hunger, walking backwards; the light meter scales stress gained. Stress persists between missions (capped at 100 in town); idle heroes recover 5/week (15 with the Puppet Theatre); kills/crits heal ~3, disarming a trap heals 8 ([1]). The numeric value and the 100-mark are both visible, so "how far to the resolve test" is always countable.

**Darkest Dungeon 2 — per hero, 0–10 pips with behaviour tiers.** Stress is ten pips. 0–3: no negative banter; 4–6: some; 7–9: 90% negative banter (which itself spreads stress and erodes affinity). At 10: 80% base chance of Meltdown (HP set to 10%, −15% deathblow resist, −3 affinity with every ally, 40% chance of a negative quirk) or 20% Resolute (heal 67% HP, +2 affinity); the Flagellant instead goes Toxic ([3]). Relationships are separate pairwise affinity pips. The pip count makes "one hit from meltdown" literally countable, but the *triggers* of affinity change are much less legible (see Q2).

**Frostpunk — per city, two opposed 0–100% meters.** Hope (belief in survival) and Discontent (willingness to tolerate the captain) sit permanently on the HUD ([4], [5]). Hope 0% or Discontent 100% triggers an ultimatum: roughly two days to reverse course or exile/deposition ([4], [6]). A community-documented emergency rule fires on a >15% swing within two days even away from the extremes, with a shorter deadline ([4]; corroborated by [6]). Causes are split into **permanent modifiers** (laws, buildings, Purpose path) and **temporary ones** (kept/broken promises, events, ceremonies); Discontent is effectively the sum of active unmet-need complaints, each removable by fixing the need ([4]). Hope is asymmetric: small gradual gains, large chunk losses (a mass-death night can erase a week of gains) ([4]). Wikipedia notes hope was added after the team identified it as the essential survival driver — discontent alone wasn't enough ([7]).

**XCOM 2 — global campaign doom meter, 12 countable pips.** The Avatar Project is a red gauge on the geoscape made of 12 blocks that fill black→red as ADVENT builds facilities and completes dark events ([8], [9]). Each facility shows how many pips it contributes; assaulting it removes them (1–2), and story missions also reduce progress ([8], [10]). When all 12 fill, a **doom countdown** starts instead of instant loss; reducing progress below full stops/resets it. Countdown length varies by source and difficulty: 7–28 days ([11]), 21 days default ([10]), ~20 days ([12]) — treat the exact number as difficulty-dependent and not pinned down here. The Long War 2 mod deliberately *hides* the meter until discovered and raises it to 20 pips ([13]) — opacity used as a difficulty lever.

**Into the Breach — per tile, forecast instead of meter.** There is no accumulating stress bar; pressure is surfaced as **enemy intent**: each Vek's next-turn attack is telegraphed on the exact tiles it will hit, so the player solves a perfect-information puzzle ([14], [15], [16]). The GDC 2019 postmortem frames this as information design: "make future consequences legible" and use randomness "to create situations, not verdicts" ([15], [16]). A global grid-power bar acts as the campaign's doom meter (buildings lost drain it; zero ends the run) — widely documented, but not verified in the sources fetched for this report (see Confidence).

**Battle Brothers — per character, five named states shown as flags.** The devs replaced an earlier "large abstract number changing every turn" with five discrete states: Confident (+1, hit/defense bonus), Steady (0), Wavering (−1, slight debuff and worse future checks), Breaking (−2, significant debuff, likely to flee on the next failed check), Fleeing (−3, no actions, moves away, can rally back to Wavering) ([17]). Undead add a sixth, Unbreakable ([18]). Confident is documented as +10% attack and defense ([19]). States change on **morale checks against the Bravery attribute**, triggered by visible events: an ally slain (negative; harder if the dead was powerful and nearby), an enemy slain (positive; a chieftain's death lifts everyone), heavy wounds ([17]). Mood on the campaign layer sets starting morale and drifts toward Content daily ([20]).

**This War of Mine — per character, a named mood ladder.** Content → Sad → Depressed → Broken ([21], [22]). Sad: slower, less responsive. Depressed: stops mid-task to complain, moves lethargically. Broken: cannot act at all, even for self-preservation, and must be attended to by other survivors ([22]). Triggers are moral events: killing, witnessing trauma, crimes, neighbour events ([21]). Crucially, the underlying **sympathy/personality system has no visible measures or stats** — it is inferred from bio comments and dialogue ([23]).

### Q2. What players praised as readable, criticised as opaque

**Praised:**
- Battle Brothers' state flags: the dev blog's stated goal was a system "easy to read and utilize", with a clear continuum of descriptive states so players can act *before* a brother breaks and understand *why* anyone flees ([17]). Community explanations trace exact chains (steady → wavering → breaking → fleeing from specific events), which is only possible because triggers are visible ([24]).
- XCOM 2's countable pips: players describe deliberately "riding" the doom timer — letting it fill, then knocking pips off to reset the countdown — a strategy that requires the meter and per-facility pip values to be legible ([12], [10]).
- Frostpunk's complaint-driven Discontent: fixing a specific need visibly removes its modifier; guides teach triage by reading the active complaints ([4]).

**Criticised:**
- Frostpunk's vague magnitude feedback: a Steam thread asks for exact values because the game "just says 'slight/major/etc' change", and players only learn the real stakes (the 15%-in-2-days rule) at the crisis moment ([6]).
- XCOM 2's timer opacity: threads titled "Can someone explain the Avatar timer to me?" document confusion about reset rules and a patch bug that hid blacksite pip values ([10]); the countdown's existence surprises players who expected instant loss at full pips ([11], [12]).
- DD2's relationships: Steam and Reddit threads ("Relationship system is awful", "Why is the relationship system so awful?") complain that affinity triggers are unpredictable, negative changes outweigh positive ones, and meltdowns domino the whole party; players explicitly contrast it with DD1's "more balanced and manageable" stress ([25], [26]).
- This War of Mine's hidden sympathy: the wiki itself says "little is understood about the full effects" of morale and that sympathy "displays no visible measures or stats" ([21], [23]); players report broken characters as hard to diagnose and recover ([27]).

Pattern: praise tracks **visible causes + countable distance to threshold**; criticism tracks **hidden accumulators, vague words, and asymmetric/opaque triggers** — not the existence of pressure itself.

### Q3. UI patterns for "one bad hit from breaking" and for planning

1. **Named states with icons, defined consequences** (BB flags, TWoM mood words, DD2 pips). Glanceable across many units; each state maps to exact mechanics. BB is the strongest precedent: discrete states were chosen *over* a continuous number for legibility ([17]).
2. **Segmented bars / pips with a marked threshold** (DD1's 100-line, XCOM's 12 blocks, DD2's 10 pips). Distance to disaster becomes countable ("2 pips from meltdown"); pairing the segment with the numeric value supports both glance and precision.
3. **Forecast of the future state** (ITB threat tiles; Frostpunk promise timers and weather). Showing what *will* happen lets players plan; ITB's whole design is built on it ([14], [15]). Deterministic rules make this cheap to compute exactly.
4. **Grace-period countdown after crossing** (Frostpunk ultimatum ~2 days, XCOM doom clock, BB's rally chance from Fleeing, DD1's Death's Door). Crossing the line starts a visible recovery window instead of instant failure — pressure becomes a timed puzzle.
5. **Source-tagged modifier lists** (Frostpunk permanent vs temporary modifiers; DD's enumerable stress sources). Every change shows cause and amount; this is the fix for the "slight/major" complaint ([4], [6]).
6. **Per-source contribution display** (XCOM facility pips). Players can compute which action removes how much pressure — planning, not guessing ([10]).

Anti-patterns to avoid: hidden accumulators (TWoM sympathy), vague magnitude words (Frostpunk events), opaque pairwise triggers (DD2), and hiding the meter entirely (LW2) — the last is a legitimate difficulty choice elsewhere but contradicts Simple War's transparency pillar.

## Relevance to Simple War

- **Pillar 2 (transparent deterministic rules)** and **pillar 3 ("conditions, not vague labels", the game literally says "one bad hit from breaking")** (GDD 01, Pillars) align exactly with what players praised: countable distance + visible causes. The findings argue for showing the *distance to Break/Surge in pool points* plus the *pending flows*, not just the band name.
- **Rules Spec §2.8** already defines the vocabulary: five bands (Surging 90–100 … Broken <15), Float/Sink verbs, pending sinks shown as **Vacuum** in forecasts, **Surge/Break** crossings, drift toward Neutral, and a source-tagged per-battle **ledger** (R6Q3). Patterns 2, 3 and 5 above map one-to-one onto these: band ticks on a segmented meter, Vacuum forecast in the planning UI, ledger entries as the modifier list.
- **Pillar 1 (parallel play)** raises the stakes on glanceability: with several battles on one clock, per-squad meters must aggregate into something a Commander can scan (BB's flags-at-a-glance goal is the precedent; XCOM's single global gauge is the opposite extreme).
- **Legend (pillar 4, fraying reality; Open topic 5)** is where the doom-meter patterns are most relevant: XCOM's fill-then-countdown and Frostpunk's ultimatum are both models for "Legend crossed a threshold → a visible window before a legendary/fraying consequence". Whether Legend should have such a window, and what fills it, are design questions for the user's interview — this report only supplies the patterns.
- Accessibility (GDD 01: never colour alone) favours BB-style icons + words over colour-only bars; DD2's pip tiers show how behaviour tiers can be tied to numeric ranges without vague labels.

## Options and recommendations (for the Legend interview; none decided here)

- **A. Band-first display (BB model).** Each pool shows its named band + icon; exact % and distance-to-threshold on hover/verbosity. Trade-off: alone it hides "how close to the edge", which pillar 3 wants explicit; pair with B.
- **B. Segmented meter with threshold ticks (DD1/XCOM model).** Five band segments, ticks at 15/40/65/90, numeric value at chosen verbosity; "one bad hit" computed as forecasted incoming Float vs points to 15%. Trade-off: five pools × many squads × parallel battles is a lot of bars; needs an aggregated scan view.
- **C. Forecast-first planning (ITB model).** Planning UI shows pending Vacuum/Float and the resulting band before orders commit. Trade-off: more UI surface, but determinism makes the forecast exact — this is Simple War's home advantage.
- **D. Consequence countdown for Legend (Frostpunk/XCOM model).** A Legend Break/Surge starts a visible timer or pip-track toward a fraying/legendary event, recoverable by player action. Trade-off: adds timer pressure and new balance surface; fits WeGo pulses but the semantics are the user's to settle.
- **E. Ledger tooltips (Frostpunk modifiers done right).** Every pool change lists source + amount from the existing ledger; verbosity slider already promised by pillar 2. Trade-off: density; default verbosity must be chosen.

Recommendation: A+B+C+E compose cleanly with the existing SIMPL contract and are reversible UI choices; D is the genuinely new design option to put to the user for Legend. Avoid hidden accumulators and vague magnitude words in all variants.

## Sources

1. https://darkestdungeon.wiki.gg/wiki/Stress_(Darkest_Dungeon) — official wiki: 0–200 gauge, 100 threshold, heart attack at 200, relief numbers (fetched).
2. https://darkestdungeon.wiki.gg/wiki/Heart_attack — heart attack effects, stress reset to 170 (search preview).
3. https://darkestdungeon.wiki.gg/wiki/Stress_(Darkest_Dungeon_II) — official wiki: 0–10 pips, banter tiers, Meltdown/Resolute/Toxic numbers (fetched).
4. https://eatcreatesleep.net/how-hope-and-discontent-actually-work-in-frostpunk/ — community guide: 0–100 scale, ultimatums, 15%-in-2-days rule, modifier taxonomy (fetched; single guide for some numbers).
5. https://www.gamepressure.com/frostpunk/what-happens-when-discontent-or-hope-reach-critical-values/zfad7c — laws/buildings affect the meters (search preview).
6. https://steamcommunity.com/app/323190/discussions/0/2266943550311885540/ — player complaint: "slight/major" feedback, 15%/2-day crisis rule (search preview).
7. https://en.wikipedia.org/wiki/Frostpunk — design intent of hope vs discontent meters (search preview).
8. https://xcom2.wiki.fextralife.com/Avatar_Project — geoscape gauge, countdown, facility removal (fetched).
9. https://gamesfuze.com/how-to/xcom-2-how-to-reduce-avatar-project-levels/ — 12 blocks, black→red fill (search preview).
10. https://steamcommunity.com/app/268500/discussions/0/412446890554267906/ — 21-day doom counter, reset behaviour, per-facility pips (search preview).
11. https://totalgaming.blog/xcom-2-avatar-project-finishes-consequences — 7–28 day countdown by difficulty (search preview; single source for the range).
12. https://www.reddit.com/r/Xcom/comments/44rs7y/what_is_the_exact_lose_condition_for_the_game/ — "riding" the doom timer strategy (search preview).
13. https://www.ufopaedia.org/index.php/AVATAR_Project_(LW2) — LW2 hides the meter, 20 pips (search preview).
14. https://hayao.dev/docs/codex/anchor-into-the-breach — enemy intent telegraphed per tile, perfect information (search preview).
15. https://www.gdcvault.com/play/1025772/-Into-the-Breach-Design — official GDC 2019 postmortem page, Matthew Davis (search preview; PDF slides not fetchable).
16. https://gamedesign.gg/watch/into-the-breach-postmortem/ — talk summary: legible future consequences, randomness as situations not verdicts (fetched).
17. https://battlebrothersgame.com/dev-blog-20-bravery-morale/ — primary dev source: five states, checks, explicit readability goal (fetched).
18. https://battlebrothers.fandom.com/wiki/Morale — six states incl. Unbreakable (search preview).
19. https://steamcommunity.com/sharedfiles/filedetails/?id=2549815780 — Confident +10% attack/defense (search preview).
20. https://battlebrothers.fandom.com/wiki/Mood — campaign mood drifts to 50%/Content (search preview).
21. https://this-war-of-mine.fandom.com/wiki/Morale — mood states, Depressed/Broken (search preview).
22. https://steamcommunity.com/sharedfiles/filedetails/?id=348422581 — Sad/Depressed/Broken behavioural effects (search preview).
23. https://this-war-of-mine.fandom.com/wiki/Sympathy — hidden personality system, no visible stats (search preview).
24. https://steamcommunity.com/app/365360/discussions/0/3158630999998210776/ — player-traced morale state chain (search preview).
25. https://steamcommunity.com/app/1940340/discussions/0/4407417835485002186/ — DD2 relationships criticism vs DD1 stress (search preview).
26. https://www.reddit.com/r/darkestdungeon/comments/13g2pd1/why_is_the_relationship_system_so_awful/ — meltdown domino effect, asymmetric affinity (search preview).
27. https://www.reddit.com/r/ThisWarofMine/comments/w51gaf/marko_is_broken/ — recovering Broken characters (search preview).

## Confidence and gaps

- **High confidence:** DD1/DD2 numbers (official wiki, fetched), Battle Brothers states and design rationale (primary dev blog, fetched), XCOM pip structure (multiple agreeing sources), TWoM state ladder and effects (multiple sources).
- **Medium:** Frostpunk's exact ultimatum length and the 15%-in-2-days emergency rule rest mainly on one community guide plus a corroborating Steam snippet; the fandom wiki returned 403 and could not be checked. HUD placement of the meters conflicted between two guides (top-right vs bottom), so placement is not claimed.
- **Medium:** XCOM doom-countdown length varies across sources (7–28 / 21 / ~20 days); likely difficulty-dependent, not pinned down.
- **Gaps:** Into the Breach's grid-power doom bar is widely known but was not verified in fetched sources (the GDC PDF was not fetchable; the Memory Card analysis was login-walled); threat-tile details rest on secondary summaries of the GDC talk. DD1 affliction names were not enumerated here because the fetched pages did not list them. TWoM suicide risk at Broken was not verified and is omitted. Player-sentiment claims from search previews are indicative, not a systematic review.