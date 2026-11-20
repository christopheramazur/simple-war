# Art styles and assets for a clear, easy to read, accessible tactics game
Date: 2026-11-20 (UTC). Requested by: craft-researcher.

## Questions
1. Which strategy/tactics games are praised for at-a-glance readability, and what shared techniques make units readable (silhouettes, limited palettes, outlines, team-colour placement, icons)?
2. Which free asset packs fit a 2D isometric tactics game with desaturated terrain and simple assets, with commercial-friendly licences (CC0/permissive)? Exact URLs and licence names; unclear licences marked unusable.
3. Colour-blind-safe palette guidance for unit/team colours and state indicators that never rely on colour alone: concrete palettes with hex values and sources, plus icon/shape redundancy patterns.

## Short answer (5 lines)
- Readability is information design, not fidelity: Into the Breach, Advance Wars, Wargroove and Unity of Command 2 all pair distinct unit silhouettes with dark outlines, muted terrain, saturated team markers and redundant icons/shapes.
- Telegraph everything: ITB shows every enemy attack; UoC2 shows predicted combat results and encodes strength as filled/hollow dots, not colour — a perfect model for a deterministic WeGo game.
- Best free isometric terrain: Kenney's Isometric Tiles / Isometric Miniature series (CC0, verified on pack pages) and Screaming Brain Studios' CC0 iso packs; OpenGameArt hosts CC0 collections and CC0 Wesnoth-style unit sprites.
- Team colours: Okabe–Ito (8 hexes below) or Paul Tol's bright/high-contrast schemes; always pair colour with shape, icon, pattern or label; test in greyscale and under protan/deutan simulation.
- Avoid mainline Wesnoth art unless you accept GPL/CC-BY-SA share-alike; avoid sprite-rip archives entirely (copyrighted, unusable).

## Findings

### 1. Readable tactics games and their shared techniques
- **Into the Breach** (Subset Games, 2018): 2D isometric pixel art with black outlines plus interior lines and a muted, dark ~12-colour palette ([1]). Its GDC 2019 postmortem states the core constraint: all enemy attacks are telegraphed, there is no hit/miss chance, and resolution is completely deterministic during the player turn ([2], slide text verified via search excerpt). Readability comes from outlining units against desaturated ground and making threat tiles/icons the loudest thing on screen.
- **Advance Wars / Re-Boot Camp**: the remake is praised for a "crisp, clean new art style" ([4]); the series' long-standing strength is that each unit type is a distinct vehicle/infantry silhouette readable at map zoom, with team colour applied to the whole small sprite and type icons in the UI. (Original-GBA readability claims rest on the remake reviews and general reputation; no primary design doc was found.)
- **Wargroove** (Chucklefish): developers say faction palette-swapping was carefully tested so every unit reads well in every team colour, and that each unit was designed around a unique gameplay role (its crit condition), which gives it a visual identity; water/shader effects were constrained so they never damage pixel-art clarity ([3]).
- **Unity of Command 2** (2x2 Games): PC Gamer (91/100) describes division strength as "steps" drawn as dots under the unit — full circle = active, empty circle = suppressed — and notes the game simply shows likely combat results; the interface is called one of the best in its genre ([5]). Shape (filled/hollow) carries state without colour.
- **Battle for Wesnoth**: long-lived open-source hex tactics with 2D sprite units; the wiki documents unit-art specifications artists must match ([9]) and the project's licences ([8]). It is the reference for hex-grid clarity and team-colour discipline, though its art is copyleft (see Q2).
- **Songs of Conquest** (Lavapotion) — cautionary tale: a guide documents that its large-pixel style "greatly lowers the readability of objects and characters", especially at max zoom, with no way to disable it; the mitigation is holding ALT to highlight and caption every interactive object ([6]). Lavapotion describe mixing 2D pixel art with 3D lighting/depth ([7]). Lesson: beauty effects (bloom, depth of field, big pixels) must be toggleable and must never eat unit readability.

**Shared techniques:** (a) type-first silhouettes — one recognisable shape per unit class; (b) dark outlines separating units from terrain; (c) desaturated, low-contrast terrain so saturated units pop; (d) limited palettes with team colour on small, consistent markers (base ring, banner) rather than noisy full-sprite recolours; (e) icons + numbers for state (HP, suppression, orders); (f) telegraphed intent and predicted outcomes; (g) redundant shape coding (filled/hollow, hatching); (h) readability checked at the smallest target zoom/screen.

### 2. Free asset packs (licences verified where stated; nothing downloaded)
**Kenney — CC0 (Creative Commons Zero 1.0), verified directly on two pack pages ([11], [12]); full isometric index at [10]:**
| Pack | URL | Fit |
|---|---|---|
| Isometric Tiles Landscape | https://kenney.nl/assets/isometric-tiles-landscape | terrain tiles (CC0 verified) |
| Isometric Tiles City / Buildings / Vehicles | https://kenney.nl/assets/isometric-tiles-city · /isometric-tiles-buildings · /isometric-tiles-vehicles | structures, props |
| Isometric Miniature Prototype | https://kenney.nl/assets/isometric-miniature-prototype | greybox/prototype pieces (CC0 verified) |
| Isometric Miniature Farm / Dungeon / Library / Bases | https://kenney.nl/assets/isometric-miniature-farm · /isometric-miniature-dungeon · /isometric-miniature-library · /isometric-miniature-bases | themed props, unit bases |
| Isometric Blocks; Isometric Roads (+ Water) | https://kenney.nl/assets/isometric-blocks · /isometric-roads · /isometric-roads-water | simple terrain blocks |
Each pack page states its licence; the two checked are CC0 and Kenney's catalogue is CC0 throughout — re-check the page of any pack before shipping. Style is clean, simple, slightly stylised; desaturating terrain textures in-engine fits the GDD direction.
**Screaming Brain Studios (itch.io) — CC0:** Isometric Tiles – Town Pack, https://screamingbrainstudios.itch.io/iso-town-pack; the page states all assets are "released under the Public Domain (CC0) license … commercial or non-commercial" (licence text verified via search excerpt; direct fetch was rate-limited, re-verify at download) ([13]). Companion Floor/Object/Overworld/Wall packs appear in itch's CC0 isometric index ([14]); exact URLs unverified. True 2:1 isometric renders, old-school look.
**OpenGameArt — CC0 collections (page text verified via search excerpts; direct fetchs blocked 403):**
- CC0 – Isometric Tiles: https://opengameart.org/content/cc0-isometric-tiles — "Tiles and blocks for isometric games, all in Public Domain, no credit required" ([15]).
- CC0 Isometric collection: https://opengameart.org/content/cc0-isometric ([16]).
- Blarumyrran's public-domain Wesnoth sprites: https://opengameart.org/content/blarumyrrans-publicdomain-wesnoth-sprites — fantasy unit sprites explicitly "Licensed by CC0 to public domain" per the LPC mirror excerpt ([17]). The only verified CC0 route to Wesnoth-style units.
**Copyleft, usable with obligations:** mainline Wesnoth visual/audio assets are GPL-2.0-or-later or CC-BY-SA-4.0 ([8]). Commercial use is allowed, but derivatives must carry the same licence — a real constraint for a game that sells story campaigns and hosts Workshop mods. Prefer the CC0 subset above.
**Unusable / unverified:** Advance Wars sprite archives (spriters-resource, spritedatabase, awrev) are copyrighted rips — unusable. Any itch.io pack without an explicit licence statement (e.g. PixelFrog's Tiny Swords could not be fetched, 429) is **unusable until its licence is confirmed**. OGA's "400+ Isometric Town Tiles" and "1000+ Isometric Floor Tiles" pages exist but their licences were not directly verified — treat as unverified.

### 3. Colour-blind-safe palettes and non-colour redundancy
**Okabe–Ito palette** (Okabe & Ito, Color Universal Design; hexes verified at [19], principles at [18]):
black `#000000`, orange `#E69F00`, sky blue `#56B4E9`, bluish green `#009E73`, yellow `#F0E442`, blue `#0072B2`, vermillion `#D55E00`, reddish purple `#CC79A7`.
Design rules from the source: use vermillion instead of pure red (protanopes see dark red as near-black); use bluish green, never yellow-green; avoid red/green pairs; alternate warm/cool colours; keep brightness/saturation differences between same-temperature colours; make marks thick/bold; label directly instead of distant colour keys; **always add redundant coding** (shapes, line types, hatching, position) so the figure survives without colour ([18]).
**Paul Tol schemes** (hexes verified from the author's official `tol_colors.py`, BSD-3 licence, [20][21]):
- *bright* (up to 7 teams): blue `#4477AA`, red `#EE6677`, green `#228833`, yellow `#CCBB44`, cyan `#66CCEE`, purple `#AA3377`, grey `#BBBBBB`.
- *high-contrast* (2–3 teams, also works in greyscale/monochrome vision): blue `#004488`, yellow `#DDAA33`, red `#BB5566`.
- *vibrant* alternative: orange `#EE7733`, blue `#0077BB`, cyan `#33BBEE`, magenta `#EE3377`, red `#CC3311`, teal `#009988`, grey `#BBBBBB`.
Tol notes WCAG-style contrast: for text/lines needing ≥4.5:1 on white, use his dark scheme or bright's blue/green/purple ([20]).
**Suggested team mapping for Simple War:** 2 factions → blue `#0072B2` vs vermillion `#D55E00` (Okabe–Ito; distinct under protanopia/deuteranopia and in brightness); 3rd/4th → sky blue `#56B4E9` / orange `#E69F00`, or Tol high-contrast blue/yellow/red for a 3-faction set that also survives greyscale.
**Redundancy patterns (never colour alone):** filled vs hollow markers for strength/suppression (UoC2, [5]); distinct icons per order and state (move/attack/hold/fall back); hatching or outline style per team in addition to colour; direct text labels ("one bad hit from breaking" — already GDD pillar 3); position/shape differences on the minimap. The Game Accessibility Guidelines list "ensure no essential information is conveyed by a fixed colour alone", high UI contrast and readable default font size as basic-tier requirements, and name colourblindness among the four most-complained-about accessibility issues ([22]). Verify palettes by simulating protan/deutan vision (Tol publishes ImageMagick conversion formulas, [20]) and by greyscale screenshots.

## Relevance to Simple War
- **GDD 01 Vision, "Presentation direction" (R3Q21):** battlefields start 2D isometric with desaturated terrain so squads stand out; assets stay simple. Kenney/SBS CC0 terrain desaturated in-engine matches this exactly; units should be the only saturated, outlined elements. The later dedicated art pass can replace placeholders without touching rules.
- **GDD 01 Vision, "Input and UI" accessibility + "Platforms":** colour-blind-safe palettes, never colour alone, scalable UI/text, Steam Deck as design target. Adopt Okabe–Ito/Tol hexes as data (options menu colour presets), pair every state colour with an icon/shape, and test readability at 1280×800 handheld distance and max zoom-out — the Songs of Conquest failure mode ([6]).
- **GDD 01 Vision, pillars 2–3 (transparent deterministic rules; conditions not vague labels):** ITB-style telegraphs and UoC2-style predicted results are the presentation of WeGo determinism; the planning UI's drafted orders need distinct icons, not just coloured arrows.
- **GDD 01 Vision, pillar 5 + business model:** data-as-data and Workshop mods mean assets must be safely redistributable; CC0 packs are frictionless, while GPL/CC-BY-SA Wesnoth art would impose share-alike on derivative content packages. Free-to-play with paid campaigns still requires commercial-use licences — CC0 covers it.

## Options and recommendations
1. **Prototype now with Kenney CC0 isometric terrain + simple marker units (recommended).** Trade-off: placeholder look, but zero licence risk, instant iteration, and the GDD explicitly defers the art pass.
2. **Add Screaming Brain CC0 packs for richer terrain variety.** Trade-off: busier style; verify each pack's licence text at download (direct pages were rate-limited during research).
3. **Commission/build Wargroove-style minimal unit sprites with a palette-swapped team-colour layer.** Trade-off: real art cost; requires testing every unit in every team colour as Chucklefish did ([3]). Best long-term fit for "simple assets".
4. **Use Blarumyrran's CC0 Wesnoth-style sprites for fantasy units.** Trade-off: side-view hex aesthetic, not isometric; only the CC0 subset avoids copyleft.
5. **Palette policy:** ship Okabe–Ito-based team presets plus a Tol high-contrast 3-colour preset; enforce icon/shape redundancy in the UI kit; add a greyscale/CVD-simulation check to the mock pipeline (`hx godot mock`). Trade-off: small upfront tooling cost, large accessibility payoff.

## Sources
1. https://gameartstyles.com/game/into-the-breach — ITB style analysis: isometric pixel art, black outlines, muted palette.
2. https://media.gdcvault.com/gdc2019/presentations/Into%20the%20Breach%20Postmortem%20Final.pdf — GDC 2019 postmortem slides; telegraphed, deterministic attacks (excerpt via search).
3. https://www.gamedeveloper.com/design/an-inside-look-at-i-wargroove-s-i-wicked-design-choices — Chucklefish interview: palette swaps, unit-role design, pixel pipeline.
4. https://www.nintendolife.com/reviews/nintendo-switch/advance-wars-1plus2-re-boot-camp — Re-Boot Camp review: "crisp, clean new art style" (excerpt).
5. https://www.pcgamer.com/unity-of-command-2-review/ — UoC2 review: step dots (filled/hollow), shown combat odds, praised UI.
6. https://www.gamepressure.com/songs-of-conquest/can-the-pixel-art-style-be-turned-off/za1142b — SoC readability complaint; ALT-highlight workaround.
7. https://explorminate.org/songs-of-conquest-qa/ — Lavapotion on mixing 2D pixel art with 3D (excerpt).
8. https://wiki.wesnoth.org/Wesnoth:Copyrights — official: art is GPL-2.0+ or CC-BY-SA-4.0.
9. https://wiki.wesnoth.org/Create_Art — Wesnoth unit-art specifications (excerpt).
10. https://kenney.nl/assets/tag:isometric — index of Kenney isometric packs.
11. https://kenney.nl/assets/isometric-tiles-landscape — CC0 licence verified on page.
12. https://kenney.nl/assets/isometric-miniature-prototype — CC0 licence verified on page.
13. https://screamingbrainstudios.itch.io/iso-town-pack — CC0 statement (search excerpt; direct fetch 429).
14. https://itch.io/game-assets/assets-cc0/free/tag-isometric — itch.io CC0 isometric index.
15. https://opengameart.org/content/cc0-isometric-tiles — CC0 iso tiles (excerpt; direct fetch 403).
16. https://opengameart.org/content/cc0-isometric — CC0 isometric collection (excerpt).
17. https://opengameart.org/content/blarumyrrans-publicdomain-wesnoth-sprites (mirror: https://lpc.opengameart.org/content/blarumyrrans-publicdomain-wesnoth-sprites) — CC0 unit sprites (excerpt).
18. https://jfly.uni-koeln.de/color/ — Okabe & Ito, Color Universal Design: principles, redundant coding.
19. https://siegal.bio.nyu.edu/color-palette/ — Okabe–Ito hex/RGB table (academic reference).
20. https://sronpersonalpages.nl/~pault/ — Paul Tol's colour schemes (site moved from personal.sron.nl).
21. https://sronpersonalpages.nl/~pault/data/tol_colors.py — official hex definitions, BSD-3.
22. https://gameaccessibilityguidelines.com/basic/ — industry accessibility guidelines, basic tier.

## Confidence and gaps
- **High confidence:** palette hexes (primary sources [18–21]); Kenney CC0 (two pages fetched); Wesnoth licensing (official wiki); ITB/Wargroove/UoC2 techniques (developer talk/interview/review).
- **Medium confidence:** Screaming Brain and OpenGameArt licences rest on search excerpts of the pages themselves (direct fetchs blocked 403/429); re-verify on the pack page before downloading. The RPS Into the Breach UI-design article exists but was blocked (403) and is not cited for content.
- **Gaps:** no verified CC0 *unit-focused* isometric pack found (Tiny Swords licence unverified, itch rate-limited); Advance Wars original-era readability rests on remake reviews and reputation, not a primary design source; no Steam-Deck-specific readability study was located — handheld testing remains to be done in-project.
