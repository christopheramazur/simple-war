# Main Concepts

**Status**: Draft  
**Last Updated**: 2026-03-18  
**Purpose**: High-level overview of how Simple War is structured — its ECS architecture, player-facing experience, and the relationship between Campaigns, Armies, and Battles — so designers and developers can reason about the system and begin implementation.

---

## 1. Big Picture

Simple War is about **Players** using **Commanders** to lead **Armies** on a **Campaign**. Campaigns take place across a **Sector Map**. A Campaign might have many **Activities** such as **Armybuilding** to rally forces, **Battle** to establish dominance in a sector, **Travel** to bring forces where they need to be, **Trade** to acquire equipment or offload excess, and more. A Campaign concludes for the Player when they have either achieved its **Objectives**, or when they can no longer participate in any Activities. The Conclusion of a Campaign results in a **Score** which determines the ultimate victor, even if all a Player's Commanders and Armies have been lost.

Under the hood, every game object — every Campaign, Commander, Army, Unit, Model, Item, Battlefield, and Battle — is an **Entity** in an **Entity–Component–System (ECS)** architecture. What an Entity *is* comes from its **Components** (data). What an Entity *does* is determined by **Systems** (logic). The next section introduces this architecture; all subsequent sections use its vocabulary.

---

## 2. Architecture: Entity–Component–System

Simple War uses an ECS architecture throughout. Understanding three concepts is sufficient to read the rest of this document and all rule documents (see rule 200.1–200.5 in Entity System Rules for the formal definitions):

- **Entity** — A unique identifier (ID). An Entity has no inherent data or behavior; everything about it comes from Components.
- **Component** — A data structure attached to an Entity. Components hold state (e.g., a Statline Component holds Endurance, Durability, Morale, Speed, Reflex). **Marker Components** (Tags) carry no data beyond their presence and serve as keywords for grouping and filtering (e.g., `Infantry`, `Vehicle`).
- **System** — A unit of logic that operates on Entities possessing a specific set of Components. Systems read Components, perform calculations, and write results back to Components. All game logic lives in Systems.

An **archetype** is a common combination of Components that defines a category of Entity. The standard archetypes are:

| Archetype | What It Represents | Key Components |
|---|---|---|
| Model | An individual figure | Statline, Equipped Items, Destruction State |
| Unit | A group of Models | Statline, Faction Keywords, Unit Keywords, Composition, Abilities, Value, Zone, Morale State |
| Item | Equipment or consumable | Item Type; optionally Attack Profile, Armour |
| Commander | A leader of an Army | Statline, Equipment, Abilities, Army Reference |
| Army | All Units under a Commander | Commander Reference, Unit References |
| Battleforce | Units selected for a Battle | Army Reference, Unit References, Total Value |
| Battle | A structured conflict | BattleStageComponent, TurnCounterComponent, PhaseComponent, VictoryConditionsComponent, and others (see rule 100.1 in Battle Rules) |
| Campaign | The top-level game structure | CampaignStageComponent, SectorMapRefComponent, Objectives, Scoring Rules (see rule 800.1 in Campaign Rules) |

The core **Systems** that drive gameplay:

| System | Purpose |
|---|---|
| Battle System | Orchestrates Battle flow: advances Stages and Phases, delegates to other Systems |
| Campaign System | Manages Campaign-level logic: Sector Map navigation, Activity resolution, Modifier layering |
| Combat System | Resolves attacks via the Attack Pipeline and Defense Pipeline |
| Zone System | Manages Entity Zone transitions (Battlefield, Reserves, Casualty Report, etc.) |
| Movement System | Reads spatial Components, resolves movement Orders |
| Deployment System | Places Units on the Battlefield within Deployment Zones |
| Morale System | Manages Morale state transitions based on test results |
| Ability System | Evaluates Ability conditions and effects during timing windows |

Not everything is an Entity. The Roster validation process, Score calculation, and the Deployment process itself are structural or bookkeeping objects that do not carry Components.

---

## 3. Breakdown of Player Activities

- Players build and maintain **Armies** which are led by **Commanders**.
  - This is similar to Heroes of Might and Magic. A Commander might appear as a powerful warrior on the field, or may be a strategist orchestrating events from afar, or anything in between.
  - Commanders are Entities of the Commander archetype — their Components include a Statline, Equipment, Abilities, and an Army reference (see rule 260.1 in Entity System Rules).
  - There may be cases where multiple Commanders lead an army. A Player's Armies and Battleforces must always be led by at least one Commander at the start of a Battle.

- Armies are composed of **Units** (and ultimately the **Models** and **Items** those Units are composed of; see `Terminology`).
  - An Army doesn't have any innate limits on size or composition. Instead, the Campaign will impose different restrictions through **Campaign Modifiers** — Component modifications and System parameter overrides — that influence what Units are allowed in an Army and how large it can or must be (see rule 850.1 in Campaign Rules).
  - Unlike Heroes of Might and Magic, not all the Models in a Unit are uniform. Some may have **Abilities**, Items, or **Characteristics** that set them apart.

- **Rosters** determine the restrictions in place for **Battleforces** involved in a Battle.
  - These may be restrictions on total Battleforce value, limits to the allowed **Factions** or Units, or other filtering restrictions.
  - The Zone System validates Battleforces against Roster requirements (see rule 270.3 in Entity System Rules).
  - Thematically, Rosters are imposed on largescale violent conflict by The Law and its remnant Enforcers, as they try to prevent the Galaxy from descending into despotism.

- Battles are fought between opposing Battleforces on a **Battlefield**.
  - A Battle is an Entity of the Battle archetype. The Battle System orchestrates its four Stages: Planning, Deployment, Engagement, and Consolidation (see rule 100.1 in Battle Rules).
  - A Commander must be leading each Battleforce, but does not need to be present on the Battlefield.
  - Like Heroes of Might and Magic, there may be opportunities to retreat, or resolve a battle diplomatically, or accept the surrender of an opponent in exchange for Campaign-specific resources.

- A Battle consists of 4 primary **Stages**: **Planning**, **Deployment**, **Engagement**, and **Consolidation**.
  - Planning is where Players determine which of their Commanders and Battleforces will be involved in the Battle, how the Units in those Battleforces will be Deployed and Composed, and which other strategic assets or resources they will commit.
  - Engagement is the primary resolution stage. It consists of a repeating cycle of **Turns**, each broken into **Phases** (Rally, Issue Orders, Execute, Resolve Combat) tracked by the Battle Entity's PhaseComponent.
    - Players simultaneously issue **Orders** to their Units in secret. Once all Players are finished giving out Orders, there will be a chance to issue Reactions. Once all of the Orders and Reactions are issued, the Battle System delegates to the Combat System, Movement System, and other Systems to resolve them.

- Battleforces are drafted from Units in a Commander's Army and **Deployed** to Battlefields.
  - Players Deploy their Battleforces at the same time, hidden from each other.
  - Units are set up on the Battlefield in formation, similar to Total War style games. The Deployment System handles Unit placement within Deployment Zones defined by the Battlefield Entity's DeploymentZonesComponent (see section 300 in Movement and Positioning Rules).
  - Commanders, Abilities, and Campaign Modifiers can all influence how and where Units can be set up.

- **Reinforcements** are Units from a Battleforce whose Zone Component is set to Reserves rather than Battlefield at the start of a Battle.
  - Reinforcements are instead Deployed to the Battlefield through other methods, such as hidden infiltrators waiting in ambush; outflanking cavalry ready to arrive where and when they're least expected; teleporting reserves awaiting the perfect opportunity to turn the tides; and more.
  - Commanders, Abilities, and Campaign Modifiers can all influence how and where Reinforcements can be set up.

- Commanders navigate the **Sector Map** with their Armies to participate in **Activities**.
  - The Campaign System manages Sector Map navigation and Activity resolution (see rule 800.4 in Campaign Rules).
  - Commanders will traverse the Sector Map in various ways depending on the type of Campaign and the Commanders involved.
    - e.g. a Human commander might travel over land via marching or ATV, or across worlds in a human spaceship. A Lawbringer may simply teleport. The Bloom might march, but could pathfind via Eleventh Thought. The Kraken simply shifts its focus to where the fighting is at, coordinating any of its tentacles already present.

- Activities are represented on the Sector Map by **Plots**, points of interest to a Commander.
  - Not all Plots are accessible to all Commanders, and not all Commanders are interested in all Plots.
  - The generic Activities which are almost always accessible are Armybuilding and Battle activities.
  - Commanders, Abilities, Campaign Modifiers, and Factions involved can all influence how a Player interacts with Plots.

- Campaigns tie together Rosters, Battles, and other activities into a structured experience with an **Opening** and a **Conclusion**.
  - The Opening consists of gameplay choices such as your Faction, **Allegiances**, where you wish to place your initial Commanders on the Sector Map, what Unit selections will be in your initial Armies, and other configurations on a per-Campaign basis.
  - The Conclusion is where Players receive their final scores and the overall victor is determined.

---

## 4. User Experience Details

Simple War has a number of gameplay or gameplay adjacent options to select from the Main Menu:
- Quickplay
- Skirmish
- Story
- Multiplayer
- Armybuilding
- Campaign Editor
- Unit Editor
- Settings
- Exit Game

As well, at any point during the game, the Player has access to a context-aware menu through a configurable Hotkey (by default F10), or through an easily located Menu button (by default located on the top-right corner of the screen). This Menu button provides a popup menu with options:
- Main Menu
- Settings
- Exit the Game

There are also contextual options when appropriate, such as:
- Save, when opened from the Sector Map or during Battle
- Concede Campaign or Battle, when opened from Sector Map or during Battle

### Quickplay
Quickplay is for jumping directly into a Battle, without regard for the wider Campaign experience. There is a simplified Army Selection where the Player selects Commanders and their Armies for both themselves and a computer opponent, and then selects a Battlefield and Objectives for the Battle, and then can begin a Battle using all of those Armies in full as the Commanders' Battleforces on that Battlefield.

### Skirmish
Skirmish allows the Player to select a Campaign from a list, configure available settings for that Campaign such as starting Commanders, Faction, Difficulty, Number of Opponents, etc. These options are primarily provided by and depend on the Campaign — some or all options may be fixed, and others may be configurable; some may have defaults, others may force the Player to choose.

The Campaign Selection Screen consists largely of two displays:
- Campaign List Display
  - Campaigns are listed here, with a searchbar at the top
- Campaign Details Display
  - When a Campaign is selected, its details and configurable options appear here

There is also the option to load an existing Story saved game from this scene.

### Story
Story is a series of Campaigns detailing the game's narrative through gameplay. These Campaigns are linked together in many ways, with the Player's choices influencing what options are available throughout.

There is also the option to load an existing Skirmish saved game from this scene.

### Multiplayer
Multiplayer provides the option for Players to engage in Campaigns with other Players, both cooperatively and competitively.

There are multiple Multiplayer game modes: Freeplay, Unranked, and Ranked.

Freeplay allows Players to choose any Campaign, including custom Campaigns, and use any custom Factions or Units they want.

Unranked allows Players to use only the official Simple War Campaign and Unit data, and does not track or affect a Player's Ranked performance.

Ranked allows Players to use a curated Competitive Campaign set, with only the official Simple War Unit data. Wins, Losses, and metadata about a Player's gameplay such as Faction and Commander choices, score, and more are all tracked to provide comprehensive Player Rankings.

There is also the option to load an existing Multiplayer saved game from this scene. Players who join the game are able to select their positions, e.g. if Player 1 and Player 2 were playing, saved the game, and then at a later point loaded it, the accounts associated with Player 1 and Player 2 are not locked to resuming as those positions — they could swap, or be entirely different players.

### Armybuilding
Armybuilding is the standalone Army management experience, accessible outside of any Campaign. Players can create, edit, duplicate, and delete Armies without the constraints of a Campaign Roster or Sector Map context.

The Armybuilding Screen presents two main areas:
- Army List Panel
  - Displays all of the Player's saved Armies, with a searchbar and filters for Faction, Commander, and Army value range.
  - Each entry shows the Army's name, Commander, Faction, total Army value, and validation status (whether the Army meets any Roster requirements it is listed against).
- Army Editor Panel
  - When an Army is selected, the editor opens with the full Army composition: Commander, Units, Models, and equipped Items.
  - Players can add or remove Units from the Army, change Unit composition (swapping Models or equipment), and rename the Army.
  - A running Army value total updates live as changes are made.
  - Validation warnings appear inline when a change would violate a Roster the Army is currently listed against.

Armies built here are available for use in Quickplay, Skirmish, Story, and Multiplayer. Changes to an Army that is currently participating in an active Campaign do not affect that Campaign's snapshot of the Army; only future Battles see the updated version.

### Campaign Editor
Campaign Editor allows Players to create, edit, and share custom Campaigns. A Campaign defines the Sector Map, Activities, Objectives, Roster requirements, and narrative flow that Players experience during Skirmish or Multiplayer.

The Campaign Editor Screen is divided into three main areas:
- Campaign Browser
  - Lists the Player's custom Campaigns alongside installed community Campaigns, with search and filter options.
  - Each entry shows the Campaign name, author, Player count, estimated duration, and publication status (Draft, Published, or Archived).
- Sector Map Canvas
  - A visual editor for placing and connecting Plots on the Sector Map. Players drag-and-drop Plot nodes, draw travel connections between them, and assign Activities (Armybuilding, Battle, Narrative Event, Trade, etc.) to each Plot.
  - Travel connections can have requirements (e.g. "complete this Activity first") and visual style (solid, dashed, or hidden).
- Properties Panel
  - When a Plot, connection, or the Campaign itself is selected, its configurable properties appear here: Activity type, Roster restrictions, Objectives, narrative text, AI opponent settings, difficulty scaling, and other Campaign-level parameters.
  - Campaign Modifiers are configured here as Component modifications (e.g., overriding BattlefieldDimensionsComponent, setting TurnLimitComponent) and System parameter overrides — not freeform rule text (see rule 850.1 in Campaign Rules).

Custom Campaigns can be exported and shared with other Players. The editor validates that the Campaign graph is completable (no unreachable Plots, at least one valid path from Opening to Conclusion) before allowing publication.

### Unit Editor
Unit Editor allows Players to create, edit, and share custom Units for use in custom Campaigns and Freeplay Multiplayer. Official Campaigns and Ranked Multiplayer use only the official Unit data and do not permit custom Units.

The Unit Editor Screen presents:
- Unit Browser
  - Lists the Player's custom Units alongside official Units (read-only) for reference. Filters for Faction Keywords, Unit Keywords, and value range are available.
  - Players can duplicate an official Unit as a starting point for a custom variant.
- Component Editor
  - The primary editing surface, structured around the Unit archetype's Components: name, Faction Keywords (marker Components), Unit Keywords (marker Components), Composition (Models and their equipped Items), Statline Component (Endurance, Durability, Morale, Speed, Reflex), Abilities, and Value.
  - Model slots can be added or removed. Each Model slot defines its Statline Component values, default Items, and available equipment options with associated Equipment Costs.
  - Attack Profile Components for weapons are edited inline, specifying category, range brackets, damage, damage type, and modifiers.
- Validation Panel
  - Provides live feedback on the Unit's internal consistency: missing Characteristics, orphaned Keywords, cost imbalances, and Abilities that reference undefined rules.
  - A balance estimate gives a rough comparison of the custom Unit's value against official Units with similar roles.

Custom Units can be exported and shared. The editor enforces structural validity (every Model has a Statline Component, every weapon has at least one Attack Profile Component) but does not enforce balance; that responsibility falls to the Campaign's Roster system.

### Settings
Settings provides access to all game configuration options. Changes apply globally and persist across sessions.

The Settings Screen is organized into tabbed categories:
- Gameplay
  - Turn timer defaults, auto-save frequency, tooltip verbosity, confirmation prompts for destructive actions (Concede, Exit), and difficulty presets for AI opponents.
- Controls
  - Rebindable Hotkeys (including the Menu Hotkey, default F10), mouse sensitivity, scroll speed, camera inversion, and drag thresholds for multi-select and unit movement.
- Video
  - Resolution, display mode (windowed, borderless, fullscreen), frame rate cap, VSync, quality presets (Low, Medium, High, Ultra), and individual toggles for shadows, anti-aliasing, particle density, and grid marker visibility.
- Audio
  - Master, music, sound effects, UI, and voice volume sliders. Output device selection and spatial audio toggle.
- Accessibility
  - Colorblind modes (Protanopia, Deuteranopia, Tritanopia), UI scaling, font size, screen reader support, and reduced motion options for animations and camera transitions.

All settings display their current value alongside the default, and a "Restore Defaults" option is available per tab and globally.

### Exit Game
Exit Game closes the application. If the Player has an active unsaved session (Campaign in progress, unsaved Army edits, or an in-progress Battle), a confirmation dialog appears listing the unsaved contexts and offering to save before exiting. Selecting "Save and Exit" persists all unsaved state; selecting "Exit without Saving" discards changes since the last save; selecting "Cancel" returns the Player to their previous screen.

---

## 5. Campaigns

A **Campaign** is an Entity of the Campaign archetype (see rule 800.1 in Campaign Rules) — the top-level game structure that organizes all gameplay for a group of Players. The **Campaign System** manages Campaign-level logic: Sector Map navigation, Activity resolution, and Modifier layering.

Every Campaign Entity has at least:

- **Opening** — determine the terms of the Campaign:
  - Number and composition of activities (for example: 3 Battles, or 2 Battles and 1 narrative event).
  - Objectives that Players should try to achieve.
- **Activities** — the things Players do during the Campaign:
  - In the most basic case, each Player builds an Army, then fights in a Battle against the other Player.
  - More complex Campaigns may add, remove, or modify activities (extra Battles, narrative events, strategic map moves, etc.).
- **Conclusion** — determine the victor of the Campaign based on its objectives and results.

Campaign Modifiers alter how Battles work by modifying Components on Battle Entities and overriding System parameters — without changing the core Battle Rules (see rule 850.1 in Campaign Rules). Examples include:

- Setting TurnLimitComponent to enforce a maximum turn count.
- Overriding BattlefieldDimensionsComponent or DeploymentZonesComponent to change the playing field.
- Adding or tightening Roster requirements for Battleforce validation.
- Modifying VictoryConditionsComponent to change Battle victory conditions.

For the first digital prototype, we assume a **Generic Campaign** that:

- Uses a default Roster with no special restrictions.
- Has a single Battle as its only activity.
- Uses straightforward "most victory points / wipeout" style victory conditions.

---

## 6. Rosters and Armies

**Building an Army** is how a Player prepares for a Battle.

- A Player selects and configures **Units** (Entities of the Unit archetype) to fill out an **Army** (an Entity of the Army archetype) until the Player is satisfied and (optionally) meets Campaign or Roster requirements.
- Armies are organized by a **Roster** system:
  - A **Roster** is a Zone that organizes Battleforces. The Zone System validates Battleforces against Roster requirements; a Battleforce can be listed in any Roster whose requirements it meets (see rule 270.3 in Entity System Rules).
  - The **default Roster** has no restrictions.

At this overview level:

- An **Army** is "the set of Unit Entities a Player brings to a Battle".
- Each Army has a total **Value** (via its Units' Value Components) that summarizes its overall strength for pairing and balancing Battles.
- Campaigns and formats can define additional Roster types with stricter requirements through Campaign Modifiers.

For the barebones implementation, we only need:

- A way to define and store a small number of Armies per Player.
- A simple validation step that checks "Army can be used in this Battle / Campaign".

---

## 7. Battles

**Fighting a Battle** involves Players participating in four ordered Stages, tracked by the Battle Entity's BattleStageComponent and advanced by the **Battle System** (see rule 100.2 in Battle Rules):

1. **Planning**
2. **Deployment**
3. **Engagement**
4. **Consolidation**

A Battle is generally:

- Fought between **two opposing Battleforces** of similar total Value.
- Played on a **single Battlefield** (an Entity with spatial Components such as BattlefieldDimensionsComponent, DeploymentZonesComponent, and TerrainIndexComponent; see section 300 in Movement and Positioning Rules).
- Fought until one Battleforce has been wiped out or another victory condition in the Battle Entity's VictoryConditionsComponent is met.

Campaign Modifiers can also modify how Players engage in Battle by overriding Components on the Battle Entity, such as:

- Setting TurnLimitComponent to enforce a different turn count.
- Modifying VictoryConditionsComponent to change victory conditions or scoring.
- Adding or tightening Roster requirements for Battleforce validation.

---

## 8. Battle Stages (High Level)

At a high level, each Stage of a Battle looks like this. The Battle System advances through these Stages in strict order, delegating to specialized Systems during each Stage:

- **Planning Stage**
  - Players select Units from an Army to compose a Battleforce. The Zone System validates each Battleforce against Roster requirements.
  - Faction Relationships and other pre-Battle information are revealed.

- **Deployment Stage**
  - The Deployment System places Units from each Battleforce onto the Battlefield within designated Deployment Zones according to the Battle or Campaign rules.
  - Units not designated for initial Deployment have their Zone Component set to Reserves.

- **Engagement Stage**
  - Players command their Units in a repeating cycle of **Turns**, each broken into **Phases** tracked by the Battle Entity's PhaseComponent: Rally, Issue Orders, Execute, Resolve Combat.
  - Simple War uses a **true simultaneous turn** system (see `Terminology – Fighting a Battle` for more detail).
  - During Execute and Resolve Combat, the Battle System delegates to the Movement System, Combat System, Morale System, Zone System, and Ability System to resolve Orders and their consequences.

- **Consolidation Stage**
  - Players determine the victor of the Battle based on VictoryConditionsComponent.
  - The Battle Entity's CasualtyReportComponent and ScoringComponent record casualties, objectives scored, and other outcomes for use by the Campaign System.

For the barebones digital Battle, we primarily need:

- A Battlefield Entity where two Battleforces can be deployed.
- A minimal Turn and Phase structure in the Engagement Stage, driven by the Battle System.
- A simple Consolidation step that declares a winner and records high-level results for the Campaign layer.

---

## 9. Digital Prototype

For the initial digital prototype, our focus is on a quickplay user experience starting from a main menu.

- Player launches game
  - Main menu appears, "Simple War" title, "Quickplay" and "Quit" are their options
  - Quickplay begins a Quickplay Campaign
  - Quit ends the game

- Quickplay launches to a simple Campaign (a Campaign Entity with the `Quickplay` marker Component)
  - A Sector Map with two Activities: Armybuilding, Battle.
    - Armybuilding here allows the Player to add a pre-built selection of Units to their Commander's Army
    - Battle here has a single Roster that allows the Player to use every Unit from their Army as a Battleforce
    - The Battle will be against an identical Battleforce led by an identical Commander

  - The Player has one Commander
    - A generic Commander Entity with no special Abilities
    - Deployable to the Battlefield as its own Unit
    - Generic "slightly better than a regular Unit" Statline Component and equipped Items
    - The Commander begins on the Armybuilding Plot and must complete that Activity to move to the Battle Plot

- A basic **Engagement** Stage with a Turn system driven by the Battle System that can be expanded later.
- A flexible **Campaign** layer where the Campaign System applies Campaign Modifiers to Battle Entities without changing the core Battle Rules.

---
