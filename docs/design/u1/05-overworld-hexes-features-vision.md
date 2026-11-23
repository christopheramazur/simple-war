# U1 draft 05: Overworld hexes, features, owner actions, vision and caravans

**Status:** draft for owner review (design delegate, 2026-11-23). Nothing here is in the GDD yet.
**Source:** `docs/design/u1/brief.md`, section "Overworld Map".
**Scope:** (1) larger hexes that are made of the features they hold, (2) selecting single features, (3) remote "owner actions", (4) tuning movement and vision, (5) the caravan as an entity whose payload is made of components.

Owner statements are tagged **U1Q20–U1Q27** (settled). The numbers start at 20 so they don't clash with the battle drafts of this round; whoever merges the U1 drafts may renumber them. Everything else is *proposed*.

| Tag | Owner statement (brief) |
|---|---|
| U1Q20 | Hexes are much larger. They are composable entities that hold and show the feature entities they are made of. |
| U1Q21 | Features have a default arrangement in a hex. Map creation can override it; play cannot. |
| U1Q22 | A road on the hex keeps the same arrangement, offset slightly out of the road's way depending on the road's direction. |
| U1Q23 | Each of several features on a hex is selectable on the map and in the selected hex's sidebar, and is highlighted in both places. |
| U1Q24 | Some owned features can be used without a commander present: buying items and squads, and updating rally points. |
| U1Q25 | Overworld movement comes down a bit, caravans especially. Overworld vision goes up a bit. |
| U1Q26 | Controlled hexes give at least self-vision. Features add more by kind: a mine 1, a barracks 2, a village or caravan 3 (more with scouts in a caravan). Defaults are sensible, configurable and based on the entity. |
| U1Q27 | A caravan is an entity. Its payload is components that systems read to grant behaviours and capabilities (e.g. scouts raise its sight). |

---

## 1. Findings: what exists today

### 1.1 Hexes and features (sim)
- **Grid:** pointy-top odd-r hexes, integer axial maths (`src/sim/overworld/hex.gd:1-120`). Neighbour order `Hex.DIRS` is E, NE, NW, W, SW, SE (`hex.gd:11-14`). On screen (y down), direction *k* is at angle −60·k°.
- **Features** are rows of the SoA table `OverworldFeatures`: `plot`, `tmpl`, `owner`, `cleared`, `output`, `progress`, `returns` (`overworld_features.gd`). A plot holds any number of features but at most one of each template (`overworld_state.gd:156-169`). `plot_features` is a derived cache in ascending template order (`overworld_state.gd:57-59, 178-190`).
- **Maps** are pass lists: `fill`, `rect`, `place`, `line`, `scatter`, with an optional `owner` (`map_gen.gd:9-29`; schema `src/sim/data/data_schema.gd:193-205`). A `place` pass carries only `feature, col, row, owner`.
- **Feature template fields** (`data_schema.gd:449-492`, compiled in `overworld_rules.gd:381-405`) include `icon` and `tile` as drawing-only art. A hex feature has no `color`, `layer` or `connects` field yet; those exist only on battle terrain features (`data_schema.gd:353`, GDD 03 §3.5).
- **Roads** are just a feature (`hex_road`, `move_cost −5`, `data/packages/core/defs/overworld.json:6`) laid by `line` passes. Sites already share road hexes: on `skirmish_mirror` the owned village sits on the road at (1,4) (`skirmish.json:16-17`).

### 1.2 Hexes and features (presentation)
- **Scale:** `ContextView.HEX_SIZE = 26.0` px circumradius at zoom 1 (`src/presentation/war_room/context_view.gd:22`), so a hex is about 45 × 52 px. Zoom runs 0.5–4.0, and zooming to 3.0 enters a battle (`src/presentation/contexts/view_contexts.gd:32-36`).
- **One look per hex:** a hex draws **one** colour, tile and icon. The first feature in a hard-coded `FEATURE_COLORS` order wins (`context_view.gd:39-47, 464-508`). Ownership is a single dot (`context_view.gd:283-294`). Commanders are drawn at the hex centre (r = 0.36·s), detachments at the fixed offset (+0.42, +0.38)·s (`context_view.gd:322-380`).
- **Hit testing:** a click goes to the nearest hex centre (`plot_at`, `context_view.gd:520-531`). Nothing on the map can be picked below the hex.
- **Selection state** (`ViewContexts`, `view_contexts.gd:44-49`) holds `selected` (commander), `selected_plot` and `selected_detachment`. There is no feature selection.
- **Sidebar:** `CommandPanel` lists a hex's features as dim labels. It adds "Set rally point…" / "Clear" under each owned producing feature during Planning (`command_panel.gd:252-258, 293-315`). `HexCard` formats `OverworldSession.inspect_plot`, which already returns per-feature dictionaries with `id` (`overworld_session.gd:1004-1061`, `hex_card.gd:29-60`).
- **Map editor:** the World maps tab (`addons/simple_war_tools/overworld_painter.gd`, `HexView` at :776, zoom 2–96 px) edits through `OverworldCanvas` (`src/tools/overworld_canvas.gd`). That model keeps **one painted ground feature per hex** (`overworld_canvas.gd:26-28`) plus objects (`place` passes with owners). A road painted over forest can't be represented, and no per-hex layout data exists. `ConnectShape` (`src/tools/connect_shape.gd`) computes wall and road pieces for the **square** battle grid only (N/E/S/W).

### 1.3 What can be done remotely today
| Action | API | Needs a commander? | Gate |
|---|---|---|---|
| Choose a production option | `set_output` (`overworld_session.gd:252`, `convoys.gd:92`) | **No** | Planning, feature owned and producing |
| Set or clear a rally point (supply line) | `set_supply_line` (`overworld_session.gd:263`, `convoys.gd:108`) | **No** | Planning, owned; destination passable as known |
| Rally a garrison or convoy | `rally` (`overworld_session.gd:314`, `convoys.gd:165`) | **No** | Planning, own detachment, not in battle |
| Steer a garrison or convoy | `set_convoy_route` (`overworld_session.gd:275`, `convoys.gd:134`) | **No** | Planning, own detachment, not in battle |
| Recruit, hire, refit, convert, battle | `set_activity` (`overworld_orders.gd:33-73`, resolved in `overworld_activities.gd:27-76`) | **Yes**: the route ends on the hex, one activity per commander | The commander ends there, not in battle |
| Answer an offer | `answer_offer` (`overworld_turn.gd:66-109`) | **Yes**: a free, uncontested commander on the hex | — |

- **Rally points are already remote.** What is missing is the UI path from a single selected feature. "Buying" squads or items remotely doesn't exist: production is a timed loop (`convoys.gd:214-234`), and recruiting is commander-only.
- **The GDD is out of step:** Rules Spec §2.9 *Interaction timing* says stable outcomes, including "setting up supply lines", are "handled during planning, when routing through", but the code lets the owner set supply lines from anywhere. The §3 text fixes this.
- **Quirk: production ignores battles.** `Convoys.produce` doesn't check engagements. `_make` skips a detachment that is in an engagement and **spawns a fresh one on the battle hex** (`convoys.gd:243-255`). Remote buying would have the same hole, so §3 settles both.
- **No UI for `set_output`:** only `HeadlessOverworld` calls it (`src/api/headless_overworld.gd:53-55`).

### 1.4 Movement and vision numbers (data)
- **Movement costs:** base cost 10 per hex (`overworld_rules.gd:9`, every map). Forest +5 (15), hills +10 (20), road −5 (5), lake impassable (`overworld.json:3-7`).
- **Commanders:** field_commander 60 mp / sight 3; outrider 90 / 4; siege_captain 50 / 3 (`overworld.json:74-80`); jeff_commander 50 / 3 (`angelfall.json:62`). The compiled default sight is 2 (`overworld_rules.gd:255`).
- **Detachments and convoys:** `convoy_movement` defaults to 40 (`overworld_rules.gd:13`) and is set to 40 on `test_vale` and `skirmish_mirror` (`skirmish.json:9`). `detachment_sight` defaults to 1 for garrisons **and** convoys alike (`overworld_rules.gd:12, 288`). It is used by vision (`overworld_vision.gd:117-120`) and by mid-move glimpses (`overworld_movement.gd:160, 188`).
- **Feature sight:** village 2, depot 1, barracks 1, mine 1 (`overworld.json:10-27`); frontier_town 2, spaceport 1 (neutral, so it gives no vision) (`angelfall.json:66-72`).
- **Self-vision exists already:** every owned feature is a source and "every source sees its own plot". `Hex.within(p, 0)` is the plot itself (`overworld_vision.gd:112-126`). An owned feature with `sight` 0 (the schema default) already lights its own hex. Only neutral features don't.
- **What a radius covers:** radius 1/2/3/4/5 is 7/19/37/61/91 hexes. `skirmish_mirror` is 20×10 = 200 hexes, so radius 3 is 18% of the map and radius 4 is 30%.

### 1.5 Store, saves and replays
- **Tables:** detachments are one SoA table, `player, plot, engagement, dest_plot, dest_commander, line` (`overworld_detachments.gd:9-28`). A convoy is a detachment with a destination (`Convoys.is_convoy`, `convoys.gd:36-37`). Payload is **relational**: `ow_squad.detachment` and `ow_item.detachment` point at it (`overworld_squads.gd:7-9`, `overworld_items.gd:8-12`). That is the ECS "relationship" pattern; a component bag would be the alternative.
- **Missing columns are safe:** `SoaTable.restore` fills a column missing from an old save with its declared default (`src/sim/core/soa_table.gd:205-218`, sw-uyv). **Missing tables are not:** `SimContext.restore` indexes `tabs[String(k)]` for every table (`src/sim/core/sim_context.gd:99-101`), so a new table breaks old saves unless that line is guarded.
- **Content changes already invalidate saves and replays:** loading refuses a save made with different content (data hash), and so does a replay (GDD 04 §4.8). `SAVE_VERSION = 1` in `overworld_session.gd:33` and `match_driver.gd:30`. Every tuning bead below therefore makes old saves and replays unloadable by design. Only a change to the snapshot's *shape* would need a version bump.

---

## 2. Prior art (short)

- **Heroes of Might and Magic: map objects.** Dwellings and mines are single objects on the adventure map. You flag them once by visiting, and they then pay or grow on their own. Flagging an external dwelling raises growth in every matching town the player owns, with no further visit ([Might and Magic wiki, Dwelling](https://mightandmagic.fandom.com/wiki/Dwelling); [Heroes 3 wiki, Dwelling](https://heroes.thelazy.net/index.php/Dwelling)). Buying from a dwelling still needs a hero there.
  - *Take:* ownership by visiting (we already have it, R7Q8). Remote buying is the convenience that HoMM's town screen gives and its map dwellings don't, so it should cost a little more than buying in person.
- **Civilization: sight radius.** Sight is the number of tiles a source reveals, typically 2 for units. Terrain height extends or blocks it ([Civilization wiki, Sight](https://civilization.fandom.com/wiki/Sight); [CivFanatics, Civ VI LOS](https://forums.civfanatics.com/resources/civ-vi-los.27654/)).
  - *Take:* small integer radii, plus a per-source data value. Terrain-blocked overworld sight stays out of scope (§2.9 says "radius only").
- **Humankind and Old World: tile composition.** In Humankind a tile's yield and its district are separate sources, and an outpost draws on its tile and the six neighbours ([Humankind wiki, District](https://humankind.fandom.com/wiki/District); [Exploitation](https://humankind.fandom.com/wiki/Exploitation)). Old World separates rural from urban improvements, and urban ones depend on adjacency ([Old World wiki, Cities](https://wiki.hoodedhorse.com/Old_World/Cities); [Designer Notes #2](https://www.designer-notes.com/old-world-designer-notes-2-city-sites/)).
  - *Take:* split a hex into **layers** (ground / path / sites). Paths are drawn from their neighbours.
- **Battle Brothers: caravans.** A caravan is a world-map party that travels between settlements. Its escort contract has you travel *with* it, and its guards depend on the region ([Worldmap Update 0.6.0.16](https://battlebrothersgame.com/?p=13632); [Dev Blog #61, contracts](https://www.indiedb.com/games/battle-brothers/news/how-contracts-will-work-part-1)). Fog clears farther out than locations are scouted ([Nexus mod note](https://www.nexusmods.com/battlebrothers/mods/643)).
  - *Take:* a caravan is a visible, interceptable party. Its sight is a property of the party, and what it carries changes what it can do.
- **ECS component design.** In archetype ECS, entities with the same component set share storage, and **relationships** are components whose data points at another entity ([ECS FAQ](https://github.com/SanderMertens/ecs-faq); [Hytale ECS explainer](https://hytale.com/news/2024/6/summer-2024-technical-explainer-hytale-s-entity-component-system-oPwpCAMdI); [Wikipedia: ECS](https://en.wikipedia.org/wiki/Entity_component_system)).
  - *Take:* the SoA tables and holder-ID columns are already the relationship form. Capabilities should be **derived** from relationships plus template data by one reader (§2.13 "systems read effective values"). Runtime add/remove of components is not needed.

---

## 3. Proposed GDD text

Each block names its target. **Insert** means new text; **Replace** quotes the line it replaces.

### 3.1 Rules Spec (`02 Rules Spec.md`) §2.9 Overworld

**Insert at the end of "### Map and features" (after the Turn order bullet's sub-list):**

```markdown
- **Hexes are places made of features** (U1Q20): a hex shows the features it holds as separate things, not as one terrain colour. Each feature has a drawing `layer`:
  - **Ground** (plains, forest, hills, lake): the hex's surface. The ground with the highest `draw_order` is drawn as the hex's tile.
  - **Path** (roads): drawn as a strip from the hex centre to each side whose neighbour holds a feature it `connects` with.
  - **Site** (village, mine, barracks, depot, caches, camps, shrines): an object drawn in a slot of the hex, selectable on its own.
  - The layer and layout are drawing only: the rules never read them. Movement cost, sight, control and activities are unchanged.
- **Arrangement** (U1Q21, U1Q22; proposed numbers): sites take slots from a fixed table by how many sites the hex has (1–7). They are ordered by `layout_priority` (higher first), then template ID. An eighth or later site shares the last slot with a "+n" badge.
  - **Roads:** on a hex with a path, the arrangement keeps its shape and moves as a group out of the road's way, towards the middle of the widest gap between road directions, and shrinks slightly to fit. Any site still on the road is pushed off it.
  - **Map overrides:** a map may place any site at an exact point in its hex (`at` on its `place` pass). Play never changes the arrangement.
- **Selecting a feature** (U1Q23): any known site can be selected by itself, on the map or in the hex's panel; both highlight it. Selecting a feature also selects its hex. What the player can do with it depends on owning it (Owner actions).
```

**Replace** under "Interaction timing (R6Q14)":
> `- **Stable outcomes** (production, pickups, setting up supply lines) are handled during planning, when routing through.`

with:

```markdown
  - **Stable outcomes** (pickups, captures) happen as a commander routes through. Settings an owner keeps on its features (production output, rally points) and owner actions are made during planning from anywhere, with no commander (U1Q24).
```

**Replace** the "Turn order" bullet's first line:
> `- **Turn order:** a turn resolves as movement, then activities, then production; then uncertain features are offered for the next turn.`

with:

```markdown
- **Turn order:** a turn resolves as movement, then activities, then owner actions, then production; then uncertain features are offered for the next turn.
```

**Insert after the "Activities" sub-bullet group (before "Production:" in Turn order):**

```markdown
  - **Owner actions** (U1Q24; proposed): a feature's owner may use it without a commander. Actions are planned during Planning and resolved after activities. A feature lists which ones it allows in `owner_actions`; the vocabulary is closed:
    - **Buy:** one option of its `recruits` (a squad) or its `sells` (items, `count` per purchase). It costs the option's cost plus the feature's `remote_markup` percent (default 25, rounded up). Buying in person stays the commander's `recruit` activity, at the plain price, straight into the army.
    - **Rally point:** set or clear where the feature's output goes (its supply line; see Production and logistics). Already an owner setting; listed here so the UI offers it per feature.
    - **Output:** choose which `produces` option it makes.
  - **Limits:** each feature takes `purchases_per_turn` buys a turn (default 1). The Value is paid when the action resolves, not when planned.
  - **Where a bought squad or item goes:** like produced output. Without a rally point it joins the owner's garrison on the feature's hex (a new garrison if none). With one, it leaves next turn as a caravan on that line. Items go into that garrison's or caravan's War Chest.
  - **Cancelled, with nothing paid, when:**
    - the feature is no longer the player's (captured during movement this turn);
    - the hex is engaged (a battle is there);
    - the hex is contested: a hostile commander, or a hostile garrison or caravan with squads, is on it when the action resolves;
    - the player lacks the Value.
    - The owner sees the reason as an event.
  - **Fog:** an owned feature always sees its own hex, so planning never acts blind. Enemies see a bought squad or item appear as a garrison or caravan, never what it holds.
  - **Not remote:** hire, refit, convert, battle and answering offers still need a commander on the hex (open question in draft 05 §4).
```

**Insert under "### Production and logistics", replacing the "Production:" bullet's last sentence** "While the owner can't pay, it waits, ready to go." with:

```markdown
While the owner can't pay, it waits, ready to go. While its hex is engaged, production holds its progress and makes nothing (proposed).
```

**Replace** the "Convoy movement" bullet:
> `- **Convoy movement:** a convoy is a detachment with a destination. ...`

with:

```markdown
  - **Caravans** (U1Q27; proposed): a squad group without a commander is a **band**. A band is either a **garrison** (holding a hex) or a **caravan** (made to travel). The kind is data (`band` templates) and gives the band its base sight and movement points.
    - **Becoming a caravan:** a garrison sent somewhere (rally, steering, a supply line) becomes a caravan. A caravan that halts stays a caravan: it keeps its sight and can be steered again.
    - **Becoming a garrison:** a caravan that reaches its plot joins the player's garrison there, or becomes that garrison if there is none.
    - **Walking:** each turn a caravan walks the cheapest path it knows, around hexes it knows are guarded, for its movement points. It moves on the commanders' timeline, after commanders at equal times.
    - **Payload:** what a band carries are components: its squads, their equipped items, and its War Chest. Each squad (and each item it equips) may add to the band's overworld stats (`overworld` contributions). A scout team adds 1 sight to a caravan, up to the band kind's cap.
    - **Effective stats:** systems read a band's effective sight and movement (base + payload, capped), never the raw data. Its tooltip shows each term.
```

**Replace** the Fog of war "Sight sources" bullet:
> `- **Sight sources:** commanders, convoys, controlled features and detachments each have a sight radius in hexes.`

with:

```markdown
  - **Sight sources:** commanders, controlled features, garrisons and caravans each have a sight radius in hexes. A source always sees its own hex, so every controlled hex gives at least self-vision (U1Q26). Defaults by kind are data (U1Q26):
    - **Features:** mine 1, barracks 2, depot 2, village 3, frontier town 3.
    - **Bands:** garrison 1, caravan 3, plus 1 per scout squad aboard, up to +2.
    - **Commanders:** 4, the outrider 5.
```

**Insert under "### Guards and movement" → "Movement:"**:

```markdown
  - **Speeds** (U1Q25; data defaults): field commander 50 movement points, outrider 80, siege captain 40, Jeff 45; caravans 30. With the base cost of 10, that's 5, 8, 4, 4 and 3 open hexes a turn (double on roads).
```

### 3.2 Data Model (`03 Data Model.md`) §3.5

**Append to the "Hex feature" "Fields:" list:**

```markdown
    - **Drawing only** (U1Q20–U1Q22; the rules never read them): `layer` (`ground`, `path` or `site`; default `site`), `draw_order` (int, ground and path stacking; default 0), `layout_priority` (int; sites with higher values take the first slots; default 0), `connects` (hex features a path joins besides itself; empty = only itself), `color` (six hex digits; replaces the war room's colour table, sw-ll4.8).
    - **Owner actions** (U1Q24): `owner_actions` (a closed list: `buy`, `rally`, `output`; default `["rally", "output"]` for features with `produces`, else empty), `sells` (item options: `item`, `count`, `cost`), `remote_markup` (percent added to a remote buy; default 25), `purchases_per_turn` (default 1).
    - **Sight:** `sight` (hexes beyond its own hex; default 0 = its own hex only). It counts only while the feature is owned.
```

**Insert after the "Commander" bullet:**

```markdown
- **Band** (`band`, U1Q27): the kinds of commander-less squad groups.
  - **Fields:** `name`, `sight` (hexes), `movement_points` (per turn, the same units as move costs), `payload_stats` (which overworld stats its payload may raise: `sight`, `movement_points`), `caps` (stat → most its payload may add), `icon`.
  - **Core kinds:** `band_garrison` (sight 1, 30 points, payload raises nothing) and `band_caravan` (sight 3, 30 points, payload raises `sight`, cap +2).
  - **Overrides:** a map's `detachment_sight` and `convoy_movement` still override the garrison's sight and the caravan's movement points when set (older maps).
- **Overworld contributions** (`overworld` on a squad or an item, U1Q27): stat → amount, e.g. `{"sight": 1}`. A band whose kind lists the stat in `payload_stats` adds the contributions of its squads and their equipped items, summed in squad-ID order and capped by its `caps`. Chest items carry nothing. Core data: `scout_team` and `marksman_team` carry `{"sight": 1}`.
```

**Replace** the map template's "Detachments" bullet:
> `- **Detachments:** `detachment_sight`, a detachment's sight radius in hexes (default 1); `convoy_movement`, the points a convoy moves each turn (default 40).`

with:

```markdown
  - **Bands:** `detachment_sight` and `convoy_movement` are optional overrides of the `band_garrison` sight and the `band_caravan` movement points (unset = the band template's; the core template defaults are 1 and 30).
  - **Site placement** (U1Q21): a `place` pass may carry `at`, `[x, y]` in thousandths of the hex radius from its centre (y down, each within −700..700). It pins that site there instead of its slot. On a mirror map the partner's `at` is negated (a half turn). Drawing only.
```

**Insert at the end of §3.5 (drawing data, not package data):**

```markdown
- **Hex layout table** (`data/ui/hex_layout.json`, U1Q21–U1Q22): UI data like `styles.json`, not a package template.
  - **Slots:** the slot points for 1–7 sites, in thousandths of the hex radius, and the site radius.
  - **Roads:** the road half-width, the group shift and scale on a road hex, and the clearance a pushed site keeps.
  - **Movers:** the lane where commanders and bands stand.
  - **Labels:** the zoom bands where labels appear.
```

### 3.3 Systems Architecture (`04 Systems Architecture.md`)

**§4.2, append:**

```markdown
- **Relationships and derived stats** (U1Q27): a payload is rows pointing at their holder (`ow_squad.detachment`, `ow_item.detachment`), not a component bag. Capabilities are derived: `OverworldStats` is the one reader of a commander's, band's or feature's effective overworld `sight` and `movement_points`.
  - **What it adds up:** the template base, then payload contributions in ID order, capped.
  - **What it returns:** the value with its terms, for tooltips.
  - **Rules:** integer only and deterministic. Vision, convoy planning and glimpses call it, never the raw columns.
  - **New store state:** `ow_detachment.band` (band template index; −1 in older saves means "derive it: caravan if it has a destination") and `OverworldState.owner_orders` (feature ID → {"action", "option", "player"}, saved and hashed like `activities`).
```

**§4.4 Overworld, append to the bullet list:**

```markdown
  - **Owner actions (U1Q24):** `set_owner_action(player, feature, action, option)` (Planning only; "" clears; `buy` names a `recruits` squad or `sells` item). `observe` adds the player's `owner_orders`.
  - **Features:** `inspect_feature(player, feature)` returns one feature as `inspect_plot` lists it, plus `actions`: each owner action it allows, with its cost and why not. It is read-only, any phase, and works from memory for features out of sight. `inspect_plot` builds its feature list from it.
  - **Bands:** `observe` gives each own or allied band its `band` kind, and its effective `sight` and `movement` with terms. Enemies see the kind but not the payload.
```

**§4.8, insert a "Hex view (U1Q20–U1Q23)" block after "Readability":**

```markdown
- **Hex view (U1Q20–U1Q23; proposed numbers):**
  - **Scale:** a hex is 64 px in circumradius at zoom 1 (111 × 128 px; was 26). Zoom runs 0.25–3.0, and entering a battle moves to 2.5 (s = 160 px).
  - **Detail bands** by on-screen radius s:
    - s < 24: one glyph per hex (its first site and a count), owner marks only.
    - 24–48: every site in its slot, no names.
    - s ≥ 48: sites with owner rings and progress pips.
    - s ≥ 96: the names of owned sites.
    - At any scale the hovered and selected hex show their names on a plate. That is at most one label per hex.
  - **Layout:** `HexLayout` (presentation, static, no state) turns a hex's known features, its known road neighbours and the map's `at` overrides into site points and a mover lane. Both the war room and the World maps tab use it. Points are cached per plot until its features or its neighbours' roads change.
  - **Selection:** `ViewContexts.selected_feature` (−1 = none) sits beside `selected_plot`. Clicking a site selects it and its hex; clicking open ground selects the hex only. Selecting a commander or band, or deselecting all, clears it. `ContextView.feature_at(pos)` hit-tests the sites of the hexes in view. The hex panel lists sites as selectable rows, and hovering or selecting either highlights both.
  - **Right click:** with an owned producing site selected, a right click on a hex or on one of the player's commanders sets that site's rally point (like steering a caravan).
  - **Movers:** commanders and bands stand in the mover lane: along the hex's lower edge, or on the road when the hex has one. Up to 3 tokens, then "+n".
```

**§4.9 Map editor, append under "World maps tab, in play (sw-7ii)":**

```markdown
      - **Layout (U1Q21):** the Layout tool (Y) drags a placed site inside its hex and writes the `place` pass's `at`. Right-click resets it to its slot. The hex shows the same `HexLayout` as the game. Roads are a second painted layer (path), so a road can cross forest.
```

**§4.11 table, add rows once built:** `§2.9 Owner actions`, `§2.9 Caravans and band sight`, `§2.9 Hex composition (drawing)`.

---

## 4. Open questions for the owner

| # | Question | Blocking? | Recommended default |
|---|---|---|---|
| Q1 | Does "much larger" mean only **on screen**, or also a **world-scale** change: fewer hexes, each standing for more ground and holding more sites? | Blocks content only, not code | On screen only for now (64 px). Revisit map sizes after a playtest. |
| Q2 | What should a remote buy cost? Plain price, a markup, or plain price plus a delay? | No | +25% (rounded up), resolved the same turn. In person stays cheaper. |
| Q3 | Should **hire** (a new commander at a village) be an owner action too? | No | No: hiring stays a commander activity (it makes a commander, the scarcest thing). |
| Q4 | Should a **garrison refit** at an owned depot be an owner action? | No | No for now. File it if garrisons need sustaining. |
| Q5 | Should production **pause** while its hex is engaged? Today it keeps making squads into a fresh detachment on the battle hex (§1.3). | No | Yes, pause with progress held. |
| Q6 | Should scouts in a **commander's army** also raise the commander's sight, as they do for a caravan? | No | Not yet: commander kinds list no `payload_stats`. One data line turns it on later. |
| Q7 | Should a caravan that halts stay a caravan, or become a garrison? | No | Stay a caravan (sight 3, steerable). It becomes a garrison only on reaching a plot. |
| Q8 | Player-facing word: "convoy" or "caravan"? | No | "Caravan" in UI and glossary, with "convoy" as an alias. Code names (`Convoys`) stay until a rename bead. |
| Q9 | The tuning in §3.1 (speeds −10 to −17%, sight +1, caravan 1→3) makes radius 4 cover 30% of the 20×10 skirmish map. Is that too much vision for small maps? | No | Ship it, measure with `hx sim run` (fog-dependent AI), and revisit with Q1. |

---

## 5. Bead breakdown (ordered)

Runner key: `swarm` = small, fully specified, Qwen4-safe; `autopilot` = Haiku-sized; `autopilot-large` = needs Opus.

**B1. Overworld tuning: slower movement, more sight**: task, P2, `swarm`
- *Why:* U1Q25 and U1Q26, the numbers part only.
- *What:* data edits, plus the code default for convoy movement.

| Value (file) | Before | After |
|---|---|---|
| field_commander mp / sight (`overworld.json:74`) | 60 / 3 | 50 / 4 |
| outrider mp / sight | 90 / 4 | 80 / 5 |
| siege_captain mp / sight | 50 / 3 | 40 / 4 |
| jeff_commander mp / sight (`angelfall.json:62`) | 50 / 3 | 45 / 4 |
| village sight | 2 | 3 |
| frontier_town sight | 2 | 3 |
| barracks sight | 1 | 2 |
| depot sight | 1 | 2 |
| mine sight | 1 | 1 (unchanged) |
| `convoy_movement` on test_vale and skirmish_mirror | 40 | 30 |
| `OverworldRules.DEFAULT_CONVOY_MOVEMENT` | 40 | 30 |

- *Also:* update the §2.9 speed line and the Data Model default.
- *Acceptance:* `hx godot test` is green (fix tests that assert old numbers). `hx sim run duel_crossroads --variant baseline --seeds 3` is recorded before and after, and the summary goes in the bead notes.
- *Deps:* none.

**B2. Band templates and caravan sight (the caravan entity, step 1)**: feature, P2, `autopilot`
- *Why:* U1Q26 and U1Q27; caravans see 3 hexes; a band kind is data.
- *What:*
  - Add the `band` kind to `data_schema.gd`. Add `band_garrison` and `band_caravan` to `overworld.json`.
  - Compile them in `OverworldRules` (`bd_sight`, `bd_mp`, `bd_payload_stats`, `bd_caps`). Map `detachment_sight` and `convoy_movement` become overrides.
  - Add the `band` column to `OverworldDetachments` (default −1 = derive from `is_convoy`). Set it at every spawn and transition: drop-off, `_make`, `rally`, `set_route`, `_arrive`, `rally_survivors`.
  - New `src/sim/overworld/overworld_stats.gd` (`sight(s, kind, id)` and `movement(s, kind, id)` → `{value, terms}`).
  - `OverworldVision.sight`, `Convoys.plan` and `OverworldMovement` glimpses (`overworld_movement.gd:160, 188`) read it.
  - `observe` adds `band`, `sight` and `movement` for own and allied bands.
- *Acceptance:*
  - A garrison sees radius 1, a caravan radius 3, a halted caravan stays a caravan.
  - An old save (no `band` column) loads and plays.
  - A same-seed rerun hashes identically.
  - GDD 02, 03 and 04 are updated.
- *Deps:* B1.

**B3. Payload contributions (scouts raise caravan sight)**: feature, P3, `autopilot`
- *Why:* U1Q27; payload is read as components.
- *What:*
  - Add an `overworld` field on `squad` and `item` in the schema (closed stat set: `sight`, `movement_points`). Compile it to `sq_ow` and `it_ow`.
  - `OverworldStats` sums contributions from a band's squads and their equipped items (squad-ID order) for the stats in its `payload_stats`, capped by `caps`, with a term per source.
  - Give `scout_team` and `marksman_team` `{"sight": 1}` in `humanity.json`.
  - Hex card / band card shows "Sight 4 (caravan 3, scout team +1)".
- *Acceptance:* tests cover 0, 1 and 3 scouts (cap +2), a garrison unaffected, and the equipped-item contribution. Enemy observation doesn't reveal the terms.
- *Deps:* B2.

**B4. HexLayout: site slots, road offsets, mover lane (pure code + UI data)**: feature, P2, `autopilot-large`
- *Why:* U1Q20–U1Q22.
- *What:*
  - Add the drawing-only fields `layer`, `draw_order`, `layout_priority`, `connects` and `color` to `hex_feature` in the schema. Set core data: plains, forest, hills and lake are ground; road is a path that connects itself; the rest are sites.
  - Add `data/ui/hex_layout.json` with the slot tables (thousandths, y down; site radius 180):
    - 1: (0,−80)
    - 2: (−260,−80) (260,−80)
    - 3: (0,−320) (−260,120) (260,120)
    - 4: (−260,−300) (260,−300) (−260,160) (260,160)
    - 5: (0,−100) (−300,−380) (300,−380) (−300,240) (300,240)
    - 6: a ring of 6 at 420 around (0,−80)
    - 7: centre (0,−80) plus that ring
    - Mover lane: y = 620, x = −260 / 0 / 260.
    - Road: half-width 110, group shift 300, group scale 85%, clearance 290.
  - New `src/presentation/overworld/hex_layout.gd`, static. Inputs: site templates, road directions (the neighbour sides whose known features connect), overrides.
    - **Ordering:** sites by `layout_priority` descending, then template ID.
    - **Open direction:** the bisector of the widest angular gap between road directions (side *k* is at −60·k° on screen). A tie goes to the bisector pointing most downward, then the lowest x.
    - **Road hex:** shift the group along the open direction and scale it. Push any site within clearance of a road segment along that segment's normal (the open side if it lies exactly on the road). If any two sites still overlap, shrink the arrangement in 10% steps down to 60%.
    - **Overrides:** applied last.
    - **Output:** integer points.
- *Acceptance:*
  - GUT tests: each count 1–7; straight E–W, NE–SW, a dead end and a three-way junction; an override; determinism (same inputs, same points); no site inside the road clearance.
  - `HexLayout` is also usable from the addon.
- *Deps:* none (parallel with B1–B3).

**B5. War room hex view at the new scale, with detail bands**: feature, P2, `autopilot-large`
- *Why:* U1Q20 on screen.
- *What:*
  - `ContextView`: `HEX_SIZE` 26 → 64. Ground tile by `draw_order`; road strips from the hex centre to each connected side's midpoint (866 thousandths). Each site drawn at its `HexLayout` point with icon or colour, owner ring and progress pip. Commanders and bands drawn in the mover lane. The detail bands of §3.3.
  - `ViewContexts`: zoom constants (0.25 / 1 / 3.0, enter at 2.5).
  - Replace the `FEATURE_COLORS` table with the features' `color` (relates to sw-ll4.8).
  - Mock: `hx godot mock` of the war room → `Mocks/war_room.png`.
- *Acceptance:*
  - The mock shows a village on a road offset off it, and a hex with 3 sites.
  - No new per-frame allocations beyond the per-plot layout cache (PerfRecorder `draw_overworld` within 10% of before at the same hexes on screen).
  - Tests for `plot_at` / `feature_at` at three zooms pass.
- *Deps:* B4.

**B6. Per-feature selection and inspect_feature**: feature, P2, `autopilot`
- *Why:* U1Q23.
- *What:*
  - `OverworldSession.inspect_feature`. `inspect_plot` reuses it.
  - `ViewContexts.selected_feature` and `select_feature`, with the clearing rules.
  - `ContextView.feature_at` and highlight drawing.
  - `CommandPanel` hex section: selectable feature rows, hover and select linked both ways.
  - With a producing site selected, a right click sets its rally point. The existing "Set rally point…" moves onto the selected feature's row.
  - `ControlsHelp` and `HexCard` lines.
- *Acceptance:*
  - Clicking a site selects it on the map and in the panel, and clicking its row does the same.
  - Remembered (fogged) features are selectable and show "last seen".
  - Deselect-all clears it.
  - GUT tests for `ViewContexts` and `inspect_feature` (out of sight comes from memory; a dead ID returns {}).
- *Deps:* B5 (for hit-testing). `inspect_feature` can land first.

**B7. Map editor: site placement override (`at`) and a road layer**: feature, P3, `autopilot`
- *Why:* U1Q21. Also, today's one-ground-per-hex canvas can't hold a road over forest.
- *What:*
  - Add `at` to the `map_pass` schema (place only, −700..700). `OverworldRules` compiles a drawing-only `layout_at` (plot → template → Vector2i, partner negated on mirror maps).
  - `OverworldCanvas`: objects carry `at` (round-trip), and a second painted layer for path features.
  - `OverworldPainter`: the Layout tool (Y: drag inside the hex, right-click resets), drawing through `HexLayout`.
- *Acceptance:*
  - `test_overworld_canvas` round-trips `at` and a road over forest.
  - A mirror partner is drawn negated.
  - An `at` outside the bounds is a load error.
  - GDD 04 §4.9 is updated.
- *Deps:* B4, sw-7ii (World maps tab).
- *Related:* sw-96x (left open for the victory form and squad positions).

**B8. Owner actions in the sim: remote buy**: feature, P2, `autopilot-large`
- *Why:* U1Q24.
- *What:*
  - Schema: `owner_actions`, `sells` (`item_option`), `remote_markup`, `purchases_per_turn`. Compile to `hf_owner_actions` bits, `hf_sells`, `hf_markup`, `hf_buys`.
  - `OverworldState.owner_orders`, saved, restored and hashed like `activities` (missing in old saves = {}).
  - `OverworldOrders.set_owner_action` (validates ownership, the option, the per-turn limit, and Value at plan time as a warning only). `OverworldSession.set_owner_action` (Planning gate, logged for replay).
  - New `OverworldOwnerActions.resolve` between activities and production in `OverworldTurn.resolve`. It cancels with a reason for: not yours, engaged, contested, no Value. It pays and makes output through the `Convoys._make` path.
  - Events `squad_bought` / `item_bought` / `owner_action_cancelled`, added to `_EVENT_FIELDS` and `_HOSTILE` (redacted like `squad_produced`).
  - Core data: village and barracks get `owner_actions: ["buy","rally","output"]`; the depot `sells` one item.
- *Acceptance:*
  - Tests: a buy with no line goes to the garrison; with a line it leaves as a caravan; captured the same turn → cancelled; an engaged hex → cancelled; a hostile commander on the hex → cancelled; markup rounding; a limit of 1 a turn.
  - Replay determinism (record and rebuild).
  - GDD 02, 03 and 04 are updated.
- *Deps:* B2 (caravans as bands). Q2 and Q3 are answered or defaulted.

**B9. Owner actions UI: buy from the selected feature**: feature, P3, `autopilot`
- *Why:* U1Q24 in play.
- *What:* the selected feature's panel lists its owner actions from `inspect_feature.actions`: a buy button per option with its price and markup (disabled with the reason), output choice (the first UI for `set_output`), and the rally point. The planned buy shows as a pending line and can be cancelled. Event feed lines go through `EventText`.
- *Acceptance:* a GUT UI test drives buy → end turn → garrison grows. A Value shortfall shows its reason. Owner actions are hidden in the replay viewer (locked).
- *Deps:* B6, B8.

**B10. AI uses owner actions**: task, P3, `autopilot`
- *Why:* the AI profiles must not fall behind a human who buys remotely.
- *What:* `ExpandController` and `ProfileController` (utility process) gain a "buy at owned feature" candidate, weighted by Value surplus and garrison threat. `HeadlessOverworld` logs it.
- *Acceptance:* `hx sim run duel_crossroads --variant baseline --seeds 3` shows buys happening. No regression in the fitness spec's win-rate gates.
- *Deps:* B8.

**B11. Production pauses on an engaged hex**: bug, P3, `swarm`
- *Why:* §1.3 quirk (Q5): production spawns a fresh detachment on a battle hex.
- *What:* `Convoys.produce` skips (and holds progress for) a feature whose plot has an engagement. Add a test.
- *Acceptance:* during a battle on a barracks hex, progress is unchanged and no detachment appears. The GDD line from §3.1 is added.
- *Deps:* none. Owner OK on Q5, or the default.

**B12. GDD: insert the U1 overworld text**: task, P2, `swarm`
- *Why:* settles the design before B2–B9 build against it.
- *What:* paste §3 of this draft (as amended by the owner's answers) into GDD 02 §2.9, 03 §3.5 and 04 §4.2/§4.4/§4.8/§4.9. Add the decision log entries U1Q20–U1Q27, plus the proposals the owner accepts. Add a glossary term `caravan` (alias convoy), `band` and `owner action`.
- *Acceptance:* `hx godot check` passes (glossary JSON validates), and the links resolve.
- *Deps:* the owner answers §4 (or accepts the defaults). Do it first, before B2.

**Suggested order:** B12 → B1 and B4 (in parallel) → B2 → B5 → B6 and B8 → B3, B7, B9, B11 → B10.
- **Related existing beads:** sw-o1m (overworld epic; children done, eligible to close: file B1–B11 under a new child epic "Overworld U1"); sw-7ii and sw-96x (the editor, B7 builds on them); sw-ll4.17 (selection and stamps, done; no overlap); sw-ll4.8 (feature colour from data, folded into B5).
