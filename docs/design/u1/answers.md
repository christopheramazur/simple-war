# Round U1: owner answers (2026-11-24)

The owner answered the six blocking questions of `00-synthesis.md` §3a. Their words are quoted; the "Reading" below each one is how they're applied (GDD text and beads). Where an answer differs from the synthesis's recommendation, the synthesis's §2–§5 are superseded on that point by this file.

| ID | Question | Owner's answer | Recommendation followed? |
|---|---|---|---|
| U1Q28 | OQ-1 volley phase | "Squads with homogenous attack profiles should have units attack as they come into range, resulting in staggered attacks as the squad moves" | No (synthesis said keep lockstep) |
| U1Q29 | OQ-2 attack-move feel | "each unit moves to find a firing position within the squad's coherency, and takes up attacking as it meets the conditions to do so." | No (synthesis said squad quorum + 3 m step-out) |
| U1Q30 | OQ-3 deployment in turn-1 Planning, hidden, simultaneous | "yes" | Yes |
| U1Q31 | OQ-4 sw-tdz's six answers, placed entries as deployment defaults, `locked` pins | "yes" | Yes |
| U1Q32 | OQ-5 overworld camera during playback | "Allow for camera controls and information panels/tooltips/etc. to be viewed during playback/execution phase time, but no planning or activity." | Wider than recommended (camera only) |
| U1Q33 | OQ-6 default fire policy `prowess` after the Lab sweep | "yes" | Yes |

## Readings

### U1Q28 Staggered fire from range entry
- A unit opens fire on its own the first tick it meets the conditions to fire (target unit in range, line of fire or an indirect mode, a fire mode allowed at its current motion, timers ready). It never waits for squad-mates, and the squad never waits for a quorum before its units may shoot.
- So a homogeneous squad advancing in formation fires a ragged, staggered opening as each unit comes into range, and its units' reload and cooldown cycles stay out of phase afterwards.
- There is **no artificial slot stagger** (no seeded offset of hit accumulators). Stagger comes from movement. Squads that start the battle already in range (both holding) can still volley together; this is accepted, not a bug. Revisit only if a playtest shows it reads badly.
- Superseded: synthesis beads A13 (volley-phase spike) and A14 (slot stagger) are dropped. The synthesis's argument that stagger weakens the overkill axis (U1Q18) is noted for the D track: D-track numbers (fire range, Lab) are measured with movement-driven stagger, and the coordination stat must still show an effect there; if it doesn't, D5 records that and proposes a fix.

### U1Q29 Per-unit firing positions within coherency
- Under attack-move and attack, **each armed unit seeks its own firing position**: the nearest point it can reach, within the squad's **coherency radius** of the squad's anchor, from which it has a shot at an enemy unit of the squad it engages (the per-unit shot gate: range, minimum range, line of fire or an indirect mode). It walks there and opens fire on arrival (U1Q28). This replaces the "fire quorum" anchor stop and the 3 m "step-out".
- **The anchor** advances along its route while any armed unit has no firing position inside the coherency radius, and stops once every armed unit has one (or has a shot already). Hysteresis: it moves again only after a unit has lacked a firing position for at least 1 s. With no achievable position for some unit (e.g. a minimum range it can't clear), that unit doesn't hold the anchor.
- **Leash:** attack-move still has its leash past the attack-move point (data, default 15 m); attack has none. Hold never moves units off their slots.
- **Coherency radius** (data per formation; proposed default: the formation's half-width plus 4 m) is now a prerequisite of the attack-move feel, not a later clustering refinement.
- A unit that loses its shot (target moved, line blocked) seeks a new firing position within coherency; it returns to its slot when the squad's order no longer engages.
- **Search:** deterministic and cheap: candidate points on rings around the unit's slot toward the target, inside coherency, enterable for its movement type, first one with a shot by ring then angle index. Cost is measured in the movement spike (synthesis A6) and must fit its budget.
- Archetype behaviours (data, draft 01 §3.2 table) keep their roles but trade `quorum_pct`/`step_out` for coherency and stand-off parameters: mortars keep `keep_distance(min_range + 5)` and stand while reloading; marksmen prefer max range; assault squads have a larger coherency radius.
- Superseded: synthesis A3 ("closing to fire: quorum") becomes "per-unit firing positions" (below); A7 (step-out) is folded into it; A12b (coherency radius) moves before it.

### U1Q30 Deployment
Draft 03 §3.3–§3.5 deployment text applies as written: same Planning as turn-1 orders, hidden and simultaneous, placements anywhere in the side's area, every side's area shown, turn-1 orders can't target unseen enemy squads.

### U1Q31 Placed squads (sw-tdz)
sw-tdz's six suggestions are accepted: (1) storage is the scenario's `placed` list `{side, squad, x, y, facing?}`, facing defaulting to the side's; (2) a placed point must lie inside its side's deployment area; (3) unplaced squads deal evenly over the rest of the area, placed ones go to their cell or the nearest enterable one; (4) overworld battles ignore `placed`; (5) the planner reads positions from the battle state after deployment; (6) two entries on one cell or a squad placed twice are refused at validation. Placed entries are deployment defaults; `locked: true` pins them.

### U1Q32 Watching is reading, not acting
- During execution playback, battle **and** overworld: every camera control (pan, zoom, centre, follow) and every **information** view works: hover tooltips, the hex and feature panels, squad cards, inspection windows, battle relations, the glossary, selecting things to inspect them.
- Nothing that plans or acts: no orders, routes, reactions, deployments, purchases, owner actions, rally changes or production choices. These are refused until Planning, and their buttons are disabled with the reason.
- This amends R3Q2 ("locks out overworld view/interaction" becomes "locks out planning and activity").

### U1Q33 Default fire policy
After the Pressure Lab sweep (D6), `fire.policy` switches to `prowess` in one commit with a new baseline era (D7).

## Bead map

Created 2026-11-24 by sw-08jt.7 from `00-synthesis.md` §5 as amended by the readings above and the Qwen reviews 02, 03 and 05. Titles end in "(U1 <plan ID>)". Not created: A7 (folded into A3, U1Q29), A13 and A14 (dropped, U1Q28), the decision beads X-OQ1..6 (= sw-08jt.1..6, closed). Changed from the plan: A3 is per-unit firing positions; A6 and A12b raised to P1 and moved before A3; A4 re-read as "arrival fires the standing mode"; B13 split into B13a/B13b; C8 widened (U1Q32) and C11 moved to Opus (`large`); sw-tdz depends on C14.

| Plan ID | Bead | Depends on |
|---|---|---|
| X1 | sw-08jt.8 | — |
| A1 | sw-txnj.1 | — |
| A2 | sw-txnj.2 | — |
| A6 | sw-txnj.3 | — |
| A12b | sw-txnj.4 | A6 (sw-txnj.3) |
| A3 | sw-txnj.5 | A2 (sw-txnj.2), A6 (sw-txnj.3), A12b (sw-txnj.4) |
| A4 | sw-txnj.6 | A3 (sw-txnj.5), A1 (sw-txnj.1) |
| A5 | sw-txnj.7 | — |
| A8 | sw-txnj.8 | A4 (sw-txnj.6) |
| A9a | sw-txnj.9 | A3 (sw-txnj.5) |
| A9b | sw-txnj.10 | A9a (sw-txnj.9), A3 (sw-txnj.5) |
| A10 | sw-txnj.11 | A9b (sw-txnj.10), B4 (sw-tho3.4) |
| A11 | sw-txnj.12 | A6 (sw-txnj.3), A3 (sw-txnj.5) |
| A12a | sw-txnj.13 | A11 (sw-txnj.12) |
| A12c | sw-txnj.14 | A12a (sw-txnj.13), A12b (sw-txnj.4) |
| B1 | sw-tho3.1 | — |
| B2 | sw-tho3.2 | — |
| B3 | sw-tho3.3 | B2 (sw-tho3.2) |
| B4 | sw-tho3.4 | B3 (sw-tho3.3) |
| B5 | sw-tho3.5 | B3 (sw-tho3.3) |
| B6 | sw-tho3.6 | B3 (sw-tho3.3) |
| B7 | sw-tho3.7 | — |
| B8 | sw-tho3.8 | B6 (sw-tho3.6), B7 (sw-tho3.7) |
| B9 | sw-tho3.9 | B2 (sw-tho3.2), B6 (sw-tho3.6), B7 (sw-tho3.7) |
| B10 | sw-tho3.10 | B1 (sw-tho3.1), B9 (sw-tho3.9) |
| B11 | sw-tho3.11 | B9 (sw-tho3.9), B10 (sw-tho3.10) |
| B12 | sw-tho3.12 | B9 (sw-tho3.9) |
| B13a | sw-tho3.13 | B9 (sw-tho3.9) |
| B13b | sw-tho3.14 | B13a (sw-tho3.13) |
| B14 | sw-tho3.15 | B11 (sw-tho3.11) |
| B15 | sw-tho3.16 | B2 (sw-tho3.2), C3 (sw-bafi.3) |
| C1 | sw-bafi.1 | — |
| C2 | sw-bafi.2 | C1 (sw-bafi.1) |
| C3 | sw-bafi.3 | A1 (sw-txnj.1), A2 (sw-txnj.2) |
| C4 | sw-bafi.4 | C3 (sw-bafi.3), sw-abk |
| C5 | sw-bafi.5 | C3 (sw-bafi.3), B7 (sw-tho3.7) |
| C6a | sw-bafi.6 | C3 (sw-bafi.3) |
| C6b | sw-bafi.7 | C1 (sw-bafi.1), C4 (sw-bafi.4), C5 (sw-bafi.5), C6a (sw-bafi.6), sw-ll4.27.6 |
| C7 | sw-bafi.8 | C6b (sw-bafi.7) |
| C8 | sw-bafi.9 | C1 (sw-bafi.1) |
| C9 | sw-bafi.10 | — |
| C10 | sw-bafi.11 | C9 (sw-bafi.10) |
| C11 | sw-bafi.12 | C10 (sw-bafi.11), C1 (sw-bafi.1), C2 (sw-bafi.2) |
| C12 | sw-bafi.13 | C10 (sw-bafi.11) |
| C13 | sw-bafi.14 | C9 (sw-bafi.10) |
| C14 | sw-bafi.15 | C9 (sw-bafi.10) |
| C15 | sw-bafi.16 | C10 (sw-bafi.11) |
| D1 | sw-pd2l.1 | — |
| D2 | sw-pd2l.2 | B3 (sw-tho3.3), D1 (sw-pd2l.1), A1 (sw-txnj.1) |
| D3 | sw-pd2l.3 | A1 (sw-txnj.1), A4 (sw-txnj.6), D2 (sw-pd2l.2) |
| D4 | sw-pd2l.4 | D3 (sw-pd2l.3) |
| D5 | sw-pd2l.5 | D4 (sw-pd2l.4) |
| D6 | sw-pd2l.6 | D1 (sw-pd2l.1), D5 (sw-pd2l.5) |
| D7 | sw-pd2l.7 | D6 (sw-pd2l.6) |
| D8 | sw-pd2l.8 | D5 (sw-pd2l.5), sw-ll4.27.7 |
| E1 | sw-63wt.1 | — |
| E2 | sw-63wt.2 | E1 (sw-63wt.1) |
| E3 | sw-63wt.3 | E2 (sw-63wt.2) |
| E4 | sw-63wt.4 | — |
| E5 | sw-63wt.5 | E4 (sw-63wt.4), C2 (sw-bafi.2) |
| E6a | sw-63wt.6 | — |
| E6b | sw-63wt.7 | E5 (sw-63wt.5), E6a (sw-63wt.6) |
| E7 | sw-63wt.8 | E4 (sw-63wt.4), sw-7ii, sw-96x, sw-ll4.17 |
| E8 | sw-63wt.9 | E2 (sw-63wt.2) |
| E9 | sw-63wt.10 | E6b (sw-63wt.7), E8 (sw-63wt.9) |
| E10 | sw-63wt.11 | E8 (sw-63wt.9) |
| E11 | sw-63wt.12 | — |
