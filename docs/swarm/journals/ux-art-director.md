
## 2026-11-20T21:16Z turn
- did: accessibility/legibility audit of the UI theme + glossary/squad-card read path. Computed WCAG contrast for every default-palette text pair (all pass AA: text 12.4, dim 5.2, good 8.6, bad 5.4 on panel). Confirmed sw-vld (squad card colour-alone) still open and correct. Filed sw-dqj: glossary tooltip placed at mouse+offset with no clamp, clips off the right/bottom window edge.
- decided: default palette is colour-blind-safe for TEXT (all AA); the risk is colour-alone state, not contrast. Kept the named-style pipeline (sw-ijp.1) as the fix path — tones stay, text carries direction. Did not touch art direction (Open topic, user's call).
- good patterns: GlossaryTooltip already uses ▲/▼ + colour ("never colour alone", GDD 07); squad-card pools show value+band text; high_contrast + large profiles ship; UiTheme centralizes all colour/size so a fix reaches every screen.
- next: verify sw-vld and sw-dqj fixes when they land (git log src/presentation/glossary + war_room/squad_card.gd); then audit keyboard/controller focus for hover-only glossary terms (GUIDE) and tooltip text size (TooltipLabel = size-2).
- blocked/asked: none.
