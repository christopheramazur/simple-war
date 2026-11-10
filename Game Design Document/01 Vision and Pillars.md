# 1. Vision and Pillars

## What Simple War is
A digital-only (R1Q1), deterministic (R1Q7), simultaneous-turn (WeGo) strategy game built in Godot 4.7.2. The player is a Commander running armies across a hex overworld while several real-time-resolved battles play out in parallel on the same clock. Story campaigns are the main draw (R1Q2). The architecture must also carry a lasting competitive scene and a player-made campaign scene (R1Q2).

## Audience
Players of Heroes of Might and Magic and Total War (R1Q3). The competitive scene is sized like HoMM or SOVL, not e-sports (R1Q2). The UMS/mod scene (StarCraft custom maps) gets a comprehensive editor with "gratuitous scripting and asset use" (R1Q2).

## Pillars
1. **Parallel play is the defining pillar** (R1Q6). Several battles and the overworld advance together on a shared pulse (R2Q3). The UI makes swapping, tabbing and tiling battles fast (R2Q19). Solo and challenge runs become high-stimulation puzzles (R1Q6).
2. **Transparent, deterministic rules** (R1Q3, R1Q7). The player can see the real calculations, at a chosen verbosity, and the displayed result is the result used. There is no hidden randomness: modifiers, multipliers and deterministic accumulators ("every Nth hit") replace dice (R2Q6, R5Q5). Difficulty comes from timers and opponents' decisions, never from hidden rule information (R1Q3).
3. **Conditions, not vague labels** (R1Q3, R3Q10). The game says "one bad hit from breaking", with hoverable, context-aware defined terms (see the [Glossary](07%20Glossary.md)).
4. **Legendary results from a fraying reality** (R1Q14). As the Law frays, local reality bends: re-enacting legends makes legendary outcomes possible. This explains militia standing beside war machines, and the Legend pressure system.
5. **Data as data, highly customisable** (R1Q2, R6Q26). Gameplay lives in data, and official content ships in the same package format mods use.
6. **Fast and headless-first** (R6Q24, R7Q14). The simulation runs without graphics, as fast as possible, behind one Game API. Presentation and audio are clients (R8Q11).

## Modes and session lengths (R2Q1)
| Mode | Shape | Length |
|---|---|---|
| Story mission | Scripted campaign mission | ~40 min, varies |
| Skirmish | Overworld + battles vs AI or players | ~2 h typical; 30 min to 8 h+ configurable |
| Ranked Duel | Single battle, pre-built armies (default) | — |
| Ranked full match | Small overworld ending in a decisive battle (deception vs timing), like HotA's Jebus Cross/Duel | 30–40 min |
| Battle | — | ~8 turns ≈ 10 min at full timers |

- Turn timers apply in all modes and scale with difficulty. An untimed accessibility option exists and is flagged; challenge and ranked lock it off (R2Q2).
- Ranked starts as an **unrated competitive queue** that records results. No rating model, and no disconnect penalties, until usage data justifies them (R7Q10, R8Q8).
- Single-player data is balanced separately from multiplayer data (R1Q2). Rulesets are pinned for ranked (R3Q12).

## Platforms (R8Q9)
- **Primary:** Windows on Steam.
- **Design target:** Steam Deck. This means input-agnostic controls and readable UI scale.
- **Later:** native Linux.
- **Not planned:** Mac and consoles. Mobile is a poor fit (clicking, window management); a mobile version, if ever, would centre on autobattle.

## Input and UI (R1Q4, R8Q10)
- **Input:** fully rebindable, input-agnostic controls through GUIDE, including drag-select on stick and touch. Every input method and mapping is configurable.
- **Command set:** modern RTS/TBS commands. Select by type, on screen, or by control group. Move in formation, or to a new formation. Camera bookmarks. A consolidated ability menu across several squads.
- **HUD:** every HUD and UI portion is individually configurable.
- **Accessibility:** scalable UI and text size, colour-blind-safe palettes, never colour alone to convey state, and the untimed option.
- **Localisation:** every player-facing string is a translation key from day one, glossary terms included. English only at launch.

## Business model (R1Q5)
Free, except story campaigns and cosmetic, non-pay-to-win content such as faction skins. The project is not profit-driven.

## Presentation direction (R3Q21, R8Q11)
- **Battlefields:** start as 2D isometric with desaturated terrain, so squads and units stand out. Assets stay simple.
- **Overworld:** a hex map. The old star chart is retired.
- **Later passes:** art direction, audio and UI aesthetics each get a major dedicated pass.
- **Replay vision:** a whole-campaign replay rendering overworld movement and every battle in real time, in one view (R1Q8).
