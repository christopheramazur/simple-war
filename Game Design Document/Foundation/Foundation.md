# Foundation

Status: Draft  
Last Updated: 2026-03-18  
Purpose: High-level overview of how Simple War is structured — its ECS architecture, player-facing experience, and the relationship between Campaigns, Armies, and Battles — so designers and developers can reason about the system and begin implementation.

---

## 1. Big Picture

Simple War is about Players using Commanders to lead Armies on a Campaign. Campaigns take place across a Sector Map. A Campaign might have many Activities such as Armybuilding to rally forces, Battle to establish dominance in a sector, Travel to bring forces where they need to be, Trade to acquire equipment or offload excess, and more. A Campaign concludes for the Player when they have either achieved its Objectives, or when they can no longer participate in any Activities. The Conclusion of a Campaign results in a Score which determines the ultimate victor, even if all a Player's Commanders and Armies have been lost.

Simple War is a competitive single or multiplayer game with a replayable story-driven game-mode. User activity is tracked in replay files that can be used to upload gameplay stats for leaderboards. Replay files use hashing to ensure theyr'e self-verifying against the version of the game they were created with. Singleplayer game modes include quickplay and skirmish modes -- which allow a Player to jump directly into Battle or into smaller, self-contained Campaigns -- as well as Challenge and Story modes, which allow a player to experience curated Campaigns. There will also be support for commsquady contriutions to these game modes.

The multiplayer experience is broken into custom, unranked, and ranked. The custom game mode allow Players to interact with Player-driven content without affecting their rankings and with the understanding that the gameplay may be wildly non-standard, similar to the Use Map Settings and Arcade gameplay of Blizzard games. Unranked games are played on official campaigns using official settings, but do not affect a player's rankings. Ranked games are played on official campaigns using official settings, and affect player rankings. 

The primary aspect of Simple War that sets it apart from similar RTS and TBS style games such as Total War, Starcraft, Heroes of Might and Magic, Battle for Wesnoth, etc. is the parallel and simultaneous gameplay. In Heroes of Might and Magic, Players take turns moving around the overworld map, moving creatures on the battle map, etc. In Total War, the gameplay on the battelfield may be realtime and simultaneous, but Players still take turns on the overworld map, creating a series of sequential battles. 

Simple War breaks this up by interweaving gameplay activities. Battles take place at the same time as other overworld activities. A Player may be managing multiple Battles at once. Each Battle progresses when all Players are finished issuing orders to their Squads, and the resulting orders are executed and resolved simultaneously. These activities all may have rolling timers that cost against the Player's focus and attention, benefitting quick play and having a gameplan even if the game is turn-based. 

Like Battletech games, each Battle may also impose limitations on who and what can be involved in it. This further deepens the Player's decisionmaking when it comes to going wide or deep with their approach to dominance. Like Heroes of Might and Magic, the Squads and Commanders involved in a Battle can influence each others' morale and temperment.

---

## 2. Architecture

### Simulation Layer
All gameplay activity takes place on a simulation layer, decoupled from animation or presentation. The simulation layer produces the game's replay files. 


### Audit and Replay 
Systems produce an append-only Event record for audit and replay when they mutate state. We recreate a user session and game state deterministically from these audits. Saving uses binary serialization and works by iterating the game state and copying out the bits and pieces (required to re-construct it at load time) to the compress-and-write-to-disk threads. By comparing the final record of an replay audit to the game sate, we can verify that game state. Differences indicate that external mutations influenced game state and that the replay is not verifiable. 

### Presentation Layer
The Presentation Layer hooks into the Simulation Layer to understand what the game should be showing the player. This lets us divorce framerate, art, animation, UI/HUD, and any other presentation concerns from the gritty details underneath, and allows modders to supply their own assets and widgets to create or extend any part of how the game presents itself more easily. 

### Performance Monitoring
We make use of Godot's performance monitoring to identify bottlenecks in simulation and presentation. 

### Entity Component System
Simple War uses an ECS architecture throughout. Understanding three concepts is sufficient to read the rest of this document and all rule documents.

- Entity — A unique identifier (ID). An Entity has no inherent data or behavior; that comes from Components.
- Component — A data structure attached to an Entity. Components hold state (e.g., a Statline Component holds Endurance, Durability, Morale, Speed, Reflex). 
  - Marker Components (Tags) are a subset of Component that carry no data beyond their presence and serve as keywords for grouping and filtering (e.g., `Infantry`, `Vehicle`).
- System — A squad of logic that operates on Entities possessing a specific set of Components. Systems read Components, perform calculations, and write results back to Components. If game logic mutates state, it should be part of a System. An example might be an Inventory System, which manages changes to Inventory components. If a Backpack Inventory has a Weight field, then the Inventory System is responsible for mutating and validating that field. There may also be global governance systems that do widespread validation and garbage collection for various components.

An archetype is a common combination of Components that defines a category of Entity. Example archetypes are:

| Archetype | What It Represents | Key Components |
|---|---|---|
| Unit | An individual figure | Statline, Equipped Items, Destruction State |
| Squad | A group of Units | Statline, Faction Keywords, Squad Keywords, Composition, Abilities, Value, Zone, Morale State |
| Item | Equipment or consumable | Item Type; optionally Attack Profile, Armour |
| Commander | A leader of an Army | Statline, Equipment, Abilities, Army Reference |
| Army | All Squads under a Commander | Commander Reference, Squad References |
| Battleforce | Squads selected for a Battle | Army Reference, Squad References, Total Value |
| Battle | A structured conflict | BattleStageComponent, TurnCounterComponent, PhaseComponent, VictoryConditionsComponent, and others |
| Activity | A generic activity that is represented on the Sector Map; Battles are Activities | ActivityStatusComponent, ConditionsComponent, etc. |
| Sector Map | A visual representation of overworld state. Activities, Paths, Commanders, and Armies are represented here | VisibilityComponent, ActivityMapComponent, etc. |
| Campaign | The top-level game structure | CampaignStageComponent, SectorMapRefComponent, Objectives, Scoring Rules |

The core Systems that drive gameplay:

| System | Purpose |
|---|---|
| Battle System | Orchestrates Battle flow: advances Stages and Phases, delegates to other Systems |
| Campaign System | Manages Campaign-level logic: Sector Map navigation, Activity resolution, Modifier layering |
| Combat System | Establishes where combat happens, and how it's resolved |
| Zone System | Manages Entity Zone transitions (Battlefield, Reserves, Casualty, etc.) |
| Battle Movement System | Reads spatial Components, resolves movement Orders |
| Sector Movement System | Reads Sector Map graph, tells entities where and how they can move |
| Deployment System | Places Squads on the Battlefield within Deployment Zones |
| Morale System | Manages Morale state transitions based on test results |
| Ability System | Evaluates Ability conditions and effects during timing windows |

Not everything is an Entity, Component, or System in Simple War. There are message busses, buffers, schedulers and orchestrators, and other data structures that aren't attached to entities or components which the game's Systems use to manage or optimize gameplay state and mutation. 


### GUTS
We generate tests to ensure that validity-checking works how we expect it to. We also test that generators, factories, and other patterns create the components and entities we expect them to.Systems with comprehensive test coverage are easier to learn about and modify. 

### GUIDE
The Player should have full control over their key mappings. This means making, saving, and sharing mappings are core concerns when it comes to gameplay. Player choice and accessibility are foundational to Simple War.


### Dialogic
We use JSON read from data to structure dialogue and events into components that hook into the ECS. This allows for Player-created narrative Campaigns to supply custom dialogue and graphics for events and interactions.

### Beehave
Simple War has multiple single-player game modes that require a computer controlled opponent to make decisions which challenge the player. Beehave helps us organize this decisionmaking as components and systems that can be used and adapted in order to make campaign creation easy and accessible. As well, when playing with timers, many squads and commanders have behaviours they default to when not issued orders in time, or when affected by narrative influence. 

### RTS Style Combat Resolution
A* pathfinding, precomputed pathing on battlefield maps for each type of movement component. Squad-based formation selection available with sensible defaults. Squads will show a ghost path of their movement and destination so the Player has a complete understanding of where things intend to end up. Many units can run and gun, or can bunker down and return fire when intercepted. Battles can be configured to allow Players to issue Reactions to their Squads after everyone's issued their Orders, to build on this behavior-based reactivity. The way Reactions are distributed can be configured as well, from a Timer based free-for-all, to a Reaction banking system that Players spend in a much less time-sensitive manner. Since simulationism is a major goal of Simple War, every attack from every Unit is calculated and resolved in the simulation layer, while the presentation layer does its best to display the action. 

---

## 3. Breakdown of Player Activities

- Players build and maintain Armies which are led by Commanders.
  - This is both similar and dissimilar to Heroes of Might and Magic. Commanders are how the Player interacts with the Sector Map. They are able to move between connected Plots and engage in Activities. In Battles, a Commander might appear as a powerful warrior on the battlefield, or take more of a strategist role, providing powerful abilities from an interface, or both, or anything in between. 
  - A Player's Battleforces must always be led by at least one Commander at the start of a Battle. If a Battle ends and the Commander has been killed, the Army they were leading begins to disperse. Depending on the Squads in the Army, this may present opportunities for other Commanders -- ally and enemy -- to recruit or destroy them. 

- Armies are composed of Squads (and ultimately the Units and Items those Squads are composed of; see `Terminology`).
  - An Army doesn't have any innate limits on size or composition. Instead, the Campaign will impose different restrictions through Campaign Modifiers — Component modifications and System parameter overrides — that influence what Squads are allowed in an Army and how large it can or must be.
  - Unlike Heroes of Might and Magic, not all the Units in a Squad are uniform. Some may have Abilities, Items, or Characteristics that set them apart.
  - A Commander can typically only lead a single Army. Some Commanders may have Abilities, or there may be Campaign modifiers, which allow for more.
  - Armies are organized into Battleforces. Players can manage Battleforces through rules and templates, which Armies will automatically attempt to fill as Squads become available.

- Rosters determine the restrictions in place for Battleforces involved in a Battle.
  - These may be restrictions on total Battleforce Value, limits to the allowed Factions or Squads, or other filtering restrictions.
  - Thematically, Rosters are imposed on largescale violent conflict by The Law and its remnant Enforcers, as they try to prevent the Galaxy from descending into despotism.
  - Squads can be in any numeber of Battleforces. Battleforces are simply a way to organize a Player's strategic intent.

- Battles are fought between opposing Battleforces on a Battlefield.
  - A Battle is an Entity of the Battle archetype. The Battle System orchestrates its four Stages: Planning, Deployment, Engagement, and Consolidation 
  - A Commander must be leading each Player's Battleforce, but does not need to be present on the Battlefield. If an opposing Army is not led by a Commander, it is considered a "Neutral" Army.
  - Like Heroes of Might and Magic, there may be opportunities for Commanders to retreat, or to resolve a battle diplomatically, or to accept the surrender of an opponent in exchange for various rewards. 
  - Losing a Battle typically results in a Commander being killed or captured. In many cases, it may be possible to revive or rescue those Commanders.

- A Battle consists of 4 primary Stages: Planning, Deployment, Engagement, and Consolidation.
  - Planning is where Players determine which of their Commanders and Battleforces will be involved in the Battle, how the Squads in those Battleforces will be Deployed and Composed, and which other strategic assets or resources they will commit.
    - If a Player has multiple Commanders present at a Battle Activity, they may be able to field multiple Battleforces depending on the Campaign and Battle.
  - Deployment is where Players simultaneusly arrange their Battleforces on the Battlefield, within clearly defined Deployment Zones for each Commander. 
    - The process of Deploying Battleforces may utilize timers, secret information, or have other requirements depending on the specific Battle and Campaign rules. 
  - Engagement is the primary resolution stage. It consists of a repeating cycle of Turns, each broken into Phases (Rally, Issue Orders, React, Execute, Resolve Combat) tracked by the Battle Entity's PhaseComponent.
    - Players simultaneously issue Orders to their Squads in secret. Once all Players are finished giving out Orders, there will be a chance to issue Reactions. Once all of the Orders and Reactions are issued, the Battle System delegates to the Combat System, Movement System, and other Systems to resolve them.
  - Battles are not blocking Activities. You can start a Battle with a Commander on one Plot, and then while it is progressing, continue to engage with the rest of the Sector Map with your other Commanders. Players may be engaged in multiple Battles at once. The Campaign rules will dictate if there is any relation between the progress of Turns in a Battle and the progress of Turns on the Sector Map. 

- Battleforces are drafted from Squads in a Commander's Army and Deployed to Battlefields.
  - Players normally Deploy their Battleforces at the same time, hidden from each other.
  - Squads are set up on the Battlefield in formations, similar to Total War style games.
  - Commanders, Abilities, and Battle and Campaign Modifiers can all influence how and where Squads can be set up.

- Reinforcements are Squads from a Battleforce that were Planned to start a Battle in Reserves rather than the Battlefield.
  - Reinforcements are instead Deployed to the Battlefield through other methods, such as hidden infiltrators waiting in ambush; outflanking cavalry ready to arrive where and when they're least expected; teleporting reserves awaiting the perfect opportsquady to turn the tides; and more.
  - Commanders, Abilities, and Battle and Campaign Modifiers can all influence how and where Reinforcements can be set up.

- Similar to Heroes of Might and Magic, Commanders navigate the Sector Map with their Armies to participate in Activities.
  - The Campaign System manages Sector Map navigation and Activity resolution.
  - Commanders will traverse the Sector Map in various ways depending on the type of Campaign and the Commanders involved.
    - e.g. a Human commander might travel over land via marching or ATV, or across worlds in a human spaceship. A Lawbringer may simply teleport. The Bloom might march, but could pathfind via Eleventh Thought. The Kraken simply shifts its focus to where the fighting is at, coordinating any of its tentacles already present.
  - Once the Players are satisfied with their Commanders' positions and Activities, they can end their Turn

- Activities are represented on the Sector Map by Plots, points of interest to a Player that they can access by moving a Commander to them.
  - Not all Plots are accessible to all Commanders, and not all Commanders are interested in all Plots.
  - The generic Activities which are almost always accessible are Armybuilding and Battle activities.
  - Commanders, Abilities, Campaign Modifiers, and Factions involved can all influence how a Player interacts with Plots.

- Plots are connected on the Sector Map by Paths. Paths may be bidirectional, single-directional, have a limited number of uses, and more. 
  - This is a distillation of typical free-movement style overworld maps, which are mostly dead space or full of trap movement options. 
  - Path navigation will never result in movement that strands a Commander. 
    - There may be Campaign rules or Abilities that allow Commanders to move without Paths, which will be evaluated when checking if a Commander is permitted to use them.
    - By default, Sector Maps created using procedural generation will have rules which prevent one-way and single-use dead-ends. 

- Campaigns tie Activities into a structured experience with an Opening, a Narrative, and a Conclusion. 
  - There are many built-in configuration options a Campaign provides a Player
    - Modifications can be made to extend the existing Campaign configurations and data model to create more specific or curated experiences.
  - Campaign selection works similarly to lobby creation in games like Starcraft, Heroes of Might and Magic, etc.
    - A Directory Display allows Players to select a Campaign from a list, and to move, sort, and filter the Campaigns listed according to various metadata such as name, date, size of Sector Map, presence of custom content, when it was last played, and various other tags.
    - A dedicated Campaign Info Display allows Players to see and modify the available configuration options of the Campaign, such as number of opponents, available factions, procedural generation options, etc.
  - The Opening consists of gameplay choices such as your Allegiances, where you wish to place your initial Commanders on the Sector Map, what Squad selections will be in your initial Armies, and other configurations provided on a per-Campaign basis.
  - After the Opening, the Narrative of the Campaign begins, starting the first Turn and giving control of the Commanders to the Player.
    - Each Turn, Players declare an Intent for each of their Commanders. The typical Intents available are Travel, Event, Recruit, and Battle. 
      - Each of the Intended Activities can have a duration associated with it, consisting of how many Turns a Commander must be present to realize that Intent.
      - These Activities may be interrupted or disrupted. If a Player is recruiting and an Opponent begins a Battle with them, losing may prevent them from realizing their Intent. Similarly, if the Recruitment Activity had Army Value or Squad requirements that are no longer met after the Battle, the Activity may provide less Value to your Army than expected.
      - If one Commander Intends to Battle, and an opposing Commander on the same Plot doesn't, there may be flat-footed penalties to the Planning and Deployment of the aggressed.
      - Usually, taking part in one of the Stages takes up all of a Commander's attention for the Turn. Some abilities may allow for Commanders to declare multiple Intents by instantly Realizing one or more of them, such as through Teleportation. 
    - Simple War is, again, a game where Players resolve their turns simultaneously. This means there isn't always going to be perfect information for the Player when they are near an opponent. However, some abilities and settings allow for Commander intents to be revealed and reacted to. 
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
- Squad Editor
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

Freeplay allows Players to choose any Campaign, including custom Campaigns, and use any custom Factions or Squads they want.

Unranked allows Players to use only the official Simple War Campaign and Squad data, and does not track or affect a Player's Ranked performance.

Ranked allows Players to use a curated Competitive Campaign set, with only the official Simple War Squad data. Wins, Losses, and metadata about a Player's gameplay such as Faction and Commander choices, score, and more are all tracked to provide comprehensive Player Rankings.

There is also the option to load an existing Multiplayer saved game from this scene. Players who join the game are able to select their positions, e.g. if Player 1 and Player 2 were playing, saved the game, and then at a later point loaded it, the accounts associated with Player 1 and Player 2 are not locked to resuming as those positions — they could swap, or be entirely different players.

### Armybuilding
Armybuilding is the standalone Army management experience, accessible outside of any Campaign. Players can create, edit, duplicate, and delete Armies without the constraints of a Campaign Roster or Sector Map context.

The Armybuilding Screen presents two main areas:
- Army List Panel
  - Displays all of the Player's saved Armies, with a searchbar and filters for Faction, Commander, and Army value range.
  - Each entry shows the Army's name, Commander, Faction, total Army value, and validation status (whether the Army meets any Roster requirements it is listed against).
- Army Editor Panel
  - When an Army is selected, the editor opens with the full Army composition: Commander, Squads, Units, and equipped Items.
  - Players can add or remove Squads from the Army, change Squad composition (swapping Units or equipment), and rename the Army.
  - A running Army value total updates live as changes are made.
  - Validation warnings appear inline when a change would violate a Roster the Army is currently listed against.

Armies built here are available for use in Quickplay, Skirmish, Story, and Multiplayer. Changes to an Army that is currently participating in an active Campaign do not affect that Campaign's snapshot of the Army; only future Battles see the updated version.

### Campaign Editor
Campaign Editor allows Players to create, edit, and share custom Campaigns. A Campaign defines the Sector Map, Activities, Objectives, Roster requirements, and narrative flow that Players experience during Skirmish or Multiplayer.

The Campaign Editor Screen is divided into three main areas:
- Campaign Browser
  - Lists the Player's custom Campaigns alongside installed commsquady Campaigns, with search and filter options.
  - Each entry shows the Campaign name, author, Player count, estimated duration, and publication status (Draft, Published, or Archived).
- Sector Map Canvas
  - A visual editor for placing and connecting Plots on the Sector Map. Players drag-and-drop Plot nodes, draw travel connections between them, and assign Activities (Armybuilding, Battle, Narrative Event, Trade, etc.) to each Plot.
  - Travel connections can have requirements (e.g. "complete this Activity first") and visual style (solid, dashed, or hidden).
- Properties Panel
  - When a Plot, connection, or the Campaign itself is selected, its configurable properties appear here: Activity type, Roster restrictions, Objectives, narrative text, AI opponent settings, difficulty scaling, and other Campaign-level parameters.
  - Campaign Modifiers are configured here as Component modifications (e.g., overriding BattlefieldDimensionsComponent, setting TurnLimitComponent) and System parameter overrides — not freeform rule text (see rule 850.1 in Campaign Rules).

Custom Campaigns can be exported and shared with other Players. The editor validates that the Campaign graph is completable (no unreachable Plots, at least one valid path from Opening to Conclusion) before allowing publication.

### Squad Editor
Squad Editor allows Players to create, edit, and share custom Squads for use in custom Campaigns and Freeplay Multiplayer. Official Campaigns and Ranked Multiplayer use only the official Squad data and do not permit custom Squads.

The Squad Editor Screen presents:
- Squad Browser
  - Lists the Player's custom Squads alongside official Squads (read-only) for reference. Filters for Faction Keywords, Squad Keywords, and value range are available.
  - Players can duplicate an official Squad as a starting point for a custom variant.
- Component Editor
  - The primary editing surface, structured around the Squad archetype's Components: name, Faction Keywords (marker Components), Squad Keywords (marker Components), Composition (Units and their equipped Items), Statline Component (Endurance, Durability, Morale, Speed, Reflex), Abilities, and Value.
  - Unit slots can be added or removed. Each Unit slot defines its Statline Component values, default Items, and available equipment options with associated Equipment Costs.
  - Attack Profile Components for weapons are edited inline, specifying category, range brackets, damage, damage type, and modifiers.
- Validation Panel
  - Provides live feedback on the Squad's internal consistency: missing Characteristics, orphaned Keywords, cost imbalances, and Abilities that reference undefined rules.
  - A balance estimate gives a rough comparison of the custom Squad's value against official Squads with similar roles.

Custom Squads can be exported and shared. The editor enforces structural validity (every Unit has a Statline Component, every weapon has at least one Attack Profile Component) but does not enforce balance; that responsibility falls to the Campaign's Roster system.

### Settings
Settings provides access to all game configuration options. Changes apply globally and persist across sessions.

The Settings Screen is organized into tabbed categories:
- Gameplay
  - Turn timer defaults, auto-save frequency, tooltip verbosity, confirmation prompts for destructive actions (Concede, Exit), and difficulty presets for AI opponents.
- Controls
  - Rebindable Hotkeys (including the Menu Hotkey, default F10), mouse sensitivity, scroll speed, camera inversion, and drag thresholds for multi-select and squad movement.
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

A Campaign is an Entity of the Campaign archetype (see rule 800.1 in Campaign Rules) — the top-level game structure that organizes all gameplay for a group of Players. The Campaign System manages Campaign-level logic: Sector Map navigation, Activity resolution, and Modifier layering.

Every Campaign Entity has at least:

- Opening — determine the terms of the Campaign:
  - Number and composition of activities (for example: 3 Battles, or 2 Battles and 1 narrative event).
  - Objectives that Players should try to achieve.
- Activities — the things Players do during the Campaign:
  - In the most basic case, each Player builds an Army, then fights in a Battle against the other Player.
  - More complex Campaigns may add, remove, or modify activities (extra Battles, narrative events, strategic map moves, etc.).
- Conclusion — determine the victor of the Campaign based on its objectives and results.

Campaign Modifiers alter how Battles work by modifying Components on Battle Entities and overriding System parameters — without changing the core Battle Rules (see rule 850.1 in Campaign Rules). Examples include:

- Setting TurnLimitComponent to enforce a maximum turn count.
- Overriding BattlefieldDimensionsComponent or DeploymentZonesComponent to change the playing field.
- Adding or tightening Roster requirements for Battleforce validation.
- Modifying VictoryConditionsComponent to change Battle victory conditions.

For the first digital prototype, we assume a Generic Campaign that:

- Uses a default Roster with no special restrictions.
- Has a single Battle as its only activity.
- Uses straightforward "most victory points / wipeout" style victory conditions.

---

## 6. Rosters and Armies

Building an Army is how a Player prepares for a Battle.

- A Player selects and configures Squads (Entities of the Squad archetype) to fill out an Army (an Entity of the Army archetype) until the Player is satisfied and (optionally) meets Campaign or Roster requirements.
- Armies are organized by a Roster system:
  - A Roster is a Zone that organizes Battleforces. The Zone System validates Battleforces against Roster requirements; a Battleforce can be listed in any Roster whose requirements it meets (see rule 270.3 in Entity System Rules).
  - The default Roster has no restrictions.

At this overview level:

- An Army is "the set of Squad Entities a Player brings to a Battle".
- Each Army has a total Value (via its Squads' Value Components) that summarizes its overall strength for pairing and balancing Battles.
- Campaigns and formats can define additional Roster types with stricter requirements through Campaign Modifiers.

For the barebones implementation, we only need:

- A way to define and store a small number of Armies per Player.
- A simple validation step that checks "Army can be used in this Battle / Campaign".

---

## 7. Battles

Fighting a Battle involves Players participating in four ordered Stages, tracked by the Battle Entity's BattleStageComponent and advanced by the Battle System (see rule 100.2 in Battle Rules):

1. Planning
2. Deployment
3. Engagement
4. Consolidation

A Battle is generally:

- Fought between two opposing Battleforces of similar total Value.
- Played on a single Battlefield (an Entity with spatial Components such as BattlefieldDimensionsComponent, DeploymentZonesComponent, and TerrainIndexComponent; see section 300 in Movement and Positioning Rules).
- Fought until one Battleforce has been wiped out or another victory condition in the Battle Entity's VictoryConditionsComponent is met.

Campaign Modifiers can also modify how Players engage in Battle by overriding Components on the Battle Entity, such as:

- Setting TurnLimitComponent to enforce a different turn count.
- Modifying VictoryConditionsComponent to change victory conditions or scoring.
- Adding or tightening Roster requirements for Battleforce validation.

---

## 8. Battle Stages (High Level)

At a high level, each Stage of a Battle looks like this. The Battle System advances through these Stages in strict order, delegating to specialized Systems during each Stage:

- Planning Stage
  - Players select Squads from an Army to compose a Battleforce. The Zone System validates each Battleforce against Roster requirements.
  - Faction Relationships and other pre-Battle information are revealed.

- Deployment Stage
  - The Deployment System places Squads from each Battleforce onto the Battlefield within designated Deployment Zones according to the Battle or Campaign rules.
  - Squads not designated for initial Deployment have their Zone Component set to Reserves.

- Engagement Stage
  - Players command their Squads in a repeating cycle of Turns, each broken into Phases tracked by the Battle Entity's PhaseComponent: Rally, Issue Orders, Execute, Resolve Combat.
  - Simple War uses a true simultaneous turn system (see `Terminology – Fighting a Battle` for more detail).
  - During Execute and Resolve Combat, the Battle System delegates to the Movement System, Combat System, Morale System, Zone System, and Ability System to resolve Orders and their consequences.

- Consolidation Stage
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
    - Armybuilding here allows the Player to add a pre-built selection of Squads to their Commander's Army
    - Battle here has a single Roster that allows the Player to use every Squad from their Army as a Battleforce
    - The Battle will be against an identical Battleforce led by an identical Commander

  - The Player has one Commander
    - A generic Commander Entity with no special Abilities
    - Deployable to the Battlefield as its own Squad
    - Generic "slightly better than a regular Squad" Statline Component and equipped Items
    - The Commander begins on the Armybuilding Plot and must complete that Activity to move to the Battle Plot

- A basic Engagement Stage with a Turn system driven by the Battle System that can be expanded later.
- A flexible Campaign layer where the Campaign System applies Campaign Modifiers to Battle Entities without changing the core Battle Rules.

---


## 2. Tight Scope Digital Prototype

The initial digital prototype will focus on presenting the gameplay flow to the player for the aforementioned Warhammer 40K Comparison. The thing we care most about for this prototype is that it is responsive to typical digital controls where appropriate (examples: double-click to confirm a selection, right click for context menu if available, zooming and scrolling with the scroll wheel, panning with WASD or mouse3, drag-click an empty space to multi-select, or click-and-drag to move something, etc.)

- The Main Menu displays a "Quick Play" option (Other options for now can just be "Quit Game") 
- A "Menu" button in the top right of every screen should allow the player to Return to Main Menu, or Quit Game at any point. 
- Quick Play takes us to a Campaign Planning screen. This screen just has information about the Campaign.
  - For now, this can just say "A single Battle against a single opposing commander, with pre-built armies."
- On the bottom Right of the Campaign Planning Screen, the options for "Back" and "Embark" are available. 
- "Embark" takes us to the Campaign's Sector Map. The Sector Map should be a star chart with two options on it, represented by two circled plots on the map.
  - One of the plots is "Armybuilding" and the other is "Battle" -- they should be connected by a dotted-line arrow. 
    - If the player hovers or right-clicks the arrow for information, it should say "Requirements for travel: Build an army!"
  - There should be a small meeple to represent the player's Commander on the Armybuilding plot. 
  - We will not allow the player to move the Meeple to the Battle plot until it has completed the Armybuilding activity. 
    - Convey this visually by subtly highlighting the Armybuilding plot. 
    - Convey this through text in a note on one side of the Sector Map, saying "We need an army to approach the battle!"
  - The player can do the armybuilding activity by right-clicking its plot and selecting "Begin Activity" from a context menu, double-clicking the plot, hitting enter, or clicking "Begin Activity" in the bottom right. 
    - This takes us to an Armybuilding screen. List a single army "Militia" army and allow the player to highlight and select it with the appropriate controls, returning us to the Sector Map.
  - Once the Armybuilding activity is complete, have the Commander Meeple inherit the highlight
  - Add a small "army" meeple next to the Commander meeple.
  - Update the note to tell the player "Move your Commander to the battle!"
  - Allow the player to go to the Battle activity by moving their Commander's meeple there, double-clicking it, selecting it and hitting enter or "Move Here" in the bottom right, or right-clicking it and selecting "Move Here" from the context menu.
  - Once the commander meeple (with army meeple in tow) is at the Battle activity, 
    - Update the note to tell the player "Better them than us!"
    - the Player can begin the Battle with the same controls they did to begin the Armybuilding activity. 
    - Starting the Battle takes us to the Battle Planning screen
      - Allow the player to "Select Army" from their Commander's Battleforces (should be the same army we just built with that Commander)
        - we aren't going to demo army composition or reserves yet so this is all that's needed in the Planning stage
      - From the Planning Screen, "Deploy" button in the bottom right takes us to the Battlefield. 
        - The Battlefield should be 100 squads tall and 200 squads wide. One squad of distance corresponds to roughly one meter of in-world scale.
      - The battlefield can just be a generic grassland texture surrounded by grey.
        - Indicate that the top 20 squads are the opponent's Deployment zone by tinting them Red, with a dotted line across the board at the 20-squad mark
        - Indicate that the bottom 20 squads are the player's Deployment zone by tinting them blue, with a dotted line across the board at the 20-squad mark
        - The player should be able to zoom in on the battlefield 
        - there should be grid markers on the battlefield at appropriate zoom levels
          - When zoomed all the way in, the markers should be every 1 squad
          - as they zoom out the markers should be replaced by 3-squad and 6-squad grid markers, and vice versa
          - The player should not be able to zoom in further than a 6x6 grid of 1-squad markers, or further out than being able to see the entire battlefield and 6 squads of surrounding grey area
      - The Army that the player selected should be available to the side in the grey
        - 5 squads of "Riflemen", each consisting of 10 circles, arranged in a rectangle. 
          - For now, these circles simply maintain their position within the squad's rectangle. However, we want to make sure that the implementation we choose leaves room to extend movement, pathfinding, and formation functionality. 
        - allow the player to click and drag, multi-select-and-drag, and drop the squads onto the battlefield, but only wholly within their deployment zone
        - once they have done so, a button on the top middle that says "Engage Enemy" becomes available to click
          - The player can also hit enter, or right-click the battlefield for a context menu that should include "Engage Enemy"
        - The Deployment activity is complete, and now the engagement stage begins. The deployment zone indicators go away and the game displays the text, "Engagement Stage: Turn 1" which fades after 3 seconds.
        - The player should be able to plan the movement and pivoting of their squads with click and drag movement controls
          - display the plans using a translucent copy of the squad at the end of a dotted-line path
        - Once the player has given squad an order, they can issue by clicking "Execute Orders" in the bottom right
          - if a squad doesn't have an order, the player can still execute orders, but they should be prompted to review their remaining squads without orders
        - the rest of this is just going through turns of battle. There should be basic enemy behaviors, such as deploying their premade army on the line, moving it forward, and attacking the closest enemy to them when they are in effective range.
        - Once all enemy squads are destroyed, the game should move to the Consolidation stage, and statistics about the battle should appear
          - For now, simply list squads and units destroyed for each player, with the value of squads destroyed as the score.
          - We want to ensure that almost anything done during the battle can be used to score, so we should work out a detailed battle audit system we can use to check back on anything that may have happened. This will also help with player statistics and savefiles so it's important to begin working with it early.