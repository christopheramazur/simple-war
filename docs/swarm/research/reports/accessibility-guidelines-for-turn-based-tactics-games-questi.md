# Accessibility guidelines for turn-based tactics games

Date: 2026-11-21. Requested by: craft-researcher.

## Questions

1. Which Game Accessibility Guidelines (GAG) and Xbox Accessibility Guidelines (XAG v3.2) items apply to a deterministic WeGo tactics game with hex overworld, parallel battles, turn timers and dense UI?
2. Rank them by impact vs implementation cost for Simple War (cheap wins vs expensive).
3. What do shipped tactics/strategy games actually offer, and what do disabled players praise or criticise?
4. What does Steam Deck readability guidance imply for default fonts, UI scale and input targets?

## Short answer (5 lines)

WeGo tactics removes most motor barriers by design; the real risks are colour-only faction identity, unreadable dense UI, time pressure, and notifications lost across parallel battles. The GDD already promises the five cheap wins (untimed mode, UI/text scale, colour-blind palettes, GUIDE remapping, options menus); finish those to XAG/Deck numbers first. Never let colour alone identify a faction — Advance Wars' accessibility review fails on exactly this. Ship text ≥12px character height at 1280×800 with 200% scaling that works at every resolution (Civ VI's greyed-out scaler is the cautionary tale). Defer screen-reader narration and switch access; they are the expensive tail.

## Findings

### Q1 — Applicable items, with tier/ID

GAG items have no numeric IDs; they are named items within Basic/Intermediate/Advanced tiers ([full list](https://gameaccessibilityguidelines.com/full-list/)). Applicable to Simple War:

| Area | Basic | Intermediate | Advanced |
|---|---|---|---|
| Motor | Remap controls; simpler control alternative; all UI reachable with the gameplay input method; large, well-spaced targets (touch/small screens); game-speed option; sensitivity option; haptics toggle | Resize interfaces; no required button holds; drag/simultaneous input only as alternative (click-click equivalents); all key actions via digital presses; multiple input devices; windowed mode; stationary targets; macro system (control groups already exist) | No essential precise timing (the untimed option); 0.5s post-input cooldown; switch/eye-tracking-compatible simple schemes |
| Vision | High text/UI contrast; readable default font size; **no essential info by fixed colour alone**; large targets | Resize interfaces; contrast option; cursor colour/design choice; keep essential temporary info in the eye-line; screen-reader-friendly manual/website; distinct event sounds; hide background movement | Adjustable font size; screen-reader support incl. menus; audio description; distinct sound design per object/event |
| Hearing | Subtitles for all important speech; clear subtitle presentation; no essential info by sound alone; separate volume sliders | Customisable captions; speaker indicator; captions for significant background sounds; captions available before first sound; stereo/mono toggle; visual mirror of audio info (off-screen battle alerts) | — (signing not applicable) |
| Cognitive | Readable default font; clear text formatting and simple language; self-paced text prompts; interactive tutorials; avoid flicker; start without deep menus | Objective and controls reminders; contextual help (glossary tooltips); highlight key words; text colour/contrast choice; practice/sandbox mode; story progress summaries; save thumbnails; clear interactivity cues | Replayable narrative/instructions |
| General | Settings saved/remembered; wide difficulty choice; document accessibility features in-game and on store/website; solicit feedback | Autosave + manual save; expose tuning variables ("data as data" fits); difficulty change mid-game; impaired play-testers; skip non-core content | Settings profiles |

Not applicable: VR/FOV items, motion tracking, speech input/recognition, portrait mode. Multiplayer chat items (GAG hearing/speech intermediate; XAG 119/120) become applicable when networking lands.

[XAG v3.2](https://docs.xbox.com/build/game-principles/accessibility/xbox-accessibility-guidelines) applicable now: **101** text display, **102** contrast, **103** additional cues (no single-sense cues), **104** subtitles/captions, **105** separate audio volumes, **107** input, **108** difficulty options, **109** object clarity, **110** haptics, **112** UI navigation order, **113** visible focus, **114** UI context/labels, **115** error messages/undo, **116** time limits, **117** motion/distraction opt-outs, **118** photosensitivity, **121** feature documentation. Later: **106** screen narration, **111** audio description, **122** support, **123** mental-health/content warnings (story).

WeGo-specific notes:
- **Timers:** [XAG 116](https://docs.xbox.com/build/game-principles/accessibility/xag-deep-dives/xag-116-time-limits.md) explicitly exempts time limits that are core mechanics — Simple War's turn timers are the difficulty source (GDD 01, Pillars), so they fall under XAG 108 assists + the GDD's untimed flag, while XAG 116 still governs UI toasts/dialogue: extendable ≥10× or persist-until-dismissed.
- **Parallel battles:** GAG vision-intermediate "essential temporary info in the eye-line" + XAG 103/109 mean battle alerts must be mirrored in a persistent, glanceable place, not only as transient effects in a battle the player isn't watching.
- **Determinism/transparency:** the glossary-tooltip pillar already satisfies much of GAG cognitive-intermediate contextual help; keep verbosity settings reachable.

### Q2 — Ranked, costed checklist for Simple War

Cost: S ≈ ≤1 dev-day, M ≈ 2–5 days, L ≈ >1 week (rough agent-effort estimates). Impact: H/M/L. "GDD" = already promised in GDD 01.

| # | Bead-ready item | Impact | Cost | Ref | When |
|---|---|---|---|---|---|
| 1 | Untimed toggle, flagged, locked off in challenge/ranked | H | S | GAG adv-motor; XAG 108; GDD R2Q2 | MVP (GDD) |
| 2 | UI/text scale 100–200%, reflow without two-axis scrolling, working at **every** resolution incl. 1280×800 | H | M | XAG 101; GDD | MVP (GDD) |
| 3 | Default body text ≥12px character height @800p (~14–16px), sans-serif option, sentence case | H | S | Deck compat; XAG 101 | MVP |
| 4 | Never colour alone: faction/state via shape+label+icon; colour-blind palette presets as data | H | S–M | GAG basic-vision; XAG 102/109; GDD | MVP (GDD) |
| 5 | Remap all actions incl. UI via GUIDE; hints/glyphs update with bindings | H | S | GAG basic-motor; XAG 107; GDD | MVP (GDD) |
| 6 | Controller-complete menus: logical focus order, visible focus, single-press navigation, correct glyphs | H | M | XAG 112/113/107; Deck Verified | MVP (Deck target) |
| 7 | Drag-select alternatives (click-click box, select-by-type), activate-on-release, cancel/undo orders | H | M | XAG 107; GAG int-motor | MVP |
| 8 | Notifications persist or duration slider ≥10×; battle alerts mirrored visually in a persistent panel | H | S–M | XAG 116/103 | MVP |
| 9 | Subtitles for all story speech, speaker names, on by default; size/background options | H | S–M | GAG basic/int-hearing; XAG 104 | Angelfall (story is the draw) |
| 10 | All settings persisted; display settings per-device, not cloud-synced | H | S | GAG basic-general; Deck recs; `settings.cfg` exists | MVP |
| 11 | Difficulty range + timer scaling; change mid-game in SP; self-paced/replayable dialogue | M | S | GAG basic/int-general; XAG 108/116 | MVP |
| 12 | Photosensitivity-safe mode (no flashing; dampen fraying-reality VFX); motion opt-outs | M | S–M | GAG basic-cognitive; XAG 117/118 | with VFX pass |
| 13 | Cursor size/colour choice; contrast slider; high-contrast UI theme | M | M | GAG int-vision; XAG 102 | post-MVP |
| 14 | Per-panel HUD rearrange/hide (GDD promise) | M | L | GAG int-motor; GDD | post-MVP |
| 15 | Haptics toggle + intensity | L | S | XAG 110; GAG basic-motor | when rumble lands |
| 16 | Screen narration/TTS of menus + battle state (Godot `DisplayServer.tts_*` exists, but narrating a dense hex/battle UI is a project) | H for blind players | L | XAG 106; GAG adv-vision | defer |
| 17 | Switch-access / one-button scanning scheme | M | L | GAG adv-motor | defer |

Cheap wins confirmed: 1, 3, 4, 5, 10, 11 (untimed, fonts, palettes, remapping, captions are all S-cost because timers, palettes and strings are already data). Expensive tail: 16–17 (narration, full motor-accessibility schemes), 14 (HUD rearrangement).

### Q3 — What shipped games offer; player praise/criticism

- **Into the Breach:** mouse-only or gamepad, fully customisable hotkeys, colourblind mode, two font sizes, windowed mode, Easy/Normal/Hard/Unfair, no time pressure; Windows Magnifier works ([PCgamecontrols wiki](https://pcgamecontrols.fandom.com/wiki/Into_The_Breach)). Players report the colourblind mode swaps the red targeting reticle for bright pink, making targets readable amid fire ([Steam thread](https://steamcommunity.com/app/590380/discussions/0/1694914736007093116/)). Praised as a gem of accessible turn-based design.
- **Advance Wars 1+2 Re-Boot Camp:** [Can I Play That? review](https://caniplaythat.com/2023/06/02/advance-wars-12-re-boot-camp-accessibility-review/) (Dr. Josh Straub): no fine-motor barriers single-player ("entire game can be played with a single finger"), large readable dialogue boxes with speaker names, casual difficulty; timed online turns are the motor barrier. **Fatal flaw: faction identity is colour alone** — identical unit shapes across armies, no colourblind support; reviewer won't recommend it to colourblind players and names shapes/labels as the fix. This is the single most transferable lesson for Simple War.
- **Wargroove:** red-green and yellow-blue colourblind modes plus locking units to specific colours ([GameCritics](https://gamecritics.com/aj-small/wargroove-review/), [Confreaks & Geeks](https://www.confreaksandgeeks.com/wargroove-review/)); criticism: reviewer still loses the pointer sometimes; no mid-battle saves, only auto quicksave. **Wargroove 2** added a photosensitivity mode (disables weather effects) and vibration toggle, but was criticised as "rather meager" accessibility at launch ([Phenixx Gaming](https://web.phenixxgaming.com/2023/10/06/wargroove-2-pc-review/)).
- **Unity of Command 2:** no documented accessibility options found in searches (gap, see below); inherently untimed turn-based. Community thread complains camera control interferes with unit control ([Steam](https://steamcommunity.com/app/809230/discussions/0/1658943011693401674/)) — a warning for our overworld/battle camera sharing input with selection.
- **Civilization VI:** UI upscaling exists but is **greyed out at many resolutions** (1080p laptop, 1440p); a player titled a thread "Accessibility is terrible" because text is unreadable and the scaler unavailable; community fixes are a Workshop mod (+280% font) and a debug-console `ui scale` command ([Steam thread](https://steamcommunity.com/app/289070/discussions/0/3496509872208993569/)). A third-party [screen-reader integration mod](https://github.com/flat-arther/Civ-VI-Accessibility-Integration) adds spoken UI + keyboard navigation — evidence blind players want 4X/strategy access and official support is absent.
- **Frostpunk:** [CPT Deaf review](https://caniplaythat.com/2020/01/16/deaf-game-review-frostpunk/) scored 9.8/10: cinematic subtitles readable by default, every event has a visual icon, rumble flags alerts; wanted a gameplay-text-size option. Conflicting Steam thread claims "no option for subtitles" ([thread](https://steamcommunity.com/app/323190/discussions/0/2828702373005100824/)) — likely about non-cinematic voice; treat as unresolved. Survivor difficulty removes pause, driving keybind requests ([Reddit](https://www.reddit.com/r/Frostpunk/comments/k7em9t/more_keybinds_and_some_ui_improvements/)); active pause (order while paused) is beloved. **Frostpunk 2** colourblind players report red faction icons on red backgrounds and indistinguishable districts ([Steam](https://steamcommunity.com/app/1601580/discussions/0/594010736965982779/)) — again, colour-only state.

### Q4 — Steam Deck implications

Valve's [compatibility criteria](https://partner.steamgames.com/doc/steamhardware/compat) (Verified): native **1280×800** preferred; interface text readable at **12 in / 30 cm**; smallest font character **never below 9px height at 1280×800**, with **12px recommended**; user-configurable text size and contrast recommended; default controller config must reach all functionality with correct glyphs; on-screen keyboard for text entry; 30fps at 800p defaults. [Recommendations](https://partner.steamgames.com/doc/steamhardware/recommendations) add: mixed mouse+stick input without lockout, no launcher, offline single-player, per-device graphics settings (don't cloud-sync them), aspect-ratio support.

[XAG 101](https://docs.xbox.com/build/game-principles/accessibility/xag-deep-dives/xag-101-text-display.md) (PC): minimum default **body height 18px at 1080p** (≈13px at 800p), scaling to **200%** without lost content, no forced two-axis scrolling, sans-serif option, line width ≤80 chars, line spacing ≥1.5×, sentence-case option. [XAG 107](https://docs.xbox.com/build/game-principles/accessibility/xag-deep-dives/xag-107-input.md) touch minimums: 15mm phones / 24mm tablets; at the Deck's ~216 PPI that is ≈127px / ≈204px — realistic only for primary touch controls; pointer-driven panels should still use large, well-spaced targets (GAG basic) with generous hit areas.

Implications for Simple War: design the war room at 1280×800 first; default body text ~14–16px (floor 12px, never 9px); UI scale slider to 200% with reflow; hex/squad glyphs must stay distinguishable at 7 inches; save-name entry must invoke the Steam OSK (Steamworks API) or a controller-native entry; glyphs must follow the active device (Steam Input API recommended). Valve publishes no touch-target pixel minimum for Deck — that number is a gap, use XAG 107/GAG wording.

## Relevance to Simple War

GDD 01 *Vision*: Pillars (parallel play; transparency), *Modes* (R2Q2: timers in all modes, flagged untimed option, locked in challenge/ranked), *Platforms* (R8Q9: Deck design target = input-agnostic + readable UI), *Input and UI* (R1Q4/R8Q10: GUIDE remapping, scalable UI/text, colour-blind-safe palettes, never colour alone), *Release order* (O1Q1: MVP must ship options menus). GDD 02 *Rules Spec* §2.2 (shared pulse; independent clocks configurable, R2Q3) and §2.4 (reaction window; per-battle bonus planning time) are where untimed/assist hooks live. GDD 07 Glossary tooltips already serve cognitive contextual help. Because palettes, timers and strings are data (GDD 01 pillar 5), items 1/4/5/10 above are genuinely cheap. The ranked lockout of untimed is a settled GDD decision — do not relitigate; the unrated-queue phase (R7Q10) is a possible future place to offer it, designers' call.

## Options and recommendations

- **A (recommended): MVP baseline = GDD promises built to XAG/Deck numbers** (items 1–8, 10–11). Trade-off: ~2–3 weeks of focused work, but every item doubles as Deck Verified readiness and fixes the exact failures reviewers flag in this genre.
- **B: A + visual-accessibility pack** (12–13: photosensitivity, contrast, cursor). Trade-off: more polish before first playtest; VFX don't exist yet, so 12 is partly a constraint on future art rather than code now.
- **C: Defer narration/switch access (16–17) to a post-MVP epic.** Trade-off: blind and severe-motor players excluded until then; mitigated by keeping UI focus order and TTS-friendly string keys from day one (cheap insurance).

Do first, in order: never-colour-alone audit of faction/squad rendering (Advance Wars lesson), resolution-independent UI scale (Civ VI lesson), Deck font floor, untimed flag, persistent battle notifications.

## Sources

1. https://gameaccessibilityguidelines.com/full-list/ — GAG full list, all three tiers by category.
2. https://learn.microsoft.com/en-us/xbox/accessibility/guidelines — XAG v3.2 overview and structure.
3. https://docs.xbox.com/build/game-principles/accessibility/xbox-accessibility-guidelines — index of all 23 XAG IDs.
4. https://docs.xbox.com/build/game-principles/accessibility/xag-deep-dives/xag-101-text-display.md — text minimums, 200% scaling, spacing.
5. https://docs.xbox.com/build/game-principles/accessibility/xag-deep-dives/xag-107-input.md — remapping, digital alternatives, touch targets.
6. https://docs.xbox.com/build/game-principles/accessibility/xag-deep-dives/xag-116-time-limits.md — UI time limits; core-mechanic exemption.
7. https://partner.steamgames.com/doc/steamhardware/compat — Deck Verified criteria incl. 9px/12px text rule.
8. https://partner.steamgames.com/doc/steamhardware/recommendations — mixed input, per-device settings, offline, launchers.
9. https://pcgamecontrols.fandom.com/wiki/Into_The_Breach — ITB accessibility quick facts.
10. https://steamcommunity.com/app/590380/discussions/0/1694914736007093116/ — ITB colourblind-mode player report.
11. https://caniplaythat.com/2023/06/02/advance-wars-12-re-boot-camp-accessibility-review/ — Advance Wars accessibility review.
12. https://gamecritics.com/aj-small/wargroove-review/ — Wargroove colourblind modes, pointer criticism.
13. https://www.confreaksandgeeks.com/wargroove-review/ — Wargroove unit colour lock, quicksave.
14. https://web.phenixxgaming.com/2023/10/06/wargroove-2-pc-review/ — Wargroove 2 accessibility criticised as meager.
15. https://caniplaythat.com/2020/01/16/deaf-game-review-frostpunk/ — Frostpunk Deaf review, 9.8/10.
16. https://steamcommunity.com/app/323190/discussions/0/2828702373005100824/ — Frostpunk "poor accessibility" thread (conflicting).
17. https://steamcommunity.com/app/1601580/discussions/0/594010736965982779/ — Frostpunk 2 colourblind complaints.
18. https://www.reddit.com/r/Frostpunk/comments/k7em9t/more_keybinds_and_some_ui_improvements/ — Survivor no-pause keybind request.
19. https://steamcommunity.com/app/289070/discussions/0/3496509872208993569/ — Civ VI unreadable text, greyed-out scaler, +280% mod.
20. https://github.com/flat-arther/Civ-VI-Accessibility-Integration — third-party Civ VI screen-reader mod.
21. https://steamcommunity.com/app/809230/discussions/0/1658943011693401674/ — UoC2 camera-vs-unit control complaints.

## Confidence and gaps

High confidence: guideline texts, XAG numbers, Valve criteria, CPT reviews (primary sources, read in full). Medium: game feature lists for ITB/Wargroove/Frostpunk (community wikis/reviews, consistent across sources). Gaps: no accessibility review found for Into the Breach or Unity of Command 2; UoC2's options are undocumented in sources reached (absence claim, two search angles; official manual not read). Community threads 10/16/17/18/21 were read via search excerpts, not full pages. Civ VI colourblind-mode existence unverified (only a video guide title). Frostpunk subtitle claims conflict (15 vs 16). No Valve touch-target pixel minimum exists in the docs reached. Cost estimates are my judgement, not measured.
