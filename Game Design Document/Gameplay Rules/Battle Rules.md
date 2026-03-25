# Battle Rules

**Status**: Draft
**Last Updated**: 2026-03-18
**Purpose**: Formalizes the structure and rules for fighting a Battle in Simple War using the ECS architecture — defining the Battle archetype's Components, the Systems that advance Stages and Phases, the Order system that drives simultaneous play, and the System pipelines that resolve combat.

---

## Overview

A Battle is an Entity of the **Battle archetype** — a structured conflict between two or more opposing Battleforces on a Battlefield. The **Battle System** advances the Battle through four sequential Stages: Planning, Deployment, Engagement, and Consolidation. During the Engagement Stage, the Battle System runs a true simultaneous turn system in which all Players issue hidden Orders to their Squads, then reveal and resolve those Orders at the same time. Other Systems — the Combat System, Morale System, Movement System, Deployment System, Zone System, and Ability System — perform their respective operations within the Phases orchestrated by the Battle System.

This document defines the Battle archetype's Components, the rules governing each Stage, the Turn and Phase structure within Engagement, and the Order system that drives simultaneous play.

---

## 100.1 Battle Archetype

A Battle is an Entity of the **Battle archetype** — a Campaign Activity in which two or more Commanders commit Battleforces to fight on a Battlefield. A Battle Entity has the `Battle` marker Component and the following characteristic Components:

| Component | Type | Description |
|---|---|---|
| BattleStageComponent | Data | Current Stage: Planning, Deployment, Engagement, Consolidation, Complete |
| TurnCounterComponent | Data | Current Turn number (integer, 1-indexed; meaningful only during Engagement) |
| PhaseComponent | Data | Current Phase: Rally, IssueOrders, Execute, ResolveCombat (meaningful only during Engagement) |
| BattlefieldRefComponent | Data | Reference to the Battlefield Entity for this Battle |
| BattleforceRefsComponent | Data | References to participating Battleforce Entities |
| VictoryConditionsComponent | Data | Conditions that end the Engagement Stage (see rule 150.1) |
| ScoringComponent | Data | Scoring rules and per-Player score accumulators |
| TurnLimitComponent | Data | Optional maximum Turn count; -1 if no limit applies |
| OrderQueueComponent | Data | Map of Squad ID → Order struct, hidden per Player until an event reveals them, generally by starting the Execute Phase |
| ReactionQueueComponent | Data | Map of Squad ID → Reaction struct, hidden per Player until an event reveals thhem, generally by starting the resolution Phase |
| AuditComponent | Data | Reference log of all activity during a Battle, with timestamps and metadata |

Each Battle must have one and only one Battlefield Entity referenced by its BattlefieldRefComponent at any given time, but that reference does not have to point to the same Battlefield Entity at all times. The Battle System advances the BattleStageComponent through exactly four Stages in fixed order: Planning, Deployment, Engagement, Consolidation. No Stage may be skipped, though some Battles may be using rules that force a Stage into a certain preset configuration, such as an Ambush scenario. A Battle ends when the Consolidation Stage completes and the Battle System sets BattleStageComponent to Complete.

### Dependencies
- **Requires**: Commander archetype (see rule 260.1 in Entity System Rules), Battleforce archetype (see rule 270.2 in Entity System Rules), Battlefield Entity (see rule 300.1 in Movement and Positioning Rules), Campaign Activity archetype (see rule 820.1 in Campaign Rules)

---

## 100.2 Battle Stages

A Battle proceeds through the following Stages in strict sequential order:

1. **Planning** — Players compose Battleforces, designate Reserves and Vanguard, and receive information about Faction Relationships for the involved Commanders.
2. **Deployment** — Players place Squads from their Battleforces onto the Battlefield within designated Deployment Zones.
3. **Engagement** — Players command their Squads through a repeating cycle of Turns until a Battle End Condition is met.
4. **Consolidation** — The Battle's outcome is determined, scoring is resolved, and casualties are processed.

The Battle System tracks the current Stage in the Battle Entity's BattleStageComponent and advances to the next Stage only when the current Stage's completion conditions are met. The Battle System may not return to a previous Stage.

### Examples

#### Example 1: Minimal Battle Flow
**Setup**: Two Commanders, each with a pre-built Battleforce.
**Flow**: Planning (select Battleforces) → Deployment (place Squads) → Engagement (issue Orders, execute orders, resolve combats) → Consolidation (score, process casualties).
**Result**: Battle completes after Consolidation.

---

## 110 Planning Stage

### 110.1 Planning Stage Overview

During the Planning Stage, each participating Commander prepares a Battleforce for the Battle. The Planning Stage has the following steps, resolved in order:

1. **Compose Battleforce** (rule 110.2)
2. **Designate Transports** (rule 110.3)
3. **Designate Reserves** (rule 110.4)
4. **Designate Vanguard** (rule 110.5)
5. **Reveal Faction Relationships** (rule 110.6)

The Planning Stage completes when all participating Players have finished all steps. The Zone System validates that each Battleforce meets the Battle's Roster requirements (see rule 270.3 in Entity System Rules) before the Battle System advances to the Deployment Stage.

### 110.2 Composing Battleforces

Each Commander selects Squads from that Commander's Army to form a Battleforce for the Battle. The Battleforce must satisfy the Battle's Roster requirements. All Squads in the Battleforce begin the Planning with their Zone Component set to Reserves.

### 110.3 Designating Transports

If a Squad has the `Transport` marker Component, the owning Player may assign other Squads to be Embarked within that Transport, subject to the Transport's capacity. The Zone System sets the Embarked Squads' Zone Components to Embarked (referencing the Transport Entity) rather than the general Reserves Zone.

### 110.4 Designating Reserves

All Squads in the Battleforce begin with their Zone Component set to Reserves by default. During the Planning Stage, the Player may designate specific Squads for different types of Reserves entry (e.g., deep strike, delayed arrival). The method and timing of Reserves entry are specified by the Squad's Ability Components or the Campaign's rules.

### 110.5 Designating Vanguard

Squads with the `Vanguard` marker Component (or Squads granted `Vanguard` by a rule) may be designated as Vanguard during the Planning Stage. Vanguard Squads deploy before other Squads during the Deployment Stage (see rule 120.3a).

### 110.6 Revealing Faction Relationships

At the end of the Planning Stage, each Player's Faction Relationships are revealed to all other Players. Faction Relationships are not bilateral; a Player may declare a faction as Enemy while that faction declares the Player as Friendly. Each Player's Faction Relationships are immutable during the Battle unless a rule explicitly states otherwise.

### Edge Cases
- If a Commander has no Army or no Squads available, that Commander cannot participate in the Battle.
- If a Battleforce does not satisfy Roster requirements, the Zone System rejects the Battleforce and the Player must recompose before the Planning Stage can complete.

---

## 120 Deployment Stage

### 120.1 Deployment Stage Overview

During the Deployment Stage, Players place Squads from their Battleforces onto the Battlefield. The Deployment Stage has the following steps, resolved in order:

1. **Establish Deployment Zones** (rule 120.2)
2. **Deploy Vanguard** (rule 120.3a)
3. **Deploy Remaining Squads** (rule 120.3b)
4. **Resolve Pre-Engagement Moves** (rule 120.4)

The Deployment Stage completes when all Players have finished deploying Squads and Pre-Engagement Moves are resolved.

### 120.2 Deployment Zones

Each Battle defines Deployment Zones on the Battlefield via the Battlefield Entity's DeploymentZonesComponent (see Movement and Positioning Rules). A Deployment Zone is a rectangular area assigned to a specific Player or group of Players. The Deployment System may only place Squads within the owning Player's Deployment Zone during Deployment, unless a rule explicitly states otherwise.

The default Deployment Zone configuration for a two-Player Battle on a standard 200×100 Battlefield:

- **Player A**: the 200×20 area along one long edge (y = 0 to y = 20)
- **Player B**: the 200×20 area along the opposite long edge (y = 80 to y = 100)

Campaign or scenario rules may define different Deployment Zone layouts.

### 120.3 Deploying Squads

#### 120.3a Deploy Vanguard

All Players deploy Vanguard Squads simultaneously. The Deployment System places each Vanguard Squad wholly within the owning Player's Deployment Zone, writing PositionComponents and transitioning Zone Components from Reserves to Battlefield. Once all Vanguard Squads are deployed, proceed to step 120.3b.

#### 120.3b Deploy Remaining Squads

All Players deploy remaining Squads simultaneously. The Deployment System places each Squad wholly within the owning Player's Deployment Zone. A Squad's PositionComponent defines its center point (x, y) and its FacingComponent defines its facing direction (angle in degrees, 0–359). All Units in a Squad maintain cohesion within the Squad's FootprintComponent (see Movement and Positioning Rules).

Squads designated to remain in Reserves do not deploy during this step; those Squads enter the Battlefield later according to their specific Reserves rules.

### 120.4 Pre-Engagement Moves

After all Squads are deployed, Squads with Ability Components granting Pre-Engagement Movement may execute those moves. The Deployment System resolves Pre-Engagement Moves simultaneously across all Players. The movement distance and restrictions are specified by the granting Ability Component.

### Edge Cases
- A Squad that is too large to fit wholly within a Deployment Zone cannot be deployed until the Player repositions the Squad or scenario rules adjust the Deployment Zone.
- If a Player has no Squads to deploy (all are in Reserves or Embarked), the Deployment Stage still completes for that Player.

---

## 130 Engagement Stage

### 130.1 Engagement Stage Overview

The Engagement Stage is the core of a Battle. During this Stage, Players command their Squads through a repeating cycle of Turns. Each Turn uses the **true simultaneous turn** system: all Players issue hidden Orders to their Squads, those Orders are revealed together, and the results are resolved simultaneously.

The Engagement Stage continues until a Battle End Condition is met (see rule 150.1).

### 130.2 Turns

A Turn is one complete cycle of the Phase sequence within the Engagement Stage. Turns are numbered sequentially starting from Turn 1. The Battle System tracks the current Turn number in the Battle Entity's TurnCounterComponent. At the beginning of each Turn, the Battle System announces the Turn number to all Players.

### 130.3 Turn Structure

Each Turn proceeds through the following Phases in strict sequential order:

1. **Rally Phase** (rule 131.1)
2. **Issue Orders Phase** (rule 132.1)
3. **Execute Phase** (rule 133.1)
4. **Resolve Combat Phase** (rule 134.1)

No Phase may be skipped. A Phase completes before the next Phase begins. After the Resolve Combat Phase completes, the Turn ends and the next Turn begins (returning to the Rally Phase), unless a Battle End Condition is met.

---

## 131 Rally Phase

### 131.1 Rally Phase

During the Rally Phase, the following steps resolve in order for all Squads on the Battlefield:

1. **Morale Recovery**: The Morale System moves each Squad's Morale State Component one stage toward the Squad's Morale Baseline. If a Squad's Morale State Component is currently Surging, the Morale System resets it to Neutral instead.
2. **Endurance Recovery**: Each Squad that did not perform an Endurance-taxing action during the previous Turn recovers 1 to its Endurance Remaining Component (or the Squad's Endurance recovery rate, if defined by an Ability Component).
3. **Status Cleanup**: Remove all expired temporary marker Components and effects from all Squads. The Battle System processes removals simultaneously across all Squads.
4. **Reserves Check**: Squads in Reserves that have met their entry conditions are flagged as eligible for deployment this Turn (see rule 132.2c).

The Rally Phase is resolved automatically by the Battle System, which delegates to the Morale System (step 1) and the Zone System (step 4). Players do not make decisions during this Phase.

On Turn 1, steps 1–3 are skipped (there is no previous Turn to recover from). Step 4 still applies.

### Examples

#### Example 1: Morale Recovery
**Setup**: Squad A's Morale State Component is Poor, Morale Baseline is Neutral.
**Rally**: The Morale System moves the Morale State Component one stage toward Neutral → Squad A's Morale State Component becomes Neutral.

#### Example 2: Surging Reset
**Setup**: Squad B's Morale State Component is Surging after using a Surge Action last Turn.
**Rally**: The Morale System resets the Morale State Component to Neutral.

---

## 132 Issue Orders Phase

### 132.1 Issue Orders Phase Overview

During the Issue Orders Phase, all Players simultaneously and secretly assign one Order to each of their eligible Squads. Orders are hidden from other Players until the Execute Phase.

A Squad is eligible to receive an Order if the Squad's Zone Component is set to Battlefield and its Destruction State Component is not destroyed. A Squad's current Component state (Morale State Component, Endurance Remaining Component, Zone Component) may restrict which Order types are available, but the Squad always receives exactly one Order.

If a Player does not assign an Order to a Squad before the Player confirms readiness (or the Phase timer expires in digital play), that Squad receives the default Order: Hold (see rule 132.2a).

The Issue Orders Phase completes when all Players have confirmed their Orders or the Phase timer expires.

### 132.2 Order Types

The following Orders are available during the Issue Orders Phase. Each Order specifies what the Squad will attempt during the Execute Phase.

#### 132.2a Hold

The Squad holds its current position and facing. The Squad does not move. The Combat System may resolve attacks against designated targets within range and line of sight using the Squad's equipped ranged Attack Profile Components. Hold is the default Order if no Order is assigned. Hold does not tax Endurance.

#### 132.2b Advance

The Squad moves up to a distance equal to the Squad's Speed value toward a designated target point (x, y). The Squad may make attacks against designated targets within range and line of sight after movement resolves. Advance does not tax Endurance.

#### 132.2c Deploy from Reserves

Available only to Squads in Reserves that have been flagged as eligible during the Rally Phase (rule 131.1, step 4). The Squad enters the Battlefield at a position specified by the Squad's Reserves entry rules. The Squad may not make attacks or move further during the Turn the Squad deploys.

#### 132.2d Run

The Squad moves up to a distance equal to twice the Squad's Speed value toward a designated target point (x, y). The Squad may not make attacks during a Turn in which the Squad Runs. Running taxes Endurance by 1.

#### 132.2e Charge

The Squad moves up to a distance equal to 1.5 times the Squad's Speed value (rounded down to the nearest whole number) toward a designated enemy Squad. If the charging Squad's final position is within 1 distance squad of the target Squad, the charging Squad and the target Squad are both placed in Melee. Charging taxes Endurance by 1. A Squad with Broken Morale may not Charge.

#### 132.2f Dig In

The Squad does not move. The Battle System attaches the `Dug In` marker Component to the Squad (a Status Tag with expiry: until the Squad moves or a rule removes it). While the `Dug In` marker Component is present, the Combat System adds +2 to the Squad's Evasion Rating (terrain and cover rules may modify this bonus). The Squad may make attacks against designated targets within range and line of sight. Dig In does not tax Endurance.

#### 132.2g Fall Back

The Squad moves up to a distance equal to the Squad's Speed value directly away from the nearest enemy Squad. The Squad may not make attacks during a Turn in which the Squad Falls Back. Fall Back does not tax Endurance. A Squad with Broken Morale that receives the Fall Back Order moves up to twice the Squad's Speed value instead.

#### 132.2h Surge Action

Available only to Squads whose Morale State Component is Surging. The Ability System activates the special action defined by the Squad's Surge Ability Component. After the Surge Action resolves, the Morale System resets the Squad's Morale State Component to Neutral (processed during the next Rally Phase). A Squad may perform only one Surge Action per Battle unless a rule explicitly grants additional uses.

### 132.3 Order Parameters

Each Order includes the following parameters, as applicable:

| Parameter     | Type               | Required For         | Description                                     |
|---------------|--------------------|----------------------|-------------------------------------------------|
| Target Point  | (x, y) coordinate  | Advance, Run         | Destination position on the Battlefield         |
| Target Squad   | Squad reference      | Charge               | The enemy Squad the charging Squad moves toward   |
| Attack Targets| Squad reference(s)   | Hold, Advance, Dig In| Enemy Squads to attack during resolution         |
| Surge Ability | Ability reference   | Surge Action         | The Surge Ability to activate                   |

If an Order requires a Target Point and the designated point is unreachable (distance exceeds the Order's allowed movement), the Squad moves as far as possible along the direct path toward the target point.

### 132.4 Order Restrictions

- A Squad receives exactly one Order per Turn.
- A Squad whose Morale State Component is Broken may not receive the Charge or Surge Action Orders.
- A Squad whose Endurance Remaining Component is zero may not receive Orders that tax Endurance (Run, Charge).
- A Squad in Melee may only receive Hold, Charge (targeting a Squad already in the same Melee), or Fall Back Orders, unless a rule explicitly permits otherwise.

### Edge Cases
- If a Player's only remaining Squads are in states that prevent all Orders except Hold, those Squads receive the Hold Order by default.
- If an Order's target Squad is destroyed before execution (by simultaneous resolution), the Squad defaults to Hold for movement and the Battle System selects the nearest valid attack target within range, if any.

---

## 133 Execute Phase

### 133.1 Execute Phase Overview

During the Execute Phase, all Orders are revealed simultaneously and resolved together. The true simultaneous turn system means that no Player's Orders take priority over another Player's Orders. All Squads act within the same time slice.

The Execute Phase proceeds through the following resolution steps in order:

1. **Reveal Orders** (rule 133.2)
2. **Declare Reactions** (rule 133.3)
3. **Resolve Movement** (rule 133.4)
4. **Resolve Attacks** (rule 133.5)

### 133.2 Reveal Orders

All Players' Orders are revealed simultaneously. The Battle System reads the Battle Entity's OrderQueueComponent and displays each Squad's assigned Order and its parameters (target point, target Squad, attack targets) to all Players. Once Orders are revealed, Orders may not be changed.

### 133.3 Declare Reactions

After Orders are revealed and before movement resolves, each eligible Squad may declare one Reaction. All Players declare Reactions simultaneously and secretly; Reaction declarations are revealed to all Players at the same time, before movement resolves. A Squad may declare at most one Reaction per Turn. Reactions are optional.

#### 133.3a Reposition

**Trigger**: An enemy Squad's revealed Order would move that enemy Squad to within a distance of twice the reacting Squad's Speed value from the reacting Squad.
**Effect**: The reacting Squad makes an immediate move of up to half the Squad's Speed value (rounded down) to a new position. Reposition movement resolves before standard Order movement (rule 133.4).
**Cost**: Taxes Endurance by 1.
**Requirement**: The reacting Squad's Reflex value must be greater than 0.

#### 133.3b Evade

**Trigger**: The reacting Squad is designated as an attack target by one or more enemy Squads' revealed Orders.
**Effect**: The reacting Squad gains a temporary Evasion bonus equal to the Squad's Reflex value, applied to all incoming attacks this Turn.
**Cost**: None.
**Requirement**: The reacting Squad must not be in Melee. The reacting Squad's Reflex value must be greater than 0.

#### 133.3c Return Fire

**Trigger**: The reacting Squad is designated as an attack target by one or more enemy Squads' revealed Orders.
**Effect**: The reacting Squad makes an immediate ranged attack against one of the attacking enemy Squads, resolved simultaneously with all other attacks during rule 133.5. The Combat System applies the reacting Squad's ranged Attack Profile Components with a −1 Modifier to hit probability (representing hasty fire).
**Cost**: None.
**Requirement**: The reacting Squad must have a ranged Attack Profile Component equipped. The target must be within the Attack Profile Component's maximum range.

### 133.4 Resolve Movement

All movement from Orders and Reactions resolves simultaneously. The Movement System uses the following procedure:

1. **Snapshot** the current PositionComponent of all Squads.
2. The Movement System calculates each Squad's intended destination based on the Squad's Order and the Squad's allowed movement distance (derived from the Statline Component's Speed value).
3. The Movement System applies Reposition movement (rule 133.3a) to establish adjusted PositionComponents for reacting Squads.
4. The Movement System moves all remaining Squads toward their intended destinations simultaneously.
5. If two or more Squads from opposing Players would occupy overlapping positions:
   a. If one or both Squads issued a Charge Order targeting the other, both Squads are placed in Melee at the point of contact.
   b. Otherwise, the Movement System stops each Squad at the closest valid position before the overlap, maintaining a minimum separation of 1 distance squad.
6. The Movement System writes updated PositionComponents for all Squads on the Battlefield.

Movement does not provoke attacks by default. If a rule grants a Squad the ability to make attacks against Squads that move through a specified area (e.g., Overwatch), those attacks resolve during step 4 before final positions are set.

### 133.5 Resolve Attacks

All attacks from Orders and Reactions resolve simultaneously. The Combat System processes each attack through its Attack and Defense Pipelines (see Combat Resolution in Terminology):

1. For each Squad with an attack Order (Hold with targets, Advance with targets, Dig In with targets, Return Fire), identify the attacking Units and target Units.
2. **Attack Pipeline**: The Combat System distributes attacks from each attacking Unit to the closest Unit in the target Squad.
3. **Attack Pipeline**: The Combat System calculates hit probability for each attack: Baseline Competence (derived from the attacker's Statline Component's Endurance; see rule 210.7a in Entity System Rules) + Attack Profile Component Modifiers − target Evasion Rating (derived from the target's Statline Component's Reflex and Speed; see rule 210.7b in Entity System Rules). Hit probability has a floor of 5% and a ceiling of 95%.
4. **Attack Pipeline**: For each successful hit, the Combat System produces a Damage Instance containing the Attack Profile Component's Damage Value, Damage Type, and source metadata.
5. All Damage Instances are produced simultaneously; no attack result is applied until the Attack Pipeline has completed for all attacks.
6. **Defense Pipeline**: The Combat System applies all Damage Instances to target Units simultaneously, mitigated by each target's Armour Component values and Armour Resistances (see Combat Resolution — Being Attacked in Terminology).
7. The Combat System marks destroyed Units by setting their Destruction State Component. If all Units in a Squad are destroyed, the Zone System transitions the Squad's Zone Component to Casualty Report.

### Edge Cases
- If a Squad's attack target is destroyed during simultaneous resolution, the attacking Squad's attacks still resolve against the target as the target existed at the start of the Execute Phase. All attacks are pre-committed against the snapshot state.
- If two Squads destroy each other simultaneously, both Squads are moved to the Casualty Report.

---

## 134 Resolve Combat Phase

### 134.1 Resolve Combat Phase

During the Resolve Combat Phase, the Battle System processes the aftermath of the Execute Phase by delegating to the Combat System, Morale System, and Zone System. The following steps resolve in order:

1. **Melee Resolution**: Squads in Melee that have not yet attacked this Turn exchange attacks simultaneously using melee Attack Profile Components. The Combat System applies the same Attack and Defense Pipeline process as rule 133.5, limited to melee Attack Profile Components and restricted to Units within 1 distance squad of an opposing Unit.
2. **Morale Tests**: Each Squad that suffered one or more casualties this Turn makes a Morale Test. The Morale System compares the number of casualties taken to the Squad's Morale Characteristic (from the Statline Component). If casualties exceed the Morale Characteristic, the Morale System worsens the Squad's Morale State Component by one stage. If casualties are fewer than or equal to the Morale Characteristic, the Morale System improves the Morale State Component by one stage (maximum Good; Surging is only reached through Surge triggers defined in the Squad's Ability Components).
3. **Destruction Processing**: For each Squad that was destroyed this Turn, confirm the Squad's Zone Component is set to Casualty Report and the Battle System records the Turn number and cause of destruction in the Battle Entity's CasualtyReportComponent.
4. **Battle End Check**: Evaluate all Battle End Conditions (rule 150.1). If any condition is met, the Engagement Stage ends and the Battle proceeds to the Consolidation Stage. Otherwise, the current Turn ends and the next Turn begins.

### Examples

#### Example 1: Morale After Light Casualties
**Setup**: Squad C has Morale Characteristic 3 (Statline Component) and Morale State Component Neutral. The Combat System destroys 2 Units this Turn.
**Morale Test**: The Morale System compares casualties (2) ≤ Morale Characteristic (3). Morale State Component improves one stage → Squad C's Morale State Component becomes Good.

#### Example 2: Morale After Heavy Casualties
**Setup**: Squad D has Morale Characteristic 2 (Statline Component) and Morale State Component Neutral. The Combat System destroys 3 Units this Turn.
**Morale Test**: The Morale System compares casualties (3) > Morale Characteristic (2). Morale State Component worsens one stage → Squad D's Morale State Component becomes Poor.

---

## 140 Consolidation Stage

### 140.1 Consolidation Stage Overview

The Consolidation Stage resolves the Battle's outcome and processes lasting effects. The following steps resolve in order:

1. **Determine Victor** (rule 140.2)
2. **Process Scoring** (rule 140.3)
3. **Process Casualties** (rule 140.4)
4. **Clean Up Battlefield** (rule 140.5)

The Consolidation Stage completes when all steps have resolved. After Consolidation, the Battle System sets the Battle Entity's BattleStageComponent to Complete and control returns to the Campaign System.

### 140.2 Determining the Victor

The Victor is determined by the Battle Entity's VictoryConditionsComponent. The default victory condition: the last Player with at least one non-destroyed Squad (Destruction State Component is false) whose Zone Component is Battlefield wins. If multiple Players meet this condition simultaneously (e.g., multiple Players have surviving Squads when a Turn limit is reached), the Victor is determined by scoring (rule 140.3). If scoring is tied, the Battle is a draw.

Campaign or scenario rules may define additional or alternative victory conditions (e.g., objective control, Turn limit, point thresholds).

### 140.3 Scoring

The Battle System tallies scores for each Player based on the Battle Entity's ScoringComponent. Default scoring awards:

| Event                              | Points                              |
|------------------------------------|-------------------------------------|
| Enemy Squad destroyed               | Equal to the destroyed Squad's Value Component |
| Objective controlled at Battle end | As defined by the objective         |
| Victor bonus                       | As defined by the scenario          |

If the Battle has no explicit scoring rules, the Victor is determined solely by rule 140.2.

### 140.4 Processing Casualties

For each Squad whose Zone Component is set to Casualty Report:

1. Record the Squad's Component state at the time of destruction (Turn number, cause, number of remaining Units if any) in the Battle Entity's CasualtyReportComponent.
2. Apply Campaign-level casualty rules (e.g., permanent losses, recovery chances, reinforcement pools; see rule 822.5 in Campaign Rules).
3. If no Campaign-level casualty rules apply, the Squad remains in the Casualty Report Zone for the Campaign System to process later.

For each Squad whose Zone Component is Confirmed KIA, the Zone System removes all references to the Squad from other Entities' Components and Zones. Confirmed KIA Squads may not be returned to play except by rules that explicitly override this restriction.

### 140.5 Cleaning Up the Battlefield

1. Remove all temporary marker Components (Status Tags) and effects from all remaining Entities.
2. The Zone System transitions all Squads' Zone Components from Battlefield back to the owning Commander's Army.
3. The Zone System clears all Embarked Zone Component references.
4. Clear the Battlefield Entity's spatial Components (PositionComponents, TemporaryTagsComponents, etc.).
5. If any Entity was Removed from Play during the Battle, the Zone System removes all references to that Entity from all Entities' Components and Zones.

---

## 150 Battle End Conditions

### 150.1 Battle End Conditions

The Engagement Stage ends and the Battle proceeds to Consolidation when any of the following conditions are met at the end of any Resolve Combat Phase (rule 134.1, step 4):

1. **Annihilation**: All Squads belonging to all but one Player are destroyed.
2. **Turn Limit**: The current Turn number exceeds the Battle's maximum Turn count, as defined by the Campaign or scenario. If no maximum is defined, this condition does not apply.
3. **Objective Complete**: A Player achieves an objective that the scenario designates as an immediate win condition.
4. **Mutual Destruction**: All Squads from all Players are destroyed simultaneously. The Battle is a draw unless scenario rules specify otherwise.
5. **Concession**: A Player concedes the Battle. The conceding Player's remaining Squads are treated as destroyed for scoring purposes. The remaining Player or Players are declared Victor(s).

---

## Simultaneous Resolution — Design Rationale

The true simultaneous turn system operates on a **snapshot-calculate-apply** unit, implemented across multiple Systems coordinated by the Battle System:

1. **Snapshot**: At the start of the Execute Phase, the Battle System captures the complete Component state — all Squad PositionComponents, Statline Components, Morale State Components, Zone Components, and marker Components.
2. **Calculate**: Using the snapshot as input, the Movement System and Combat System calculate all Order outcomes independently. No Order reads the results of another Order; every System calculation references the snapshot.
3. **Apply**: The Movement System writes all PositionComponent updates at once; the Combat System writes all DamageTakenComponent and DestructionStateComponent updates at once.
4. **Post-Process**: The Resolve Combat Phase delegates to the Combat System (Melee resolution), the Morale System (Morale Tests), and the Zone System (Zone transitions for destroyed Squads).

This guarantees that no Player gains an advantage from resolution order. Every Player's Orders are evaluated against an identical Component state. The system is fully deterministic given the same inputs and random seed.

---

## Glossary Additions

- **Advance**: An Order type. The Movement System moves the Squad up to Speed distance toward a target point; the Combat System may resolve attacks. (Rule 132.2b)
- **Battle**: An Entity of the Battle archetype — a Campaign Activity in which Commanders commit Battleforces to fight on a Battlefield. The Battle System advances it through four Stages. (Rule 100.1)
- **Battle archetype**: The characteristic Component combination for a Battle Entity: BattleStageComponent, TurnCounterComponent, PhaseComponent, BattlefieldRefComponent, BattleforceRefsComponent, VictoryConditionsComponent, ScoringComponent, TurnLimitComponent, OrderQueueComponent, ReactionQueueComponent, CasualtyReportComponent. (Rule 100.1)
- **Battle End Condition**: A condition that, when met, causes the Battle System to end the Engagement Stage and advance to Consolidation. (Rule 150.1)
- **Battle System**: The System that orchestrates Battle flow — advancing Stages, running the Turn/Phase loop, coordinating other Systems, and managing the snapshot-calculate-apply cycle. (Rule 100.1, 130.2)
- **BattleStageComponent**: A data Component on the Battle Entity tracking the current Stage: Planning, Deployment, Engagement, Consolidation, Complete. (Rule 100.1)
- **Charge**: An Order type. The Movement System moves the Squad toward an enemy Squad at 1.5× Speed; if contact is made, both enter Melee. Taxes Endurance. (Rule 132.2e)
- **Concession**: A Player voluntarily ends the Battle, forfeiting the outcome. (Rule 150.1)
- **Deploy from Reserves**: An Order type allowing eligible Reserves Squads to enter the Battlefield. The Deployment System handles placement. (Rule 132.2c)
- **Deployment Zone**: A designated area on the Battlefield, defined by the Battlefield Entity's DeploymentZonesComponent, where a Player may place Squads during the Deployment Stage. (Rule 120.2)
- **Dig In**: An Order type. The Squad holds position and the Battle System attaches the `Dug In` marker Component for an Evasion bonus. (Rule 132.2f)
- **Dug In**: A temporary marker Component (Status Tag) granting an Evasion Rating bonus via the Combat System. Removed when the Squad moves. (Rule 132.2f)
- **Evade**: A Reaction. The Combat System grants a temporary Evasion bonus equal to Reflex for the Turn. (Rule 133.3b)
- **Execute Phase**: The third Phase of a Turn. All Orders are revealed and resolved simultaneously by the Movement System and Combat System. (Rule 133.1)
- **Fall Back**: An Order type. The Movement System moves the Squad away from the nearest enemy Squad. (Rule 132.2g)
- **Hold**: An Order type and the default Order. The Squad maintains position; the Combat System may resolve attacks. (Rule 132.2a)
- **Issue Orders Phase**: The second Phase of a Turn. Players secretly assign Orders, stored in the Battle Entity's OrderQueueComponent. (Rule 132.1)
- **Melee**: A state in which two or more opposing Squads are within 1 distance squad and the Combat System resolves melee Attack Profile Components. (Rule 132.2e, 134.1)
- **Order**: A hidden instruction assigned to a Squad during the Issue Orders Phase, stored in the OrderQueueComponent, specifying the Squad's action for the Turn. (Rule 132.1)
- **OrderQueueComponent**: A data Component on the Battle Entity mapping Squad IDs to Order structs, hidden per Player until the Execute Phase. (Rule 100.1, 132.1)
- **Phase**: A sub-part of a Turn. The Battle System advances Phases in fixed sequence: Rally, Issue Orders, Execute, Resolve Combat. (Rule 130.3)
- **PhaseComponent**: A data Component on the Battle Entity tracking the current Phase within the Engagement Stage. (Rule 100.1)
- **Rally Phase**: The first Phase of a Turn. The Morale System recovers Morale; Endurance recovers; the Battle System removes expired temporary marker Components. (Rule 131.1)
- **Reaction**: An optional out-of-sequence response declared after Orders are revealed but before the Movement System resolves movement. (Rule 133.3)
- **ReactionQueueComponent**: A data Component on the Battle Entity mapping Squad IDs to Reaction structs, hidden per Player until resolution. (Rule 100.1)
- **Reposition**: A Reaction. The Movement System makes a short move before standard movement resolves. (Rule 133.3a)
- **Resolve Combat Phase**: The fourth Phase of a Turn. The Combat System resolves Melee, the Morale System tests Morale, and the Battle System checks Battle End Conditions. (Rule 134.1)
- **Return Fire**: A Reaction. The Combat System resolves a hasty ranged attack against an attacker at −1 hit probability. (Rule 133.3c)
- **Run**: An Order type. The Movement System moves the Squad at 2× Speed; no attacks. Taxes Endurance. (Rule 132.2d)
- **Snapshot-Calculate-Apply**: The resolution unit used by the simultaneous turn system, coordinated by the Battle System across the Movement and Combat Systems. (Rule 133.1, Simultaneous Resolution)
- **Stage**: A major division of a Battle tracked in the BattleStageComponent: Planning, Deployment, Engagement, Consolidation. (Rule 100.2)
- **Surge Action**: An Order type available only to Squads with Surging Morale (Morale State Component). The Ability System activates the Squad's Surge Ability Component. (Rule 132.2h)
- **Turn**: One complete cycle of all four Phases within the Engagement Stage, tracked in the TurnCounterComponent. (Rule 130.2)
- **TurnCounterComponent**: A data Component on the Battle Entity holding the current Turn number (integer, 1-indexed). (Rule 100.1, 130.2)
- **Vanguard**: Squads with the `Vanguard` marker Component that deploy before other Squads during the Deployment Stage. (Rule 110.5, 120.3a)

---

## Implementation Notes

### Battle-Specific Component Definitions

The following Components are defined by Battle Rules and attached to the Battle Entity. These extend the Component catalog in Entity System Rules (Appendix A.2).

| Component | Type | Description |
|---|---|---|
| `BattleStageComponent` | `{ stage: enum(Planning, Deployment, Engagement, Consolidation, Complete) }` | Current Stage of the Battle |
| `TurnCounterComponent` | `{ turn: int }` | Current Turn number (1-indexed; meaningful only during Engagement) |
| `PhaseComponent` | `{ phase: enum(Rally, IssueOrders, Execute, ResolveCombat) }` | Current Phase within the Engagement Stage |
| `BattlefieldRefComponent` | `{ battlefield_id: string }` | Reference to the Battlefield Entity |
| `BattleforceRefsComponent` | `{ battleforce_ids: list<string> }` | References to participating Battleforce Entities |
| `VictoryConditionsComponent` | `{ conditions: list<VictoryCondition> }` | Battle End Conditions that trigger Consolidation |
| `ScoringComponent` | `{ rules: list<ScoringRule>, scores: map<player_id, int> }` | Scoring rules and per-Player score accumulators |
| `TurnLimitComponent` | `{ max_turns: int? }` | Optional maximum Turn count; null if no limit |
| `OrderQueueComponent` | `{ orders: map<squad_id, OrderStruct> }` | Per-Squad Orders, hidden per Player until Execute Phase |
| `ReactionQueueComponent` | `{ reactions: map<squad_id, ReactionStruct> }` | Per-Squad Reactions, hidden per Player until resolution |
| `CasualtyReportComponent` | `{ entries: list<{ squad_id: string, turn: int, cause: string, remaining_units: int }> }` | Ordered list of destroyed Squads with metadata |
| `RandomSeedComponent` | `{ seed: int }` | Seeded PRNG for deterministic replay |

**Order struct**: `{ type: enum(Hold, Advance, Run, Charge, FallBack, DigIn, DeployFromReserves, SurgeAction), target_point: {x: float, y: float}?, target_squad_id: string?, attack_target_ids: list<string>?, surge_ability_ref: string? }`

**Reaction struct**: `{ type: enum(Reposition, Evade, ReturnFire), target_squad_id: string? }`

### Battle System Responsibilities

The Battle System is the orchestrating System for Battle resolution. It reads and writes the Battle Entity's Components and delegates to other Systems during specific Phases.

| System | Reads | Writes | Battle Phase |
|---|---|---|---|
| **Battle System** | BattleStageComponent, TurnCounterComponent, PhaseComponent, VictoryConditionsComponent, OrderQueueComponent, ReactionQueueComponent | BattleStageComponent, TurnCounterComponent, PhaseComponent, CasualtyReportComponent, ScoringComponent | All Phases |
| **Zone System** | ZoneComponent, DestructionStateComponent, Roster requirements | ZoneComponent | Planning (Roster validation), Rally (Reserves check), Resolve Combat (destruction transitions), Consolidation (cleanup) |
| **Deployment System** | ZoneComponent, PositionComponent, CompositionComponent, DeploymentZonesComponent | ZoneComponent, PositionComponent | Deployment Stage |
| **Movement System** | StatlineComponent (Speed), PositionComponent, OrderQueueComponent | PositionComponent | Execute Phase (rule 133.4) |
| **Combat System** | StatlineComponent, AttackProfileComponent, ArmourComponent, Modifier data, DestructionStateComponent, DamageTakenComponent | DamageTakenComponent, DestructionStateComponent | Execute Phase (rule 133.5), Resolve Combat (rule 134.1 Melee) |
| **Morale System** | MoraleStateComponent, StatlineComponent (Morale), CasualtyReportComponent | MoraleStateComponent | Rally Phase (rule 131.1), Resolve Combat (rule 134.1 Morale Tests) |
| **Ability System** | AbilityRefsComponent, MoraleStateComponent, ZoneComponent, MarkerComponents | Varies by Ability effect | Execute Phase (Surge Actions), timing-window-dependent |

### Digital Implementation Considerations

- The OrderQueueComponent is stored server-side and is not visible to other Players until the Battle System reveals it during the Execute Phase (rule 133.2), preventing information leaks in multiplayer.
- The Phase timer for Issue Orders is configurable per Battle or Campaign (default: 120 seconds), stored as metadata on the PhaseComponent.
- AI-controlled Players submit Orders through the same interface. The Battle System does not differentiate between human and AI Order sources.
- The Battle System must support serialization and deserialization of all Battle Entity Components for save/load and replay functionality.
- Random outcomes (hit rolls) use the seeded pseudorandom number generator stored in the RandomSeedComponent. The seed is recorded at Battle start for deterministic replay.
- Squad-level Components (PositionComponent, ZoneComponent, MoraleStateComponent, EnduranceRemainingComponent, TemporaryTagsComponent) are defined in Entity System Rules and Movement and Positioning Rules; Battle Rules consume them but do not redefine them.

---

## Version History

| Version | Date       | Changes                       |
|---------|------------|-------------------------------|
| 0.1     | 2026-03-17 | Initial draft of Battle Rules |
| 0.2     | 2026-03-18 | ECS alignment: defined Battle archetype with 12 characteristic Components; replaced all "the engine" references with specific Systems (Battle System, Combat System, Morale System, Movement System, Deployment System, Zone System); replaced tag references with marker Component language; updated state tracking to reference Components; rewrote simultaneous resolution for ECS pipeline language; restructured Implementation Notes with Component definitions and Battle System reads/writes table; updated Glossary with ECS-aware entries; flagged tabletop holdovers (Melee formalization, Line of Sight definition, Pre-Engagement Movement as Ability Component) |
