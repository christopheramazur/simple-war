# Campaign Rules

**Status**: Draft
**Last Updated**: 2026-03-18
**Purpose**: Formalizes the rules governing Campaign Entities in Simple War, including Sector Map structure, Activity resolution, Objectives, Scoring, and how Campaign Modifiers alter Battle Components and System parameters.

---

## Overview

A Campaign is the overarching structure through which Players experience Simple War. Every game session takes place within a Campaign, from a single Quickplay Battle to a multi-session Story arc. Campaigns define *what happens*, *in what order*, and *under what conditions* — organizing Activities on a Sector Map, imposing constraints through Rosters and Campaign Modifiers, and determining victory through Objectives and Scoring.

This document defines the rules governing Campaign Entity structure, the Sector Map archetype, Activity resolution, Objectives, Scoring, and the mechanisms by which Campaign Modifiers alter Battle Components and System parameters without changing the core Battle Rules (see rules 100.1–150.1 in Battle Rules). The Campaign System is the System responsible for managing all Campaign-level logic (see rule 200.4 in Entity System Rules and Appendix A.3 therein).

---

## 800 Campaign

### 800.1 Campaign Definition

A Campaign is an Entity of the Campaign archetype — its Components include a CampaignStageComponent, a SectorMapRefComponent, and the `Campaign` marker Component (see rule 200.5 in Entity System Rules and Appendix A.5 therein). A Campaign is the top-level game structure that organizes all gameplay for a group of Players. Every gameplay session in Simple War takes place within exactly one Campaign.

A Campaign Entity has:

- **IdComponent**: A unique string identifier.
- **DisplayNameComponent**: A human-readable label.
- **Marker Components**: Including the `Campaign` marker Component and any descriptive marker Components (e.g., `Quickplay`, `Skirmish`, `Story`).
- **SectorMapRefComponent**: Reference to the Sector Map Entity that defines the Campaign's geography (see rule 810.1).
- **CampaignStageComponent**: The current Campaign Stage (see rule 800.2).
- **Activities**: The set of Activity definitions available on the Sector Map (see rule 820.1).
- **Objectives**: The conditions Players pursue during the Campaign (see rule 830.1).
- **Scoring Rules**: The configuration for tallying Campaign Score (see rule 840.1).
- **Campaign Modifiers**: Component modifications and System overrides that alter how Battles and other Activities function within this Campaign (see rule 850.1).
- **Conclusion Conditions**: The conditions under which the Campaign ends (see rule 800.5).
- **Player Count**: The number of Players the Campaign supports (minimum 1, maximum defined per Campaign).

### 800.2 Campaign Stages

A Campaign proceeds through three sequential Stages:

1. **Opening** — Players configure their starting positions, select Factions, choose Commanders, and establish initial Armies.
2. **Active Play** — Players navigate the Sector Map, engage in Activities, and pursue Objectives.
3. **Conclusion** — The Campaign ends, final Scores are tallied, and the Victor is determined.

The Campaign System tracks the current Campaign Stage via the CampaignStageComponent. The Opening must complete before Active Play begins. Active Play continues until a Conclusion Condition is met (see rule 800.5).

### 800.3 Opening

During the Opening, each Player performs the following configuration steps. The Campaign definition specifies which steps are available, which have fixed values, and which are Player-configurable:

1. **Select Faction**: Choose a Faction from the Campaign's allowed Factions. Some Campaigns fix the Faction; others allow free choice. The selected Faction determines which Units, Commanders, and narrative options are available.
2. **Select Allegiances**: Declare initial Faction Relationships toward other Factions present in the Campaign. Allegiances may be fixed by the Campaign or chosen by the Player.
3. **Select Commanders**: Choose one or more starting Commanders from the Campaign's available pool or from the Player's collection. Each Commander has an Army (see rule 260.1 in Entity System Rules). The Campaign defines the minimum and maximum number of starting Commanders.
4. **Establish Initial Armies**: Populate each Commander's Army. The Campaign may provide pre-built Armies, allow free armybuilding subject to Roster restrictions, or offer a selection of pre-built options.
5. **Place Commanders**: Position each Commander on the Sector Map at a designated starting Plot. The Campaign defines which Plots are valid starting locations.

The Opening completes when all Players have finished all configuration steps. The Campaign System validates all selections against the Campaign's rules before advancing the CampaignStageComponent to Active Play.

### 800.4 Active Play

During Active Play, Players take turns navigating the Sector Map with their Commanders and engaging in Activities. Active Play continues until a Conclusion Condition is met.

Active Play operates in **Campaign Rounds**. Each Campaign Round:

1. All Players simultaneously issue movement orders for their Commanders on the Sector Map (see rule 810.5).
2. Commander movement resolves.
3. Players engage in Activities at their Commanders' current Plots (see rule 820.1). Activity resolution order is defined by the Campaign; the default is simultaneous.
4. The Campaign System evaluates Conclusion Conditions (see rule 800.5).

Some Campaigns may not use Campaign Rounds and instead allow free-form navigation where Players move Commanders and engage in Activities at their own pace. The Campaign definition specifies the time model.

### 800.5 Conclusion Conditions

A Campaign enters the Conclusion Stage when any of the following conditions are met, as evaluated at the end of each Campaign Round (or after each Activity resolution in free-form Campaigns):

1. **Objectives Complete**: A Player achieves all required Objectives designated as Campaign-ending (see rule 830.3).
2. **Round Limit**: The Campaign Round count exceeds the Campaign's maximum, if defined.
3. **Elimination**: All of a Player's Commanders are permanently lost and the Player has no means to acquire new Commanders. A Player eliminated in this way receives their current Campaign Score.
4. **Concession**: A Player concedes the Campaign. The conceding Player's remaining resources are forfeited for scoring purposes.
5. **Mutual Agreement**: All Players agree to end the Campaign early.
6. **Campaign-Specific Condition**: A condition defined by the Campaign (e.g., "Control 5 of 7 key Plots", "Accumulate 1000 Campaign Score").

### 800.6 Conclusion

During the Conclusion:

1. **Final Scoring**: Each Player's Campaign Score is finalized (see rule 840.1). Any end-of-Campaign scoring bonuses are applied.
2. **Determine Victor**: The Player with the highest Campaign Score is the Victor. If Scores are tied, the Campaign's tiebreaker rule applies. The default tiebreaker is: most Objectives completed, then most Battles won, then most surviving Units by total Value. If still tied, the Campaign is a draw.
3. **Record Results**: Campaign results, including per-Player Scores, Objectives completed, Battles fought, and narrative outcomes, are recorded for use in linked Campaigns (Story mode) or Player Rankings (Ranked Multiplayer).

---

## 810 Sector Map

### 810.1 Sector Map Definition

A Sector Map is an Entity of the Sector Map archetype — its Components include Plot references, Connection references, and the `Sector Map` marker Component (see Appendix A.5 in Entity System Rules). A Sector Map is the navigable graph that defines a Campaign's geography. A Sector Map has:

- **Plots**: Entities of the Plot archetype — nodes on the graph representing locations where Activities occur (see rule 810.2).
- **Connections**: Entities of the Connection archetype — edges linking Plots, defining valid movement paths (see rule 810.3).

Every Campaign has exactly one Sector Map, referenced by the Campaign's SectorMapRefComponent.

### 810.2 Plots

A Plot is an Entity of the Plot archetype — its Components include a DisplayNameComponent, an ActivityRefComponent, and the `Plot` marker Component (see Appendix A.5 in Entity System Rules). A Plot is a location on the Sector Map. Each Plot Entity has:

| Component / Property | Type | Required | Description |
|---|---|---|---|
| IdComponent | string | Yes | Unique identifier |
| DisplayNameComponent | string | Yes | Human-readable label (e.g., "Outpost Sigma", "Supply Depot") |
| ActivityRefComponent | Activity reference or null | Yes | The Activity available at this Plot, or null if the Plot is a waypoint |
| Marker Components | set of strings | No | Descriptive marker Components (e.g., `Fortified`, `Contested`, `Hidden`) |
| OwnerComponent | Player reference or null | No | The Player who controls this Plot, if applicable |
| StartingPlotComponent | boolean | No | Whether Commanders may be placed here during the Opening |
| CapacityComponent | integer or null | No | Maximum number of Commanders that may occupy this Plot simultaneously; null means unlimited |

A Plot with an ActivityRefComponent allows Commanders at that Plot to engage in the referenced Activity. A Plot with no Activity (a waypoint) serves only as a transit point on the Sector Map.

### 810.3 Connections

A Connection is an Entity of the Connection archetype — its Components include a SourcePlotRefComponent, a DestPlotRefComponent, a TravelCostComponent, a BidirectionalComponent, and the `Connection` marker Component (see Appendix A.5 in Entity System Rules). A Connection links two Plots on the Sector Map and defines the rules for travelling between them. Each Connection Entity has:

| Component / Property | Type | Required | Description |
|---|---|---|---|
| IdComponent | string | Yes | Unique identifier |
| SourcePlotRefComponent | Plot reference | Yes | Origin Plot |
| DestPlotRefComponent | Plot reference | Yes | Target Plot |
| BidirectionalComponent | boolean | Yes | Whether travel is allowed in both directions; default true |
| TravelCostComponent | integer ≥ 0 | Yes | Number of Campaign Rounds required to traverse; default 1 |
| RequirementsComponent | list of Conditions | No | Conditions that must be met before a Commander may use this Connection (e.g., "Complete the Armybuilding Activity") |
| Marker Components | set of strings | No | Descriptive marker Components (e.g., `Hidden`, `Hazardous`) |

The Campaign System checks the RequirementsComponent before permitting traversal. If the BidirectionalComponent is false, the Connection may only be traversed from Source to Destination.

### 810.4 Sector Map Validity

A valid Sector Map must satisfy all of the following:

1. The Sector Map has at least one Plot.
2. Every Plot designated as a Starting Plot is reachable from at least one other Starting Plot (unless the Campaign has exactly one Player).
3. There are no orphaned Plots: every Plot is either a Starting Plot or reachable from a Starting Plot via one or more Connections.
4. At least one path exists from a Starting Plot to a Plot whose Activity is designated as Campaign-ending (if the Campaign has Conclusion Conditions based on Activity completion).

Campaign Editor validation (see Main Concepts — Campaign Editor) enforces these constraints before a Campaign is published.

### 810.5 Commander Movement

During Active Play, each Commander occupies exactly one Plot at a time. Commanders move between Plots via Connections.

Movement rules:

1. A Commander may move along one Connection per Campaign Round, unless a rule grants additional movement.
2. If the Connection's Travel Cost is greater than 1, the Commander is **in transit** for that many Campaign Rounds. A Commander in transit occupies neither the Source nor Destination Plot and may not engage in Activities until arrival.
3. A Commander may choose not to move, remaining at the current Plot.
4. If multiple Commanders belonging to the same Player are at the same Plot, the Player may combine or split Armies between them during the Activity resolution step of the Campaign Round, subject to Campaign rules.
5. If Commanders belonging to opposing Players occupy the same Plot and the Plot has a Battle Activity, the Campaign may require those Commanders to resolve a Battle (see rule 822.2).

### 810.6 Plot Control

Some Campaigns track Plot control. When a Commander completes an Activity at a Plot, that Plot's Owner may change to the Commander's Player, as defined by the Activity's rules. Plot control may be a component of Objectives and Scoring.

---

## 820 Activities

### 820.1 Activity Definition

An Activity is an Entity of the Activity archetype — its Components include an ActivityTypeComponent, a CompletionConditionsComponent, and the `Activity` marker Component (see Appendix A.5 in Entity System Rules). An Activity is a structured interaction that a Commander performs at a Plot on the Sector Map. Each Activity Entity has:

| Property | Type | Required | Description |
|---|---|---|---|
| ID | string | Yes | Unique identifier |
| Display Name | string | Yes | Human-readable label |
| Activity Type | enum | Yes | The category of Activity: Armybuilding, Battle, Narrative Event, Trade, or Custom |
| Prerequisites | list of Conditions | No | Conditions the Commander must meet to begin the Activity |
| Completion Conditions | list of Conditions | Yes | Conditions that determine when the Activity is finished |
| Rewards | list of Effects | No | Effects applied to the Commander or Player upon completion |
| Repeatable | boolean | Yes | Whether the Activity can be performed more than once; default false |
| Campaign Modifiers | list of Modifiers | No | Modifiers applied to the Activity's resolution (see rule 850.1) |

A Commander may engage in one Activity per Campaign Round, unless a rule grants additional Activity slots. A Commander may only engage in an Activity at the Commander's current Plot.

### 820.2 Activity Resolution

When a Commander engages in an Activity:

1. The Campaign System validates the Activity's RequirementsComponent. If any Prerequisite is not met, the Commander may not begin the Activity.
2. The Activity resolves according to its ActivityTypeComponent rules (see rules 821–825).
3. The Campaign System evaluates the CompletionConditionsComponent. If all Conditions are met, the Activity completes.
4. Upon completion, Rewards are applied as Component modifications to the relevant Entities.
5. The Campaign System evaluates whether the Activity's completion triggers any Objective progress (see rule 830.1).

Some Activities (particularly Battles) may span multiple Campaign Rounds. A Commander engaged in a multi-round Activity may not move on the Sector Map or engage in other Activities until the current Activity completes or is abandoned, as permitted by the Activity's rules.

---

## 821 Armybuilding Activity

### 821.1 Armybuilding Activity Overview

An Armybuilding Activity allows a Commander to add Units to, remove Units from, or reconfigure the Commander's Army. Armybuilding is the primary mechanism by which Players prepare forces for Battle.

### 821.2 Armybuilding Resolution

When a Commander engages in an Armybuilding Activity:

1. The Campaign System presents the available Unit pool to the Player. The available pool is determined by the intersection of:
   a. The Campaign's allowed Units (which may be filtered by Faction, Campaign stage, or narrative progression).
   b. The Activity's specific offerings (which may be a subset or curated selection).
   c. Any resource constraints (if the Campaign uses a resource economy).
2. The Player adds, removes, or reconfigures Units in the Commander's Army.
3. All changes are validated against the Campaign's Roster requirements (see rule 850.3).
4. The Activity completes when the Player confirms the Army composition.

### 821.3 Armybuilding Constraints

Campaigns may impose the following constraints on Armybuilding:

- **Unit Pool Restrictions**: Limit which Units are available (by Faction Keyword marker Components, Unit Keyword marker Components, or explicit lists).
- **Value Caps**: Limit the total Army Value or the Value added in a single Armybuilding Activity.
- **Availability Limits**: Restrict how many copies of a specific Unit a Player may include across all Armies.
- **Resource Costs**: Require expenditure of Campaign Resources (see rule 825.1) to acquire Units.
- **Progression Gates**: Unlock Units based on Campaign progress (e.g., "Available after completing 2 Battles").

The default Armybuilding Activity has no constraints beyond the Campaign's Roster requirements.

---

## 822 Battle Activity

### 822.1 Battle Activity Overview

A Battle Activity initiates a Battle (see rule 100.1 in Battle Rules) between Commanders at the same Plot. The Battle Activity is the bridge between the Campaign layer and the Battle Rules: it defines the conditions under which a Battle occurs, applies Campaign Modifiers to the Battle, and processes the Battle's results for Campaign purposes.

### 822.2 Battle Initiation

A Battle Activity may be initiated in one of the following ways:

1. **Voluntary**: A Commander at a Plot with a Battle Activity chooses to begin the Activity. The Campaign defines who the opponent is (another Player's Commander at the same Plot, an AI Commander, or a pre-defined scenario opponent).
2. **Mandatory**: The Campaign requires a Battle when opposing Commanders occupy the same Plot. The Campaign System automatically initiates the Battle Activity.
3. **Scripted**: The Campaign's narrative dictates that a Battle occurs at a specific Plot under specific conditions. The Battle's parameters (opponent, Roster, Battlefield, Objectives) are pre-defined.

### 822.3 Battle Setup

When a Battle Activity is initiated:

1. The Campaign System determines the participating Commanders. Each Commander must have at least one Unit in the Commander's Army.
2. Campaign Modifiers are applied to the Battle as Component modifications and System parameter overrides (see rule 850.1). These may alter the Roster requirements, Battlefield Components (BattlefieldDimensionsComponent, TerrainIndexComponent), DeploymentZonesComponent, Turn limit, victory conditions, or scoring.
3. The Battle proceeds through all four Battle Stages as defined in Battle Rules (Planning, Deployment, Engagement, Consolidation).
4. Upon Battle completion, the Campaign System processes Battle results for Campaign purposes (see rule 822.4).

### 822.4 Battle Results Processing

After a Battle's Consolidation Stage completes (see rule 140.1 in Battle Rules):

1. **Score Integration**: The Campaign System adds the Battle's per-Player Scores to each Player's Campaign Score (see rule 840.2).
2. **Casualty Persistence**: The Campaign's casualty rules determine what happens to Units whose Zone Component is Casualty Report (see rule 822.5).
3. **Objective Evaluation**: The Campaign System checks whether the Battle's outcome contributes to any Campaign Objectives (see rule 830.1).
4. **Plot Effects**: If the Battle was at a contested Plot, the Campaign System may update the Plot's OwnerComponent to the Victor's Player (see rule 810.6).
5. **Narrative Triggers**: The Battle's outcome may trigger narrative events or cause the Campaign System to add new Plot and Connection Entities to the Sector Map.

### 822.5 Campaign Casualty Rules

Campaigns define how Battle casualties are handled at the Campaign level. The following options are available (Campaigns choose one or combine them):

1. **Full Recovery**: All destroyed Units are restored to full strength after the Battle. No permanent losses. Suitable for Quickplay and competitive formats.
2. **Partial Recovery**: A percentage of destroyed Units (defined by the Campaign) are restored. The remaining Units are permanently lost from the Commander's Army.
3. **Reinforcement Pool**: Destroyed Units enter a Reinforcement Pool. The Player may spend Campaign Resources or Armybuilding Activities to recover Units from the Pool.
4. **Permanent Loss**: All destroyed Units are permanently removed from the Commander's Army. Suitable for high-stakes Story Campaigns.
5. **Mixed**: The Campaign specifies different recovery rules based on context (e.g., a victorious Commander recovers 75% of casualties; a defeated Commander recovers 50%).

The default Campaign Casualty Rule is Full Recovery.

---

## 823 Narrative Event Activity

### 823.1 Narrative Event Overview

A Narrative Event is an Activity that presents the Player with a story-driven scenario requiring decisions. Narrative Events are the primary mechanism for delivering Campaign narrative, branching storylines, and non-combat consequences.

### 823.2 Narrative Event Structure

A Narrative Event has:

| Property | Type | Required | Description |
|---|---|---|---|
| ID | string | Yes | Unique identifier |
| Display Name | string | Yes | Human-readable title |
| Narrative Text | string | Yes | Story text presented to the Player |
| Choices | list of Choice | Yes | The options available to the Player (minimum 1) |
| Prerequisites | list of Conditions | No | Conditions that must be met for this Event to appear |
| Marker Components | set of strings | No | Descriptive marker Components (e.g., `Faction-specific`, `Moral Dilemma`) |

### 823.3 Choices

Each Choice within a Narrative Event has:

| Property | Type | Required | Description |
|---|---|---|---|
| ID | string | Yes | Unique identifier |
| Display Text | string | Yes | The text shown to the Player for this option |
| Conditions | list of Conditions | No | Additional conditions the Commander must meet to select this Choice (e.g., "Commander has the `Diplomat` marker Component") |
| Effects | list of Effects | Yes | The mechanical outcomes of selecting this Choice |

### 823.4 Narrative Event Effects

Effects applied by Narrative Event Choices may include:

- **Add/Remove Units**: Add or remove specific Units from the Commander's Army.
- **Add/Remove Items**: Grant or revoke Items to specific Models.
- **Modify Campaign Score**: Award or deduct Campaign Score.
- **Modify Faction Relationships**: Alter the Player's relationships with specific Factions.
- **Unlock/Lock Plots**: Reveal hidden Plots or Connections on the Sector Map, or make existing ones inaccessible.
- **Trigger Activity**: Force the Commander into a specific Activity (e.g., an ambush Battle).
- **Grant/Revoke Marker Components**: Add or remove marker Components from the Commander, Army, or specific Units.
- **Modify Campaign Resources**: Adjust the Player's Campaign Resource totals (see rule 825.1).
- **Narrative State Change**: Set a narrative flag that later Narrative Events, Activities, or Conclusion Conditions reference.

### 823.5 Narrative Event Resolution

When a Commander engages in a Narrative Event:

1. The Campaign System presents the Narrative Text.
2. The Campaign System filters Choices by their Conditions; only valid Choices are shown.
3. The Player selects one Choice.
4. All Effects of the selected Choice are applied as Component modifications to the relevant Entities.
5. The Activity completes.

If only one Choice is valid, the Player must select that Choice. If no Choices are valid (all Conditions fail), the Narrative Event cannot be engaged and the Commander may not begin the Activity.

---

## 824 Travel Activity

### 824.1 Travel Activity Overview

A Travel Activity represents events that occur during movement between Plots, such as encounters, hazards, or opportunities discovered in transit. Travel Activities are optional; a Campaign may use them to enrich the journey between Plots or may omit them entirely.

### 824.2 Travel Events

When a Commander moves along a Connection, the Campaign may trigger a Travel Event before the Commander arrives at the Destination Plot. A Travel Event functions as a Narrative Event (see rule 823.1) with the following additional properties:

- **Connection Reference**: The Connection that triggered the Event.
- **Interruptible**: Whether the Event blocks the Commander's arrival at the Destination until resolved; default true.

If the Travel Event is Interruptible and unresolved, the Commander remains in transit until the Event resolves.

---

## 825 Trade Activity

### 825.1 Campaign Resources

Some Campaigns use a resource economy to gate access to Units, Items, and narrative options. Campaign Resources are tracked per Player. Each Campaign Resource has:

| Property | Type | Required | Description |
|---|---|---|---|
| ID | string | Yes | Unique identifier |
| Display Name | string | Yes | Human-readable label (e.g., "Credits", "Requisition Points", "Influence") |
| Starting Amount | integer ≥ 0 | Yes | Amount each Player begins with |

Campaign Resources are not Entities; they are bookkeeping values managed by the Campaign system.

### 825.2 Trade Activity Overview

A Trade Activity allows a Commander to exchange Campaign Resources for Units, Items, or other benefits. Trade Activities provide an economic layer beyond the base Armybuilding system.

### 825.3 Trade Resolution

When a Commander engages in a Trade Activity:

1. The Campaign System presents the available trades, each specifying a cost (in Campaign Resources) and a reward (Units, Items, marker Components, or other Effects).
2. The Player selects one or more trades, subject to available Campaign Resources.
3. Campaign Resources are deducted and rewards are applied.
4. The Activity completes.

Trade Activities are optional. Campaigns that do not use Campaign Resources do not include Trade Activities.

---

## 830 Objectives

### 830.1 Objective Definition

An Objective is a condition that Players pursue during a Campaign. Objectives provide direction and determine which actions earn Campaign Score. Each Objective has:

| Property | Type | Required | Description |
|---|---|---|---|
| ID | string | Yes | Unique identifier |
| Display Name | string | Yes | Human-readable description (e.g., "Control the Citadel", "Win 3 Battles") |
| Type | enum | Yes | Primary, Secondary, Hidden, or Bonus (see rule 830.2) |
| Conditions | list of Conditions | Yes | What must be true for the Objective to be completed |
| Score Award | integer ≥ 0 | Yes | Campaign Score awarded upon completion |
| Campaign-Ending | boolean | Yes | Whether completing this Objective triggers a Conclusion Condition; default false |
| Assignee | scope enum | Yes | Who can complete this Objective: Per-Player, Shared, or First-Come |
| Repeatable | boolean | No | Whether the Objective can be completed more than once; default false |
| Reveal Condition | list of Conditions | No | Conditions under which the Objective becomes visible to the Player (for Hidden Objectives) |

### 830.2 Objective Types

| Type | Description |
|---|---|
| **Primary** | Core Objectives that drive the Campaign. A Campaign must have at least one Primary Objective. Primary Objectives are visible to all Players from the Opening. |
| **Secondary** | Optional Objectives that provide additional Campaign Score. Visible from the Opening. |
| **Hidden** | Objectives not visible until their Reveal Condition is met. Once revealed, they function as Primary or Secondary Objectives. |
| **Bonus** | One-time Objectives tied to specific Activities or narrative moments. Awarded immediately upon completion. |

### 830.3 Objective Evaluation

The Campaign System evaluates Objectives at the following times:

1. After each Activity resolves.
2. After each Battle's Consolidation Stage.
3. At the end of each Campaign Round.
4. At specific narrative trigger points defined by the Campaign.

When an Objective's Conditions are met:

1. The Objective is marked as completed for the qualifying Player(s).
2. The Score Award is added to the qualifying Player(s)' Campaign Score.
3. If the Objective is Campaign-Ending, the Campaign enters the Conclusion Stage.

For **First-Come** Objectives, only the first Player to meet the Conditions earns the Score Award. For **Per-Player** Objectives, each Player may complete the Objective independently. For **Shared** Objectives, all Players share the completion (cooperative Campaigns).

---

## 840 Scoring

### 840.1 Campaign Score

Each Player maintains a Campaign Score, an integer starting at 0. Campaign Score increases through Objective completion, Battle performance, and Campaign-specific bonuses. Campaign Score determines the Victor at the Conclusion.

### 840.2 Score Sources

Campaign Score is accumulated from the following sources:

| Source | Description | When Applied |
|---|---|---|
| Objective Completion | Score Award from completed Objectives (see rule 830.1) | Upon Objective completion |
| Battle Score | Score from Battle Consolidation (see rule 140.3 in Battle Rules) | After each Battle |
| Activity Bonuses | Campaign-defined bonuses for completing Activities (e.g., first Player to complete Armybuilding earns 10 points) | Upon Activity completion |
| Narrative Event Awards | Score granted by Narrative Event Choices (see rule 823.4) | Upon Narrative Event resolution |
| Plot Control | Score awarded for controlling Plots at specific Campaign stages (see rule 810.6) | At Campaign evaluation points |
| Conclusion Bonuses | End-of-Campaign bonuses defined by the Campaign (e.g., "10 points per surviving Commander") | During Conclusion |

### 840.3 Battle Score Integration

When a Battle resolves within a Campaign, the Battle's per-Player Scores (see rule 140.3 in Battle Rules) are integrated into Campaign Score. The Campaign defines the integration method:

1. **Direct**: Battle Score is added directly to Campaign Score (1:1 ratio). This is the default.
2. **Scaled**: Battle Score is multiplied by a Campaign-defined factor before being added.
3. **Capped**: Battle Score contribution per Battle is capped at a Campaign-defined maximum.
4. **Objective-Only**: Battle Score is not added to Campaign Score; only Battle Objectives contribute.

### 840.4 Tiebreaking

When two or more Players have equal Campaign Score at the Conclusion, the following tiebreakers apply in order:

1. Most Primary Objectives completed.
2. Most total Objectives completed.
3. Most Battles won.
4. Highest total surviving Army Value across all Commanders.
5. Draw.

Campaigns may define custom tiebreaker sequences that replace the defaults.

---

## 850 Campaign Modifiers

### 850.1 Campaign Modifier Definition

A Campaign Modifier is a data structure defined by the Campaign that alters how an Activity (particularly a Battle) functions without changing the core rules in Battle Rules or Entity System Rules. Campaign Modifiers work by overriding System parameters or injecting, removing, or modifying Components on Entities involved in the Activity. Campaign Modifiers are the primary mechanism by which Campaigns create variety.

Each Campaign Modifier has:

| Property | Type | Required | Description |
|---|---|---|---|
| ID | string | Yes | Unique identifier |
| Display Name | string | Yes | Human-readable label |
| Target | enum | Yes | What the Modifier affects: Battle, Armybuilding, Narrative Event, Sector Map, or Global |
| Effect | Component modification or System override | Yes | The mechanical alteration, expressed as one or more Component additions, removals, or value changes, or as an override to a System's parameters |
| Scope | enum | Yes | Per-Battle, Per-Activity, Per-Round, or Persistent |
| Conditions | list of Conditions | No | When the Modifier is active |

Campaign Modifiers are applied by the Campaign System before the target Activity begins resolution. The Campaign System layers active Modifiers according to precedence rules (see rule 850.4) and passes the modified Component state and System parameters to the Activity's resolution Systems.

### 850.2 Battle Modifiers

Campaign Modifiers that target Battles alter Component values or System parameters on Battle-level Entities. The following subsections describe the categories of modification.

#### 850.2a Roster Restrictions

The Campaign may inject additional requirements into the Roster validation performed by the Zone System (see rule 270.3 in Entity System Rules). These are expressed as constraints on Battleforce Components:

- Minimum or maximum TotalValueComponent.
- Allowed or excluded Faction Keyword marker Components.
- Allowed or excluded Unit Keyword marker Components.
- Required Unit inclusions (e.g., "Battleforce must include at least one Unit with the `Heavy` marker Component").
- Commander requirements (e.g., "Commander must have the `Strategist` marker Component").

#### 850.2b Turn Limit

The Campaign may set a TurnLimitComponent on the Battle Entity, imposing a maximum Turn count. When the Turn count is reached, the Battle System advances the Battle to Consolidation regardless of other Battle End Conditions (see rule 150.1 in Battle Rules).

#### 850.2c Deployment Zone Modifications

The Campaign may override the DeploymentZonesComponent on the Battlefield Entity (see rule 120.2 in Battle Rules):

- Non-standard Deployment Zone sizes or positions.
- Asymmetric Deployment Zones.
- Multiple Deployment Zones per Player.
- Restricted areas within Deployment Zones.

#### 850.2d Battlefield Modifications

The Campaign may modify Components on the Battlefield Entity:

- Override BattlefieldDimensionsComponent for non-standard Battlefield dimensions.
- Pre-populate TerrainIndexComponent with terrain features.
- Attach environmental effect Components (e.g., VisibilityModifierComponent, HazardousZoneComponent) that other Systems read during resolution.

#### 850.2e Victory Condition Modifications

The Campaign may alter or replace the default Battle victory conditions (see rules 140.2 and 150.1 in Battle Rules) by modifying the Battle Entity's victory condition Components:

- Alternative victory conditions (e.g., "Destroy the target building", "Hold the center for 3 consecutive Turns").
- Additional scoring criteria for the Battle.
- Modified Annihilation conditions (e.g., "Battle ends when one Player loses 50% of Units by Value").

#### 850.2f Additional Battle Rules

The Campaign may attach transient Components or System parameter overrides that apply during specific Battle Stages or Phases:

- Pre-Battle Component modifications (e.g., "Reduce each Unit's EnduranceRemainingComponent by 2 due to forced march").
- Per-Turn System hooks (e.g., "At the start of each Rally Phase, the Combat System deals 1 damage to each Unit with the `Exposed` marker Component").
- Post-Battle Component modifications (e.g., "Add the `Decorated` marker Component to the Victor's Commander Entity").

### 850.3 Armybuilding Modifiers

Campaign Modifiers that target Armybuilding may alter the available Unit pool, Value caps, or Armybuilding process (see rule 821.3).

### 850.4 Modifier Precedence

When multiple Campaign Modifiers affect the same aspect of an Activity:

1. Modifiers with narrower Scope take precedence over broader Scope (Per-Battle > Per-Activity > Per-Round > Persistent).
2. Within the same Scope, Modifiers are applied in the order defined by the Campaign.
3. Restrictive Modifiers (limitations) take precedence over permissive Modifiers (expansions). A restriction can only be overridden by a Modifier that explicitly names the restriction it overrides.

---

## 860 Campaign Templates

### 860.1 Generic Campaign

The Generic Campaign is the minimal Campaign used as a starting point for all other Campaigns. It defines:

- **Sector Map**: Variable; defined per instance.
- **Opening**: Select Faction, select Commanders, establish Armies.
- **Activities**: Armybuilding, Battle.
- **Roster**: Default Roster (no restrictions; see rule 270.3 in Entity System Rules).
- **Casualty Rules**: Full Recovery.
- **Conclusion**: Based on Campaign-specific Objectives and Scoring.

All other Campaign templates extend the Generic Campaign by overriding or adding properties.

### 860.2 Quickplay Campaign

The Quickplay Campaign is designed for immediate play with minimal configuration:

- **Player Count**: 1 (versus AI).
- **Sector Map**: Two Plots (Armybuilding, Battle) connected by a single Connection.
  - The Connection requires the Armybuilding Activity to be completed before traversal.
- **Opening**: Fixed Faction, single Commander, pre-built Army selection.
- **Activities**:
  - **Armybuilding**: Select one pre-built Army from a curated list.
  - **Battle**: Single Battle against an identical AI-controlled Battleforce led by an identical AI Commander.
- **Roster**: Default Roster; the Player's full Army is used as the Battleforce.
- **Casualty Rules**: Not applicable (single Battle).
- **Objectives**: Primary — Win the Battle. Score Award: 100 Campaign Score.
- **Scoring**: Direct Battle Score integration.
- **Conclusion**: After the single Battle completes.

### 860.3 Skirmish Campaign

The Skirmish Campaign supports configurable single-player or multiplayer scenarios:

- **Player Count**: Configurable (1–N, where N is defined per Skirmish Campaign).
- **Sector Map**: Defined by the selected Skirmish Campaign; varies in complexity.
- **Opening**: Configurable Faction, Commanders, starting Armies, and difficulty.
- **Activities**: Armybuilding, Battle, Narrative Events (Campaign-dependent), Trade (Campaign-dependent).
- **Roster**: Campaign-defined; may range from default to highly restrictive.
- **Casualty Rules**: Campaign-defined; default is Partial Recovery (50%).
- **Objectives**: Campaign-defined Primary, Secondary, and Hidden Objectives.
- **Scoring**: Campaign-defined integration method.
- **Conclusion**: Campaign-defined.

### 860.4 Story Campaign

Story Campaigns deliver the game's narrative through a sequence of linked Campaigns:

- **Player Count**: 1 (narrative focus).
- **Sector Map**: Authored; may evolve as the story progresses (Plots and Connections added/removed).
- **Opening**: Narrative-driven; Player choices carry forward from previous Story Campaigns.
- **Activities**: Full range — Armybuilding, Battle, Narrative Events, Travel Events, Trade.
- **Roster**: Varies per Battle; narrative context imposes restrictions.
- **Casualty Rules**: Mixed or Permanent Loss; consequences carry weight.
- **Objectives**: Heavily narrative-driven; Hidden Objectives are common.
- **Scoring**: Objective-Only; narrative outcomes are more important than raw Battle performance.
- **Conclusion**: Narrative-driven; multiple endings are possible based on Player choices.
- **Persistence**: Commander state, Army composition, Faction Relationships, and narrative flags persist across linked Story Campaigns.

### 860.5 Multiplayer Campaign

Multiplayer Campaigns extend the Skirmish framework for multiple human Players:

- **Freeplay**: Any Campaign (including custom), any Units (including custom). No ranking impact.
- **Unranked**: Official Campaigns and Unit data only. No ranking impact.
- **Ranked**: Curated Competitive Campaign set, official Unit data only. Results affect Player Rankings.

Multiplayer Campaigns follow the same rules as Skirmish Campaigns with the following additions:

- All Players must confirm readiness before each Campaign Round advances.
- Phase timers (configurable per Campaign) prevent indefinite delays.
- Concession rules apply per Player; a conceding Player's Campaign Score is finalized at the time of concession.

---

## Glossary Additions

- **Active Play**: The second Campaign Stage, during which Players navigate the Sector Map and engage in Activities. (Rule 800.4)
- **Activity**: A structured interaction a Commander performs at a Plot; classified as Armybuilding, Battle, Narrative Event, Travel, Trade, or Custom. (Rule 820.1)
- **Armybuilding Activity**: An Activity allowing a Commander to add, remove, or reconfigure Units in the Commander's Army. (Rule 821.1)
- **Battle Activity**: An Activity that initiates a Battle between Commanders at the same Plot. (Rule 822.1)
- **Bonus Objective**: A one-time Objective tied to a specific Activity or narrative moment, awarded immediately upon completion. (Rule 830.2)
- **Campaign**: An Entity of the Campaign archetype (CampaignStageComponent, SectorMapRefComponent, `Campaign` marker Component); the top-level game structure organizing all gameplay. (Rule 800.1)
- **Campaign Modifier**: A Campaign-defined data structure that alters how an Activity functions through Component modifications and System parameter overrides, without changing core rules. (Rule 850.1)
- **Campaign Resource**: A bookkeeping value tracked per Player, used to gate access to Units, Items, and narrative options. (Rule 825.1)
- **Campaign Round**: One cycle of Commander movement and Activity resolution during Active Play. (Rule 800.4)
- **Campaign Score**: An integer tracked per Player, accumulated through Objectives, Battles, and Activities, determining the Campaign Victor. (Rule 840.1)
- **Choice**: An option within a Narrative Event, with Conditions and Effects. (Rule 823.3)
- **Conclusion**: The final Campaign Stage, during which Scores are finalized and the Victor is determined. (Rule 800.6)
- **Conclusion Condition**: A condition that, when met, causes the Campaign to enter the Conclusion Stage. (Rule 800.5)
- **Connection**: An Entity of the Connection archetype (SourcePlotRefComponent, DestPlotRefComponent, TravelCostComponent, BidirectionalComponent, `Connection` marker Component); an edge on the Sector Map linking two Plots. (Rule 810.3)
- **First-Come Objective**: An Objective where only the first Player to meet the Conditions earns the Score Award. (Rule 830.3)
- **Full Recovery**: A Campaign Casualty Rule where all destroyed Units are restored after a Battle. (Rule 822.5)
- **Generic Campaign**: The minimal Campaign template used as the foundation for all others. (Rule 860.1)
- **Hidden Objective**: An Objective not visible until its Reveal Condition is met. (Rule 830.2)
- **In Transit**: The state of a Commander moving along a Connection with Travel Cost greater than 1. (Rule 810.5)
- **Mandatory Battle**: A Battle automatically initiated when opposing Commanders occupy the same Plot. (Rule 822.2)
- **Narrative Event**: An Activity presenting story-driven scenarios with Player choices and mechanical consequences. (Rule 823.1)
- **Narrative State Change**: A narrative flag set by a Narrative Event Choice, referenced by later Events and Conditions. (Rule 823.4)
- **Objective**: A condition Players pursue during a Campaign, providing direction and Campaign Score. (Rule 830.1)
- **Opening**: The first Campaign Stage, during which Players configure starting positions, Factions, Commanders, and Armies. (Rule 800.3)
- **Partial Recovery**: A Campaign Casualty Rule where a percentage of destroyed Units are restored after a Battle. (Rule 822.5)
- **Per-Player Objective**: An Objective each Player may complete independently. (Rule 830.3)
- **Permanent Loss**: A Campaign Casualty Rule where all destroyed Units are permanently removed. (Rule 822.5)
- **Plot**: An Entity of the Plot archetype (DisplayNameComponent, ActivityRefComponent, `Plot` marker Component); a node on the Sector Map representing a location where Activities occur. (Rule 810.2)
- **Plot Control**: Ownership of a Plot, which may change based on Activity outcomes. (Rule 810.6)
- **Primary Objective**: A core Campaign Objective visible from the Opening. (Rule 830.2)
- **Quickplay Campaign**: A minimal Campaign designed for immediate play: two Plots, one Battle. (Rule 860.2)
- **Reinforcement Pool**: A Campaign Casualty Rule where destroyed Units enter a pool recoverable through Activities. (Rule 822.5)
- **Scripted Battle**: A Battle with pre-defined parameters dictated by the Campaign's narrative. (Rule 822.2)
- **Secondary Objective**: An optional Campaign Objective providing additional Campaign Score, visible from the Opening. (Rule 830.2)
- **Sector Map**: An Entity of the Sector Map archetype (Plot references, Connection references, `Sector Map` marker Component); the navigable graph defining a Campaign's geography. (Rule 810.1)
- **Shared Objective**: An Objective where all Players share the completion (cooperative Campaigns). (Rule 830.3)
- **Skirmish Campaign**: A configurable Campaign template supporting single or multiplayer play with variable complexity. (Rule 860.3)
- **Story Campaign**: A narrative-driven Campaign template with persistent consequences across linked Campaigns. (Rule 860.4)
- **Trade Activity**: An Activity allowing a Commander to exchange Campaign Resources for Units, Items, or benefits. (Rule 825.2)
- **Travel Activity**: An Activity representing events during movement between Plots. (Rule 824.1)
- **Travel Cost**: The number of Campaign Rounds required to traverse a Connection. (Rule 810.3)
- **Travel Event**: A Narrative Event triggered during Commander movement along a Connection. (Rule 824.2)
- **Voluntary Battle**: A Battle initiated by Player choice at a Plot with a Battle Activity. (Rule 822.2)

---

## Implementation Notes

### Component Definitions

The following lists the Components required for Campaign-level Entity support, following the same format as Entity System Rules. Components already cataloged in Entity System Rules Appendix A.2 are referenced, not repeated.

**Campaign Entity Components**:
- `IdComponent`: `{ id: string }` — globally unique
- `DisplayNameComponent`: `{ display_name: string }`
- `MarkerComponents`: `set<string>` — includes `Campaign` plus descriptive markers (e.g., `Quickplay`, `Skirmish`, `Story`)
- `CampaignStageComponent`: `{ stage: enum(Opening, ActivePlay, Conclusion, Complete) }`
- `CurrentRoundComponent`: `{ round: int }` — 1-indexed; meaningful only during Active Play
- `SectorMapRefComponent`: `{ sector_map_id: string }`
- `ObjectivesComponent`: `list<ObjectiveDefinition>` — with per-Player completion state
- `CampaignModifiersComponent`: `list<CampaignModifierDefinition>` — active Modifier definitions
- `ConclusionConditionsComponent`: `list<ConditionDefinition>`
- `ScoringRulesComponent`: `{ integration_method: enum, factor: float?, cap: int? }`

**Player State Components (within Campaign)**:
- `PlayerIdComponent`: `{ player_id: string }`
- `FactionRefComponent`: `{ faction: string }`
- `FactionRelationshipsComponent`: `map<faction_id, enum(Friendly, Allied, Enemy, Neutral)>`
- `CommanderRefsComponent`: `list<string>` — Commander Entity IDs
- `CampaignScoreComponent`: `{ score: int }` — default 0
- `CampaignResourcesComponent`: `map<resource_id, int>`
- `ObjectivesCompletedComponent`: `set<string>` — Objective IDs
- `NarrativeFlagsComponent`: `map<string, value>` — for Narrative State tracking

**Plot Entity Components** (extends core IdComponent, DisplayNameComponent, MarkerComponents):
- `ActivityRefComponent`: `{ activity_id: string? }` — null for waypoints
- `OwnerComponent`: `{ player_id: string? }`
- `StartingPlotComponent`: `{ is_starting: bool }`
- `CapacityComponent`: `{ max_commanders: int? }` — null = unlimited
- `CommandersPresentComponent`: `list<string>` — Commander Entity IDs currently at this Plot

**Connection Entity Components** (extends core IdComponent, MarkerComponents):
- `SourcePlotRefComponent`: `{ plot_id: string }`
- `DestPlotRefComponent`: `{ plot_id: string }`
- `BidirectionalComponent`: `{ bidirectional: bool }`
- `TravelCostComponent`: `{ cost: int }`
- `RequirementsComponent`: `list<ConditionDefinition>`

**Commander Campaign-Level Components** (extends Commander archetype from Entity System Rules):
- `CurrentPlotRefComponent`: `{ plot_id: string? }` — null if in transit
- `TransitComponent`: `{ connection_id: string?, rounds_remaining: int }` — 0 if not in transit
- `CurrentActivityRefComponent`: `{ activity_id: string? }`
- `ActivityStateComponent`: `{ state: serialized }` — Activity-specific state

**Activity Instance Components** (extends core IdComponent, DisplayNameComponent, MarkerComponents):
- `ActivityTypeComponent`: `{ type: enum(Armybuilding, Battle, Narrative, Travel, Trade, Custom) }`
- `ActivityStatusComponent`: `{ status: enum(Available, InProgress, Completed, Locked) }`
- `ParticipatingCommandersComponent`: `list<string>` — Commander Entity IDs
- `CompletionConditionsComponent`: `list<ConditionDefinition>`
- `RequirementsComponent`: `list<ConditionDefinition>`
- `ActiveModifiersComponent`: `list<CampaignModifierDefinition>` — Modifiers active for this instance

### System Responsibilities

The Campaign System reads and writes Campaign-level Components:

| System | Reads | Writes |
|---|---|---|
| **Campaign System** | CampaignStageComponent, CurrentRoundComponent, ObjectivesComponent, ConclusionConditionsComponent, ScoringRulesComponent, CampaignModifiersComponent | CampaignStageComponent, CurrentRoundComponent, CampaignScoreComponent, OwnerComponent, ActivityStatusComponent, NarrativeFlagsComponent |
| **Campaign System (Commander movement)** | CurrentPlotRefComponent, TransitComponent, RequirementsComponent (Connection), BidirectionalComponent, TravelCostComponent | CurrentPlotRefComponent, TransitComponent, CommandersPresentComponent |
| **Campaign System (Activity resolution)** | ActivityTypeComponent, RequirementsComponent, CompletionConditionsComponent, ActiveModifiersComponent | ActivityStatusComponent, Component modifications per Activity type |

### Digital Implementation Considerations

- All Components referenced above must support serialization and deserialization for save/load functionality.
- Sector Map rendering requires 2D graph layout. Plot Entities should have optional PositionHintComponent `{ x: float, y: float }` for visual placement; the Campaign System may auto-layout if position hints are not provided.
- Narrative Event text supports markdown formatting for rich presentation.
- Campaign Modifiers are applied as a stack: the Campaign System evaluates which Modifiers are active, layers them according to precedence rules (see rule 850.4), and applies the resulting Component modifications and System parameter overrides before passing control to the Activity's resolution Systems.
- AI Commanders in single-player Campaigns use the same Campaign System interfaces as human Players. The AI decision layer selects movement targets, Activity choices, and Narrative Event Choices based on Campaign-defined AI profiles.
- Multiplayer synchronization requires all Players to submit Campaign Round actions before resolution proceeds. A timeout mechanism (configurable per Campaign) auto-submits default actions for Players who exceed the time limit.
- Story Campaign persistence requires a separate save format that records the complete Component state across linked Campaigns, including all NarrativeFlagsComponent data, Commander Entity histories, and Army Entity snapshots.

### Relationship to Existing Rules

| Campaign Concept | Existing Rule Reference | Interaction |
|---|---|---|
| Commanders and Armies | Entity System Rules 260–270 | Campaign System provides Commander and Army Entities to Battle |
| Battleforces and Rosters | Entity System Rules 270.2–270.3 | Campaign Modifiers inject additional requirements into Zone System Roster validation |
| Battle Stages | Battle Rules 100–150 | Campaign Modifiers override Battle Entity Components and System parameters |
| Battle Scoring | Battle Rules 140.3 | Campaign System integrates Battle Score into CampaignScoreComponent |
| Battle Casualties | Battle Rules 140.4 | Campaign Casualty Rules process Units in Casualty Report Zone after Battle |
| Deployment Zones | Battle Rules 120.2 | Campaign Modifiers may override DeploymentZonesComponent on Battlefield Entity |
| Turn Limits | Battle Rules 150.1 | Campaign Modifiers may set TurnLimitComponent on Battle Entity |

---

## Dependencies

This document defines Campaign-level structures referenced by:

- **Battle Rules** (100-series): Campaigns initiate Battles, impose Modifiers, and process Battle results.
- **Entity System Rules** (200-series): Campaigns use Commanders, Armies, Battleforces, and Rosters.
- **Movement and Positioning** (300-series): Sector Map movement is distinct from Battlefield movement.
- **Abilities and Effects** (500-series, not yet drafted): Abilities may reference Campaign state (e.g., "once per Campaign").

This document depends on:

- **Entity System Rules** (200-series): Commander, Army, Battleforce, Roster, Unit archetypes; Component and System definitions; marker Component conventions.
- **Battle Rules** (100-series): Battle Stages, Scoring, Casualty Processing, and Battle End Conditions.
- **Movement and Positioning Rules** (300-series): Spatial Components (BattlefieldDimensionsComponent, DeploymentZonesComponent, TerrainIndexComponent) referenced by Campaign Modifiers.

---

## Version History

| Version | Date | Changes |
|---|---|---|
| 0.1 | 2026-03-17 | Initial draft: Campaign definition, Sector Map, Activities (Armybuilding, Battle, Narrative Event, Travel, Trade), Objectives, Scoring, Campaign Modifiers, Campaign Templates |
| 0.2 | 2026-03-18 | ECS update: replaced 'Entity with X tag' patterns with archetype + Component definitions for Campaign, Sector Map, Plot, Connection, Activity; replaced 'the engine' with the Campaign System; expressed Campaign Modifiers as Component modifications and System parameter overrides; restructured Implementation Notes with Component definitions and System responsibilities table |
