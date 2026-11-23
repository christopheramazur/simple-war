# Mock art refresh — work brief (bead sw-5fo)

You are updating **one batch** of UI mocks so they show the **current core art**. You have no
other context. Read only: the mock `.gd` files assigned to your batch, plus
`src/presentation/art/art_set.gd`. Everything else you need is in this brief.

---

## 1. Goal and rules

- **Goal:** every mock PNG shows the art the game actually ships today (Kenney hex/ground
  tiles plus the placeholder units, commanders, feature icons), obtained through `ArtSet`.
- **Edit only the mock `.gd` files of your batch**, i.e. files under `src/presentation/mocks/`.
  No gameplay or presentation code outside that folder, no `data/` edits, no new art files,
  no manifest/template edits, no harness edits.
- **Never `load()` / `preload()` a PNG path.** Art comes only from `ArtSet`
  (`ArtSet.core()` or `ArtSet.from_loader(loader)`), exactly as real views do.
  A `null` texture means "no art" — keep the mock's existing colour/shape fallback.
- **Tabs** for indentation (match the file). **Static typing** on new vars/params/returns
  (`var tex: Texture2D`, `func f(x: int) -> void`). No new `class_name`s.
- **Keep each mock's layout, frame size, constants and purpose.** Do not restyle, do not
  reflow, do not "improve" wording beyond what the change requires.
- **Update the doc comment at the top** of a mock only if what it shows changes; say what
  changed and cite `sw-5fo`.
- **Do not commit. Do not run `bd`. Do not run the Godot executable directly** — only the
  `harness/bin/hx` commands in §6.
- Text glyphs (pool/band icons), colour swatches, palettes and abstract UI decorations are
  **not art**. Leave them alone.

---

## 2. Art inventory (core package, `data/packages/core/manifest.json`)

All paths below are relative to `data/packages/core/`. "template.field" is what you pass to
`ArtSet.texture(template, field)`.

| asset id | file | depicts | template(s) · field |
|---|---|---|---|
| `commander_field_commander` | `art/commanders/field_commander.png` | field commander portrait (placeholder) | `field_commander` · icon |
| `commander_outrider` | `art/commanders/outrider.png` | outrider portrait (placeholder) | `outrider` · icon |
| `commander_siege_captain` | `art/commanders/siege_captain.png` | siege captain portrait (placeholder) | `siege_captain` · icon |
| `unit_trooper` | `art/units/trooper.png` | trooper sprite | `trooper`, `rifle_squad` · icon |
| `unit_sergeant` | `art/units/sergeant.png` | squad leader sprite | `sergeant` · icon |
| `unit_gunner` | `art/units/gunner.png` | LMG gunner sprite | `gunner`, `heavy_weapons_team` · icon |
| `unit_marksman` | `art/units/marksman.png` | marksman sprite | `marksman`, `marksman_team` · icon |
| `unit_rocketeer` | `art/units/rocketeer.png` | rocketeer sprite | `rocketeer`, `rocket_team` · icon |
| `unit_scout` | `art/units/scout.png` | scout sprite | `scout`, `scout_team` · icon |
| `unit_chi_operative` | `art/units/chi_operative.png` | CHI operative sprite | `chi_operative`, `chi_operatives` · icon |
| `unit_breacher` | `art/units/breacher.png` | breacher sprite | `breacher`, `assault_squad` · icon |
| `unit_engineer` | `art/units/engineer.png` | combat engineer sprite | `engineer`, `engineer_team` · icon |
| `unit_mortarman` | `art/units/mortarman.png` | mortarman sprite | `mortarman`, `mortar_team` · icon |
| `kn_hex_plains` | `art/kenney/hex/plains.png` | plains hex (Kenney, desaturated) | `hex_plains` · tile |
| `kn_hex_forest` | `art/kenney/hex/forest.png` | forest hex | `hex_forest` · tile |
| `kn_hex_hills` | `art/kenney/hex/hills.png` | hills hex | `hex_hills` · tile |
| `kn_hex_ore_deposit` | `art/kenney/hex/ore_deposit.png` | ore deposit hex | `hex_ore_deposit` · tile |
| `kn_hex_village` | `art/kenney/hex/village.png` | village hex | `hex_village` · tile |
| `kn_hex_barracks` | `art/kenney/hex/barracks.png` | barracks hex | `hex_barracks` · tile |
| `kn_hex_depot` | `art/kenney/hex/depot.png` | depot hex | `hex_depot` · tile |
| `kn_hex_mine` | `art/kenney/hex/mine.png` | mine hex | `hex_mine` · tile |
| `kn_hex_shrine` | `art/kenney/hex/shrine.png` | shrine hex | `hex_shrine` · tile |
| `kn_hex_bandit_camp` | `art/kenney/hex/bandit_camp.png` | bandit camp hex | `hex_bandit_camp` · tile |
| `tile_road` | `art/tiles/road.png` | road hex (placeholder) | `hex_road` · tile |
| `tile_lake` | `art/tiles/lake.png` | lake hex (placeholder) | `hex_lake` · tile |
| `tile_plains` | `art/tiles/plains.png` | plains hex (old placeholder) | none in the shown defs (superseded by `kn_hex_plains`) |
| `tile_forest` | `art/tiles/forest.png` | forest hex (old placeholder) | none in the shown defs |
| `tile_hills` | `art/tiles/hills.png` | hills hex (old placeholder) | none in the shown defs |
| `icon_village` | `art/features/village.png` | village feature icon | `hex_village` · icon — unverified (grep line truncated) |
| `icon_barracks` | `art/features/barracks.png` | barracks feature icon | `hex_barracks` · icon — unverified |
| `icon_depot` | `art/features/depot.png` | depot feature icon | `hex_depot` · icon — unverified |
| `icon_mine` | `art/features/mine.png` | mine feature icon | `hex_mine` · icon — unverified |
| `icon_shrine` | `art/features/shrine.png` | shrine feature icon | `hex_shrine` · icon — unverified |
| `icon_bandit_camp` | `art/features/bandit_camp.png` | bandit camp feature icon | `hex_bandit_camp` · icon — unverified |
| `icon_ore_deposit` | `art/features/ore_deposit.png` | ore deposit feature icon | `hex_ore_deposit` · icon |
| `icon_supply_cache` | `art/features/supply_cache.png` | supply cache icon | `hex_supply_cache` · icon |
| `icon_arms_cache` | `art/features/arms_cache.png` | arms cache icon | `hex_arms_cache` · icon |
| `icon_angel_host` | `art/features/angel_host.png` | angel host icon | `hex_angel_host` · icon |
| `kn_ground_open` | `art/kenney/ground/open.png` | open battle ground (Kenney) | `open` · texture |
| `kn_ground_water` | `art/kenney/ground/water.png` | deep water battle ground (Kenney) | `water` · texture |
| `ground_road` | `art/terrain/road.png` | road battle ground (placeholder) | `road` · texture |
| `ground_forest` | `art/terrain/forest.png` | forest battle ground (placeholder) | `forest` · texture |
| `ground_ruins` | `art/terrain/ruins.png` | ruins battle ground (placeholder) | `ruins` · texture |
| `ground_wall` | `art/terrain/wall.png` | wall battle ground (placeholder) | `wall` · texture |

Notes:
- Equipment templates name `icon` ids (`weapon_lmg`, `weapon_rifle`, `armour`, `kit`) that
  have **no asset in the manifest** → `texture()` returns `null`. Keep their fallback.
- Kenney art is CC0 (Hexagon Pack, Tiny Battle); everything else is project placeholder
  pixel art (`art/CREDITS.md`). Do not add or replace files.

---

## 3. How to get art (from `src/presentation/art/art_set.gd`)

```gdscript
var art: ArtSet = ArtSet.core()                       # art_set.gd:41 — core package, cached once
# or, if the mock already has a PackageLoader `l`:
var art2: ArtSet = ArtSet.from_loader(l)              # art_set.gd:24
var tex: Texture2D = art.texture(tid)                 # art_set.gd:52 — default field "icon"
var tile: Texture2D = art.texture("hex_forest", "tile")     # hex ground
var ground: Texture2D = art.texture("forest", "texture")    # battle terrain
if tex == null:
	pass  # no art: keep the mock's existing colours/shapes (context_view.gd:825 pattern)
# also: art.has_art(id, field) -> bool; art.shaped(id, "tile") -> pre-cut hex;
#       art.image(id, field) -> Image (RGBA8) for compositing
```

`texture()` and `image()` cache `null` too, so a missing asset stays missing for the process.

---

## 4. Per-mock verdicts

"Real scene" = the mock instances a shipped scene/component; that scene owns its art
(`war_room.gd:288` does `_main.art = ArtSet.core()`), so the mock needs **no code change**.
Whether `WarDataPanel`/`MapCanvas`, `OptionsScreen`, `SquadCard`, `GlossaryTooltip` use
`ArtSet` is **unverified** from the bundle — do not plumb art into them from a mock; if their
PNG shows no art, note it as unresolved in your report.

| mock | what it draws today | verdict | change list |
|---|---|---|---|
| `angelfall_mock.gd` | 2× `angelfall.tscn` (`WarRoom`), driven by real turns | RE-RENDER ONLY — all art comes from the scene | none |
| `battle_summary_mock.gd` | `war_room.tscn`; SIMPL bands are word+icon text | RE-RENDER ONLY — real scene; band glyphs are not art | none |
| `combat_fx_mock.gd` | 3× `ContextView` with `v.art = ArtSet.core()` already set | RE-RENDER ONLY — already wired to `ArtSet` | none |
| `convoy_steer_mock.gd` | `MainMenu.skirmish_room(...)` | RE-RENDER ONLY — real scene | none |
| `fire_cues_mock.gd` | `ContextView`, `v.art = ArtSet.core()` | RE-RENDER ONLY — already wired | none |
| `glossary_mock.gd` | `GlossaryLabel` + 5 `GlossaryTooltip`s, text only | RE-RENDER ONLY — no hand-drawn stand-ins; tooltip internals unverified | none |
| `inspection_window_mock.gd` | hand-built window; inner `Portrait` class draws a **silhouette stand-in for a unit** in `_card()`; inner `Icon` class draws stat glyphs | **UPDATE** — `Portrait` → unit art via `ArtSet` | see §4.1 |
| `main_menu_mock.gd` | `main_menu.tscn` + `MainMenu.skirmish_room` | RE-RENDER ONLY — real scenes | none |
| `map_objects_mock.gd` | `WarDataPanel`, Maps tab, Objects tool | RE-RENDER ONLY — real screen; its terrain drawing is not in this bundle (unverified) | none |
| `map_painter_mock.gd` | `WarDataPanel` + `MapCanvas` paint calls | RE-RENDER ONLY — real screen; no hand-drawn art in the mock | none |
| `map_playtest_mock.gd` | `MainMenu.editor_screen()` → `MainMenu.play_map` | RE-RENDER ONLY — real screens | none |
| `options_fit_mock.gd` | `OptionsScreen.open_over` in a 640×400 frame | RE-RENDER ONLY — pure UI, no art subject | none |
| `options_mock.gd` | `main_menu.tscn` + `OptionsScreen` | RE-RENDER ONLY — real scenes | none |
| `profile_card_mock.gd` | `main_menu.tscn`, Aggressor profile card | RE-RENDER ONLY — real scene; profile card art unverified | none |
| `reserves_mock.gd` | `war_room.tscn`, battle tab | RE-RENDER ONLY — real scene | none |
| `results_mock.gd` | `MainMenu.skirmish_room` + `ResultsScreen` | RE-RENDER ONLY — real scenes | none |
| `slice_art_mock.gd` | 2× war room (`demo_view` "move"/"plan") | RE-RENDER ONLY — this is the art showcase; scenes supply the art | none |
| `small_screen_mock.gd` | war room + `main_menu.tscn` at 853×480 | RE-RENDER ONLY — real scenes | none |
| `squad_card_mock.gd` | real `SquadCard.build/moment`; `_ctx()` passes rules, weapon names, glossary | RE-RENDER ONLY — no hand-drawn stand-ins; band icons are text glyphs. Do **not** invent an `art` key in `_ctx()` (unsupported/unverified) | none |
| `team_palette_mock.gd` | `_Canvas._draw/_squad/_commander`: circles, diamonds, squares = **team colour tokens**, CVD-simulated via `_s()` | RE-RENDER ONLY — palette swatches, not unit/commander stand-ins; sprites would bypass `_s()` and break the CVD comparison | none |
| `telegraph_mock.gd` | `ContextView`, `v.art = ArtSet.core()`, templates from `tests/fixtures/rules` | RE-RENDER ONLY — already wired; fixture ids may not match core art → `null` fallback is expected, do not "fix" it | none |
| `war_room_mock.gd` | 4× `war_room.tscn` (`demo_view` move/pip/plan/play) | RE-RENDER ONLY — real scenes | none |
| `war_room_readability_mock.gd` | `MainMenu.skirmish_room` + `war_room.tscn` battle | RE-RENDER ONLY — real scenes | none |

### 4.1 `inspection_window_mock.gd` — exact edit (batch B1)

Only the unit portrait changes. Everything else (`Icon`, `_bar`, `POOL_COLORS`, `_chip`,
`_effect_chip`, `_who_tile`, `Follow`, all sizes `W`/`W_NARROW`/`TIP_W`/`H`/`GAP`, the four
variants, the tooltips) stays byte-identical.

1. Inner class `Portrait`: add `var tex: Texture2D = null`. In `_init()` add
   `texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST` (pixel art). Keep
   `custom_minimum_size = Vector2(40, 40)` and `size_flags_vertical`.
2. `Portrait._draw()`: when `tex != null`, draw the texture aspect-fitted into `size`
   instead of the background rect + silhouette; when `tex == null`, keep today's drawing
   exactly. Draw the rank chevron and the hurt corner **after** the texture in both cases
   (they carry information the art does not).

```gdscript
		if tex != null:
			var ts := Vector2(tex.get_size())
			var d := ts * minf(size.x / ts.x, size.y / ts.y)
			draw_texture_rect(tex, Rect2((size - d) * 0.5, d), false)
		else:
			# existing draw_rect + draw_circle + draw_colored_polygon silhouette
			pass
```

3. `_card(v, units, i)`: after `var portrait := Portrait.new()` set
   `portrait.tex = ArtSet.core().texture(String(u["template"]))`
   (`u["template"]` is already used there for the `sergeant` check). Templates resolve to
   `unit_trooper` / `unit_sergeant`; `ArtSet.core()` caches itself, so calling it per card is
   cheap, but prefer one `var art: ArtSet = ArtSet.core()` hoisted into `_squad_tab()` and
   passed down if that keeps the diff small — either is acceptable.
4. `Icon` (accuracy / damage / evasion / move) **stays hand-drawn**: abstract stat glyphs,
   no art exists for them.
5. Doc comment: add one line, e.g. "Unit portraits now use the core unit art via `ArtSet`
   (sw-5fo); the silhouette remains the no-art fallback." Keep the existing bead cites.

---

## 5. Batches

- **B1** — `src/presentation/mocks/inspection_window_mock.gd` (alone: large file, ~700 lines).
- **R (re-render only, no code edits)** — `angelfall_mock.gd`, `battle_summary_mock.gd`,
  `combat_fx_mock.gd`, `convoy_steer_mock.gd`, `fire_cues_mock.gd`, `glossary_mock.gd`,
  `main_menu_mock.gd`, `map_objects_mock.gd`, `map_painter_mock.gd`, `map_playtest_mock.gd`,
  `options_fit_mock.gd`, `options_mock.gd`, `profile_card_mock.gd`, `reserves_mock.gd`,
  `results_mock.gd`, `slice_art_mock.gd`, `small_screen_mock.gd`, `squad_card_mock.gd`,
  `team_palette_mock.gd`, `telegraph_mock.gd`, `war_room_mock.gd`,
  `war_room_readability_mock.gd`.
  Every mock PNG predates the Kenney terrain art, so all of these are re-rendered at the end
  even though their scripts do not change.

---

## 6. Verify (per batch)

For each file you changed:

```
harness/bin/hx godot check src/presentation/mocks/<file>.gd
harness/bin/hx godot mock res://src/presentation/mocks/<name>_mock.gd
```

Then **open `Game Design Document/Mocks/<name>.png`** and confirm with your own eyes that
the art shows (B1: real trooper/sergeant sprites in the unit cards, chevron and hurt corner
still visible, four variants and both tooltips unchanged in size/position). A green `check`
alone is not proof.

For batch R: run only the `mock` command per mock and eyeball the PNG for terrain/hex art.
CVD variant PNGs exist for `squad_card` and `team_palette` (`*_deutan/_protan/_greyscale`,
`team_palette_okabe_ito_*`, `team_palette_tol_high_contrast_*`); `team_palette_mock.gd`
reads `TEAM_PALETTE_PRESET` / `TEAM_PALETTE_SIM`, but the harness invocation that produces
the variants is **unverified** — re-render the base PNG and list the variants as unresolved.

Then append a **3-line** report to `docs/delegate/mock-art/REPORTS.md` (append, do not
rewrite others' entries):

```
B1 | inspection_window_mock.gd | sw-5fo
PNG: unit cards show core trooper/sergeant icons, rank chevron + hurt corner kept, layout and tooltips unchanged.
Unresolved: none.
```

---

## 7. Pitfalls visible in the code

- **Sizing:** a `TextureRect` defaults to keep-size behaviour and will blow up a 40×40 slot.
  If you use one, set `custom_minimum_size`, `expand_mode = TextureRect.EXPAND_IGNORE_SIZE`
  and `stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED`. Drawing in `_draw()` with
  an aspect-fitted `draw_texture_rect` (as in §4.1) avoids the issue entirely.
- **Filtering:** `ArtSet` builds `ImageTexture.create_from_image(Image.load_from_file(...))`,
  so project import settings do not apply. Set
  `texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST` on the drawing item or the pixel art
  will look blurred when scaled.
- **`ArtSet.core()` cost:** the first call runs `PackageLoader.load_dirs` over the whole core
  package; it is cached in `static var _core`. Call it once per build where convenient, not
  in a tight per-pixel/per-frame path.
- **Null is normal:** missing refs cache `null`. Equipment icons have no asset; fixture
  templates (`telegraph_mock.gd`) may not match core ids. Keep the colour fallback, never
  substitute a direct PNG load.
- **Hex tiles:** `ArtSet.shaped(id, "tile")` says the art is already cut to a hex (transparent
  top-left corner) — draw it whole, do not clip it a second time.
- **Aspect/shape:** icon and tile PNG sizes are unverified; always fit to the slot rather
  than assuming square dimensions.
- **Mock harness:** these are `RefCounted` scripts with `static func build() -> Control`;
  `inspection_window_mock.gd`'s `Follow` positions itself in `_process`, and several mocks
  hook `ready` with `CONNECT_DEFERRED`. Do not restructure those hooks — how many frames the
  harness ticks is unverified, and changing them can silently move tooltips.
- **Static state:** `inspection_window_mock.gd` keeps `_tps` and `_disguise` in static vars
  across the four variants; do not reset or reorder them.
