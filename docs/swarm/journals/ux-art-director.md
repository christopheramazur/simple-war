
## 2026-11-20T21:16Z turn
- did: accessibility/legibility audit of the UI theme + glossary/squad-card read path. Computed WCAG contrast for every default-palette text pair (all pass AA: text 12.4, dim 5.2, good 8.6, bad 5.4 on panel). Confirmed sw-vld (squad card colour-alone) still open and correct. Filed sw-dqj: glossary tooltip placed at mouse+offset with no clamp, clips off the right/bottom window edge.
- decided: default palette is colour-blind-safe for TEXT (all AA); the risk is colour-alone state, not contrast. Kept the named-style pipeline (sw-ijp.1) as the fix path — tones stay, text carries direction. Did not touch art direction (Open topic, user's call).
- good patterns: GlossaryTooltip already uses ▲/▼ + colour ("never colour alone", GDD 07); squad-card pools show value+band text; high_contrast + large profiles ship; UiTheme centralizes all colour/size so a fix reaches every screen.
- next: verify sw-vld and sw-dqj fixes when they land (git log src/presentation/glossary + war_room/squad_card.gd); then audit keyboard/controller focus for hover-only glossary terms (GUIDE) and tooltip text size (TooltipLabel = size-2).
- blocked/asked: none.

## 2026-11-21T05:25Z turn
- did: APPROVEd both open proposals; each reached 2 APPROVE / no BLOCK, so created the beads (5/8 daily cap): sw-ijp.5 CVD team colours as data + options preset (P1, parent sw-ijp), sw-rlg mock-pipeline greyscale/CVD variants, sw-kys.9 CC0 licence shortlist (parent sw-kys), sw-136.3 tutorial pacing gap note, sw-136.4 slice glossary-tooltip audit (parent sw-136). Both proposals set Status: accepted; supervisor auto-commit 215d3a2 carried the votes.
- decided: vote guards on sw-ijp.5: per-use WCAG AA (team colours double as TEXT in battle_panel/results_screen; Okabe-Ito hexes are darker than today's pair - derived lighter text tones from the single source OK), neutral id 30 distinguishable in every preset, shape/label redundancy not colour swaps alone, presets in user://settings.cfg render-time only, never data/packages. sw-136.4 must reference sw-dqj/sw-vld not re-report, and cover tooltip legibility + non-mouse reachability.
- did (own lens): filed sw-wqc (P2 bug): GlossaryLabel is hover-only (meta_hover signals, no focus path); war_room.gd:434 + command_panel.gd:319 terms unreachable by keyboard/controller; no glossary browse screen exists; definition text is SmallDimLabel - check at 1280x800. Reversible fix: focusable terms via GUIDE + term-anchored clamped tooltip.
- reviewed: merges sw-ll4.1.1/.2 + sw-aty are test-infra/harness, outside UI lens; sw-vld/sw-dqj still open, no fixes landed yet.
- next: review sw-ijp.5 implementation against the text-contrast guard; verify sw-vld/sw-dqj/sw-wqc fixes when they land; tech-lead vote still pending on both proposals but 2-APPROVE consensus already met.
- blocked/asked: none.

## 2026-11-21T07:45Z turn
- did: no inbox questions, both proposals already accepted (no votes due). Reviewed merges sw-uyv (sim formation sizing), sw-p70 (test infra), sw-ll4.26.1 (map-editor regression test) - outside UI lens or sound. sw-vld/sw-dqj/sw-wqc/sw-ijp.5 all still open, no fixes landed.
- did (own lens): keyboard-activation audit of the war room. Filed sw-hk0 (P2 bug): war_room.gd _input releases button focus on every keypress except Enter, so Tab cannot traverse controls and Space on a focused button falls through to end_turn_requested (~line 1300) instead of pressing it. Violates GDD 01 Input (input-agnostic) + Accessibility. Linked sw-wqc (depends on this) and sw-ll4.9.2 (GUIDE remap, coordinate).
- decided: assumption recorded in sw-hk0 - standard button semantics while a control has focus, game hotkeys when none does; most reversible reading, GDD doesn't settle Space-on-button. Exempt TAB/SPACE from release_focus rather than redesigning hotkeys.
- good patterns: armed-target instructions ARE visible (war_room hints() ~557, not tooltip-only); reactions list has full keyboard-accessible buttons (glyph+name, ~1231) with the radial as mouse shortcut; UiRoot restores focus when windows close; command-panel tooltips are previews, state shows after press.
- noted, no bead: placeholder text dim@0.7 on field ~3.6:1 and disabled button text dim@0.6 (both WCAG-exempt categories); TooltipLabel = size-2 = 14px, acceptable for secondary text; glossary definition 13px SmallDim already covered by sw-wqc acceptance.
- next: verify sw-hk0/sw-wqc/sw-dqj/sw-vld fixes when they land (git log src/presentation/war_room + glossary); then controller path audit (GUIDE mappings for focus nav/activation, reaction radial via stick) and sw-ijp.5 text-contrast guard review.
- blocked/asked: none.
