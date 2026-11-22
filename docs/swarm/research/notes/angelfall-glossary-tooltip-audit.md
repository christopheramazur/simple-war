# Angelfall slice: glossary-tooltip coverage and legibility audit (sw-136.4)

Audit only. No code, data or GDD changed; follow-ups are candidates for the designers (no beads filed).
Already tracked, not re-reported: **sw-dqj** (tooltip edge clamp), **sw-vld** (colour-alone squad card).
Method: read of main at `3b14c82` (after sw-ll4.27.2/.3). Nothing was run in-engine, so "hover works" means the code path exists, not that it was seen on screen.

## 1. How hover currently works

- **Glossary** (`src/presentation/glossary/glossary.gd`): 87 `term` templates in `data/packages/core/defs/glossary.json` (GDD 07 is the authority; a test keeps the two in sync). Links match name, plural and alias, whole words, longest first.
- **Only `GlossaryLabel` makes a term hoverable** (`glossary_label.gd`, a `RichTextLabel` with meta links; `_on_hover` shows `GlossaryTooltip` at mouse + (14, 18)). It is built in exactly two places: `war_room.gd:445 _title()` and `command_panel.gd:319 _title()`. Those are panel headings, orders/reactions/abilities headings, battle-menu summaries and the Events log lines (`war_room.gd:1566`).
- **Every other label is a plain `Label`** (`UiTheme.label` / `SquadCard._lbl`): battle panel, squad card, hex card, results screen, planning widgets, banners. A term there is not hoverable, even if it is in the glossary.
- The context-aware tooltip values (Bands, stats, pools, Bad Hit, units) are implemented and tested in `Glossary.tooltip`, but the squad card never passes a `GlossaryLabel`, so the live-value path has no caller in the slice's battle UI. GDD 07 promises "every tooltip is context-aware"; today only the Events log and headings reach it, with `context = {}` (no live values).
- Native `tooltip_text` (Godot's `TooltipLabel` style) is used on a few buttons and the battle summary line (`command_panel.gd:131,276,304`, `war_room.gd:362-394,774`). Those are hand-written strings, not glossary text.

## 2. Term-by-term table

Legend: **Hover** = a `GlossaryLabel` shows the glossary tooltip. **Gloss.** = entry in `glossary.json` (and GDD 07). "Heading/log" = hoverable only because the text goes through `_title()`.

### 2a. Terms the slice UI shows

| Term | Where shown (file:line) | Hover | Gloss. |
|---|---|---|---|
| Commander | `command_panel.gd:63,189` titles ("Commander N: ...") | y | y |
| Battleforce | `command_panel.gd:63` title | y | y |
| Army | `command_panel.gd:189` title ("army n/cap squads") | y | y |
| Squad / squads | `command_panel.gd:189`; `war_room.gd:1151,1184`; squad card name line `squad_card.gd:45` ("N / M units") | y in headings; **n** on the card | y |
| Unit / units | `squad_card.gd:45` ("alive / size units") | **n** | y |
| Supply line(s) | `command_panel.gd:86` heading | y | y |
| Movement (bank) | `command_panel.gd:108` heading "Movement" | y only if "Movement" matches an alias; it does not ("Movement bank" is the term), so **n** | y (Movement bank) |
| Activity / Activities | `command_panel.gd:159` "Activity at <hex>" | y | y |
| Convoy / Detachment | `command_panel.gd:125,221`; `hex_card.gd:69`; `war_room.gd:893-921` notes | y in `_title` headings and Events log; **n** in hex card, buttons, notes | y |
| Garrison | `command_panel.gd:125,221`; `hex_card.gd:69` | n | **n** (not a term) |
| Reserve(s) | `war_room.gd:780,1151` ("reserves", "reserve squad can join") | y in 1151 heading; **n** at 780 | y (Reserve is the *planning* bank, not battle reserves: meaning clash) |
| Reaction(s) / Reaction window | `war_room.gd:1278` heading, `:579,731` phase text | y heading; **n** phase text | y |
| Reveal / Execute / Planning / Intermission / Pulse | phase text and HUD (`war_room.gd:560-740`) | **n** (plain `_phase_text`) | y |
| Ability / Abilities | `war_room.gd:1198` "Abilities (Q)" | y | y |
| Halt / Fall back / Retarget (reaction names) | `war_room.gd:731,1292`; `reaction_radial.gd:35` | n (native tooltip is just the capitalised id) | **n** |
| Intent ghost | planning previews (`context_view.gd`, drawn) | n (no text) | y |
| Influence | `battle_panel.gd:21` ("influence N · value N") | **n** | y |
| Value | `battle_panel.gd:21`; `hex_card.gd:44-60` ("Value a turn", "N Value") | **n** | y |
| Zone | `battle_panel.gd:25` ("Zone <id>: owner (n of m)") | **n** | y |
| Capture Rate (CR) | not shown in the slice UI (only in data: civilians 10, CR-0 patrol 0, `angelfall.json` `af_shuttle` text). A player cannot read it; see 3.2 | n/a | y |
| Victory Points (VP) | not shown (`Victory` banner is the outcome word, not VP) | n/a | y |
| Sight | `squad_card.gd:73` ("sight N m") | **n** | y (`stat:squad.sight`) |
| Concealment / Detection / Ambush / Intercept | not on the slice's card | n/a | y |
| Stamina / Instinct / Morale / Prowess / Legend (SIMPL) | `squad_card.gd:378,470` meter names (`pool.capitalize()`) | **n** | y (live value context `pool:*` exists) |
| Bands: Surging / Primed / Neutral / Fraying / Broken | `squad_card.gd:421,436` ("icon word value") | **n** | y (`band` context exists) |
| Surge / Break | band words, and Events log lines | y in log only | y |
| Evasion / Block / Floor / Absorption | `squad_card.gd:123` "Defence: ..." line | **n** | y (`stat:defense.*`) |
| Temporary HP / Bad Hit | squad card health / hold text | **n** | y |
| Readying / Reloading | `squad_card.gd:210` `Glossary.hold_text` ("Reloading (n ticks left)") | **n** (the *text* comes from the glossary file, but is not linked) | y (Readying), "Reloading" no |
| Squad activity words ("Holding position", "Falling back"...) | `squad_card.gd:53` | **n** | `activity.*` keys only, no term |
| Effect / Status / Stack / Keyword | `squad_card.gd:131-133` | n | y |
| Order | `squad_card.gd:56` "Order: ..." | n | **n** |
| Health / HP | `squad_card.gd:96` | n | **n** (Temporary HP only) |
| Hex / plot / feature names ("Frontier town", "Spaceport") | `hex_card.gd`, `war_room.gd:1520` | n | n (Plot, Feature are terms; hex is not) |

### 2b. Angelfall lore terms (the ones the bead names)

| Term | Where shown | Hover | Gloss. |
|---|---|---|---|
| **Angel** | Map names `hex_angel_blockade` ("Angel blockade"), squad names ("Angel host", "Angel choir", `angelfall.json` `angel_host/angel_choir`); message `angelfall.intro` ("the angels are not") | **n** on map/hex card/squad card (plain labels). **y** in the Events log only if the message reaches `_title()`; "Angel host" matches "Angel", the lower-case "angels" matches via the plural form | y (`term_angel`: "A lensed counterfactual, a 'messenger from nonsense'") |
| **Ruin / Ruined** | Battlefield terrain "ruins" (`angelfall_spaceport`) shows as terrain only; no Ruin/Ruined UI text in the slice | n/a | y (`term_ruin_ruined`: "Law scoured beyond function. A zone condition."). **Mismatch:** the slice's `ruins` terrain (feature id, shown only if a terrain name reaches a linked label) is a place, the glossary term is a zone *condition*; "Ruin" + "s" is a linked form, so any linked text naming the terrain would show the condition definition |
| Angelfall | Mission/map title "Angelfall: the frontier" (`angelfall.json`), banners | **n** (names go through plain labels; `_banner` is a plain label) | y |
| The Law / Raw magic / Second Magic / Null / Legivore / Lawbringer / EoAT | Not shown anywhere in the slice UI | n/a | y |
| Capture Rate (robots "have Capture Rate 0") | trigger `text` only (designer note, not shown) | n/a | y |
| Influence | see 2a | **n** | y |

### 2c. Slice messages (`angelfall.json`)

All eight message strings (`angelfall.intro/dispersed/hunt/won/jeff_lost/ai_hint/hangars_open/shuttle`) are shown in the Events log through `war_room.gd:1566 _title()`, so hover is wired for them. Defined terms they contain: **angels/Angel** (intro), **console / hangars** (not terms), **civilians** (not a term), **Planetary AI** (not a term). Only the intro line has a term hit (angels). Nothing in `won`, `jeff_lost`, `hangars_open` is a defined term.

The banner (`war_room.gd:1577`, "Victory/Defeat — <mission text>") is a plain label: not hoverable.

## 3. Findings (candidate follow-ups, not filed)

1. **Hover covers headings and the log, not the data.** The places a first-time player meets SIMPL, bands, Influence, Zone, Value, Sight and Defence are plain `Label`s. The context-aware tooltip implemented for exactly those terms (`context` field) is unreachable from the squad card. Candidate: render squad-card and battle-panel lines through `GlossaryLabel` with `context = {inspection, squad, unit}`. Needs a design call on density (underline every word vs a "?" affordance) and on the squad card's clip/redraw behaviour.
2. **Capture Rate is the pillar-3 example term but is invisible in the slice.** Nothing in battle UI states it. Candidate: show CR on the card (it also explains why robots do not capture hangars, `af_shuttle`); designer decision on whether a first-play slice should surface it.
3. **Ruin/Ruined clash.** The glossary defines a zone condition; the slice's `ruins` terrain hex would link to it. Candidate: rename the term entry, scope matching, or name the terrain differently. Designer decision (lore).
4. **"Movement" heading does not link**; the term is "Movement bank". Candidate alias.
5. **Terms with no entry but shown:** Garrison, Order, Health, Halt/Fall back/Retarget (reaction names), Reloading, Hex, Convoy-vs-detachment hex text. Candidate: add entries (GDD 07 + `glossary.json` together) or accept them as plain English.
6. **Meaning clash:** glossary "Reserve" is the planning-time bank; the slice UI says "reserves" for squads that can join a battle (`war_room.gd:780,1151`). The Reserve tooltip would be wrong there. Candidate: rename one of them.
7. **Phase words in `_phase_text`** (Planning, Reveal, Execute, Reaction window, Intermission, Pulse) are defined terms shown as plain text during the tutorial-critical turn loop. Candidate: link them.
8. **Native vs glossary tooltips look different.** Buttons use Godot's default tooltip at size 14 with hand-written text; glossary tooltips use the card. Candidate: one visual language, same definitions.
9. **Messages with `angelfall.*` keys carry the English as fallback**, so lore terms in them are linked by string match, not by key. Fine for EN; flag for translation (R8Q10): linking is on the translated text, so a translation drops links unless glossary entries are translated too.

## 4. Legibility at 1280x800 (Steam Deck)

Sizes from `data/ui/styles.json` and `ui_theme.gd`, default profile, scale 100% (logical = device pixels, per `accessibility-baseline-1280x800.md`):

| Part | Style | Size (px) | Contrast (default / high-contrast) |
|---|---|---|---|
| Glossary tooltip title | default Label | 16 | text on panel (`dde2ea` on `1d2128`) high |
| Live value line | ValueLabel | 15 | green/red + ▲/▼ (not colour alone) |
| Definition text | SmallDimLabel | **13** | dim `8a93a3` on panel `1d2128` = **5.2 : 1** (high-contrast: 11.8 : 1) |
| "See also" line | CaptionDimLabel | **12** | same 5.2 : 1 |
| Native `TooltipLabel` (buttons) | `maxi(size-2, 10)` | 14 | `text` on `background` |

- Contrast passes WCAG AA (4.5 : 1) in the default theme; text size is the weak point. The glossary definition, the main payload, is **13 px**, and 12 px for "See also". The baseline note computes ~8.6 px cap height for 12 px and ~9.3 px for 13 px: at or just above Valve's ~9 px floor, below the 12 px character-height guidance. The size-2 `TooltipLabel` (14 px) is bigger than the glossary tooltip's definition text, so the claim that tooltips are "size-2 text" holds only for the native tooltip; the glossary card is smaller than that.
- **Width:** card is 300 px (`WIDTH`, labels 280 px wrapped) on a 1280 px screen: fine. At 200% scale (640 logical) it takes nearly half the width; placement is at the mouse (+14, +18) with no clamp (sw-dqj, not re-reported).
- **Touch/Deck use:** the tooltip appears only while the pointer is over a link; there is no pinning, so a trackpad/touch user must keep the cursor still while reading 3+ lines.

## 5. Reachability without a mouse

- `GlossaryLabel` is a `RichTextLabel` with `meta_hover_started/ended` only. It has no `focus_mode` setting (default NONE), no `meta_clicked` handler and no key or controller binding. A keyboard or controller player **cannot reach any glossary tooltip**.
- sw-ll4.9.2 (GUIDE actions for every key) is closed: war room, replay viewer and window-close keys now use GUIDE contexts. Glossary focus is not part of it; no action for "open glossary / next term" exists (`src/presentation/input/guide_keys.gd`).
- The native button tooltips are not reachable by controller either (Godot shows them on hover only), so even the hand-written hints fail.
- Pillar 3's promise ("every term explained") therefore does not hold for controller players. Candidates for the designers: (a) a focusable term list or "?" on each panel, (b) a GUIDE action that cycles linked terms in the focused panel and pins the tooltip (also fixes pinning for trackpad users, see section 4), (c) a Glossary entry in the Options/Help dialog (`controls_help.gd` does not mention glossary hover at all).

## 6. Summary

| Check | Result |
|---|---|
| Glossary entries exist for slice terms | mostly y (about 7 shown words lack an entry, section 3 item 5) |
| Hover shown in slice | headings and log only; squad card, battle panel, hex card, phase text, banners: no |
| Lore terms (Angel, Ruin) | entries exist; hover only in the log; Ruin clash |
| Tooltip legibility at 1280x800 | contrast OK; 13/12 px body below the native tooltip's 14 px |
| Reachable without a mouse | no |
