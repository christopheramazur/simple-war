
## 2026-11-21 13:5x UTC turn (worker-sw-1jy.4, attempt 2)
- did: implemented downward points-to-drop: BattleRules.band_for/points_to_drop (pure static, same FPDR mapping as band_of), squad_card verbose text "· N to <band>", 4 new GUT tests; commits f23b59b + 3337c5c on swarm/sw-1jy.4.
- decided: distance = smallest loss that drops one band; Broken/no-cap = -1 (no text); FPDR tie-rounding gives up to 0.5% headroom at a floor (displayed = used).
- tests: hx godot check 0 errors; full suite 480/480 (7809 asserts).
- next: orchestrator review/merge; upward/both directions = one-line helper extension later.

## 2026-11-21 14:3x UTC turn (worker-sw-ll4.27.3, attempt 2)
- did: merge-conflict-only attempt. Merged main into swarm/sw-ll4.27.3 (merge ff9a7d4); resolved the single squad_card.gd conflict keeping BOTH features verbatim: 1jy.4 verbose points-to-drop meter text AND the activity line / weapons block / moment(). Regenerated squad_card.png (verbose card now shows "· N to <band>").
- decided: combined build() doc comment; kept ctx param signature. No other files touched.
- tests: hx godot check 0 errors (156 scripts); full hx godot test 496/496 (8002 asserts).
- next: orchestrator review/merge; branch ready.

## 2026-11-21 14:3x UTC turn (worker-sw-luo, attempt 1)
- did: audit-only bead sw-luo; wrote docs/swarm/research/notes/accessibility-baseline-1280x800.md checking report items 1-11 against war room/Angelfall/main menu at ec393cd; commit 2e07760 on swarm/sw-luo. No code changes, no new beads.
- decided: statuses — done: 8 (persistent event feed/PiP/reactions), 10 (settings.cfg per-device); partial: 1 (untimed sim flag only, no UI/wiring), 2 (scale works everywhere but UiWindow.dialog has no scroll -> clips at 200%@800p, logical 640x400), 3 (Caption 12px carries essential band text; map draw_string floor 8px), 4 (sw-vld still open), 5 (GUIDE covers planning only; war-room/replay/Esc keys hard-coded; static hints), 6 (focus styles+modal focus done, zero joypad handling), 7 (click/type-select yes, orders fire on press, no undo), 11 (AI profiles only); missing: 9 (no voice yet, Dialogic installed but no timelines).
- next: orchestrator review/merge; note lists candidate follow-ups F1-F10 (no beads created): untimed wiring, modal scroll at 200%, 1280x800 in SIZES, text floors, GUIDE completion+remap UI, controller nav, release-activate+undo, subtitles with M4 voice, difficulty/assist menu.
- blocked/asked: none; R2Q2 ranked lockout treated as settled, only wiring gap recorded.

## 2026-11-21 14:5x UTC turn (worker-sw-opt, attempt 1)
- did: F2 modal fit at 200% + F3 Deck size. ui_window.dialog() and ControlsHelp.window() now centre-while-fit / scroll-vertically inside the viewport (main-menu pattern sw-ll4.26.3), horizontal scroll off, scroll focus_mode NONE (no focus trap, Esc passes to UiRoot); help body width capped to viewport minus margins (autowrap); GameSettings.SIZES += 1280x800. Before/after mock at logical 640x400 shows Close off-screen before, reachable after. 4 new GUT tests. Commits a7bff93 + ab2d055 on swarm/sw-opt.
- decided: whole-body vertical scroll (title at top / Close at bottom, both reachable) instead of pinned header/footer, to keep dialog() API and every caller unchanged; matches the merged main-menu precedent. ScrollContainer h_scroll_bar.max_value can read nonzero while disabled-and-fit, so tests assert geometry (centre/panel <= viewport) not that range.
- tests: hx godot check 0 errors; full hx godot test 493/493 (7974 asserts).
- next: orchestrator review/merge; attempt 2 = F4 text floors once sw-ll4.27.3/.6 merge (do not touch squad_card/context_view before then).
- blocked/asked: none. War-room 640x360 stage (battle col 290 + side min 220) runtime-verify left as follow-up, out of attempt-1 scope.

## 2026-11-22 turn (autopilot, sw-rlg)
- did: mock_runner.gd now writes <name>_greyscale/_protan/_deutan.png beside the normal PNG via new shared src/presentation/mocks/cvd_sim.gd (same Machado 2009 / WCAG maths as team_palette_mock); godot.py mock_variant_paths + `variants` in output; README documented; pytest added. Proof: team_palette mock -> 3 variants.
- decided: conversion on the Godot side (no Python deps); normal PNG path/content untouched.
- tests: hx godot check 0 errors; pytest run.

## 2026-11-22 turn (autopilot, sw-kys.9)
- did: wrote docs/swarm/research/notes/cc0-asset-shortlist.md. Kenney (carried forward) and SBS Town Pack (CC0 verified verbatim on the page) are usable. Other SBS iso packs (not linked from the page) and the Blarumyrran OGA sprites (403 on the page, search excerpt only) are marked unverified/unusable.
- decided: a search excerpt is not page verification, so Blarumyrran stays unusable until a person reads the page.
- tests: docs-only, none.

## 2026-11-22 turn (autopilot, sw-136.3)
- did: wrote docs/swarm/research/notes/angelfall-tutorial-pacing-gaps.md: 4 gaps (stakes escalation, objective ordering, first lift-off vs taught mechanics, first battle is the finale), each with options and GDD refs.
- decided: options only, no chosen fix, no GDD/code/data edits.
- tests: docs-only, none.

## 2026-11-22 turn (autopilot, sw-136.4)
- did: wrote docs/swarm/research/notes/angelfall-glossary-tooltip-audit.md: term-by-term table (hover y/n, glossary y/n), 9 candidate follow-ups, legibility at 1280x800, no-mouse reachability.
- found: only `_title()` headings and the Events log are hoverable; squad card, battle panel, hex card, phase text are plain Labels; no keyboard/controller path to any tooltip; Ruin term clashes with the ruins terrain; "Reserve" meaning clash. Glossary card definition is 13 px (native tooltip 14 px).
- decided: audit only, no beads filed, sw-dqj and sw-vld referenced not re-reported. Nothing was run in-engine.
- tests: docs-only, none.
