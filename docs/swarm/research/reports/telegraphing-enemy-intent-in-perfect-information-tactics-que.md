# Telegraphing enemy intent in perfect-information tactics

Date: 2026-11-21. Requested by: games-researcher.

## Questions
1. How do Into the Breach, Frozen Synapse, Combat Mission (WeGo), XCOM 2 and Invisible, Inc. display enemy intent — granularity, what stays hidden, when revealed?
2. What did players praise or criticise about fairness, puzzle-feel and tension?
3. Which patterns keep tension without hiding rule information, and what breaks when everything is telegraphed?
4. What is the cheapest legible intent display for a small skirmish MVP?

## Short answer (5 lines)
- Into the Breach telegraphs every enemy attack on its target tiles, with zero hit/miss RNG; difficulty comes from protecting buildings under triage, not secrecy.
- Frozen Synapse and Combat Mission hide enemy orders entirely (WeGo): tension comes from simultaneous commitment, prediction and spotting; both offer replay/simulation instead of previews.
- XCOM 2 hides intent but sells risk transparency (concealment, overwatch as visible conditional rules); Invisible, Inc. draws guard vision cones per tile and even makes telegraphy a difficulty setting.
- Full telegraphy trades war-feel for puzzle-feel and creates "perfect decision" pressure (Mode 7's own postmortem calls this out).
- Cheapest high-value MVP subset: per-squad stance icons plus ITB-style attack telegraphs (target + computed damage); full enemy plan previews are the expensive, risky end.

## Findings

### 1. Mechanics per game
**Into the Breach.** The GDC 2019 postmortem slides state the constraint plainly: "Telegraphed Attacks — All enemy attacks shown — No hit/miss chance — Completely deterministic (during player turn)" ([2], slide text recovered via search index; the PDF itself would not fetch). Every Vek's intended attack is marked on the board before the player acts; the player moves first, then enemies execute what was shown. What stays hidden is only what has not been committed yet (future spawns and next-turn intent); knockback and displacement are the puzzle verbs, and civilian buildings/grid power are the stakes ([1][3][4]). Reviews describe it as "bite-sized tactical puzzles with perfect information" ([5], snippet) and note there is not always a winning move ([6], snippet).

**Frozen Synapse.** WeGo: unlimited planning time, then ~5 seconds of simultaneous execution. Orders are waypoints plus facing, stance, speed and a default action on sighting an enemy; "time-to-aim" means the unit that sees its antagonist first generally wins ([7][9]). Enemy plans are never shown. Instead the game lets you *simulate* your plan "assuming that enemy forces maintain their current strategies" ([9]) — prediction, not telegraphy. A "light" mode shows all movement; "dark" mode hides enemies outside allied line of sight but reports last-known position and time since seen ([9]). Combat is deterministic from weapon strength, stance and poise ([9]). Mode design is a difficulty lever: Extermination uses a very short time limit and random starts; Secure/Charge use Contract-Bridge-style bidding so players set their own territory goals; Disputed reveals its objectives mid-match ([8]).

**Combat Mission (WeGo).** Planning phase (unlimited in single player), then a fixed 60-second real-time execution phase in which the player can only watch, replay and move the camera ([10]). Enemy orders are never telegraphed; asymmetry comes from spotting: per-unit LOS blocked by terrain, weather and night; imprecise "sound" contacts (grey symbol, red question mark); spotted units can vanish again; long-range contacts can be misidentified; CMx1 used "absolute spotting", CMx2 per-unit "relative spotting" ([10]). A click-to-display LOS tool is sometimes the only way to know what a unit can see. Conditional orders exist — "covered arc" fires only when a target type enters a defined arc/range — and units react autonomously during execution (take cover, break, flee; tanks pop smoke when they detect a targeting laser) ([10]). Players praise rewatchable replays from any unit's viewpoint ([11][12], snippets); a CMSF2 Steam thread complains that contact reports disappearing when you click away makes micromanagement hard (snippet).

**XCOM 2 (contrast case, IGO/UGO).** No enemy plan preview; intent is revealed only as the enemy turn plays out. The legible layer is *conditional rules*: concealment (enemies patrol unaware; the area shown around a patrolling pod is roughly its movement range), overwatch (fires on enemy movement in LOS; from concealment it has no aim penalty and can crit), and explicit break rules — attacking, moving too close, being flanked (the flanker gets a free shot), running through windows/doors, failing a hack; one reveal usually reveals the whole squad except Phantom Rangers ([13]). A Dark Event (Vigilance) enlarges the alert radius, i.e. the hidden-intent envelope is itself a visible, named modifier ([13]). Community threads debate the ambush/overwatch timing ("scamper") as the fairness hotspot ([14], snippet).

**Invisible, Inc.** Guard intent is shown as per-tile vision cones: primary vs peripheral vision, blocked by hard/tall cover, a tile counts as seen at ≥45% coverage; hovered tiles report Watched / Noticed / Hidden / safe ([15]). Cones render only on tiles you currently see; guards out of vision vanish but leave red "last known position" ghosts for the turn ([15]). Crucially, telegraphy is a difficulty dial: below Expert Plus all corporate vision on seen tiles is drawn; on Expert Plus cones appear only for guards currently in your vision ([15]). What stays hidden: future facing/patrol choices and unseen guards. Players praise the hover-for-info legibility ("75 hours… never had any problems with guard cones", [16], snippet); bug reports about a mis-rendered cone size ([17], snippet) show how much trust rides on the display being exactly right.

### 2. Praise and criticism
- ITB: praised for making planning central and prevention (not damage) the goal; "knowing about a disaster and preventing it are entirely different skills" ([4]). Criticised for repetition across runs and high cognitive load despite minimal visuals ([4]); "puzzle, not war" is the recurring framing ([5][6], snippets).
- Frozen Synapse: Eurogamer and Edge 9/10, Metacritic 85, IGF Audience Award ([9]); the prediction mind-game is the celebrated core ("Where do I think your shotgunner will be in five seconds?", [8]). The developers' own postmortem is the sharpest criticism: dense fiddly UI, a counter-intuitive first level that cost them PAX 10 selection, insta-death unforgivingness, and — key for us — "a constant sense of pressure on the player to make a perfect decision… you feel like you could have predicted events perfectly: that's often not a great sensation… it just leads to significant frustration" ([7]).
- Combat Mission: WeGo praised for careful planning plus replay review ([11][12], snippets); friction is UI/spotting bookkeeping, not fairness.
- Invisible, Inc.: cones + hover praised as legible ([16]); edge cases where the drawn cone and actual spotting disagree generate bug reports and forum threads ([17], snippet).

### 3. Tension without hidden rules
Patterns that recur across the five games:
1. **Competing obligations** — ITB's buildings/grid force triage; FS Secure/Charge bidding makes you own your goal; CM victory flags ([4][8][10]).
2. **Timers and escalation** — FS Extermination's short limit, Disputed's mid-match objectives; ITB's per-mission turn pressure; Invisible Inc's security responses escalate when anything out-of-place is seen ([8][4][15]).
3. **Numbers/action economy** — three mechs vs many Vek; CM company-to-battalion scale ([4][10]).
4. **Simultaneous commitment** — even with perfect rules, you must guess the opponent's *choice*; FS and CM keep this as the core mind-game ([7][8][10]).
5. **Visible conditional reactions** — time-to-aim, covered arcs, overwatch: the rule is public, the trigger depends on movement ([7][10][13]).
What breaks when everything is telegraphed: perfection pressure and frustration (Mode 7, primary source [7]); puzzle-feel displacing war-feel and repetition ([4][5]); analysis paralysis risk grows with order granularity (FS's waypoint "tangles" [7]). Inference, flagged as such: fully previewable deterministic plans also invite save-scumming/optimisation loops unless commitment is locked.

### 4. Cheapest legible subset for the MVP
Planning value per UI cost, low to high:
- **Stance/intent icons per squad** (attack-move, hold, fall back, readying): trivial overlay, names states instead of drawing geometry; fits Pillar 3 "conditions, not vague labels".
- **Attack telegraphs** (ITB-style): for each committed enemy attack, mark the target squad/tile and show the computed damage at the chosen verbosity. One marker + one tooltip per attack; deterministic math already exists (Pillar 2), so this is mostly rendering. Highest planning value per pixel.
- **Threat envelopes** (overwatch/engagement arcs, XCOM/CM-style): medium cost; shows where moving is dangerous without promising exact plans.
- **Full plan preview** (FS-style ghost paths for every enemy order): highest cost (waypoint overlap, temporal ordering — exactly the UI tangles Mode 7 regretted [7]) and highest perfection-pressure risk.
- **Replay-only** (CM): cheapest to build, least planning value; tension must then come from spotting and numbers.

## Relevance to Simple War
- Pillar 2 (GDD 01) demands transparent deterministic rules and says difficulty comes "from timers and opponents' decisions, never from hidden rule information" — attack telegraphs + stance icons implement this directly; hidden *intent* (opponent decisions) is explicitly allowed, hidden *rules* are not.
- Rules Spec 2.8 Prowess already floats when "enemy squads reacting to your orders, such as a revealed charge turning their attack-move into a retreat" — the design assumes some order visibility, and the reaction is the designed uncertainty. ITB locks intent during the player turn; Simple War's WeGo resolves both sides at once, so a telegraph would be *committed intent at reveal time*, with Execute-time Prowess reactions as the tension source — mirroring FS's "simulate assuming current strategy" caveat ([9]). Analysis, not a GDD decision.
- Rules Spec 2.9 keeps overworld guard forces hidden until engagement; nothing here argues against that — CM shows a whole game built on spotting asymmetry.
- Turn timers (GDD 01, R2Q2) and SIMPL pools are the native equivalents of ITB's grid pressure and FS's escalation; battle length ~8 turns (GDD 01) suits telegraphed triage over long prediction chains.
- MVP is skirmish vs AI (GDD 01 release order): an AI's committed orders are cheap to expose, and verbosity options already exist as a concept in Pillar 2.

## Options and recommendations
1. **Stance icons only (minimum).** Trade-off: cheapest, readable at a glance; low planning value — players still can't aim around specific attacks.
2. **Stance icons + attack telegraphs with computed damage (recommended MVP default).** Trade-off: modest UI cost, maximal planning value, matches Pillar 2; risks puzzle-feel and perfection pressure — mitigate with timers, SIMPL pressure and Execute-time Prowess reactions rather than secrecy.
3. **Add threat envelopes (overwatch/engagement arcs) as a verbosity layer.** Trade-off: medium cost; helps movement planning; more screen clutter on 2D iso maps.
4. **Full enemy plan preview as an optional low-difficulty/Accessibility setting (Invisible Inc's "show danger zones" precedent [15]).** Trade-off: expensive, FS-style tangles and frustration risk; keeps competitive/ranked defaults clean.
5. **Replay-only, no previews (CM default).** Trade-off: cheapest and most "war-like", but weakest fit with Pillar 2's visible-calculations promise and with Prowess's revealed-order reactions.
The amount of next-turn plan to show remains a design decision for the designers/user; this report only ranks cost/value.

## Sources
1. https://www.gdcvault.com/play/1025772/-Into-the-Breach-Design — GDC Vault page, Matthew Davis' GDC 2019 ITB design postmortem (metadata/abstract).
2. https://media.gdcvault.com/gdc2019/presentations/Into%20the%20Breach%20Postmortem%20Final.pdf — postmortem slides; "Telegraphed Attacks" slide text recovered via search index (direct fetch failed in an earlier session; not re-attempted).
3. https://gamedesign.gg/watch/into-the-breach-postmortem/ — talk summary: information design, constrained randomness, enemy intent.
4. https://www.gamerevs.com/reviews/into-the-breach/ — 2026 review: telegraphy, prevention-as-goal, repetition and cognitive-load criticism.
5. https://www.games-genie.com/games/into-the-breach — verdict snippet: "perfect information… every enemy move telegraphed" (snippet only).
6. https://www.nintendolife.com/reviews/switch-eshop/into_the_breach — review snippet: scenarios with no winning move (snippet only).
7. https://www.gamedeveloper.com/audio/postmortem-mode-7-games-i-frozen-synapse-i- — Mode 7 postmortem (primary): prediction focus, time-to-aim, learning curve, perfection pressure.
8. https://www.gamedeveloper.com/design/road-to-the-igf-mode-7-games-i-frozen-synapse-i- — IGF interview (primary): 5-second plans, Extermination/Secure/Charge/Disputed mode design, cut Railgun/Endplays.
9. https://en.wikipedia.org/wiki/Frozen_Synapse — gameplay: simulate-assuming-current-strategy, light/dark modes, deterministic combat, reception scores.
10. https://en.wikipedia.org/wiki/Combat_Mission — WeGo 60s phases, spotting/sound contacts/LOS tool, covered arcs, morale, absolute vs relative spotting.
11. https://boardgamegeek.com/thread/1958317/the-wego-game-system — player praise of CM replays from any unit's viewpoint (snippet only).
12. https://www.reddit.com/r/computerwargames/comments/kgvi2s/combat_mission_games_wego_or_real_time_commands/ — WeGo vs RT player discussion (snippet only).
13. https://www.ufopaedia.org/index.php/Concealment_(XCOM2) — concealment, overwatch ambush rules, break conditions, Vigilance dark event.
14. https://www.reddit.com/r/Xcom/comments/40cr4k/xcom_2the_ambush_overwatch_conundrum/ — ambush/overwatch timing fairness debate (snippet only).
15. https://iiwiki.werp.site/vision — Invisible Inc community wiki: cone geometry, 45% tile rule, Watched/Noticed/Hidden, Expert Plus telegraphy toggle, last-known ghosts (CC BY-NC-SA 4.0).
16. https://www.reddit.com/r/invisibleinc/comments/37pxjh/review_of_invisible_incs_interface/ — player praise of cone legibility and hover info (snippet only).
17. https://steamcommunity.com/app/243970/discussions/0/1753528351091959889/ — guard-turn peripheral-vision edge case (snippet only).

## Confidence and gaps
- High confidence: FS and CM mechanics (primary postmortem + Wikipedia), XCOM 2 concealment (UFOpaedia), Invisible Inc vision (detailed community wiki), ITB telegraphy constraint (GDC slide text).
- Medium: ITB reception claims rest on one 2026 review plus snippets; the GDC talk video/PDF was not directly readable, so finer postmortem claims (e.g. exact emergence-telegraph timing, difficulty iteration) are unverified here.
- Snippet-only sources are marked; no claim rests on a single snippet alone except the BGG replay-viewpoint detail.
- Not verified: XCOM 2 shot-preview UI specifics and pod-activation rules; Invisible Inc alarm-timer details; Combat Mission forum threads (battlefront.com returned 403). The Execute-time telegraph/reaction interaction in §Relevance is my analysis, not a sourced or GDD-settled design.
