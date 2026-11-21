
## 2026-11-21 13:5x UTC turn (worker-sw-1jy.4, attempt 2)
- did: implemented downward points-to-drop: BattleRules.band_for/points_to_drop (pure static, same FPDR mapping as band_of), squad_card verbose text "· N to <band>", 4 new GUT tests; commits f23b59b + 3337c5c on swarm/sw-1jy.4.
- decided: distance = smallest loss that drops one band; Broken/no-cap = -1 (no text); FPDR tie-rounding gives up to 0.5% headroom at a floor (displayed = used).
- tests: hx godot check 0 errors; full suite 480/480 (7809 asserts).
- next: orchestrator review/merge; upward/both directions = one-line helper extension later.

## 2026-11-21 14:3x UTC turn (worker-sw-luo, attempt 1)
- did: audit-only bead sw-luo; wrote docs/swarm/research/notes/accessibility-baseline-1280x800.md checking report items 1-11 against war room/Angelfall/main menu at ec393cd; commit 2e07760 on swarm/sw-luo. No code changes, no new beads.
- decided: statuses — done: 8 (persistent event feed/PiP/reactions), 10 (settings.cfg per-device); partial: 1 (untimed sim flag only, no UI/wiring), 2 (scale works everywhere but UiWindow.dialog has no scroll -> clips at 200%@800p, logical 640x400), 3 (Caption 12px carries essential band text; map draw_string floor 8px), 4 (sw-vld still open), 5 (GUIDE covers planning only; war-room/replay/Esc keys hard-coded; static hints), 6 (focus styles+modal focus done, zero joypad handling), 7 (click/type-select yes, orders fire on press, no undo), 11 (AI profiles only); missing: 9 (no voice yet, Dialogic installed but no timelines).
- next: orchestrator review/merge; note lists candidate follow-ups F1-F10 (no beads created): untimed wiring, modal scroll at 200%, 1280x800 in SIZES, text floors, GUIDE completion+remap UI, controller nav, release-activate+undo, subtitles with M4 voice, difficulty/assist menu.
- blocked/asked: none; R2Q2 ranked lockout treated as settled, only wiring gap recorded.
