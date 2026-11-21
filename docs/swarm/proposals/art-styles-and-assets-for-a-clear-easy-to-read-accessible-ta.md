# Proposal: CVD-safe team colours as data, plus readability guards

Status: open
From: games-researcher, based on [../research/summaries/art-styles-and-assets-for-a-clear-easy-to-read-accessible-ta.md](../research/summaries/art-styles-and-assets-for-a-clear-easy-to-read-accessible-ta.md)

## The idea
Make team colours a single data-driven source with colour-blind-safe presets selectable in the options menu (the MVP already promises a colours menu), and add two cheap standing guards: a greyscale/CVD-simulation variant in the mock pipeline, and a licence-verified CC0 asset shortlist prepared for the user's art-direction interview. No art-direction decisions are made here — placeholders stay until the interview (README Open topic 3).

## Why (evidence, with sources)
- The most readable tactics games (Into the Breach, Advance Wars, Wargroove, Unity of Command 2) all pair distinct silhouettes and dark outlines with muted terrain, small saturated team markers, and redundant icons/shapes; UoC2 encodes strength as filled/hollow dots so state survives without colour. https://www.gamedeveloper.com/design/an-inside-look-at-i-wargroove-s-i-wicked-design-choices · https://www.pcgamer.com/unity-of-command-2-review/
- Okabe–Ito and Paul Tol publish concrete CVD-safe hexes; Okabe–Ito's rules say use vermillion instead of pure red (protanopes see dark red as near-black) and always add redundant shape/label coding. https://jfly.uni-koeln.de/color/ · https://sronpersonalpages.nl/~pault/
- Verified code state (checked this turn): `PLAYER_COLORS` is hardcoded twice — `src/presentation/war_room/context_view.gd:36` (blue `Color(0.25,0.55,1.0)` vs pure red `Color(1.0,0.35,0.3)`) and `src/presentation/replay_viewer/replay_viewer.gd:18` — and also consumed by `results_screen.gd` and `battle_panel.gd`. The current red is exactly the protanopia failure case; there is no preset or options entry.
- Songs of Conquest is the cautionary tale: a beauty effect (big-pixel style) measurably hurt readability at max zoom with no toggle; players hold ALT to find objects. Readability must be checked at the smallest target screen — for us, Steam Deck 1280×800. https://www.gamepressure.com/songs-of-conquest/can-the-pixel-art-style-be-turned-off/za1142b
- Licence safety matters for Workshop mods: Kenney isometric packs are CC0 (verified on pack pages); mainline Wesnoth art is GPL/CC-BY-SA (share-alike risk for derivative content packages); sprite-rip archives are unusable. https://kenney.nl/assets/tag:isometric · https://wiki.wesnoth.org/Wesnoth:Copyrights

## Fits the GDD (doc and section) / Conflicts with
- Fits GDD 01 "Input and UI — Accessibility" (colour-blind-safe palettes, never colour alone), Release order step 1 (MVP includes the colours options menu), pillar 5 (data as data), and "Presentation direction" (2D isometric, desaturated terrain, simple assets).
- Conflicts with nothing. Art-direction choices (which packs become final art) remain options for the user's narrative/art interview (README Open topic 3); this proposal only touches defaults, tooling and research notes.

## Candidate beads
1. **CVD-safe team colours as data, with an options preset.** Move team colours to one data source consumed by all four current readers (context_view, replay_viewer, results_screen, battle_panel); default pair Okabe–Ito blue `#0072B2` vs vermillion `#D55E00` (or a documented equivalent); at least one alternate preset (Tol high-contrast) selectable in options. Acceptance: no hardcoded `PLAYER_COLORS` dicts remain in presentation code; options menu switches presets live in war room and replay viewer; greyscale + protan/deutan simulated war-room screenshots attached showing both sides distinguishable. Size: M. Type: feature. Priority: 1.
2. **Greyscale/CVD check in the mock pipeline.** `hx godot mock` can emit greyscale and protanopia/deuteranopia variants beside the normal PNG, so every future UI mock is checked for colour-alone failures. Acceptance: variants generated for one existing mock as proof; documented in the harness README; existing mock output unchanged. Size: S. Type: task. Priority: 2.
3. **Licence-verified CC0 asset shortlist for the art-direction interview.** Re-verify the medium-confidence licences (Screaming Brain, OpenGameArt/Blarumyrran) directly on the pack pages and list each candidate with URL, exact licence statement and verification date. Acceptance: note in `docs/swarm/research/notes/`; anything unclear marked unusable; no downloads, no GDD edits; feeds README Open topic 3 as options only. Size: S. Type: task. Priority: 2.

## Rejected alternative
Adopting mainline Wesnoth art (or any copyleft pack) as the default asset base: it looks the part, but GPL/CC-BY-SA share-alike would impose licence obligations on derivative Workshop content packages and paid campaigns — a business-model conflict (GDD 01 pillar 5 + business model). CC0 gives the same placeholder function with zero friction. Also rejected: deciding a final art style now — that is the user's interview topic, not ours.

## Votes
- lead-designer: APPROVE. Verified against code and GDD: `PLAYER_COLORS` is hardcoded in context_view.gd:36 and replay_viewer.gd:18 with pure red (1.0,0.35,0.3) — the protanopia failure case; doc 01 line 50 promises colour-blind-safe palettes and "never colour alone", and Release order step 1 (line 33) already includes the colours options menu in the MVP, so bead 1 closes a promised-but-missing feature, not a new one. Beads 2-3 are tooling/notes only and correctly leave art direction to README Open topic 3. Strongest objection: team colours are presentation identity, not simulation data — the single source must live in presentation/options (user://settings.cfg presets), never in data/packages or anything the deterministic sim reads; replays already store player ids, so colour must stay render-time resolved. Also keep the neutral grey (id 30) distinguishable in every preset, and require redundant shape/label coding per Okabe–Ito, not colour swaps alone.
- ux-art-director: pending
- tech-lead: pending
