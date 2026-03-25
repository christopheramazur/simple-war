# Simple War Terminology

> **Status**: Authoritative Source
> **Last Updated**: 2026-03-18
>
> This is the single canonical terminology reference for Simple War. All GDD sections, rule documents, and implementation code should reference terms as defined here. The Overview folder contains a redirect pointing here.

---

# Players
Players are the acting participants in the game. A Player is any participant — the owning participant and all opposing participants. Other actors may also be Players in certain contexts. In ECS terms, a Player is an Entity with Player-related Components (Faction, Relationships, owned Armies).

# Architecture: Entity–Component–System (ECS)

Simple War uses an Entity–Component–System architecture. Understanding these three concepts is essential for reading all rules and implementation documents.

- **Entity**: A unique identifier (ID) in the game world. An Entity has no inherent data or behavior — all of its properties, capabilities, and state are defined by the Components attached to it.
- **Component**: A data structure attached to an Entity. Components hold state (e.g., a Statline Component holds Endurance, Durability, Morale, Speed, Reflex). An Entity's set of Components determines what it is and how it participates in the game.
- **System**: A squad of logic that operates on Entities that have a specific set of Components. Systems read Component data, perform calculations, and write results back to Components. For example, the Combat System reads Attack Profile and Statline Components to produce Damage Instances, and the Zone System manages transitions between Zones.

An **archetype** is a common combination of Components that defines a category of Entity. Squads, Units, Items, Commanders, Armies, and Battleforces are all archetypes — each has a characteristic set of Components described in the Entity System Rules (section 200–270).

## Examples of Entities and Non-Entity Objects
A Campaign is an Entity. The Battlefield is an Entity. Armies are Entities. Squads are Entities. Units, Weapons, and most Squad interactions are Entities. The Roster system is not an Entity. Score is not an Entity. Deployment (the process) is not an Entity.

# Tags

Tags are **marker Components** — Components that carry no data beyond their presence. Tags are attached to Entities to provide keywords that group and differentiate Entities when determining whether rules affect them.

Tags are classified into the following categories (see rule 200.3 in Entity System Rules):

- **Entity Tags** identify what is inherent to an Entity, such as an Infantry Unit having the Infantry Tag.
- **Status Tags** identify effects which are not inherent to an Entity, communicating events such as "This Entity was ordered to Run" or "This Entity is on fire."

Rules that reference a Tag always specify the exact Tag name. A rule that says "Squads with the Infantry tag" affects only Entities that have the `Infantry` marker Component.

## Referencing Entities
When a rule needs to describe relationships between Entities from a particular Entity's perspective, the following reference terminology is used (see rule 200.6 in Entity System Rules):

**Own** is used to indicate Entities that belong to the reference Entity.
**Other** is used to indicate Entities that do not belong to the reference Entity.
**Any** is used to indicate all Entities.

Terms involving Faction Relationships such as Friendly, Allied, Enemy, Neutral are used to indicate Entities that belong to the Faction Relationships of the Faction the reference Entity belongs to. Faction Relationships are not bilateral; a Player may be an Enemy of a Faction that Player deems Friendly. Faction Relationships are revealed to all Players in the Planning Stage of a Battle (see rule 110.6 in Battle Rules). Some rules may allow Faction Relationships to update during the Engagement Stage; those rules dictate how and when this is done and revealed, and how other Players are allowed to react.

# Zones

A Zone is a state Component on an Entity that identifies where the Entity exists in the game's logical space. The **Zone System** manages transitions between Zones, enforcing state-change rules and notifying other Systems when an Entity's Zone changes. Entities are added to or removed from Zones to indicate something about their state having changed in ways that Players should be aware of. Example Zones include "on the Battlefield" and "in a Transport".

## In Play
Being In Play is the base Zone state for all Entities participating in a Campaign. When Players begin a Campaign, they are In Play, that Campaign is In Play, the Rosters and Armies they are adding to the Campaign are added In Play. Entities In Play are able to reference and be referenced by other Entities and rules.

## Removed from Play
When an Entity is Removed from Play, the Zone System strips it of the ability to reference other Entities or rules, including itself and its own rules. Its Zone Component can never change again. If an Entity was Removed from Play during a Battle, after that Battle's Consolidation, the Zone System removes all references to the Entity from all Entities and Zones.

## Battlefield
The primary Zone where most of a Player's time will be spent. When an Entity's Zone Component is set to Battlefield, that Entity is said to be "on the Battlefield".

## Reserves
Entities whose Zone Component is set to Reserves are waiting to enter the Battlefield. Different Reserves rules further inform Players how and when Squads in Reserves will enter the Battlefield.

## Embarked
Entities whose Zone Component is set to Embarked are within another Entity that is a Transport or fortification. Entities Embarked in an Entity that is in Reserves are also in Reserves, but Entities that are Embarked elsewhere are handled case by case. An example of this is that Entities Embarked within an Entity on the Battlefield are still simply Embarked, not on the Battlefield. Entities can only disembark if they are Embarked, and if the Entity they are Embarked in is on the Battlefield. Explicit rules for the process of embarking and disembarking will cover this, as well as the case for disembarking from an Entity that has been destroyed or Removed from Play.

## Casualty Report
When Entities are destroyed, the Zone System transitions them to the Casualty Report. The way an Entity is destroyed can contribute to the state it is recorded in, which can affect how it is returned to action. Many Entities have methods of returning to the Battlefield or Reserves from the Casualty Report. If an Entity enters the Casualty Report during a Battle, after that Battle's Consolidation, Campaign-level rules address that Squad's continued service (see rule 822.5 in Campaign Rules).

## Confirmed KIA
When Entities are Confirmed KIA, they can no longer reference other Entities or rules. They have not necessarily been Removed from Play, but the Zone System permits transition out of this Zone only by a small number of rules.

## Rosters
Rosters are Zones that organize Battleforces. The Zone System validates Battleforces against Roster requirements; a Battleforce can be listed in any Roster whose requirements it meets. The default Roster has no requirements. Campaigns, tournaments, and companion rules may add Rosters with specific requirements and restrictions that Battleforces must be validated against in order to be listed in (see rule 270.3 in Entity System Rules).

## Zones and State
The Zone System enforces state consistency. If a Squad becomes destroyed, the Zone System transitions that Squad to the Casualty Report. If a Squad is not destroyed, it should not be in the Casualty Report. Exceptions to this management of state will be explicit and specific.

# Commanders
Commanders are Entities of the Commander archetype — their Components include a Statline, Equipment, Abilities, and an Army reference. Players attach Armies to Commanders in order to participate in different Campaign Activities. In Simple War, Commanders are used like in Heroes of Might and Magic; the Player accesses a Battleforce through the Commander that is leading that Army. Commanders move on the Sector Map based on their own Characteristics in order to engage in Activities (see rule 260.1 in Entity System Rules). A Player can have multiple Commanders, and each Commander can have access to a large Army from which to field Battleforces.

# Armies
Armies are Entities of the Army archetype — their Components include a Commander reference and a list of Squad references. Armies keep track of all the Squads a Player's Commander has rallied. Armies inherit all of the Tags (marker Components) of the Squads in them (see rule 270.1 in Entity System Rules).

# Battleforces
Battleforces are Entities of the Battleforce archetype — a subset of an Army's Squads selected for a specific Battle. If the Army is all of the Squads available to a Commander, the Battleforce is what the Commander fields for a given Battle (see rule 270.2 in Entity System Rules).

# Squads
Squads are Entities of the Squad archetype — their Components include a Statline, Faction Keywords, Squad Keywords, Composition, Abilities, Value, and a Zone Component. Squads group Units, providing the interface that defines how those Units collectively engage with Zones and other Entities. Squads inherit all of the Tags (marker Components) of the Units in them. Squads can also inherit states from Units, if all of the Units in that Squad are in that state. An example of this is "destroyed" — a Squad is not destroyed until every Unit in that Squad is destroyed (see rule 240.1 in Entity System Rules).

## Statline
The Statline Component holds the basic Characteristics shared by Units in a Squad: Endurance, Durability, Morale, Speed, and Reflex. These Characteristics are innate to each Unit (see rule 210.1 in Entity System Rules). Units in a Squad may have different values for these; the Combat System operates at the Unit level, using each individual Unit's own Statline values.

The Statline can be modified by Item Components, Ability Components, and rules affecting the Unit or the Unit's Squad. The Statline is used in combination with Tags (marker Components) and Abilities to inform Systems of a Unit's capabilities. An example: a Unit with a Speed of 6 moves 6 distance squads under a standard Advance Order, but if the Unit has access to jet packs, that Speed of 6 is not fully indicative of the Unit's manoeuvrability. Similarly, a Unit with low Endurance but powerful Armour may take a long time to destroy.

### Endurance
During an Engagement, Squads take actions which may tax their Endurance. Running for multiple Turns in a row, fighting a prolonged Melee, digging tunnels, and other acts of extreme exertion reduce a Squad's Endurance. When a Squad has no remaining Endurance, that Squad can no longer perform actions that would tax it. Endurance recovers when Squads take actions that do not tax it (see rule 210.2 in Entity System Rules).

### Durability
When a Squad takes an instance of damage, the Combat System tracks it against the Unit closest to the source of the damage. When the damage matches or exceeds that Unit's Durability, that Unit is destroyed. A single instance of damage can only destroy one Unit from a Squad, even if it greatly exceeds that Unit's Durability (see rule 210.3 in Entity System Rules).

### Morale
A combination of Characteristic (in the Statline Component) and state (a separate Morale State Component). The **Morale System** manages state transitions: when a Squad's Morale is tested against the Characteristic, the state can worsen, stay Neutral, or improve. The states are Broken, Poor, Neutral, Good, and Surging. The Morale Characteristic determines how well a Squad handles these tests. Squads with Broken Morale may not Charge, capture Objectives, or perform Surge Actions (see rule 132.4 in Battle Rules). Squads with Good or Surging Morale perform better at those activities. A Surging Squad can be prompted to perform a Surge Action. The Morale System moves state one stage toward the Squad's Morale Baseline each Turn, and resets after a Surge (see rule 210.4 in Entity System Rules).

### Speed
The standard movement distance a Squad can maintain without taxing Endurance. The Movement System reads Speed from the Statline Component. Moving at high Speeds contributes to Evasion Rating (see rule 210.5 in Entity System Rules).

### Reflex
Used when reacting, or responding to events out of sequence. Determines how effective Evasion Rating is (see rule 210.6 in Entity System Rules).

### Evasion Rating
A derived value computed by the Combat System from a Unit's Reflex, Speed, and situational modifiers. Evasion allows a Squad to make an out-of-sequence movement Reaction, limited by how evasive the Squad is, and how successful the Reaction is (see rule 210.7b in Entity System Rules).

## Squad Abilities
One of the defining features of a Squad is that Squads are more than the sum of their parts. This is expressed through Ability Components attached to the Squad. A Squad has a Passive Ability, an Active Ability, and a Surge Ability. Some Squads may have more or fewer, or have Abilities accessible by purchasing Items or being in certain configurations of Army. The **Ability System** evaluates Ability Components during the appropriate timing windows (see rule 250.1 in Entity System Rules).

## Squad Composition
The Composition Component defines which Units make up a Squad and in what quantities. The Units that can be in a Squad, and the Items those Units can be configured with, are defined along with the values of those Items in the Squad's Composition (see rule 240.2 in Entity System Rules).

## Datasheets
Comprehensive Squad reference for Player convenience. Contains information about the Squad's Composition options, Characteristics, Value, availability, equipment, Abilities, and restrictions (see rule 240.5 in Entity System Rules). 

# Units
Units are Entities of the Unit archetype — their Components include a Statline, Equipped Items, and destruction state. Units define how a Squad's baseline capability declines as it takes casualties. Each Unit represents and contributes to the Squad's ability to affect an Engagement. Units are the most granular interactive Entities in Simple War (see rule 230.1 in Entity System Rules).

## Equipping Items
Items are Entities of the Item archetype — their Components include Item Type, and optionally Attack Profile, Armour, Consumable charges, or Equipment modifiers. Items provide additional rules by being equipped to a Unit. Units can be equipped with more than one Item, but equipment categories may prevent a Unit from equipping all of the Items available to it at any given time. When a Unit is equipped with an Item, that Unit is said to be that Item's Bearer. Units do not gain the Tags (marker Components) of Items they are equipped with innately, though some Items can confer Tags to their Bearer or Bearer's Squad (see rule 230.2 in Entity System Rules).

## Weapons and Armour
Some of the most important Item archetypes a Unit can equip. Weapon Components provide Attack Profiles to the Combat System; Armour Components provide damage reduction through the Defense Pipeline. In most cases, Units in a Squad will be equipped with the same Weapons and Armour, but it is not uncommon to encounter variety in loadouts (see rules 220.3 and 220.6 in Entity System Rules).

### Weapon Characteristics
Weapons provide Attack Profile Components to the Units that equip them. A single Weapon can provide multiple Attack Profiles (for example, a rifle may have both a ranged "Fire" profile and a melee "Bayonet" profile). Each Attack Profile Component defines its own Category, Range, Damage Value, and Damage Type (see rule 220.3 in Entity System Rules).

#### Attack Profiles
An Attack Profile Component describes a single way a Weapon can be used. It includes:
- **Category**: melee or ranged, determining which engagement contexts the Attack Profile can be used in.
- **Range**: for ranged attacks, expressed as Min, Short, Long, Max. The range between Short and Long is the Effective Range, which does not incur a range-based penalty. The ranges between Min and Short, and between Long and Max, incur penalties. Attacks cannot target Units within Min or beyond Max range. For melee attacks, Range is limited to close proximity.
- **Damage Value**: the base damage produced on a successful hit.
- **Damage Type**: the category of damage (Kinetic, Concussive, Energy, etc.), which interacts with Armour Resistances.
- **Modifiers**: optional flat or multiplicative adjustments to damage or hit probability.

See rule 220.4 in Entity System Rules.

#### Damage
Each successful attack produces a Damage Instance — an intermediate data object with a value and a type. The Combat System resolves Damage Instances individually against the target Unit through the Defense Pipeline.

#### Modifiers
Attack Profile Components and Item Components can carry Modifier data that adjusts hit probability, Damage Value, or Armour interaction. The Combat System applies Modifiers during the relevant step of the pipeline (see rule 220.9 in Entity System Rules).

# Timings

Timings describe **when** things happen in Simple War and in what order. At this level the focus is on the order of Stages, Phases, and Turns rather than the detailed rules of each action.

- **Stage**: A large section of a Battle (Planning, Deployment, Engagement, Consolidation). Stages always happen in this order (see rule 100.2 in Battle Rules).
- **Turn**: A repeating slice of time inside the Engagement Stage. Each Turn is resolved using the true simultaneous turn system (see rule 130.2 in Battle Rules).
- **Phase**: A sub-part of a Turn (for example: Rally, Issue Orders, Execute, Resolve Combat). Phases give structure to what Players can do on each Turn (see rule 130.3 in Battle Rules).

In the barebones implementation, the engine's **Battle System** needs to:

- Track which Stage the Battle is in (as a Component on the Battle Entity).
- Advance from one Stage to the next in order.
- Run a Turn loop during Engagement, with a fixed set of Phases processed by the relevant Systems.

# Armybuilding

Armybuilding is the process of assembling a legal force that a Player can bring to a Battle or Campaign. This section stays high level; detailed construction rules live in the Army and Faction documents.

## Faction Keywords
Faction Keywords are marker Components that identify which broad force or allegiance a Squad belongs to (for example: a political bloc, species, or military organization). They are used to enforce Roster restrictions, determine which rules apply, and connect Squads to specific Campaigns or scenarios.

## Characters
Characters are special Squads or Units that represent leaders, heroes, or key specialists. They often unlock additional rules, modify other Squads, or serve as focal points for Objectives. Roster and Campaign rules can require or limit Characters.

## Squad Keywords
Squad Keywords are marker Components that describe battlefield roles and capabilities (for example: Infantry, Vehicle, Artillery, Recon). They help Systems target the right Squads and give structure to how different forces are composed without hard-coding specific factions.

## Unit Keywords
Unit Keywords are marker Components that capture more granular traits at the Unit level (for example: Heavy Weapon, Medic, Pilot). They modify how Units interact with their Squad, equipment, and battlefield actions while still rolling up into the Squad’s overall behavior.

## Equipment Costs
Equipment Costs express how much it “costs” to equip Units and Squads with Weapons, Armour, and other gear when building an Army. At this overview level it is enough to know that:

- Each option has an associated cost.
- Battleforces and Rosters can impose caps or bands on total cost.
- The system is designed so different Campaigns can reinterpret or tweak costs without changing the underlying data structures.

# Combat Resolution
The **Combat System** simulates combat at the Unit level. Individual Units make attacks against individual target Units, with the Combat System resolving each interaction transparently. Squads serve as groupings that determine which Units attack which targets (closest Units in the target Squad), but the Combat System processes resolution Unit-by-Unit.

The Combat System pipeline is separated into two independent stages: **Making Attacks** and **Being Attacked**. The attack stage reads attacker Components (Statline, Attack Profiles, Modifiers) and produces Damage Instances as intermediate data. The defense stage reads target Components (Statline, Armour, Resistances) and consumes those Damage Instances. The Morale System, Ability System, and other reactive Systems observe combat results downstream and are not part of the core Combat System pipeline.

A Unit's Datasheet shows its baseline combat Characteristics, determined by its default Items before any options are chosen for it.

## Combat Characteristics

These values are derived by the Combat System from Component data; they are not stored as Components themselves but computed on demand:

- **Baseline Competence**: derived from the Statline Component's Endurance. Represents the Unit's general effectiveness when making attacks (see rule 210.7a in Entity System Rules).
- **Evasion Rating**: derived from the Statline Component's Reflex and Speed, plus situational modifiers (Status Tags, terrain). Represents how difficult the Unit is to hit (see rule 210.7b in Entity System Rules).
- **Armour Value**: derived from equipped Armour Item Components. Reduces incoming damage after a hit is confirmed (see rule 210.7c in Entity System Rules).
- **Armour Resistances**: per-Damage-Type modifiers on Armour Components (for example, composite Armour may resist Kinetic damage but be weak to Concussive). See rule 220.7 in Entity System Rules.

## Making Attacks (Attack Pipeline)

The Combat System reads attacker Components and produces Damage Instances. Each attacking Unit resolves its attacks individually:

1. The Combat System selects an Attack Profile Component from the Unit's equipped Weapon(s) based on context (range to target, Attack Category).
2. The Combat System distributes the Unit's attacks to target Units in the target Squad, closest first.
3. For each attack, hit probability is computed from Component data: attacker's Baseline Competence (derived from Statline) + Weapon Modifiers − target's Evasion Rating (derived from Statline and situational modifiers). Hit probability has a floor of 5% and a ceiling of 95%, ensuring unlikely outcomes are always possible.
4. On a successful hit, the Combat System produces a **Damage Instance** — an intermediate data object containing the Damage Value, Damage Type, and source metadata.

See rule 133.5 in Battle Rules.

## Being Attacked (Defense Pipeline)

The Combat System reads target Components and consumes Damage Instances. Each target Unit resolves incoming damage individually:

1. The Unit receives one or more Damage Instances from the Attack Pipeline.
2. Each instance is mitigated by the Unit's Armour Value Component, adjusted by the Armour's Resistance to the Damage Type.
3. If mitigated damage meets or exceeds the Unit's Durability (from the Statline Component), that Unit is destroyed.
4. A single Damage Instance can only destroy one Unit; overkill does not carry over to the next Unit.
5. Sub-lethal damage is tracked on the Unit's damage Component for future resolution.

## Damage Types

Damage Types categorize the nature of damage produced by the Attack Pipeline and interact with Armour Resistance Components in the Defense Pipeline:

- **Kinetic**: physical impact damage (bullets, blades). Armour with Resistance 0 for Kinetic provides its full Armour Value.
- **Concussive**: blast and shockwave damage (explosions, grenades). Many Armour types have negative Resistance to Concussive, reducing effective protection.
- **Energy**: directed energy damage (arcane blasts, plasma). Armour Resistance to Energy varies widely: some Armour types are highly resistant, others are vulnerable.

Additional Damage Types can be introduced as needed. Each Armour Component defines its Resistance modifier per Damage Type (see rule 220.8 in Entity System Rules).

# Fighting a Battle

Fighting a Battle is how Simple War resolves direct conflict between Armies. The Battle is divided into Stages (Planning, Deployment, Engagement, Consolidation), and within Engagement into Turns and Phases. See Battle Rules (rules 100.1–150.1) for full details.

## Planning
Composing Battleforces, designating Transports, Reserves, and Vanguard, and revealing Faction Relationships. See rules 110.1–110.6 in Battle Rules.

## Deployment
Placing Squads on the Battlefield within Deployment Zones, including Vanguard deployment and Pre-Engagement Moves. See rules 120.1–120.4 in Battle Rules.

## Engagement
The core of a Battle. Players command Squads through a repeating cycle of Turns using the true simultaneous turn system. See rules 130.1–134.1 in Battle Rules.

### The Turn System
Each Turn proceeds through four Phases: Rally, Issue Orders, Execute, Resolve Combat (see rule 130.3 in Battle Rules).

### The Order System

Simple War uses a **true simultaneous turn** system. During the Issue Orders Phase, Players give hidden Orders to their Squads, then reveal and resolve those Orders together. This keeps Battles dynamic and reduces “I-go-you-go” downtime while remaining deterministic and computable for the digital engine. See rules 132.1–132.4 in Battle Rules.

### Reactions
After Orders are revealed, eligible Squads may declare Reactions: Reposition, Evade, or Return Fire. See rules 133.3a–133.3c in Battle Rules.

### Surge Actions
A Squad with Surging Morale may perform a Surge Action. See rule 132.2h in Battle Rules.

## Consolidation
Determining the Victor, processing Scoring, handling Casualties. See rules 140.1–140.5 in Battle Rules.

# The Generic Campaign
The minimal Campaign template: default Roster, configurable Activities, Campaign-defined Objectives and Scoring. See rule 860.1 in Campaign Rules.


