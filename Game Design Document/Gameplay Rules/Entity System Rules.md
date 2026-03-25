# Entity System Rules

**Status**: Draft
**Last Updated**: 2026-03-18
**Purpose**: Formalizes the rules governing Entities, Components, Systems, and the archetypes that define the structural building blocks of Simple War — the structures that all implementations (tabletop and digital) must satisfy.

---

## Overview

Simple War uses an **Entity–Component–System (ECS)** architecture. Every game object is an **Entity** (a unique identifier). What an Entity *is* and how it participates in the game is determined entirely by the **Components** attached to it. **Systems** contain all logic: they read Components, perform calculations, and write results back to Components.

This document defines the core Components and the standard **archetypes** — characteristic combinations of Components that define categories of Entities such as Units, Squads, Items, Commanders, Armies, and Battleforces. Every rule in other sections (Battle Rules, Combat Resolution, Movement, etc.) operates on the structures defined here.

This document builds bottom-up: foundational concepts first (Entities, Components, marker Components), then the data Components that describe capability (Statline, Items, Attack Profiles), then the archetypes that combine them (Units, Squads, Abilities), and finally the organizational archetypes that group them (Commanders, Armies, Battleforces).

---

## 200 Entities and Components

### 200.1 Entity

An Entity is a unique identifier (ID) in the game world. An Entity has no inherent data or behavior — all of its properties, capabilities, and state are defined by the Components attached to it. Being an Entity is the only prerequisite for an object to participate in the rules system — to be referenced by rules, to occupy Zones, and to interact with other Entities.

Objects that are not Entities do not have Components and do not participate in the rules system. Examples of non-Entity objects: the Roster system, Score, Deployment (the process). These objects serve structural or bookkeeping roles but do not participate directly in the rules system as Entities.

### 200.2 Components

A Component is a data structure attached to an Entity. An Entity's set of Components determines what it is and how it participates in the game. Components hold state; they do not contain logic. Systems read Component data, perform calculations, and write results back to Components.

Components are classified into the following categories:

- **Data Components** hold structured state (e.g., a Statline Component holds Endurance, Durability, Morale, Speed, Reflex; an Attack Profile Component holds Category, Range, Damage Value, Damage Type).
- **Marker Components (Tags)** carry no data beyond their presence. They are attached to Entities to provide keywords that group and differentiate Entities when determining whether rules affect them. At the rules level, a marker Component is a presence-only identifier attached to an Entity. Marker Components are case-sensitive.

An Entity may have any number of Components, including zero or more marker Components. Adding or removing a Component from an Entity changes which rules and Systems apply to that Entity.

**Implementation notes (Godot ECS patterns)**  
The following are implementation strategies, not additional rules concepts. Rules continue to speak in terms of marker Components and their presence.

- **Godot ECS add-on implementations** (such as frameworks that use `ECSComponent` or `ECSDataComponent`) typically represent a marker Component as a class that extends the framework's base Component type and declares no additional fields (or a single boolean flag used only for editor convenience). For example, an `InfantryTag` marker Component may be implemented as an empty GDScript class that extends `ECSComponent` and is attached to all Entities that should have the `Infantry` marker Component.
- **Manual node-based ECS implementations** in Godot may represent a marker Component as either:
  - A simple child Node attached to the Entity's root Node (e.g., an `InfantryTag` Node); Systems check for presence with a structural query such as `has_node("InfantryTag")`, or
  - A string stored in a `MarkerComponents` set on the Entity (e.g., `markers = {"Infantry", "Human"}`); Systems check for presence with `markers.has("Infantry")`.

Both patterns are valid as long as they preserve the rules-level behavior that marker Components are presence-only identifiers attached to Entities and are compared using case-sensitive string equality.

### 200.3 Marker Components (Tags)

Marker Components serve two purposes:

1. **Grouping**: Marker Components collect Entities into logical categories so that rules can target sets of Entities by marker Component (e.g., "all Entities with the Infantry marker Component").
2. **Differentiation**: Marker Components distinguish Entities from one another so that rules can apply selectively (e.g., "Entities with the Vehicle marker Component are not affected by this rule").

Marker Components are classified into the following categories:

- **Entity Tags** identify what is inherent to an Entity, such as an Infantry Unit having the `Infantry` marker Component.
- **Status Tags** identify effects that are not inherent to an Entity, communicating events such as "This Entity was ordered to Run" or "This Entity is on fire."

Rules that reference a marker Component always specify the exact name. A rule that says "Squads with the Infantry tag" affects only Entities that have the `Infantry` marker Component.

### 200.4 Systems

A System is a squad of logic that operates on Entities possessing a specific set of Components. Systems read Component data, perform calculations, and write results back to Components. Systems contain all game logic; Components contain all game state.

The core Systems referenced by these rules include:

| System | Operates On | Purpose |
|---|---|---|
| **Zone System** | Entities with a Zone Component | Manages transitions between Zones, enforces state-change rules, notifies other Systems |
| **Combat System** | Entities with Attack Profile, Statline, Armour Components | Resolves attacks through the Attack and Defense Pipelines |
| **Morale System** | Entities with a Morale State Component | Manages Morale state transitions based on test results |
| **Ability System** | Entities with Ability Components | Evaluates Ability conditions and effects during timing windows |
| **Movement System** | Entities with a Statline Component and Zone Component | Reads Speed, resolves movement Orders |

Additional Systems may be introduced as rules are drafted. Each System specifies which Components it requires.

### 200.5 Archetypes

An archetype is a common combination of Components that defines a category of Entity. Archetypes are not enforced by the engine — they are conventions documented here so that designers and developers share a vocabulary. The standard archetypes are:

| Archetype | Characteristic Components |
|---|---|
| Unit | Statline, Equipped Items, Destruction State |
| Squad | Statline, Faction Keywords, Squad Keywords, Composition, Abilities, Value, Zone, Morale State |
| Item | Item Type; optionally Attack Profile, Armour, Consumable, Equipment |
| Commander | Statline, Equipment, Abilities, Army Reference, Commander marker Component |
| Army | Commander Reference, Squad References, Army marker Component |
| Battleforce | Army Reference, Squad References, Total Value, Battleforce marker Component |

### 200.6 Object References

When a rule needs to describe relationships between Entities from a particular Entity's perspective, it uses the following reference terms:

- **Own**: Objects that belong to the reference Entity. A Commander's Own Squads are the Squads in that Commander's Army.
- **Other**: Objects that do not belong to the reference Entity.
- **Any**: All objects, regardless of ownership.

When a rule involves Faction Relationships, the following terms apply:

- **Friendly**: Entities belonging to a Faction the reference Entity's Faction considers Friendly.
- **Allied**: Entities belonging to a Faction the reference Entity's Faction considers Allied.
- **Enemy**: Entities belonging to a Faction the reference Entity's Faction considers Enemy.
- **Neutral**: Entities belonging to a Faction the reference Entity's Faction considers Neutral.

Faction Relationships are **not bilateral**: Faction A may consider Faction B as Friendly while Faction B considers Faction A as Enemy. Faction Relationships are revealed during the Planning Stage (see rule 110.6 in Battle Rules) and are immutable during a Battle unless a rule explicitly states otherwise.

---

## 210 Statline Component

### 210.1 The Statline Component

The Statline Component is a data Component holding the base Characteristics shared by Units. Every Entity of the Unit archetype has a Statline Component with exactly five Characteristics: Endurance, Durability, Morale, Speed, and Reflex. Each Characteristic is an integer value greater than or equal to 0.

Units in the same Squad may have different Statline Component values. The Combat System operates at the Unit level, using each individual Unit's own Statline Component values (see Combat Resolution in Terminology).

A Unit's Statline Component can be modified by equipped Item Components, Ability Components, and rules affecting the Unit or the Unit's Squad. Modifications are applied as additive or multiplicative adjustments and are tracked separately from the base value.

### 210.2 Endurance

Endurance is an integer Characteristic in the Statline Component representing a Unit's capacity for sustained exertion. Actions that tax Endurance (such as the Run or Charge Orders; see rules 132.2d and 132.2e in Battle Rules) reduce the Squad's Endurance by the specified amount. When a Squad's remaining Endurance reaches 0, that Squad may not receive Orders that tax Endurance.

Endurance recovers when a Squad performs actions that do not tax it. The default recovery rate is 1 Endurance per Turn for Squads that did not perform an Endurance-taxing action during the previous Turn (see rule 131.1 in Battle Rules).

Baseline Competence — a Unit's general effectiveness when making attacks — is derived from Endurance by the Combat System (see rule 210.7a).

### 210.3 Durability

Durability is an integer Characteristic in the Statline Component representing how much damage a Unit can absorb before being destroyed. When the Combat System resolves a Damage Instance whose mitigated value meets or exceeds the Unit's Durability, that Unit is destroyed.

A single Damage Instance can destroy at most one Unit. Damage that exceeds the target Unit's Durability does not carry over to other Units. Sub-lethal damage (damage below Durability) is tracked on the Unit's Damage Taken Component for future resolution.

### 210.4 Morale

Morale is both a Characteristic in the Statline Component and a separate Morale State Component. The Characteristic is an integer value used by the Morale System when making Morale Tests. The Morale State Component holds one of five values, ordered from worst to best:

1. **Broken**
2. **Poor**
3. **Neutral**
4. **Good**
5. **Surging**

Every Squad has a **Morale Baseline** value in its Morale State Component, which is the Morale state the Morale System trends the Squad toward over time. The default Morale Baseline is Neutral.

The Morale System tests casualties against the Morale Characteristic: if casualties exceed the Morale Characteristic, the Squad's Morale state worsens by one stage; if casualties are fewer than or equal to the Morale Characteristic, the Morale state improves by one stage (maximum Good). Surging is not reached through Morale Tests; it is reached only when a condition in one of the Squad's Ability Components explicitly sets Morale to Surging. See rule 134.1 in Battle Rules.

During the Rally Phase, the Morale System moves each Squad's Morale state one stage toward the Squad's Morale Baseline. If the Squad's Morale state is Surging, it resets to Neutral instead (see rule 131.1 in Battle Rules).

Morale state affects which Orders and actions a Squad may take:
- A Squad with Broken Morale may not receive the Charge or Surge Action Orders (see rule 132.4 in Battle Rules).
- A Squad with Surging Morale may perform a Surge Action (see rule 132.2h in Battle Rules).

### 210.5 Speed

Speed is an integer Characteristic in the Statline Component representing the typical distance a Squad can move in a single Turn without taxing Endurance. The Movement System reads Speed from the Statline Component.

- **Advance**: move up to Speed distance squads (rule 132.2b in Battle Rules).
- **Run**: move up to 2 × Speed distance squads; taxes Endurance (rule 132.2d in Battle Rules).
- **Charge**: move up to floor(1.5 × Speed) distance squads toward a target; taxes Endurance (rule 132.2e in Battle Rules).
- **Fall Back**: move up to Speed distance squads away from the nearest enemy Squad; a Squad with Broken Morale moves up to 2 × Speed instead (rule 132.2g in Battle Rules).

Speed also contributes to a Unit's Evasion Rating (see rule 210.7b).

### 210.6 Reflex

Reflex is an integer Characteristic in the Statline Component representing a Unit's ability to react to unexpected events. Reflex determines:

- Whether a Squad may declare a Reposition or Evade Reaction (Reflex must be greater than 0; see rules 133.3a and 133.3b in Battle Rules).
- The magnitude of an Evade Reaction's Evasion bonus (equal to the Squad's Reflex value; see rule 133.3b in Battle Rules).

Reflex contributes to a Unit's Evasion Rating (see rule 210.7b).

### 210.7 Derived Values

The following values are computed by Systems from Component data on demand. They are not stored as Components but are derived when needed, ensuring they always reflect the current state.

#### 210.7a Baseline Competence

Baseline Competence represents a Unit's general effectiveness when making attacks. The Combat System derives Baseline Competence from the Unit's Statline Component's Endurance value. Weapon Modifier Components and situational effects adjust the final hit probability relative to Baseline Competence.

#### 210.7b Evasion Rating

Evasion Rating represents how difficult a Unit is to hit. The Combat System derives Evasion Rating from the Unit's Statline Component's Reflex and Speed values, plus situational modifiers (such as the `Dug In` marker Component or the Evade Reaction).

#### 210.7c Armour Value

Armour Value is the sum of the Armour Value properties from all Armour Components on Items equipped to the Unit. The Combat System uses Armour Value to reduce incoming damage after a hit is confirmed. The interaction between Armour Value, Armour Resistances, and Damage Types is specified in the Combat Resolution rules.

### Examples

#### Example 1: Reading a Statline Component
**Setup**: A Rifleman Unit's Statline Component contains Endurance 10, Durability 10, Morale 10, Speed 10, Reflex 10.
**Meaning**: The Unit can sustain moderate exertion, absorb 10 damage before the Combat System marks it as destroyed, has average morale resilience, the Movement System moves it 10 distance squads per Advance, and it has decent reactive capability.

#### Example 2: Asymmetric Statline Component
**Setup**: A Maw Fiend Unit's Statline Component contains Endurance 15, Durability 100, Morale 20, Speed 8, Reflex 12.
**Meaning**: Extremely tough (100 Durability), highly resilient morale, moderate speed, good reflexes. The high Durability means the Combat System requires substantial damage to destroy it in a single engagement.

---

## 220 Item Components

### 220.1 Item Archetype

An Item is an Entity of the Item archetype. An Item's Components provide additional rules, Characteristics, or capabilities to the Unit that equips it. An Item Entity has:

- **ID**: A unique string identifier.
- **Display Name Component**: A human-readable label.
- **Description Component**: Flavour text describing the Item.
- **Item Type Component**: One or more type classifications that define the Item's mechanical role (see rule 220.2).

An Item may have marker Components (Tags). An Item that is equipped to a Unit does not automatically confer its marker Components to the Unit or the Unit's Squad. If an Item confers marker Components to its bearer or bearer's Squad, the Item's rules state this explicitly.

### 220.2 Item Type Component

An Item's Item Type Component holds one or more of the following types. A single Item may have multiple types simultaneously (e.g., a Power Shield has both Weapon and Armour types).

| Type | Description |
|---|---|
| Weapon | Provides one or more Attack Profile Components to the bearer (see rule 220.3) |
| Armour | Provides an Armour Component to the bearer (see rule 220.6) |
| Consumable | May be used a limited number of times; expended after use |
| Equipment | Provides passive benefits, marker Components, or rule modifications |

An Item's type determines how its Components interact with the bearer, equipment categories, and other rules.

### 220.3 Weapons

A Weapon is an Item with Weapon in its Item Type Component. A Weapon provides one or more Attack Profile Components to the Unit that equips it. Each Attack Profile Component describes a single way the Weapon can be used.

A single Weapon may provide multiple Attack Profile Components. For example, a rifle may have both a ranged "Fire" profile and a melee "Bayonet" profile.

### 220.4 Attack Profile Component

An Attack Profile Component defines how a Weapon is used to make an attack. The Combat System reads Attack Profile Components when resolving attacks. Each Attack Profile Component has the following properties:

| Property | Type | Required | Description |
|---|---|---|---|
| ID | string | Yes | Unique identifier for the base Attack Profile |
| Display Name | string | Yes | Human-readable label for this use of the Weapon |
| Category | enum: melee, ranged | Yes | Determines which engagement contexts the profile can be used in |
| Range | Range Brackets | Yes | Distances at which the profile can target (see rule 220.5) |
| Damage Value | integer ≥ 0 | Yes | Base damage produced on a successful hit |
| Damage Type | string | Yes | Category of damage (see rule 220.8) |
| Damage Count | integer ≥ 1 | No | Number of Damage Instances per attack; defaults to 1 |
| Modifiers | list of Modifiers | No | Adjustments to hit probability, damage, or armour interaction (see rule 220.9) |

When an Item provides an Attack Profile Component, the Item may override any of the base Attack Profile's properties (Damage Value, Range, Modifiers) with Item-specific values. The Item-specific values take precedence.

### 220.5 Range Brackets

Range Brackets define the distances at which an Attack Profile Component can target. A ranged Attack Profile Component defines four distance thresholds:

| Bracket | Description |
|---|---|
| **Min** | Minimum targeting distance. Attacks cannot target Units within Min distance. |
| **Short** | Beginning of effective range. |
| **Long** | End of effective range. |
| **Max** | Maximum targeting distance. Attacks cannot target Units beyond Max distance. |

The **effective range** is the interval [Short, Long]. The Combat System does not apply a range-based penalty to attacks within effective range.

The intervals (Min, Short) and (Long, Max) are the **penalty ranges**. The Combat System applies a penalty to hit probability for attacks in these intervals.

For melee Attack Profile Components, Range is limited to a Max distance (default 1 distance squad) representing close proximity. Melee profiles have no Min, Short, or Long brackets.

All Range values are integers representing distance squads.

### 220.6 Armour Component

An Armour Component provides:

| Property | Type | Required | Description |
|---|---|---|---|
| Armour Value | integer ≥ 0 | Yes | Amount of damage reduction the Combat System applies to incoming Damage Instances |
| Armour Type | string | Yes | Descriptive label for the armour category (e.g., composite, heavy_plate, energy_shield) |
| Resistances | map of Damage Type → integer | Yes | Per-Damage-Type modifier added to or subtracted from Armour Value when the Combat System resolves damage of that type |
| Hit Modifiers | map of context → float | No | Adjustments to hit probability when the bearer is targeted in specific contexts (e.g., ranged attacks, melee attacks, specific damage types) |

A Unit may equip multiple Items with Armour Components. The Unit's total Armour Value is the sum of all equipped Armour Components' Armour Values. Resistances and Hit Modifiers stack additively across equipped Armour Components.

### 220.7 Armour Resistances

Armour Resistances modify the effective Armour Value against specific Damage Types. When the Combat System resolves damage:

**Effective Armour = Armour Value + Resistance for the incoming Damage Type**

A positive Resistance increases protection against that Damage Type. A negative Resistance decreases protection. A Resistance of 0 has no effect.

Every Armour Component must define a Resistance value for each Damage Type defined in the game (see rule 220.8). If a new Damage Type is introduced, Armour Components that do not define a Resistance for it are treated as having Resistance 0.

### 220.8 Damage Types

Damage Types categorize the nature of damage produced by the Combat System's Attack Pipeline. Each Damage Type interacts differently with Armour Resistances in the Defense Pipeline. The base Damage Types are:

| Damage Type | Description |
|---|---|
| **Kinetic** | Physical impact damage (bullets, blades). Armour with Resistance 0 for Kinetic provides its full Armour Value. |
| **Concussive** | Blast and shockwave damage (explosions, grenades). Many Armour Components have negative Resistance to Concussive, reducing effective protection. |
| **Energy** | Directed energy damage (arcane blasts, plasma). Armour Resistance to Energy varies widely: some Armour Components are highly resistant, others are vulnerable. |

Additional Damage Types may be introduced. Each new Damage Type must define how it interacts with existing Armour Components by specifying default Resistance values.

### 220.9 Modifier Data

Modifiers are adjustment data applied by the Combat System during relevant steps of resolution. A Modifier has:

| Property | Type | Description |
|---|---|---|
| Target | string | What the Modifier adjusts: `hit_probability`, `damage_value`, or `armour_interaction` |
| Operation | enum: add, multiply | How the adjustment is applied |
| Value | number | The adjustment amount |

Modifiers from Attack Profile Components, Item Components, Ability Components, and situational effects are combined by the Combat System during resolution. Additive Modifiers are summed first, then multiplicative Modifiers are applied in the order specified by the Combat Resolution rules.

### 220.10 Consumable Component

A Consumable Component tracks a finite use count. Each use expends one charge. When all charges are expended, the Consumable is no longer available for use until restored by a rule. The number of charges is defined by the count of the Item in the Unit's Equipped Items Component.

### Examples

#### Example 1: Multi-Profile Weapon
**Setup**: A Human Rifle Item has two Attack Profile Components: "Fire" (ranged, kinetic, damage 3, range 5/10/30/40) and "Bayonet" (melee, kinetic, damage 2, range max 1).
**Meaning**: The bearer gains access to both profiles. The Combat System selects the appropriate Attack Profile Component based on context (range to target, engagement type).

#### Example 2: Armour with Resistances
**Setup**: Human Combat Armour Item has an Armour Component with Armour Value 2 and Resistances: kinetic 0, concussive −1, energy +1.
**Meaning**: The Combat System computes effective armour as: 2 against kinetic, 1 (2 − 1) against concussive, 3 (2 + 1) against energy.

#### Example 3: Dual-Type Item
**Setup**: A Power Shield Item has both an Armour Component (value 3, energy_shield type) and an Attack Profile Component ("Shield Bash" melee profile) via its Weapon type.
**Meaning**: The Item provides both protection (read by the Defense Pipeline) and an attack option (read by the Attack Pipeline) simultaneously.

---

## 230 Unit Archetype

### 230.1 Unit

A Unit is an Entity of the Unit archetype — its Components include a Statline Component, an Equipped Items Component, and a Destruction State Component. Units are the most granular interactive Entities in Simple War. Each Unit Entity has:

- **ID**: A unique string identifier.
- **Display Name Component**: A human-readable label.
- **Equipped Items Component**: A list of Item references, each with a count, defining the Unit's equipment loadout.
- **Statline Component**: Endurance, Durability, Morale, Speed, and Reflex values (see rule 210.1).
- **Damage Taken Component**: Integer tracking sub-lethal damage accumulated.
- **Destruction State Component**: Boolean indicating whether the Unit is destroyed.

Units define how a Squad's baseline capability declines as it takes casualties: each Unit contributes to the Squad's ability to affect an engagement, and the Combat System removing a Unit reduces that contribution.

### 230.2 Bearer Relationship

When a Unit equips an Item, the Unit is the Item's **Bearer**. The Bearer relationship establishes:

1. The Unit gains access to all rules, Attack Profile Components, and Statline modifications provided by the Item's Components.
2. The Unit does **not** automatically gain the Item's marker Components (Tags). If an Item confers marker Components to its Bearer or Bearer's Squad, the Item's rules state this explicitly.
3. A Unit may equip multiple Items. Equipment categories (e.g., "a Unit may equip at most one Item with a heavy_plate Armour Component") are defined by the Squad's Composition rules or by Item-specific restrictions.
4. When the Combat System marks a Unit as destroyed, all Items in that Unit's Equipped Items Component remain associated with the destroyed Unit in the Casualty Report but are no longer in play.

### Examples

#### Example 1: Basic Unit
**Setup**: A Rifleman Unit Entity is equipped with a Human Rifle (count 1), Human Combat Armour (count 1), a Combat Knife (count 1), and Frag Grenades (count 3).
**Meaning**: The Combat System reads the Unit's Attack Profile Components from the Rifle and Knife, Armour Component from the Combat Armour, and the Consumable Component from the Frag Grenades (3 charges).

---

## 240 Squad Archetype

### 240.1 Squad

A Squad is an Entity of the Squad archetype — its Components include a Statline Component, Faction Keyword marker Components, Squad Keyword marker Components, a Composition Component, Ability Components, a Value Component, and a Zone Component. Squads group Units, providing the collective interface through which those Units engage with Zones, other Entities, and the rules system. Squads are the primary Entities that Players interact with when issuing Orders (see rule 132.1 in Battle Rules), moving on the Battlefield, and tracking state.

A Squad Entity has:

- **ID**: A unique string identifier.
- **Display Name Component**: A human-readable label.
- **Faction Keyword marker Components**: One or more marker Components identifying the Squad's allegiance (e.g., `Human`, `Xenos`, `Chaos`).
- **Squad Keyword marker Components**: One or more marker Components describing the Squad's battlefield role (e.g., `Infantry`, `Vehicle`, `Monster`).
- **Statline Component**: The Characteristic values for Units in the Squad (see rule 210.1). Individual Units may have different values as defined by the Composition.
- **Value Component**: An integer representing the Squad's strength for armybuilding and scoring purposes (see rule 240.6).
- **Ability Components**: A list of Ability references (see rule 250.1).
- **Composition Component**: The Units and their counts that make up the Squad (see rule 240.2).
- **Unit Options Component**: Optional additional or replacement Units that can be added during armybuilding.
- **Item Options Component**: Optional equipment changes that can be made to Units during armybuilding.
- **Zone Component**: The Squad's current Zone, managed by the Zone System (e.g., Battlefield, Reserves, Embarked, Casualty Report).
- **Morale State Component**: The Squad's current Morale state and Morale Baseline, managed by the Morale System (see rule 210.4).
- **Endurance Remaining Component**: Integer tracking current Endurance for Orders that tax it.

### 240.2 Composition Component

A Squad's Composition Component defines which Units make up the Squad and in what quantities. Each entry specifies:

- **Unit ID**: A reference to a Unit definition (see rule 230.1).
- **Count**: The number of that Unit in the Squad (integer ≥ 1).

The total number of Units in a Squad is the sum of all Composition entry counts. A Squad must have at least one Unit.

**Unit Options** allow Players to add Units to or replace Units in the Squad during armybuilding. Each Unit Option specifies the Unit to add, the count, the value cost, and any conditions (e.g., "available only if Squad size is 20 or more").

**Item Options** allow Players to change equipment on specific Units during armybuilding. Each Item Option specifies the Item to add, the Unit receiving it, the count, the value cost, and optionally the Item being replaced.

### 240.3 Tag Inheritance

A Squad inherits all marker Components (Tags) from all Units in the Squad. If any Unit in the Squad has a marker Component, the Squad has that marker Component.

Tag inheritance is recalculated whenever the Squad's Unit composition changes (e.g., the Combat System destroys a Unit or a Unit is added). If all Units with a particular marker Component are removed from the Squad, the Squad loses that marker Component.

### 240.4 State Inheritance

A Squad can inherit states from its Units when **all** Units in the Squad share that state. The primary example: the Zone System transitions a Squad to the Casualty Report only when every Unit in the Squad is destroyed.

A Squad is **not** in a given state if at least one Unit in the Squad is not in that state, unless a rule explicitly states otherwise.

### 240.5 Datasheets

A Datasheet is a comprehensive reference document for a Squad, compiled from the Squad's Component data for Player convenience. A Datasheet contains:

- Squad name, Faction Keyword marker Components, and Squad Keyword marker Components
- Composition Component (default Units, Unit Options, Item Options with costs)
- Statline Component values (Characteristics for each Unit type in the Squad)
- Default equipment (Items in each Unit's Equipped Items Component by default)
- Ability Components
- Value Component
- Restrictions (if any)

A Datasheet does not contain rules that are not part of the Squad's Component data. A Unit's Datasheet shows its baseline combat Characteristics as determined by its default Item Components before any options are chosen.

### 240.6 Value Component

The Value Component holds an integer representing the Squad's overall strength for armybuilding, Roster validation, and scoring. Each Squad definition specifies a base Value. Unit Options and Item Options modify the Squad's Value by their specified costs.

The total Value of a Battleforce is the sum of all Squad Value Components (including selected options) in that Battleforce. Rosters and Campaigns may impose caps or bands on total Battleforce Value (see rule 270.2).

### Examples

#### Example 1: Squad Composition Component
**Setup**: A Riflemen Squad's Composition Component lists: 10 × Rifleman Unit. Each Unit's Statline Component has Endurance 10, Durability 10, Morale 10, Speed 10, Reflex 10. The Squad's Value Component is 100.
**Meaning**: The Squad consists of 10 identical Unit Entities. The Squad's collective behavior is governed by Orders issued to the Squad, but the Combat System resolves damage per Unit.

#### Example 2: Unit Option
**Setup**: The Riflemen Squad has a Unit Option: add 10 more Rifleman Units for +100 Value, not required.
**Meaning**: During armybuilding, the Player may choose to increase the Composition Component from 10 to 20 Units at an additional cost of 100 to the Value Component.

#### Example 3: Item Option with Replacement
**Setup**: The Riflemen Squad has an Item Option: replace one Human Rifle with a Rocket Launcher for +20 Value.
**Meaning**: During armybuilding, the Player may swap one Unit's Equipped Items Component entry, changing that Unit's available Attack Profile Components and increasing the Squad's Value Component by 20.

#### Example 4: State Inheritance
**Setup**: A Riflemen Squad has 10 Unit Entities. The Combat System has destroyed 9; 1 survives.
**Result**: The Squad is not destroyed. The surviving Unit continues to operate under the Squad's rules. If the Combat System destroys the last Unit, the Zone System transitions the Squad to the Casualty Report.

---

## 250 Ability Components

### 250.1 Ability Component

An Ability Component is a named rule or set of rules attached to a Squad Entity that provides capabilities beyond the Squad's base Statline and equipment Components. The Ability System evaluates Ability Components during appropriate timing windows. Each Ability Component has:

- **Name**: A unique, human-readable identifier.
- **Type**: One of Passive, Active, or Surge (see rules 250.2–250.4).
- **Effect**: A precisely defined rule statement specifying the trigger (if any), affected Entities, and the mechanical outcome.
- **Restrictions**: Conditions under which the Ability cannot be used or does not apply.

A Squad has zero or more Ability Components of each type (Passive, Active, Surge). The Squad's definition specifies the exact Ability Components available. Additional Ability Components may be granted by equipped Item Components, Campaign rules, or other Entities.

### 250.2 Passive Ability Components

A Passive Ability Component is always in effect while the Squad is in play and meets any stated conditions. The Ability System applies Passive Ability Components continuously — they do not require activation, do not cost an action, and cannot be voluntarily suppressed by the owning Player.

**Rule statement form**: `While [condition], [affected Entity] [gains/has/is affected by] [effect].`

### 250.3 Active Ability Components

An Active Ability Component must be deliberately activated by the owning Player. The Ability System processes activation during a specified timing window (e.g., during the Issue Orders Phase, during the Execute Phase). Each Active Ability Component specifies:

- **Timing**: When the Ability can be activated.
- **Cost**: Any resource expenditure required (e.g., Endurance, a Consumable charge).
- **Frequency**: How often the Ability can be used (e.g., once per Turn, once per Battle).
- **Effect**: The rule statement describing the outcome.

**Rule statement form**: `When [trigger/timing], [owner] may [action] to [effect]. [Cost]. [Frequency].`

### 250.4 Surge Ability Components

A Surge Ability Component is a special Active Ability Component available only when the Squad's Morale State Component is Surging. Activating a Surge Ability Component requires the Surge Action Order (see rule 132.2h in Battle Rules). After the Ability System resolves the Surge Ability, the Morale System resets the Squad's Morale to Neutral during the next Rally Phase.

A Squad may perform at most one Surge Action per Battle unless a rule explicitly grants additional uses.

**Rule statement form**: `[Surge] When this Squad performs a Surge Action, [effect].`

### Examples

#### Example 1: Passive Ability Component — Objective Secured
**Name**: Objective Secured
**Type**: Passive
**Effect**: While this Squad is within 3 distance squads of an Objective marker and is not destroyed, the Ability System counts this Squad as controlling that Objective, even if Enemy Squads are also within 3 distance squads — unless those Enemy Squads also have the Objective Secured Ability Component.

#### Example 2: Passive Ability Component — Forward Positions
**Name**: Forward Positions
**Type**: Passive
**Effect**: During the Deployment Stage, this Squad may be placed up to 6 distance squads beyond the owning Player's Deployment Zone boundary, provided the final position is more than 9 distance squads from any Enemy Unit.

---

## 260 Commander Archetype

### 260.1 Commander

A Commander is an Entity of the Commander archetype — its Components include a Statline Component, Equipment Components, Ability Components, an Army Reference Component, and the `Commander` marker Component. Players access Battleforces through the Commander leading them. A Commander Entity has:

- **ID**: A unique string identifier.
- **Display Name Component**: A human-readable label.
- **Marker Components**: Including the `Commander` marker Component and any Faction Keyword marker Components.
- **Statline Component**: Commanders may have Characteristic values that differ from standard Squads.
- **Equipped Items Component**: Equipment available to the Commander.
- **Ability Components**: Any Commander-specific Abilities.
- **Army Reference Component**: A link to the Army Entity the Commander leads (see rule 270.1).

A Commander may be deployable to the Battlefield as a Squad (a Commander Squad). When deployed, a Commander Squad follows all standard Squad rules. A Commander Squad's Composition Component, Statline Component, and Equipped Items Component are specified in the Commander's definition.

A Commander that is not deployable as a Squad still leads the Battleforce and may provide strategic benefits, but does not appear on the Battlefield.

### 260.2 Commander–Army Relationship

Each Commander Entity leads exactly one Army Entity. A Player may have multiple Commander Entities, each with their own Army. A Squad belongs to exactly one Army at a time.

When composing a Battleforce for a Battle (see rule 110.2 in Battle Rules), the owning Player selects Squads from the Commander's Army. A Battleforce must be led by at least one Commander at the start of a Battle.

### Examples

#### Example 1: Generic Commander
**Setup**: A generic Commander Entity with a Statline Component slightly above a standard infantry Unit (e.g., Endurance 12, Durability 15, Morale 14, Speed 10, Reflex 12), equipped with standard gear via its Equipped Items Component and no special Ability Components.
**Meaning**: The Commander is deployable as a Commander Squad and participates directly in Battle.

---

## 270 Army and Battleforce Archetypes

### 270.1 Army

An Army is an Entity of the Army archetype — its Components include a Commander Reference Component, a Squad References Component, and the `Army` marker Component. An Army is the complete roster of Squads available to a Commander. An Army Entity has:

- **Commander Reference Component**: A reference to the Commander Entity leading the Army (see rule 260.1).
- **Squad References Component**: A list of Squad Entity references representing all Squads the Commander has rallied.
- **Marker Components**: An Army inherits all marker Components (Tags) from all Squads in the Army.

An Army has no innate limits on size or composition. Limits are imposed by the Campaign, Roster, or scenario rules.

### 270.2 Battleforce

A Battleforce is an Entity of the Battleforce archetype — a subset of an Army's Squads selected for a specific Battle. A Battleforce Entity has the `Battleforce` marker Component and the following Components:

- **Army Reference Component**: The source Army.
- **Squad References Component**: A subset of the Army's Squad references.
- **Total Value Component**: Computed as the sum of all Squad Value Components in the Battleforce.

A Battleforce is composed during the Planning Stage (see rule 110.2 in Battle Rules) by selecting Squads from the Commander's Army.

- A Squad may belong to at most one Battleforce at a time.
- A Battleforce must satisfy the Roster requirements of the Battle or Campaign.
- All Squads in a Battleforce begin with their Zone Component set to Reserves.

### 270.3 Rosters

A Roster is a Zone that organizes Battleforces by validating them against a set of requirements. The Zone System validates Battleforces against Roster requirements; a Battleforce can be listed in any Roster whose requirements it meets. The default Roster has no requirements.

Roster requirements may include (non-exhaustive):
- Minimum and maximum Battleforce Value
- Allowed or excluded Faction Keyword marker Components
- Allowed or excluded Squad Keyword marker Components
- Minimum or maximum counts of specific Squad archetypes
- Commander restrictions

Campaign, tournament, and companion rules may define additional Rosters.

### Examples

#### Example 1: Composing a Battleforce
**Setup**: Commander A has an Army Entity with 5 Squad Entities totalling 900 Value. The Roster requires Battleforces between 400 and 600 Value.
**Action**: Player selects 3 Squads totalling 500 Value for the Battleforce's Squad References Component.
**Result**: The Battleforce is valid. The remaining 2 Squads stay in the Army but are not part of this Battle.

---

## Glossary Additions

- **Ability Component**: A Component attached to a Squad Entity providing capabilities beyond the Statline and equipment. Classified as Passive, Active, or Surge. (Rule 250.1)
- **Active Ability Component**: An Ability Component that must be deliberately activated by the owning Player during a specified timing window. The Ability System processes activation. (Rule 250.3)
- **Archetype**: A common combination of Components that defines a category of Entity. Not enforced by the engine; a documentation convention. (Rule 200.5)
- **Armour Component**: A Component on an Item Entity that provides Armour Value and Resistances to the bearer, used by the Combat System's Defense Pipeline to reduce incoming damage. (Rule 220.6)
- **Armour Resistance**: A per-Damage-Type modifier in an Armour Component that adjusts the effective Armour Value against that type. (Rule 220.7)
- **Armour Type**: A descriptive label in an Armour Component for the category of armour (e.g., composite, heavy_plate, energy_shield). (Rule 220.6)
- **Armour Value**: The total damage reduction provided by equipped Armour Components, before Resistance adjustment. Computed on demand by the Combat System. (Rule 210.7c, 220.6)
- **Army**: An Entity of the Army archetype grouping all Squad Entities available to a Commander. Inherits marker Components from its Squads. (Rule 270.1)
- **Attack Pipeline**: The first stage of the Combat System pipeline. Reads attacker Components (Statline, Attack Profiles, Modifiers) and produces Damage Instances. (Rule 220.4, see Combat Resolution in Terminology)
- **Attack Profile Component**: A Component defining a single way a Weapon can be used, specifying Category, Range, Damage Value, Damage Type, and Modifiers. Read by the Combat System. (Rule 220.4)
- **Baseline Competence**: A derived value representing a Unit's general attack effectiveness, computed by the Combat System from the Statline Component's Endurance. (Rule 210.7a)
- **Battleforce**: An Entity of the Battleforce archetype — a subset of an Army's Squads selected for a specific Battle; must satisfy Roster requirements. (Rule 270.2)
- **Bearer**: A Unit Entity that has an Item equipped in its Equipped Items Component. (Rule 230.2)
- **Broken**: The worst Morale state in the Morale State Component. Squads with Broken Morale cannot Charge or use Surge Actions. (Rule 210.4)
- **Category** (Attack Profile): Whether an Attack Profile Component is melee or ranged. (Rule 220.4)
- **Characteristic**: One of the five base values in the Statline Component: Endurance, Durability, Morale, Speed, Reflex. (Rule 210.1)
- **Commander**: An Entity of the Commander archetype with a `Commander` marker Component that leads an Army Entity and provides access to Battleforces. (Rule 260.1)
- **Commander Squad**: A Commander Entity that is deployable to the Battlefield as a Squad, following all standard Squad rules. (Rule 260.1)
- **Component**: A data structure attached to an Entity. Components hold state; Systems contain logic. An Entity's set of Components determines what it is. (Rule 200.2)
- **Composition Component**: A Component on a Squad Entity defining the Units and their counts that make up the Squad. (Rule 240.2)
- **Concussive**: A Damage Type representing blast and shockwave damage. (Rule 220.8)
- **Consumable Component**: A Component tracking a finite use count on an Item Entity. (Rule 220.10)
- **Damage Count**: The number of Damage Instances produced per attack from an Attack Profile Component; defaults to 1. (Rule 220.4)
- **Damage Instance**: An intermediate data object produced by the Attack Pipeline containing Damage Value, Damage Type, and source metadata. Consumed by the Defense Pipeline. (Rule 220.4, see Combat Resolution in Terminology)
- **Damage Type**: A category of damage (kinetic, concussive, energy) that interacts with Armour Resistances in the Defense Pipeline. (Rule 220.8)
- **Damage Value**: The base damage produced on a successful hit by an Attack Profile Component. (Rule 220.4)
- **Data Component**: A Component holding structured state (e.g., Statline, Attack Profile). Contrast with marker Component. (Rule 200.2)
- **Datasheet**: A comprehensive Squad reference compiled from the Squad's Component data, showing Composition, Statline, equipment, Abilities, and Value. (Rule 240.5)
- **Defense Pipeline**: The second stage of the Combat System pipeline. Reads target Components (Statline, Armour, Resistances) and consumes Damage Instances. (Rule 220.6, see Combat Resolution in Terminology)
- **Destruction State Component**: A boolean Component on a Unit Entity indicating whether the Unit has been destroyed by the Combat System. (Rule 230.1)
- **Durability**: A Characteristic in the Statline Component representing how much damage a Unit can absorb before the Combat System marks it as destroyed. (Rule 210.3)
- **Effective Range**: The interval [Short, Long] of a Range Bracket where the Combat System does not apply a range-based penalty. (Rule 220.5)
- **Endurance**: A Characteristic in the Statline Component representing a Unit's capacity for sustained exertion. (Rule 210.2)
- **Energy**: A Damage Type representing directed energy damage. (Rule 220.8)
- **Entity**: A unique identifier (ID) in the game world. An Entity has no inherent data or behavior; all properties are defined by its Components. (Rule 200.1)
- **Entity Tag**: A marker Component identifying what is inherent to an Entity. (Rule 200.3)
- **Evasion Rating**: A derived value computed by the Combat System from the Statline Component's Reflex and Speed, plus situational modifiers. (Rule 210.7b)
- **Faction Keywords**: Marker Components identifying an Entity's allegiance or species. (Rule 200.3)
- **Faction Relationships**: Directional relationships (Friendly, Allied, Enemy, Neutral) between Factions; not bilateral. (Rule 200.6)
- **Good**: A Morale state one stage above Neutral in the Morale State Component. (Rule 210.4)
- **Item**: An Entity of the Item archetype providing additional rules through its Components when equipped to a Unit. (Rule 220.1)
- **Item Option**: An armybuilding option allowing equipment changes on Units within a Squad. (Rule 240.2)
- **Item Type Component**: A Component classifying an Item's mechanical role: Weapon, Armour, Consumable, or Equipment. (Rule 220.2)
- **Kinetic**: A Damage Type representing physical impact damage. (Rule 220.8)
- **Marker Component (Tag)**: A Component carrying no data beyond its presence, used to group and differentiate Entities. (Rule 200.3)
- **Unit**: An Entity of the Unit archetype representing a single individual within a Squad, carrying Statline, equipment, and destruction state Components. (Rule 230.1)
- **Unit Keywords**: Marker Components capturing granular Unit-level traits. (Rule 200.3)
- **Unit Option**: An armybuilding option allowing additional or replacement Units in a Squad. (Rule 240.2)
- **Modifier**: Adjustment data in a Component applied by the Combat System to hit probability, damage, or armour interaction. (Rule 220.9)
- **Morale**: A Characteristic in the Statline Component (integer) and a Morale State Component (Broken, Poor, Neutral, Good, Surging) governing a Squad's willingness to perform certain actions. Managed by the Morale System. (Rule 210.4)
- **Morale Baseline**: The Morale state value in the Morale State Component that the Morale System trends the Squad toward over time; default is Neutral. (Rule 210.4)
- **Morale State Component**: A Component on a Squad Entity holding the current Morale state and Morale Baseline, managed by the Morale System. (Rule 210.4)
- **Neutral**: The default Morale state in the Morale State Component. (Rule 210.4)
- **Passive Ability Component**: An Ability Component always in effect while the Squad is in play and meets stated conditions. Applied continuously by the Ability System. (Rule 250.2)
- **Penalty Range**: The intervals (Min, Short) and (Long, Max) in a Range Bracket where the Combat System applies a hit probability penalty. (Rule 220.5)
- **Poor**: A Morale state one stage below Neutral in the Morale State Component. (Rule 210.4)
- **Range Brackets**: The set of distance thresholds (Min, Short, Long, Max) in an Attack Profile Component defining targeting distances. (Rule 220.5)
- **Reflex**: A Characteristic in the Statline Component representing reactive capability, contributing to Reactions and Evasion Rating. (Rule 210.6)
- **Roster**: A Zone that validates Battleforces against a set of requirements for listing. The Zone System manages validation. (Rule 270.3)
- **Speed**: A Characteristic in the Statline Component representing typical movement distance per Turn without taxing Endurance. Read by the Movement System. (Rule 210.5)
- **Statline Component**: A data Component holding the five base Characteristics: Endurance, Durability, Morale, Speed, Reflex. (Rule 210.1)
- **Status Tag**: A marker Component identifying an effect not inherent to an Entity, communicating transient state. (Rule 200.3)
- **Surge Ability Component**: A special Active Ability Component available only at Surging Morale, activated via Surge Action Order. Resolved by the Ability System. (Rule 250.4)
- **Surging**: The highest Morale state in the Morale State Component, enabling Surge Actions. (Rule 210.4)
- **System**: A squad of logic operating on Entities with specific Components. Systems read Component data, perform calculations, and write results back. (Rule 200.4)
- **Squad**: An Entity of the Squad archetype grouping Unit Entities, providing the collective interface through which Units engage with Zones and other Entities. (Rule 240.1)
- **Squad Keywords**: Marker Components describing a Squad's battlefield role. (Rule 200.3)
- **Value Component**: An integer Component on a Squad Entity representing overall strength for armybuilding, Roster validation, and scoring. (Rule 240.6)
- **Weapon**: An Item type that provides Attack Profile Components to the bearer, read by the Combat System's Attack Pipeline. (Rule 220.3)
- **Zone Component**: A state Component on an Entity identifying where it exists in the game's logical space, managed by the Zone System. (See Zones in Terminology)

---

## Implementation Notes

### Component Definitions

The engine represents each Component as a distinct data structure. The following lists the required Components for Entity System support:

**Core Components (all Entities)**:
- `IdComponent`: `{ id: string }` — globally unique within a game session
- `DisplayNameComponent`: `{ display_name: string }`
- `MarkerComponents`: `set<string>` — the Entity's Tags; case-sensitive string equality comparisons

**Statline Component (Unit archetype)**:
- `StatlineComponent`: `{ endurance: int, durability: int, morale: int, speed: int, reflex: int }`

**Unit-specific Components**:
- `EquippedItemsComponent`: `list<{ item_id: string, count: int }>`
- `DamageTakenComponent`: `{ value: int }` — sub-lethal damage accumulated
- `DestructionStateComponent`: `{ is_destroyed: bool }`

**Squad-specific Components**:
- `FactionKeywordsComponent`: `set<string>` — Faction marker Components
- `SquadKeywordsComponent`: `set<string>` — Squad role marker Components
- `CompositionComponent`: `list<{ unit_id: string, count: int }>`
- `UnitInstancesComponent`: `list<UnitEntityRef>` — one per actual Unit in the Squad
- `ValueComponent`: `{ value: int }` — base + selected options
- `AbilityRefsComponent`: `list<AbilityRef>`
- `MoraleStateComponent`: `{ state: enum(Broken, Poor, Neutral, Good, Surging), baseline: enum(default Neutral) }`
- `EnduranceRemainingComponent`: `{ value: int }`
- `ZoneComponent`: `{ zone: enum_or_ref(Battlefield, Reserves, Embarked, CasualtyReport, ConfirmedKIA) }`
- `TemporaryTagsComponent`: `set<{ tag: string, expiry: metadata }>`

**Item-specific Components**:
- `ItemTypeComponent`: `list<enum(weapon, armour, consumable, equipment)>`
- `ConsumableComponent`: `{ charges_remaining: int }`

**Attack Profile Component**:
- `AttackProfileComponent`: `{ id: string, display_name: string, category: enum(melee, ranged), range: { min: int?, short: int?, long: int?, max: int }, damage: { type: string, value: int, count: int }, modifiers: list<{ target: string, operation: enum(add, multiply), value: number }> }`

**Armour Component**:
- `ArmourComponent`: `{ value: int, armour_type: string, resistances: map<damage_type, int>, hit_modifiers: map<context, float> }`

**Commander-specific Components**:
- `ArmyRefComponent`: `{ army_id: string }`
- `IsDeployableComponent`: `{ deployable: bool }`

**Army-specific Components**:
- `CommanderRefComponent`: `{ commander_id: string }`
- `SquadRefsComponent`: `{ squad_ids: list<string> }`

**Battleforce-specific Components**:
- `ArmyRefComponent`: `{ army_id: string }`
- `SquadRefsComponent`: `{ squad_ids: list<string> }` — subset of Army's squads
- `TotalValueComponent`: `{ value: int }` — computed

### System Responsibilities

Each System reads and writes specific Components:

| System | Reads | Writes |
|---|---|---|
| **Zone System** | ZoneComponent, DestructionStateComponent | ZoneComponent |
| **Combat System** | StatlineComponent, AttackProfileComponent, ArmourComponent, ModifierData, DestructionStateComponent, DamageTakenComponent | DamageTakenComponent, DestructionStateComponent |
| **Morale System** | MoraleStateComponent, StatlineComponent (Morale Characteristic) | MoraleStateComponent |
| **Ability System** | AbilityRefsComponent, MoraleStateComponent, ZoneComponent, MarkerComponents | Varies by Ability effect |
| **Movement System** | StatlineComponent (Speed), ZoneComponent | Position data |

### Digital Implementation Considerations

- Entity IDs must be globally unique within a game session.
- Marker Component (Tag) comparisons are case-sensitive string equality checks.
- Derived values (Baseline Competence, Evasion Rating, Armour Value) are computed on demand by the relevant System, not stored as Components, to avoid stale values after modifications.
- Unit Options and Item Options are resolved during armybuilding; the engine stores the final Composition Component and Equipped Items Components, not the option selections. The option history may be stored separately for validation replay.
- The Composition Component (list of Unit references with counts) expands into individual Unit Entity instances at runtime. Each instance tracks its own DamageTakenComponent, DestructionStateComponent, and EquippedItemsComponent independently.
- Armour stacking: when a Unit has multiple Items with Armour Components, the Combat System sums Armour Values and sums Resistances per Damage Type, then applies Effective Armour in a single step during the Defense Pipeline.

### Relationship to Existing Data

The JSON data files in `src/data/` implement the Component structures defined by these rules:

| Rule Concept | JSON File | Key Fields |
|---|---|---|
| Squad archetype (rule 240.1) | `Squads.json` | id, display_name, faction_keywords, squad_keywords, characteristics, value, composition, abilities, unit_options, item_options |
| Unit archetype (rule 230.1) | `Units.json` | id, display_name, items |
| Item archetype (rule 220.1) | `Items.json` | id, display_name, item_types (weapon, armour, consumable) |
| Attack Profile Component (rule 220.4) | `Attacks.json` | id, category, range, damage (type, value, count) |

Note: `Squads.json` includes a `weapon_skill` field mapping skill categories to integer values. This field is not yet formalized in the Terminology or these rules; it likely represents per-category attack proficiency and should be reconciled with the Baseline Competence derivation (rule 210.7a) when Combat Resolution rules are drafted.

---

## Dependencies

This document defines foundational Entity structures and Components referenced by:

- **Battle Rules** (100-series): Uses Commander, Battleforce, and Squad archetypes; Statline, Zone, and Morale State Components.
- **Combat Resolution** (400-series, not yet drafted): Uses Attack Profile, Armour, Statline Components; Modifier data; Damage Types. Processed by the Combat System.
- **Movement and Positioning** (300-series): Uses Speed from Statline Component; Squad archetype; Zone Component. Processed by the Movement System.
- **Abilities and Effects** (500-series, not yet drafted): Uses Ability Components, marker Components, Statline Component. Processed by the Ability System.
- **Armybuilding** (within Campaign rules): Uses Value Component, Composition Component, Unit Options, Item Options, Rosters. Validated by the Zone System.

---

## Version History

| Version | Date | Changes |
|---|---|---|
| 0.1 | 2026-03-17 | Initial draft: Entities, Tags, Characteristics, Items, Attack Profiles, Units, Squads, Abilities, Commanders, Armies, Battleforces |
| 0.2 | 2026-03-18 | ECS rewrite: replaced Entity/Tag definitions with Entity/Component/System; redefined Tags as marker Components; introduced Statline Component, archetypes, System definitions; updated glossary and implementation notes with Component/System terminology |
| 0.3 | 2026-03-18 | Added Appendix A: ECS Architecture Reference — consolidated Component catalog, System catalog, Tag-to-marker-Component mapping, and archetype catalog (including Campaign-level archetypes) |
| 0.4 | 2026-03-18 | Added Appendix B: Tabletop Holdover Review — identified 8 tabletop-derived concepts (Datasheets, Bearer relationship, Tag Inheritance, State Inheritance, Armour Type label, Equipment constraints as prose, Roster-as-Zone, Unit-Squad resolution hybrid) with digital-native alternative proposals |

---

## Appendix A: ECS Architecture Reference

This appendix is the consolidated quick-reference for Simple War's Entity–Component–System architecture. It catalogs all Component types, Systems, the mapping from legacy Tag terminology to marker Components, and all archetypes (battle-level and campaign-level). This appendix is the canonical starting point for all ECS implementation tasks.

### A.1 Entity

An Entity is a unique identifier (ID). It has no inherent data or behavior. All properties, capabilities, and state come from attached Components. See rule 200.1.

### A.2 Component Catalog

Every Component is either a **Data Component** (holds structured state) or a **Marker Component** (presence-only keyword). The following tables list all Component types defined across Entity System Rules and Campaign Rules.

#### Core Components (all Entities)

| Component | Category | Description | Defining Rule |
|---|---|---|---|
| IdComponent | Data | Globally unique string identifier | 200.1 |
| DisplayNameComponent | Data | Human-readable label | 200.1 |
| MarkerComponents | Marker | Set of string keywords (Tags); case-sensitive | 200.3 |

#### Statline and Combat Components

| Component | Category | Attached To | Description | Defining Rule |
|---|---|---|---|---|
| StatlineComponent | Data | Unit, Commander | Endurance, Durability, Morale, Speed, Reflex (integers ≥ 0) | 210.1 |
| DamageTakenComponent | Data | Unit | Integer: sub-lethal damage accumulated | 230.1 |
| DestructionStateComponent | Data | Unit | Boolean: whether the Unit is destroyed | 230.1 |
| AttackProfileComponent | Data | Item (Weapon) | Category, Range Brackets, Damage Value/Type/Count, Modifiers | 220.4 |
| ArmourComponent | Data | Item (Armour) | Armour Value, Armour Type, Resistances, Hit Modifiers | 220.6 |

#### Equipment and Item Components

| Component | Category | Attached To | Description | Defining Rule |
|---|---|---|---|---|
| EquippedItemsComponent | Data | Unit, Commander | List of Item references with counts | 230.1 |
| ItemTypeComponent | Data | Item | List of types: Weapon, Armour, Consumable, Equipment | 220.2 |
| ConsumableComponent | Data | Item (Consumable) | Charges remaining | 220.10 |

#### Squad Components

| Component | Category | Attached To | Description | Defining Rule |
|---|---|---|---|---|
| FactionKeywordsComponent | Marker | Squad | Faction allegiance keywords | 240.1 |
| SquadKeywordsComponent | Marker | Squad | Battlefield role keywords | 240.1 |
| CompositionComponent | Data | Squad | Unit references with counts | 240.2 |
| UnitInstancesComponent | Data | Squad | Runtime list of Unit Entity references | 240.2 |
| ValueComponent | Data | Squad | Integer: armybuilding and scoring strength | 240.6 |
| AbilityRefsComponent | Data | Squad | List of Ability references | 250.1 |
| MoraleStateComponent | Data | Squad | Current Morale state + Morale Baseline | 210.4 |
| EnduranceRemainingComponent | Data | Squad | Integer: current Endurance pool | 240.1 |
| ZoneComponent | Data | Squad, Unit | Current Zone (Battlefield, Reserves, Embarked, Casualty Report, Confirmed KIA) | 200.4 |
| PositionComponent | Data | Squad, Unit | Grid coordinates on the Battlefield | Movement Rules (300-series) |
| TemporaryTagsComponent | Data | Squad | Tags with expiry metadata (Status Tags with duration) | — |

#### Organization Components

| Component | Category | Attached To | Description | Defining Rule |
|---|---|---|---|---|
| ArmyRefComponent | Data | Commander, Battleforce | Reference to the Army Entity | 260.1, 270.2 |
| CommanderRefComponent | Data | Army | Reference to the Commander Entity | 270.1 |
| SquadRefsComponent | Data | Army, Battleforce | List of Squad Entity references | 270.1, 270.2 |
| TotalValueComponent | Data | Battleforce | Computed sum of Squad Values | 270.2 |
| IsDeployableComponent | Data | Commander | Whether the Commander deploys as a Squad on the Battlefield | 260.1 |

#### Campaign Components

These Components are defined in Campaign Rules (800-series) for campaign-level Entities.

| Component | Category | Attached To | Description | Defining Rule |
|---|---|---|---|---|
| CampaignStageComponent | Data | Campaign | Current stage: Opening, Active Play, Conclusion | 800.2 |
| SectorMapRefComponent | Data | Campaign | Reference to the Sector Map Entity | 810.1 |
| ActivityRefComponent | Data | Plot | Reference to the Activity available at this Plot | 810.2 |
| OwnerComponent | Data | Plot | Player reference for Plot control | 810.6 |
| CapacityComponent | Data | Plot | Maximum simultaneous Commanders; null = unlimited | 810.2 |
| SourcePlotRefComponent | Data | Connection | Origin Plot reference | 810.3 |
| DestPlotRefComponent | Data | Connection | Destination Plot reference | 810.3 |
| TravelCostComponent | Data | Connection | Integer: Campaign Rounds to traverse | 810.3 |
| BidirectionalComponent | Data | Connection | Boolean: travel allowed in both directions | 810.3 |
| RequirementsComponent | Data | Connection, Activity | List of Conditions that must be met | 810.3, 820.1 |
| ActivityTypeComponent | Data | Activity | Armybuilding, Battle, Narrative Event, Travel, Trade, Custom | 820.1 |
| CompletionConditionsComponent | Data | Activity | Conditions determining when the Activity finishes | 820.1 |

### A.3 System Catalog

Systems contain all game logic. Each System operates on Entities possessing specific Components.

| System | Reads | Writes | Defining Rule |
|---|---|---|---|
| **Zone System** | ZoneComponent, DestructionStateComponent | ZoneComponent | 200.4 |
| **Combat System** | StatlineComponent, AttackProfileComponent, ArmourComponent, Modifier data, DestructionStateComponent, DamageTakenComponent | DamageTakenComponent, DestructionStateComponent | 200.4, 220.4 |
| **Morale System** | MoraleStateComponent, StatlineComponent (Morale) | MoraleStateComponent | 200.4, 210.4 |
| **Ability System** | AbilityRefsComponent, MoraleStateComponent, ZoneComponent, MarkerComponents | Varies by Ability effect | 200.4, 250.1 |
| **Movement System** | StatlineComponent (Speed), ZoneComponent, PositionComponent | PositionComponent | 200.4, 210.5 |
| **Deployment System** | ZoneComponent, PositionComponent, CompositionComponent | ZoneComponent, PositionComponent | Battle Rules 120-series |
| **Campaign System** | CampaignStageComponent, Commander position, ActivityRefComponent, RequirementsComponent | CampaignStageComponent, OwnerComponent, Activity status | Campaign Rules 800-series |

**Derived values** — computed on demand by Systems, never stored as Components:

| Value | Computed By | Derived From | Rule |
|---|---|---|---|
| Baseline Competence | Combat System | StatlineComponent (Endurance) | 210.7a |
| Evasion Rating | Combat System | StatlineComponent (Reflex, Speed) + situational modifiers | 210.7b |
| Armour Value | Combat System | Sum of equipped ArmourComponent values | 210.7c |

### A.4 Tag-to-Marker-Component Mapping

All Tags are marker Components. The following table maps Tag categories used in rule prose to their ECS representation.

| Rule-Prose Term | ECS Term | Persistence | Examples |
|---|---|---|---|
| Entity Tag | Marker Component (inherent) | Permanent; part of archetype definition | `Infantry`, `Vehicle`, `Monster`, `Commander`, `Army`, `Battleforce` |
| Status Tag | Marker Component (transient) | Temporary; set/cleared by Systems during play | `Running`, `Dug In`, `On Fire`, `Exposed`, `Decorated` |
| Faction Keyword | Marker Component (set) | Permanent per Squad definition | `Human`, `Xenos`, `Chaos` |
| Squad Keyword | Marker Component (set) | Permanent per Squad definition | `Infantry`, `Vehicle`, `Artillery`, `Recon` |
| Unit Keyword | Marker Component (set) | Permanent per Unit definition | `Heavy Weapon`, `Medic`, `Pilot` |
| Archetype Tag | Marker Component (inherent) | Permanent; identifies archetype membership | `Campaign`, `Sector Map`, `Plot`, `Connection`, `Activity` |

All marker Component comparisons use case-sensitive string equality (see rule 200.3).

### A.5 Archetype Catalog

An archetype is a conventional combination of Components defining a category of Entity. Archetypes are not enforced by the engine — they are naming conventions (see rule 200.5).

#### Battle-Level Archetypes

| Archetype | Characteristic Components | Archetype Marker | Defining Rule |
|---|---|---|---|
| **Unit** | StatlineComponent, EquippedItemsComponent, DamageTakenComponent, DestructionStateComponent | — | 230.1 |
| **Squad** | StatlineComponent, FactionKeywordsComponent, SquadKeywordsComponent, CompositionComponent, ValueComponent, ZoneComponent, MoraleStateComponent, EnduranceRemainingComponent | — | 240.1 |
| **Item** | ItemTypeComponent; optionally AttackProfileComponent, ArmourComponent, ConsumableComponent | — | 220.1 |
| **Commander** | StatlineComponent, EquippedItemsComponent, ArmyRefComponent | `Commander` | 260.1 |
| **Army** | CommanderRefComponent, SquadRefsComponent | `Army` | 270.1 |
| **Battleforce** | ArmyRefComponent, SquadRefsComponent, TotalValueComponent | `Battleforce` | 270.2 |

#### Campaign-Level Archetypes

| Archetype | Characteristic Components | Archetype Marker | Defining Rule |
|---|---|---|---|
| **Campaign** | CampaignStageComponent, SectorMapRefComponent, Objectives, Scoring Rules | `Campaign` | 800.1 |
| **Sector Map** | Plot references, Connection references | `Sector Map` | 810.1 |
| **Plot** | DisplayNameComponent, ActivityRefComponent | `Plot` | 810.2 |
| **Connection** | SourcePlotRefComponent, DestPlotRefComponent, TravelCostComponent, BidirectionalComponent | `Connection` | 810.3 |
| **Activity** | ActivityTypeComponent, CompletionConditionsComponent | `Activity` | 820.1 |

#### Non-Entity Objects

The following participate in the game but are **not** Entities and have no Components:

| Object | Role | Rationale |
|---|---|---|
| Campaign Resource | Bookkeeping value per Player (Credits, Influence) | Explicitly not an Entity (rule 825.1) |
| Score | Integer accumulator per Player | Bookkeeping value, not a game object |
| Deployment (process) | Temporal stage of Battle resolution | Process, not a persistent object |
| Damage Instance | Intermediate data in the Combat System pipeline | Transient data between Attack and Defense Pipelines |

---

## Appendix B: Tabletop Holdover Review

This appendix catalogs concepts in Entity System Rules that originate from tabletop wargaming conventions and may not translate cleanly to a digital-native ECS implementation. For each holdover, a digital-native alternative is proposed. Each item has a corresponding follow-up bead for detailed resolution.

### B.1 Datasheets (Rule 240.5)

**Holdover**: A Datasheet is defined as "a comprehensive reference document for a Squad." This is a printed reference card concept from tabletop wargaming — a physical artifact Players hold in hand during play.

**Problem in digital**: In a digital implementation, the Datasheet is a dynamically-generated UI view, not a rules-level concept. Defining what a Datasheet "contains" is a presentation specification, not a game rule. No System reads or writes a Datasheet; it is purely a projection of existing Component data.

**Proposed alternative**: Reclassify Datasheets as a **UI specification** rather than a game rule. Remove rule 240.5 from Entity System Rules and relocate the field list to a UI/presentation document. Any rule that references "a Unit's Datasheet" should reference the Unit's Components directly. The Terminology entry for Datasheets should describe them as a convenience view, not a game object.

### B.2 Bearer Relationship (Rule 230.2)

**Holdover**: The "Bearer" relationship is a named concept from tabletop wargaming ("the bearer of this weapon gains..."). Rule 230.2 defines four properties of this relationship, but in ECS terms, "bearing" an Item is simply having a reference to it in the Unit's EquippedItemsComponent.

**Problem in digital**: The Bearer abstraction introduces indirection. Systems must understand that "Bearer" means "the Entity whose EquippedItemsComponent references this Item" — a concept that ECS already handles through Component references. The four Bearer rules (access to Item Components, no automatic tag inheritance, multiple Items allowed, Items lost on destruction) are either standard ECS reference semantics or should be stated as general principles.

**Proposed alternative**: Replace the Bearer relationship with **explicit Component reference semantics**:
- Point 1 (access to Item Components): Standard behavior — Systems resolve references in EquippedItemsComponent to read Item Components.
- Point 2 (no tag inheritance from Items): State as a general ECS principle: "Marker Components on a referenced Entity do not propagate to the referencing Entity unless a rule explicitly states otherwise."
- Point 3 (multiple Items): Already implicit in EquippedItemsComponent being a list.
- Point 4 (Items on destruction): Define as a Zone System behavior: "When the Zone System transitions a Unit to Casualty Report, the Unit's EquippedItemsComponent is preserved for reporting but Items are no longer accessible to other Systems."

Retain "Bearer" as a **glossary convenience term** (like "archetype") rather than a rules-level relationship.

### B.3 Tag Inheritance (Rule 240.3)

**Holdover**: "A Squad inherits all marker Components from all Units in the Squad." In tabletop, you cannot efficiently query every Unit in a Squad; you need the Squad itself to "have" the tag so you can check once. This is a physical-play optimization.

**Problem in digital**: Automatic tag propagation creates implicit state changes. When the Combat System destroys a Unit, the tag inheritance rule requires recalculating the Squad's effective marker Component set — a side effect that crosses System boundaries. It also creates unexpected behavior: a single special Unit (e.g., a Medic with the `Medic` marker Component) makes the entire Squad "have" the `Medic` tag, which may cause rules to apply at the Squad level that were intended for the Unit level.

**Proposed alternative**: Replace tag inheritance with **System-level queries**. Instead of "Squads with the Infantry tag," rules should target "Squads containing at least one Unit with the `Infantry` marker Component." Systems perform this query against Unit Components directly. This:
- Eliminates implicit state propagation
- Makes rule targeting explicit (does the rule care about "any Unit" or "all Units"?)
- Removes the recalculation requirement on Unit destruction
- Allows rules to distinguish "Squad where any Unit has tag X" from "Squad where all Units have tag X"

If Squad-level tags are needed for performance in the digital implementation, they can be maintained as a **computed cache** (like derived values in rule 210.7) rather than a rules-level inheritance mechanism.

### B.4 State Inheritance (Rule 240.4)

**Holdover**: "A Squad can inherit states from its Units when all Units share that state." The primary example is destruction: a Squad is destroyed only when all its Units are destroyed. This is a tabletop convention where you remove the last unit from the base and declare the squad destroyed.

**Problem in digital**: State inheritance is an aggregation rule disguised as an inheritance rule. In ECS, Systems should compute aggregate state on demand rather than propagating state between Entity levels. The current rule only gives one example ("destroyed") and says other cases exist but doesn't enumerate them, leaving the scope of state inheritance undefined.

**Proposed alternative**: Replace state inheritance with **explicit System aggregation rules**. For each state that can be "inherited":
- **Destruction**: "The Zone System transitions a Squad's Zone Component to Casualty Report when `all(unit.DestructionStateComponent.is_destroyed for unit in squad.units)` evaluates to true." This is a Zone System behavior, not an Entity-level inheritance rule.
- Enumerate all other inheritable states (if any exist) and define them as explicit System conditions.

This makes the aggregation logic visible in the System definition rather than hidden in a generic inheritance rule.

### B.5 Armour Type as Descriptive Label (Rule 220.6)

**Holdover**: The Armour Component requires an `armour_type: string` described as a "Descriptive label for the armour category (e.g., composite, heavy_plate, energy_shield)." This is a tabletop convention where armour categories are listed for flavor and loose rule interactions ("affects units wearing power armour").

**Problem in digital**: A required field with no defined mechanical effect is dead data. No System reads `armour_type` to make decisions. If it exists only for display, it belongs in the presentation layer, not as a required Component property. If it should have mechanical meaning (e.g., certain Abilities target specific armour types), that interaction is undefined.

**Proposed alternative**: Either:
- **(a) Remove** `armour_type` from the Armour Component and relocate to DisplayNameComponent or a flavor metadata field.
- **(b) Promote to marker Component**: If rules need to target armour by type, make armour types marker Components on the Item Entity (e.g., `Heavy Plate` marker Component). Systems can then query Items by marker Component.
- **(c) Define mechanical interactions**: Specify how `armour_type` is used by the Combat System or Ability System (e.g., "Abilities may reference `armour_type` to apply conditional effects").

### B.6 Equipment Constraints as Prose (Rules 230.2, 240.2)

**Holdover**: Equipment limitations are described in informal prose: "Equipment categories (e.g., 'a Unit may equip at most one Item with a heavy_plate Armour Component') are defined by the Squad's Composition rules or by Item-specific restrictions." This mirrors tabletop datasheets where equipment limits are stated in natural language footnotes.

**Problem in digital**: Prose-defined constraints are not machine-readable. A System cannot validate equipment legality without a human-authored parser for each constraint variant. The constraints are scattered across Squad Composition rules and Item definitions with no standard format.

**Proposed alternative**: Formalize equipment constraints as **Components or structured data**:
- An `EquipmentConstraintsComponent` on Squad or Unit Entities defining slot limits, mutual exclusions, and type restrictions in a structured format (e.g., `{ max_armour: 1, max_heavy_weapon: 1, excluded_combinations: [...] }`).
- Alternatively, an `EquipmentSlotComponent` system where each Unit has named slots with type constraints, and Items declare which slots they occupy.
- A dedicated **Equipment Validation System** reads these Components to enforce legality during armybuilding and equipment changes.

### B.7 Roster as Zone (Rule 270.3)

**Holdover**: "A Roster is a Zone that organizes Battleforces by validating them against a set of requirements." This conflates two distinct concepts: a Zone (where an Entity exists in logical space) and a validation schema (a set of constraints a Battleforce must satisfy).

**Problem in digital**: Zones are state — they answer "where is this Entity?" Rosters are validation — they answer "does this Battleforce meet these requirements?" Treating Rosters as Zones means a Battleforce's "location" is its validation status, which is semantically incorrect. A Battleforce doesn't "exist in" a Roster the way a Squad exists on the Battlefield.

**Proposed alternative**: Separate Rosters from Zones:
- A Roster is a **Validation Schema Entity** — an Entity with a `RosterRequirementsComponent` defining constraints (value range, keyword filters, composition rules).
- A Battleforce has a `RosterValidationComponent` listing which Rosters it currently satisfies, maintained by a **Roster Validation System** (or the existing Zone System in a validation role).
- The Zone System continues to manage physical/logical state (Battlefield, Reserves, etc.). Roster validation becomes a distinct concern, queryable but not conflated with spatial/state Zones.

### B.8 Unit-Squad Resolution Hybrid

**Holdover**: Orders are issued to Squads (rule 132.1 in Battle Rules), but the Combat System resolves attacks Unit-by-Unit (rule 133.5). Position is tracked at the Squad level (PositionComponent on Squad), with Units having RelativePositionComponents within the Squad's formation. This hybrid exists because tabletop games move squad bases as a group but track individual unit casualties with removable miniatures.

**Problem in digital**: The split creates complexity in the ECS architecture. The Combat System must distribute Squad-level attack Orders to Unit-level targets, resolve per-Unit, then aggregate results back to the Squad level for Morale and Zone transitions. Position is managed at two levels (Squad absolute, Unit relative). Systems must constantly bridge the Squad/Unit boundary.

**Proposed alternative**: This is more a design review than a direct holdover fix. Three options:
- **(a) Keep as-is, but justify**: Document why the two-level resolution exists as a deliberate design choice (per-Unit casualties create tactical depth; Squad-level Orders keep cognitive load manageable). Add this rationale to the design document.
- **(b) Fully Squad-level**: Abstract away individual Units. Squads have a "strength" or "unit count" value that decrements as damage accumulates. Simpler but loses per-Unit equipment variety and targeted attacks.
- **(c) Fully Unit-level**: Each Unit has its own Order. Maximum tactical depth but likely too complex for Players to manage.

Option (a) is recommended, with explicit documentation of the design rationale and clear System responsibility boundaries for the Squad/Unit bridge.
