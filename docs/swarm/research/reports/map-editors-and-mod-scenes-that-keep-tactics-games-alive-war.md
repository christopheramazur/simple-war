# Map editors and mod scenes that keep tactics games alive (Wargroove, Battle for Wesnoth, Into the Breach, Door Kickers)
Date: 2026-11-21. Requested by: games-researcher.

## Questions
1. What do these games' editors offer (terrain paint, triggers, objectives, sharing/export), what do players actually make, and which features get used most vs. dead weight?
2. What makes community maps stick: discovery, ratings, contests, curated picks — with concrete examples and numbers?
3. What should the Simple War Maps tab prioritise for a tactics MVP, and what does a JSON mod package need for map sharing (metadata, previews, versioning, dependencies)?

## Short answer (5 lines)
- The editors that sustain scenes are the ones the developers use themselves (Wargroove, Door Kickers 2), with a low floor (paint + place + play) and a closed, declarative trigger vocabulary instead of a scripting language.
- Players mostly make arenas, puzzle maps and small custom modes; full campaigns are the prestige output, not the volume. Terrain paint and unit placement carry most usage; deep cutscene tooling is where beginners stall.
- Discovery is solved by curation, not listings: Wargroove's official Spotlight + Community Choice Award, Wesnoth's in-game add-on manager with download counts and feedback links, DK2's one-click Workshop publish, ITB's single master mod-list thread (~460k views).
- Into the Breach has no editor at all; a community DLL-injected Lua loader carries a squad/weapon mod scene anyway — proof that a data-only content layer is the durable part, and that executable-code modding is fragile (Windows-only, breaks saves).
- For Simple War: ship paint + stamps + zones + the closed trigger vocabulary + one-click skirmish playtest first; package metadata should copy Wesnoth's `_server.pbl` field set (id, title, x.y.z version, type, tags, dependencies, preview, feedback) plus a ruleset pin for determinism.

## Findings

### Q1 — What the editors offer and what players make
**Wargroove** ships a three-layer editor: campaign graph (scenario markers joined by paths, branching on conditions), scenario editor (terrain paint, units, buildings, named locations/zones, victory conditions), and triggers — condition/action pairs with boolean flags, e.g. "Unit Presence: ≥1 Commander at Destination → Victory", plus an ambush example with spawn actions and a flag that a village capture can flip ([1], [2]). Cutscenes are authored per-map. Chucklefish states it is the same tool used to build the shipped campaign, and the UI is designed for gamepad as well as mouse ([1], [2]). Community output visible in the official Spotlight: competitive 4-player arena maps (Pinwheel Plains), single-turn puzzle maps built on a commander's groove (Agent's Legacy), and entirely custom game modes (Ryota Chess: both commanders locked at 1% HP, groove always charged, death pits in corners) ([3]). Full custom campaigns exist and win awards (TinyGrooveCS, updated to v3) ([3]). Notably, the community built a lineage of mods just to unlock *hidden editor content* — extra props, triggers, filters, cutscene emotes (Ophelia's unlock mod → Unicarn's Expanded Editor → Artemis-of-Dust's Expanded Editor 3 on the official Modpacker) ([5], [6]): demand for editor depth outstripped what was exposed. A Steam thread asking "what are all the parts that make up a cutscene" ([4]-adjacent discussion, snippet) suggests cutscene authoring is the steep part of the curve.

**Battle for Wesnoth** has a main-menu map editor: terrain-code painting, resize, and since 1.12 unit placement, items, time-of-day schedules and scenario naming — but the wiki is explicit that the editor "cannot create more complex WML"; scripted scenarios are hand-written ([7], [8]). A plain saved map is immediately playable in multiplayer, listed at the top as a "User Map" ([7]). The wiki's map-making guidance is effectively a balance tutorial: symmetrical arenas for MP, villages spaced ~6 hexes apart to avoid gold/healing imbalance, castles and roads placed to shape flow ([7]). Players make MP arenas, map packs, and full UMC campaigns; the forum's Multiplayer Development board alone shows 2,394 topics / 40,827 posts (snippet, [13]). The editor/WML split is the key lesson: painting is accessible to everyone, scripting is a cliff — Wesnoth accepts that cliff because WML is text, diffable and remixable.

**Into the Breach** has *no official editor or mod support*. The community built ITB-ModLoader: Lua injected via proxy DLLs (SDL2, lua5.1, opengl32), 1,530 commits, 65 GitHub stars, Windows-only, no gamepad support; modded savegames break to varying degrees ([14], [16]). The Master Mod List thread categorises mods as only "Squads" and "Miscellaneous" — "not enough mods of any other category" — and has ~459,694 views (snippets, [15]). Steam discussions recommend squad mods (Electric Shamans), weapon pools, and modded islands/enemy sets ([17]). Lesson: the durable mod surface is *unit/weapon data*, not maps — ITB's missions are generated — and code-injection modding is brittle per patch and per platform.

**Door Kickers** (1 and 2). DK1's Workshop is a data-mount system: a mod folder with `mod.xml` (name, changeNotes — its fields populate the Steam listing) and `filesystem_mount.xml`; all paths point at `data/` and are rewritten per-mod; publish/update via command-line flags ([18]). The in-editor Workshop menu offers "Play Map!" for instant testing and a Mod Uploader ([21], snippet). DK2's editor is the richest of the four: node-based wall/room drawing, material paint with blending sets, object placement with depth-selection, lighting and sound zones, weather, enemy AI configuration (roam radius + points of interest, interaction targets), waypoint patrols, triggers that link zones to unit behaviour/lights/sounds, gameplay zones (rescue/escape/EVAC), objective objects, up to three challenges per map (e.g. clock race with a recorded best time), and one-click Publish to Workshop ([19]). Two standout details: **CTRL+E opens any official map in the editor** (learn by deconstruction), and map *bundles* package several maps as a campaign for a better Workshop presentation ([19], [20]-adjacent video). Community questions on the guide cluster around triggers, AI targeting and wall editing — again, the logic layer is the hard part ([19] comments). DK2 has 209 mods on Nexus (snippet, [20]).

**Most-used vs dead weight:** none of the four publishes feature-usage telemetry, so this is inference from output, not measurement (see Gaps). Convergent evidence: terrain paint + unit placement + instant playtest are universal and carry the volume; triggers are the most-asked-about advanced feature; cutscene/decoration tooling is prestige-and-polish, and Wargroove's unlock-mod lineage shows it is wanted but gated. Nothing examined is clearly dead weight; the closest is DK2's "limit area", which the guide author notes "does not have any use as of writing" ([19]).

### Q2 — What makes community maps stick
- **Official curation with a contest.** Wargroove ran a "Community Maps Spotlight" series (at least 18 issues) picking ~3 maps per issue plus a **Community Choice Award voted by upvotes on a Reddit thread**; picks are also featured *in-game*, and a dev-made bonus map keeps the cadence ([3]). Press covered the curation (12 handpicked creations in one feature, [23]). Every map carries an 8-character share code (e.g. `DD2SDQVA`) that works across PC and consoles — Wargroove's built-in Custom Content browser, not Steam Workshop, is the primary distribution ([3], [24]).
- **In-game discovery with feedback loops.** Wesnoth's add-on manager lists type, tags, download counts and upload dates server-side; each add-on can declare a `[feedback] topic_id` linking straight to its forum thread; "Update All" works because versions are enforced x.y.z ([10], [11]). Tags became filterable categories (cooperative, survival, rng, terraforming…) ([10]). Licensing (GPL/CC-BY-SA) is enforced at upload, which keeps remixing legal and normal ([9]).
- **Low-friction publishing + guides.** DK2: publish from inside the editor; the community's video tutorial has a full text transcript, 3,029 unique visitors, 52 ratings, 102 favorites ([19]). DK1's dev-posted Workshop instructions and a community "Red Panda's Workshop Publisher" automation tool lowered the CLI barrier ([18]).
- **A single curated index where no store exists.** ITB's Master Mod List thread (~460k views) plus a Discord `#modding-discussion` channel and Nexus mirrors ([14], [15], [16]).
- **Fan infrastructure fills gaps:** WargrooveCustomMaps.com and r/customgroove exist because browsing codes in-game is weak discovery (snippets, [22]); the fan site explicitly optimises for search-engine ranking so maps can be found outside the game.

Numbers are sparse by nature: the only hard counts verified are the ITB thread views, DK2 guide stats, Nexus's 209 DK2 mods, and the Wesnoth forum board totals. Wesnoth's 1.18 add-on listing exceeds 5 MB of HTML (fetch failed on size, [12]) — consistent with many hundreds of add-ons per version branch, but I could not verify an exact count.

### Q3 — Priorities for the Simple War Maps tab and the JSON package format
Grounded in GDD 03 §3.5: `battle_map` is already a shape list (fills + stamps, merged rectangles so files diff), scenarios own zones/deployment/victory/triggers, the trigger vocabulary is closed and engine-provided with an agreed expansion list (O1Q7: `spawn_squad`, `order_squad`, `squads_in_zone`, `after_turns`…), `mirror` exists for fair 2-player overworld maps, and art is `pkg:id` references ([GDD 03]). Vision pillar 5 (data as data, official content in mod format) and R1Q2's StarCraft-UMS ambition set the ceiling; pillar 2 forbids hidden rules, which a closed trigger vocabulary satisfies by construction.

**Maps tab MVP priority order (recommendation):**
1. **Paint + stamp + instant playtest.** The shape-list editor already matches Wargroove's floor and DK's "Play Map!" loop. Add a one-button "skirmish this map vs AI profile" from the editor — our equivalent of DK2's CTRL+E, and it exercises the MVP's actual mode. Dogfood it on the Angelfall rework, as the release order already requires (GDD 01).
2. **Zones, deployment, victory, turn limit in the editor.** These are the scenario fields that make a map *playable as a scenario*; Wargroove's locations tool and DK2's gameplay zones are the direct models.
3. **Trigger UI over the closed vocabulary.** Wargroove's condition/action/flag model maps almost 1:1 onto our `trigger` template (`on`/`where`/`if`/`do`/`max_fires`, vars as flags). Present it as dropdowns, never free text. This is the feature community questions concentrate on — budget tutorial effort here.
4. **Mirror/symmetry toggle for battle maps** (overworld already has `mirror`; arenas are the volume output in every scene studied).
5. **Defer:** cutscenes/dialogue (Dialogic is presentation-only, later), campaign graph, elevation/structure layer (already reserved), lighting/sound authoring (DK-specific, not our pillar).

**Package metadata for sharing** — Wesnoth's `_server.pbl` is the best-tested field set ([10]); DK1's `mod.xml` adds changeNotes ([18]):
- **Identity:** stable `id`, `title`, `author`, `description`, `type` (battle_map / scenario / map_pack / campaign / overworld_map), `tags`, licence.
- **Version:** numeric x.y.z, enforced — Wesnoth's "Update All" only works because of this; keep a `change_notes` field per release.
- **Preview:** an icon/preview that resolves *before* install. Wesnoth learned this the hard way: custom icons only render for users who already have the add-on, hence the DataURI escape hatch ([10]). Our headless sim (pillar 6) can auto-render a map preview PNG at export — cheap and distinctive.
- **Dependencies:** declared package ids (+ minimum versions). Needed concretely for us: stamps reference other `battle_map`s and art references `pkg:id` across packages; Wesnoth's comma-list `dependencies` is the model.
- **Compatibility:** format/schema version plus a **ruleset pin** — ranked pins rulesets (GDD 01, R3Q12), so a shared map must declare which ruleset it was authored for; determinism (pillar 2) makes this non-optional.
- **Feedback:** a URL/thread field (Wesnoth `[feedback]`) so authors hear about breakage.
- **Safety:** no executable code (already our rule); unknown asset = load error (already GDD 03); validate trigger vocabulary at load, not at runtime.

## Relevance to Simple War
- GDD 01 Vision: R1Q2 promises a UMS-style scene with "gratuitous scripting" — the studied scenes show that ambition is met with a *closed declarative vocabulary plus data*, not a language (Wargroove triggers, DK2 triggers); Wesnoth is the counterexample that accepts a code cliff and pays for it in author count. Pillar 5 and the MVP release order (editor-built skirmish maps, then Angelfall rework) already align with recommendation 1.
- GDD 03 §3.5: the shape-list/stamp format is closer to Wesnoth's diffable text maps than to Wargroove's binary-ish maps — good for a git-friendly mod scene; the editor view must compensate ("the file doesn't look like the map", O1Q11), exactly as Wargroove's live view does.
- Pillar 2 (transparent rules): share-code maps must not be able to smuggle hidden modifiers; closed vocabulary + schema validation + ruleset pin is the enforcement path.
- Steam Deck target (GDD 01): Wargroove's gamepad-first editor UI is the reference for our input-agnostic requirement; ITB's Windows-only loader is the cautionary tale.

## Options and recommendations
- **A. Steam Workshop-first sharing.** Trade-off: best discovery/ratings/updates for free on PC, but networking is parked until after MVP, Workshop is awkward on Deck, and Wargroove shows cross-platform codes work without it. Defer.
- **B. Export/import JSON packages now; share codes + curated "Featured" row later (recommended).** Trade-off: weakest discovery at launch (mitigate with dev-published example maps, as Wargroove's bonus dev map does, and one transcript-style tutorial, as DK2's guide does); strongest fit with data-as-data, headless preview rendering, and the parked-networking constraint.
- **C. File export + external index only (Wesnoth-forum / ITB-GitHub model).** Trade-off: zero infrastructure, but ITB's 460k-view thread shows a single curated index is mandatory, and fan sites (WargrooveCustomMaps.com) appear whether we plan for them or not. Use as the interim discovery channel under B.
- **Editor scope:** do not chase DK2's lighting/sound/decoration depth for MVP; do chase its playtest loop and deconstruction affordance (open any shipped map in the editor). Trade-off: less "pretty map" output early, more playable scenarios — which is what skirmish needs.

## Sources
1. https://wargroove.com/the-campaign-editor/ — dev blog, campaign/scenario editor layers (full read).
2. https://wargroove.com/scripted-events/ — dev blog, triggers/conditions/actions/flags walkthrough (full read).
3. https://wargroove.com/community-maps-spotlight-18/ — curated picks, Community Choice Award, share codes (full read).
4. https://wargroove.com/get-into-the-groove-with-our-first-map-editor-video-guide/ — official editor video guides exist (snippet).
5. https://github.com/Artemis-of-Dust/wg-expanded-editor-3 — editor-unlock mod lineage on official Modpacker (snippet).
6. https://www.nexusmods.com/wargroove/mods/11 — "Unlock Hidden Map Editor Contents" feature list (snippet).
7. https://wiki.wesnoth.org/BuildingMaps — editor capabilities, map-making/balance guidance, User Map flow (full read).
8. https://wiki.wesnoth.org/BuildingScenarios — editor cannot create complex WML (snippet).
9. https://wiki.wesnoth.org/Distributing_content — add-on server publishing, licence rules, feedback tag (full read).
10. https://wiki.wesnoth.org/PblWML — full `_server.pbl` metadata schema: icon/title/version/type/tags/dependencies/feedback (full read).
11. https://addons.wesnoth.org/ — per-version server instances, 1.2→1.20 (full read).
12. https://addons.wesnoth.org/1.18/ — listing too large to fetch (>5 MB); scale evidence only.
13. https://forum.wesnoth.org/ — MP Development board: 2,394 topics / 40,827 posts (snippet).
14. https://github.com/itb-community/ITB-ModLoader — Lua/DLL loader, Windows-only, save breakage, 65 stars/1,530 commits (full read).
15. https://subsetgames.com/forum/viewtopic.php?t=32999 — Master Mod List; 403 on fetch, stats via forum-index snippet (~459,694 views, Squads/Misc only).
16. https://www.nexusmods.com/intothebreach/mods/6 — mod loader description, Windows-only (snippet).
17. https://steamcommunity.com/app/590380/discussions/0/3808405159044105963/ — squad/island/enemy mods in play (snippet).
18. https://inthekillhouse.com/steamworkshop/ — DK1 mod.xml/filesystem_mount.xml, publish/update flow (full read).
19. https://steamcommunity.com/sharedfiles/filedetails/?id=2658647468 — DK2 editor guide transcript: full tool list, CTRL+E, challenges, publish; 3,029 visitors/52 ratings (full read).
20. https://www.nexusmods.com/games/doorkickers2/mods — 209 DK2 mods (snippet).
21. https://steamcommunity.com/sharedfiles/filedetails/?id=1569771035 — DK1 Workshop HowTo: Play Map!, Mod Uploader (snippet).
22. https://www.reddit.com/r/wargroove/comments/ax1qpl/i_made_a_custom_map_sharing_site/ — fan sharing site (snippet).
23. https://nintendosoup.com/check-out-these-clever-wargroove-community-made-maps-handpicked-by-chucklefish/ — 12 curated creations (snippet).
24. https://progaming999.blogspot.com/2019/02/the-best-wargroove-mods-and-custom-maps.html — built-in sharing, not Workshop (snippet; single blog).
25. https://techraptor.net/gaming/features/6-wargroove-maps-you-need-to-check-out — map/cutscene/campaign maker coverage (snippet).

## Confidence and gaps
- **High confidence:** editor feature inventories (primary dev blogs, official wikis, full guide transcript), package-metadata recommendations (PblWML is a mature, documented schema), curation mechanisms (primary blog).
- **Inference, not measurement:** "most-used vs dead weight" — no game here publishes editor telemetry; conclusions rest on community output and question patterns. Flagged wherever used.
- **Unverified numbers:** exact Wesnoth add-on counts (1.18 page >5 MB, not fetched); Wargroove total custom-content count; the Steam Workshop hub for Wargroove exists but its contents/role vs the built-in code sharing could not be verified (source 24 is a single blog).
- **Blocked fetches:** subsetgames.com forum 403 on both hosts (not retried further per rules); ITB mod-list detail is snippet-only. Reddit sources are snippet-only (fetches blocked in prior sessions).
- **Scope note:** "Door Kickers" covered as both DK1 (data-mount Workshop) and DK2 (full 3D editor); DK2 is the richer editor reference.
