# Accessibility baseline audit at 1280×800 (XAG / Steam Deck numbers)

Date: 2026-11-21. Bead: sw-luo (worker-sw-luo, attempt 1). Base commit: ec393cd.
Method: static audit of the code, theme data and project settings at the base
commit; no runtime measurement, no code changes. Checks report items 1–11 from
`docs/swarm/research/reports/accessibility-guidelines-for-turn-based-tactics-games-questi.md`
against the war room, the Angelfall slice and the main menu. Scope excludes
screen narration and switch access (report items 16–17, deferred). The ranked
untimed lockout (GDD R2Q2) is settled and is not relitigated here; this note
only records whether the wiring exists.

## Baseline facts (how size and scale work today)

- Project window: 1280×720 base, stretch `canvas_items`, aspect `expand`
  (`project.godot:37-42`). Logical viewport is 1280×720 at any 16:9 resolution
  (content scales ×1.5 at 1080p, ×2 at 1440p) and 1280×800 at the Deck's
  16:10 native size. **800p is therefore the worst case for text size**: a
  16 px font is 16 device px there, but 24 at 1080p and 32 at 1440p.
- UI scale: `GameSettings.UI_SCALES = [0.75, 1.0, 1.25, 1.5, 2.0]`
  (`src/presentation/options/game_settings.gd:13`), applied as
  `window.content_scale_factor` (`game_settings.gd:80`). It works at every
  resolution and window mode — nothing greys it out (the Civ VI failure from
  the report does not apply). At 200% the logical viewport is 640×400 at
  1280×800 and 640×360 at 16:9 resolutions.
- Scale is applied at startup only by the main menu
  (`src/presentation/main_menu/main_menu.gd:33`) and on change by the options
  screen (`options_screen.gd:117`). Games launched from the menu inherit it on
  the same window; a scene run standalone (F6) gets the theme
  (`UiTheme.ensure`) but not the saved scale. Minor F6-parity gap, not a
  player-facing one.
- Theme as data: profiles in `data/ui/themes/` (default 16 px, large 20 px,
  high_contrast 17 px), named styles in `data/ui/styles.json`, built by
  `src/presentation/ui/ui_theme.gd`. No custom font is set anywhere, so the
  engine default sans-serif (Godot's built-in Open Sans) is used. UI strings
  are sentence case.

Text sizes in the default profile (`data/ui/styles.json`): Caption 12,
Small 13, Card 14, Value 15, (body) 16, Subhead 18, Heading 20, Title 26,
Brand 30, Hero 34; CardHead/Hud labels 13; tooltips `max(size-2, 10)` = 14
(`ui_theme.gd:209`). Sizes scale with the profile (`ui_theme.gd:230,262`)
and with `content_scale_factor`, so the Large profile and 200% scale both
reach every screen.

## Item-by-item

### 1. Untimed toggle, flagged, locked in challenge/ranked — PARTIAL

- Done (sim side): `ClockConfig.untimed` (`src/sim/core/clock_config.gd:36`);
  `PulseClock` honours it — remaining time −1, no phase timeout
  (`src/sim/core/pulse_clock.gd:130-187`); covered by
  `tests/sim/test_pulse_clock.gd`. The config round-trips through saves and
  replays (`src/api/battle_session.gd:444-453`, `src/api/match_replay.gd:66`),
  so an untimed match stays untimed on load. `ClockConfig.ranked` exists
  (`clock_config.gd:31`).
- Missing (player side): no toggle anywhere. `GameSettings.DEFAULTS`
  (`game_settings.gd:15-18`) has no untimed key; the options screen has no
  row; `MatchDriver` creates sessions without a clock config
  (`src/api/match_driver.gd:47`), so every menu game runs the timed default.
  No code forces `untimed = false` when `ranked` (ranked play does not exist
  yet; the guard must land with it — R2Q2 is settled, this is only wiring).
- Mapping: candidate follow-up F1 under sw-ll4.10 (options menus).

### 2. UI/text scale 100–200%, reflow at every resolution — PARTIAL (mostly done)

- Done: 75–200% scale persisted and applied at all resolutions (baseline
  facts above; sw-ll4.19). Main menu centres while it fits and scrolls
  vertically when it doesn't, horizontal scroll disabled
  (`main_menu.gd:74-84`; sw-ll4.26.3 closed). War room layout is data with
  scrollable columns: battle column 290 px scrolls the battle panel; side
  column 250 px (min 220, max 640, grip-resizable, `side_width` setting)
  scrolls all its lists; footer buttons outside the scroll
  (`data/ui/layouts/war_room.json`).
- Missing: **modals do not scroll.** `UiWindow.dialog()` is a CenterContainer
  + PanelContainer with no ScrollContainer and no max height
  (`src/presentation/ui/ui_window.gd:55-67`). The options screen is ~13 rows
  (`options_screen.gd:29-112`), roughly 550–600 px tall at 100%: at 200% the
  logical viewport is only 400 px tall (360 at 16:9), so the dialog overflows
  and the Close button can fall off-screen. The Controls help window is a
  fixed centred panel with a 640 px-wide body (`controls_help.gd:22-33`),
  wider than the 640 px logical viewport at 200%@800p once margins are added.
  This is exactly the XAG 101 "200% without lost content" case; the menu-fit
  work (sw-ll4.26.3) covered the main menu, not modals.
- Risk to verify at runtime: at 200% in battle view the fixed 290 px battle
  column + 220 px minimum side column leave ~130 px of stage at 640 logical
  width. Columns scroll, but the map may be too narrow to use; needs a mock
  or playtest at 640×360 before claiming 200% fully reflows.
- Missing (small): `GameSettings.SIZES` (`game_settings.gd:11-12`) has no
  1280×800 entry, so windowed mode on a Deck cannot pick its native size
  (borderless fullscreen still works).
- Mapping: sw-ll4.26 (candidate child F2 for modal fit), sw-ll4.10 (F3).

### 3. Default body text ≥12 px character height @800p — PARTIAL

- Done: body/default 16 px, Card 14, Value 15 — inside the report's ~14–16 px
  guidance at 800p; sans-serif (engine default); sentence case; Large (20 px)
  and high-contrast (17 px) profiles plus 200% scale all multiply every named
  style. Note the strict reading: Open Sans cap height is ~0.71 em, so a
  16 px font renders ~11.4 px capitals — just under the 12 px *character
  height* recommendation; the report's own convention (font size as proxy)
  passes. Raising the default to 17–18 px would satisfy both readings.
- Missing: **essential state rides on 12 px Caption labels.** The SIMPL band
  readout (icon + word + value, the primary pool state) is CaptionDimLabel
  (`src/presentation/war_room/squad_card.gd:195`), as are effect detail lines
  (:117), defence (:107) and pool/health bar names (:141, :233). 12 px font ≈
  8.6 px cap height: at/below Valve's 9 px floor and well below the 12 px
  recommendation, at the resolution the Deck target is about.
- Missing: **drawn map text can go to 8 px.** Overworld label font
  `fs = clamp(s*0.42, 9, 16)` but reach numbers draw at `maxi(fs-3, 8)`
  (`src/presentation/war_room/context_view.gd:245,299`) and commander/battle
  badges at `maxi(fs-2, 8)` (:385, :393) — an 8 px floor below Valve's 9 px
  minimum. Compact PiP labels are 12 px (:621), battle floaters 10/13 (:961).
- Mapping: theme data is sw-ll4.26.4 territory (closed; candidate F4);
  map-label floor is a candidate under the same pass.

### 4. Never colour alone — PARTIAL (one known bug left)

- Done (sw-ijp.5, closed, verified here): `TeamPalette`
  (`src/presentation/ui/team_palette.gd`) is the single presentation source
  for all four readers (context_view, replay_viewer, battle_panel,
  results_screen); Okabe-Ito default + Tol high-contrast presets, neutral
  grey apart in greyscale, AA-checked label tones; preset persisted in
  `settings.cfg`, resolved at render time, never in sim data (determinism).
  Shape + label redundancy is real: square vs round tokens
  (`context_view.gd:291-294`), "P1/P2 + count" labels (:361), player-number
  badges (:385, :393).
- Done: SIMPL bands read as icon + word + value, never colour alone
  (`squad_card.gd:21-23,184-195`, sw-1jy.3/.4); strength line is numeric
  "N / M units · yours/enemy" (:39); orders are named in text (:42).
- Missing (sw-vld, open, P2 — owns the fix): weapon accuracy/damage
  buff/debuff is colour-only via `_tone()` (`squad_card.gd:122-125`, used at
  :101-103): green/red with no +N/−N marker and no base value. The squad
  Health bar passes empty text (:45), so it has no numeric readout (per-unit
  health numbers appear only in the inspection block, :80).
- No other colour-alone state found in hex_card (no tone usage), battle_panel
  or results_screen (palette colours always carry P1/P2 text).
- Mapping: sw-vld (fix), sw-ijp.5 (done). No new bead needed.

### 5. Remap all actions incl. UI via GUIDE; hints follow bindings — PARTIAL

- Done: all planning commands are remappable GUIDEActions in one mapping
  context — hold/attack-move/fall-back/withdraw/run/abilities, 30 control-group
  actions, 8 camera bookmarks, `is_remappable = true`, display names and
  category set, context enabled/disabled with the tree
  (`src/presentation/planning/planning_input.gd:24-51`); the `actions` dict is
  exposed for a future remapping UI (:20-21).
- Missing: **no remapping UI and no binding persistence** — nothing calls
  GUIDE's remap/serialization API; sw-ll4.9.2 owns the GUIDE key work and
  sw-ll4.10 the controls-rebinding options.
- Missing: hard-coded keys outside GUIDE: war-room camera pan arrows
  (`war_room.gd:1299`), Tab/Esc/F/V/Backspace/Space (:1313-1331), Shift for
  waypoints (:590, :607), Enter (:1283); Esc in `ui_root.gd:143`; the replay
  viewer registers plain InputMap actions "until the GUIDE input layer"
  (`replay_viewer.gd:119-125`). Dialogic advance is a project InputMap action
  (`project.godot [input] dialogic_default_action`, includes joypad A).
- Missing: **hints do not follow bindings.** ControlsHelp is static text with
  the default keys baked in (`controls_help.gd:6-12`); the End turn button
  says "End turn (Space)" (`war_room.gd:345`). No glyph rendering anywhere.
- Missing: no joypad bindings for planning actions (GUIDEInputKey only).
- Mapping: sw-ll4.9.2 + sw-ll4.10; candidate F6 consolidates the leftovers.

### 6. Controller-complete menus, focus order, visible focus — PARTIAL

- Done: visible focus — accent focus styleboxes for Button, MenuButton,
  OptionButton, LineEdit, TextEdit, ItemList, Tree, CheckBox/CheckButton
  (`ui_theme.gd:165-201`). Modal focus discipline: UiRoot focuses the first
  focusable control on open, restores focus on close, Esc closes the top
  modal, keys are gated under `captures_keys`
  (`src/presentation/ui/ui_root.gd:60-63,104-147`). Touch/click targets:
  main-menu buttons ≥36 px tall (`main_menu.gd:101,137,164`), options Close
  38 px (`options_screen.gd:109`).
- Done (deliberate keyboard-first design): the war room drops button focus on
  any key press so Space stays "end turn"; Enter still presses; modal windows
  keep their focus (`war_room.gd:1276-1294`).
- Missing: **no controller path into the war room.** No `InputEventJoypad*`
  handling in `src/` (grep: zero hits); the war room's `_input` /
  `_unhandled_input` filter to `InputEventKey`, so joypad buttons never reach
  Tab/Space/Esc equivalents. Menus themselves can use Godot's default `ui_*`
  actions (which include joypad), but no focus neighbours are set for a
  logical order across war-room panels, and no device glyphs are shown.
  Dialogic advance already accepts joypad A (project input map).
- Mapping: candidate F7 (Deck Verified target); relates to sw-ll4.9.2 /
  sw-ll4.26 but no existing child covers it.

### 7. Drag-select alternatives, activate-on-release, cancel/undo — PARTIAL

- Done: box-drag has alternatives — single click select, Shift add, Ctrl
  toggle, double-click select-by-type (`controls_help.gd:9`;
  `war_room.gd:1050-1056` `select_type`). Overworld orders are click-click by
  nature (select, then right-click destination; "Send to" then click target).
- Missing: **orders fire on mouse press, not release.** ContextView emits
  clicks on `mb.pressed` (`context_view.gd:1230-1237`) and the war room acts
  immediately (`war_room.gd:1058-1068`); XAG 107 prefers activate-on-release
  so a press can be aborted by dragging off.
- Partial: cancel exists (Esc clears an armed target, right-click empty
  deselects, Backspace deselects all, right-click own commander clears its
  route — `war_room.gd:1315-1321`, `controls_help.gd:8`), but there is no
  order undo/take-back once a move/attack order is issued.
- Mapping: candidate F8; no existing bead covers this.

### 8. Notifications persist; battle alerts mirrored — DONE

- The event feed is persistent, not transient: `_refresh_log` accumulates
  per-turn EventText lines, trigger messages and the mission outcome across
  the whole match and renders the newest 14 in the scrollable side-column
  "events" panel (`war_room.gd:1474-1494`, `data/ui/layouts/war_room.json`;
  sw-ip8.7). No auto-dismiss timers exist anywhere, so there is nothing to
  extend (XAG 116 satisfied by persistence).
- Parallel-battle alerts are mirrored: persistent Reactions list panel +
  phase banner during the reaction window (`war_room.gd:699-700,1712`),
  jump-to-reaction focuses the battle and opens the radial (:1270-1274), and
  the movable picture-in-picture panel shows any other battle live
  (`pip_panel.gd`). Outcome banner persists until the results screen
  (:1496-1508). Full history lives in the match log (`src/api/match_log.gd`).
- Minor: only the newest 14 lines render; older ones stay in `messages` and
  the match log but have no in-room "show older" affordance. Not a guideline
  failure; optional polish.
- Mapping: already delivered (sw-ip8.7); none of the five listed beads owns
  this — recorded as done.

### 9. Subtitles for story speech, speaker names, options — MISSING (pre-voice)

- No voiced speech exists yet (no audio assets or voice references in `src/`
  or `data/packages/`), so there is nothing to subtitle today. The Angelfall
  slice is the war room on `angelfall_frontier`
  (`src/presentation/angelfall/angelfall.tscn`); story text arrives as
  `trigger_message` events into the persistent event feed through the
  translation-fallback `_say` (`war_room.gd:1482,1581`) — self-paced and
  persistent, which satisfies the cognitive side.
- Dialogic is installed and configured (autoload `project.godot:25`; advance
  action includes Enter/Space/X/click/joypad-A) but **no timelines or
  characters exist in the repo** (empty dch/dtl directories; no `.dtl`
  outside addons). When voiced story lands (M4), subtitles with speaker
  names, on by default, plus size/background options must land with it.
- Mapping: candidate F9, tied to the Angelfall story work; none of the five
  listed beads covers it.

### 10. All settings persisted; per-device — DONE

- `GameSettings` saves every key to `user://settings.cfg` on each change,
  type-checked on load, with defaults (`game_settings.gd:15-60`): window
  mode/size, vsync, ui_scale, turn playback seconds, ui_theme, side_width,
  team_palette. Local file only — per-device by construction, no cloud sync
  (Deck recommendation). Options apply immediately and report write errors
  (`options_screen.gd:115-121`). Settings that don't exist yet (language,
  remaps, untimed) are tracked under their own items.
- Mapping: sw-ll4.19 / sw-ijp.5 / sw-ll4.9 foundations — done.

### 11. Difficulty range + timer scaling; mid-game change; self-paced text — PARTIAL

- De facto difficulty choice exists: the skirmish opponent is an AI profile
  picked in the main menu (`main_menu.gd:107-116`), but it is not labelled or
  presented as difficulty, and there is no difficulty setting anywhere
  (grep: only a lore note in `data/packages/core/defs/angelfall.json:127`
  about easy-mode revival, which is future design text, not a feature).
- Timer scaling: `ClockConfig` is fully data (planning budget, reserve,
  bonuses, reaction window — `clock_config.gd`) and serializes, but no UI
  scales it. The options "A turn plays out over" setting is playback speed
  only (presentation; `game_settings.gd:14`), not the turn budget.
- Mid-game change: nothing to change yet. Self-paced text: done (item 9).
- Mapping: candidate F10 under sw-ll4.10; GDD R2Q3 (configurable independent
  clocks) is the hook.

## Summary

| # | Item | Status | Owner / mapping |
|---|---|---|---|
| 1 | Untimed toggle + ranked lockout | partial (sim done, no UI/wiring) | F1 → sw-ll4.10 |
| 2 | UI scale 100–200% everywhere | partial (modals clip at 200%) | F2 → sw-ll4.26; F3 → sw-ll4.10 |
| 3 | Text ≥12 px character height @800p | partial (Caption 12 px essential; 8 px map floor) | F4 → sw-ll4.26 |
| 4 | Never colour alone | partial (squad-card bug left) | sw-vld (open); sw-ijp.5 done |
| 5 | GUIDE remap incl. UI, live hints | partial (planning only) | sw-ll4.9.2 + sw-ll4.10; F6 |
| 6 | Controller-complete menus/focus | partial (focus yes, joypad no) | F7 |
| 7 | Select alternatives / release / undo | partial (alternatives yes) | F8 |
| 8 | Persistent notifications/mirrors | done | sw-ip8.7 (delivered) |
| 9 | Story subtitles | missing (no voice yet; Dialogic ready) | F9 (with M4 voice) |
| 10 | Settings persisted per-device | done | sw-ll4.19 / sw-ijp.5 |
| 11 | Difficulty + timer scaling | partial (AI profiles only) | F10 → sw-ll4.10 |

## Candidate follow-ups (not created as beads; orchestrator's call)

- **F1 (P1): Untimed option wiring.** `untimed` key in GameSettings + options
  row (flagged as assist), MatchDriver passes a ClockConfig, and the ranked
  guard (`untimed = false` when `ranked`) lands with ranked play. Sim side is
  already tested. Parent: sw-ll4.10.
- **F2 (P1): Modal fit at 200%.** ScrollContainer + max-height in
  `UiWindow.dialog()`; cap ControlsHelp body width to the viewport; verify
  war-room battle view at 640×360 logical (battle column 290 + side min 220
  leave ~130 px stage). Parent: sw-ll4.26 (new child; .3 covered only the
  main menu).
- **F3 (P2): Add 1280×800 to `GameSettings.SIZES`** so windowed mode offers
  the Deck native size. One line + test. Parent: sw-ll4.10.
- **F4 (P1): Text floors.** Raise Caption 12→14 (or move essential band/effect
  readouts to Small+) in `data/ui/styles.json`/squad_card; raise the drawn
  map-label floor from 8 to ≥9 px in context_view; consider default body
  16→17–18 px to clear the strict cap-height reading. Theme-data change,
  sw-ll4.26.4 territory.
- **F5: none — sw-vld already covers the squad-card colour-alone fix**
  (direction markers + Health numbers); keep it P2 or raise to P1 given the
  Deck target.
- **F6 (P1): GUIDE completion + remap UI.** Move war-room camera/context keys,
  replay-viewer keys and modal Esc into GUIDE actions; remapping UI with
  persisted bindings (GUIDE serialization); generate ControlsHelp and button
  hints from active bindings. Parents: sw-ll4.9.2, sw-ll4.10.
- **F7 (P2): Controller navigation.** Joypad equivalents for war-room keys
  (the `_input` filters currently drop joypad events), focus neighbours across
  panels, device-aware glyphs. Deck Verified prerequisite.
- **F8 (P2): Activate-on-release orders + order take-back.** Move order
  issuance to button release; add an undo for the last issued order.
- **F9 (P2, with M4 voice): Subtitles.** Dialogic timelines with speaker names,
  subtitles on by default, size/background options; keep the event-feed text
  path for non-voiced story.
- **F10 (P2): Difficulty/assist menu.** Label the AI-profile choice as
  difficulty, expose ClockConfig timer scaling as an assist, allow mid-game
  change in SP. Parent: sw-ll4.10.

## Caveats

- Static audit: the 200% modal-clip and 640×360 stage findings are computed
  from layout data and container types, not observed at runtime; a mock run
  (`hx godot mock`) at 200% should confirm F2 before it is sized.
- Character-height numbers use Open Sans metrics (~0.71 em cap height); the
  report itself uses font size as the proxy, and both readings are given.
- Nothing here changes the settled R2Q2 decision; F1 only wires the flag the
  GDD already promises.
