# Players
Players are the acting participants in the game. This will typically be you and your opponents, but may occasionally include other actors.

# Entities
An entity is any object that has tags attached to it. Entities can have names and other rules, or not – the only requirement to be an entity is that they are a tagged object. 

## Examples of Entities and Non-Entity Objects
A campaign is an entity. The battlefield is an entity. Armies are entities. Units are entities. Models, weapons, and most unit interactions are entities. The roster system is not an entity. Score is not an entity. Deployment is not an entity. Players are entities with the Player tag.

# Tags
Tags are metadata attached to objects that provide keywords. Keywords are used to group and differentiate entities when determining whether rules affect them or not.

## Referencing Objects
Sometimes we need to refer to something without tags. The most usual case for this is when that reference relies on an object's perspective. The following reference terminology is used in these cases:

Own is used to indicate objects that belong to the reference object.
Other is used to indicate objects that don't belong to the reference object.
Any is used to indicate all objects.

Terms involving faction relationships such as friendly, allied, enemy, neutral, etc. are used to indicate objects that belong to the faction relationships of the faction the reference object belongs to. Faction relationships are not bilateral; you may be an enemy of a faction you deem friendly. Faction relationships are revealed to all players in the Planning stage of a battle. Some rules may allow faction relationships to update during the engagement stage; these rules will dictate how and when this is done and revealed, and how other players are allowed to react. 

# Zones
Zones are used like Tags to help group and differentiate entities. Entities are added to or removed from zones to indicate something about their state having changed in ways that players should be aware of. Example zones may be "on the battlefield" or "in a transport".

## In Play
Being in play is the base state for all objects participating in a campaign. When players begin a campaign, they are in play, that campaign is in play, the rosters and armies they are adding to the campaign are added in play. Objects in play are able to reference and be referenced by other objects and rules. 

## Removed from Play
When an object is removed from play, it may no longer reference objects or rules, including itself and its own rules. It can never change zones. If an object was removed from play during a battle, after that battle's consolidation, remove references to the object from all objects and zones. 

## Battlefield
The primary zone where most of a player's time will be spent. This zone is referenced with language such as "on the battlefield".

## Reserves
Objects that are waiting to enter the battlefield are said to be "in reserves". There are different reserves rules that further inform players how and when units in reserves will enter the battlefield. 

## Embarked
Objects that are embarked are typically within another object that is a transport or fortification of some sort. Objects embarked in an object that is in reserves are also in reserves, but objects that are embarked elsewhere are handled case by case. An example of this is that objects embarked within an object on the battlefield are still simply embarked, not on the battlefield. Typically, objects can only disembark if they are embarked, and if the object they are embarked in is on the battlefield. Explicit rules for the process of embarking and disembarking will cover this, as well as the case for disembarking from an object that has been destroyed or removed from play.

## Casualty Report
When objects are destroyed, they are recorded in the casualty report. The way an object is destroyed can contribute to the state they are recorded in, which can affect how they are returned to action. Many objects have methods of returning to the battlefield or reserves from the casualty report. If an object enters the casualty report during a battle, after the battle's consolidation, there are typically rules for addressing that unit's continued service. 

## Confirmed KIA
When objects are confirmed KIA, they can no longer reference other objects or rules. They have not necessarily been removed from play, but can only be removed from this zone by a small number of rules. 

## Rosters
Rosters are a certain type of zone that help to organize Battleforces. Battleforces can be listed in a roster if they meet that roster's requirements. A Battleforce can be listed in as many rosters as it meets the criteria for. The default roster has no requirements. Campaigns, tournaments, and companion rules may add rosters with specific requirements and restrictions that Battleforces must be validated against in order to be listed in.

## Zones and State
Zones validate state. If a unit becomes destroyed, part of the rules involved in that state change will list that unit in the casualty report. If a unit is not destroyed, it shouldn't be listed in the casualty report. Exceptions to this management of state will be explicit and specific. 

# Commanders
Players attach armies to Commanders in order to participate in different Campaign Activities. In Simple War, Commanders are used like in Heroes of Might and Magic; the Player accesses a Battleforce through the Commander that is leading that army. Commanders move on the Sector Map based on their own characteristics in order to engage in activities. The player can have multiple Commanders, and Commanders can have access to a large army from which to field Battleforces.

# Armies
Armies are entities that keep track of all the units a player's commander has rallied. Armies inherit all of the tags of the units in them.

# Battleforces
Armies are broken into battleforces for specific engagements. If the Army is all of the units available to a commander, the battleforce is what they field for a given battle.

# Units
Units are entities that group models, providing the interface that defines how those models collectively engage with zones and other entities. Units inherit all of the tags of the models in them. Units can also inherit states from models, if all of the models in that unit are in that state. An example of this is "destroyed" -- a unit is not destroyed until every model in that unit is destroyed. 

## Statline
The statline is composed of the basic characteristics shared by models in a unit: Endurance, Durability, Morale, Speed, and Reflex. These characteristics are typically innate to each model. Models in a unit may have different values for these; combat resolution operates at the model level, using each individual model's own values.

The statline can be affected by items, abilities, and rules affecting the model or its unit. The statline is used in combination with keywords and abilities to inform the game of a model's capabilities. An example might be movement speed; a model with a speed of 6 might normally move 6 distance units, but if it has access to jet packs, that speed of 6 is not fully indicative of its maneuverability. Similarly, a model with low endurance but powerful armour may take a long time to destroy.

### Endurance
During an engagement, units take actions which may tax their endurance. Running for multiple turns in a row, fighting a prolonged melee, digging tunnels, and other acts of extreme exertion reduce a unit's endurance. When a unit has no remaining endurance, they can no longer perform actions that would tax it. Endurance recovers when units take actions that do not tax it.

### Durability
When a unit takes an instance of damage, keep track of it against the model closest to the source of the damage. When the damage matches or exceeds that model's durability, that model is destroyed. A single instance of damage can only destroy one model from a unit, even if it greatly exceeds that model's durability.

### Morale
A combination of characteristic and state. The state of a unit's morale affects its ability to take part in certain battle activities. When a unit's morale is tested against the characteristic, its can worsen, stay neutral, or improve. The states are broken, poor, neutral, good, and surging. The morale characteristic determines how well it handles these tests. Units with broken morale can typically never take part in capturing objectives, making charges, performing surges, etc., while units with high morale typically function better at all of those activities. A surging unit can be prompted to perform one such activity for free. Morale moves one stage toward the unit's listed baseline each turn, and resets after a surge.

### Speed
The typical movement a unit is capable of maintaining without taxing endurance. Moving at high speeds contributes to evasiveness.

### Reflex
Used when reacting, or responding to events out of sequence. Determines how effective evasiveness is. 

### Evasiveness
While not a characteristic on its own, many innate traits of units and models, including their characteristics, affect a unit's evasiveness. Evasion allows a unit to make an out of sequence movement reaction, limited by how evasive the unit is, and how successful their reaction is. 

## Unit Abilities
One of the defining characteristics of a unit is that they are more than the sum of their parts. This is expressed through unit abilities. Typically, a unit has a passive or innate ability, an active ability, and a surge ability. Some units may have more or less, or have abilities accessible by purchasing items or being in certain configurations of army. 

## Unit Composition
Units are composed of models, which have items. The models that can be in a unit, and the items those models can be configured with, are defined along with the values of those items in its composition.

## Datasheets
Comprehensive Unit reference for player convenience. Contains information about the unit's composition options, characteristics, value, availability, equipment, abilities, and restrictions. 

# Models
Models are used to define how a unit's baseline capability declines as it takes casualties. Each model represents and contributes to the unit's ability to affect an engagement. They are the most configurable components of a unit.

## Equipping Items
Items are entities that provide additional rules by being equipped to a model. Models can be equipped with more than one item, but equipment categories may prevent them from equipping all of the items available to them at any given time. When a model is equipped with an item, it is said to be that item's bearer. Models do not gain the keywords of items they're equipped with innately, though some items can confer keywords to their bearer or bearer's unit.

## Weapons and Armour
Some of the most important items a model can equip. Weapons and armour interact to determine how effective the unit is during combat resolution. Typically, models in a unit will be equipped with the same weapons and armour, but it is not uncommon to encounter variety in loadouts. 

### Weapon Characteristics
Weapons provide attack profiles to the models that equip them. A single weapon can provide multiple attack profiles (for example, a rifle may have both a ranged "Fire" profile and a melee "Bayonet" profile). Each attack profile defines its own category, range, damage value, and damage type.

#### Attack Profiles
An attack profile describes a single way a weapon can be used. It includes:
- **Category**: melee or ranged, determining which engagement contexts it can be used in.
- **Range**: for ranged attacks, expressed as min, short, long, max. The range between short and long is the effective range, which does not incur a range-based penalty. The ranges between min and short, and between long and max, are given penalties. Attacks cannot target models within min or beyond max range. For melee attacks, range is limited to close proximity.
- **Damage**: the base damage value produced on a successful hit.
- **Damage Type**: the category of damage (kinetic, concussive, energy, etc.), which interacts with armour resistances.
- **Modifiers**: optional flat or multiplicative adjustments to damage or hit probability.

#### Damage
Each successful attack produces a damage instance with a value and a type. Damage instances are resolved individually against the target model.

#### Modifiers
Attack profiles and items can carry modifiers that adjust hit probability, damage value, or armour interaction. Modifiers are applied during the relevant step of combat resolution.




# Timings

Timings describe **when** things happen in Simple War and in what order. At this level we care about the order of Stages, Phases, and Turns rather than the detailed rules of each action.

- **Stage**: A large section of a Battle (Planning, Deployment, Engagement, Consolidation). Stages always happen in this order.
- **Turn**: A repeating slice of time inside the Engagement stage. Each Turn is resolved using the true simultaneous turn system.
- **Phase**: A sub-part of a Turn (for example: Rally, Issue Orders, Execute, Resolve Combat). Phases give structure to what Players can do on each Turn.

In the barebones implementation, the engine needs to:

- Know which Stage the Battle is in.
- Advance from one Stage to the next in order.
- Run a simple Turn loop during Engagement, with a fixed set of Phases that we can refine later.

# Armybuilding

Armybuilding is the process of assembling a legal force that a Player can bring to a Battle or Campaign. This section stays high level; detailed construction rules live in the Army and faction documents.

## Faction Keywords
Faction Keywords identify which broad force or allegiance a Unit belongs to (for example: a political bloc, species, or military organization). They are used to enforce roster restrictions, determine which rules apply, and connect Units to specific Campaigns or scenarios.

## Characters
Characters are special Units or Models that represent leaders, heroes, or key specialists. They often unlock additional rules, modify other Units, or serve as focal points for objectives. Roster and Campaign rules can require or limit Characters.

## Unit Keywords
Unit Keywords describe battlefield roles and capabilities (for example: Infantry, Vehicle, Artillery, Recon). They help rules target the right Units and give structure to how different forces are composed without hard-coding specific factions.

## Model Keywords
Model Keywords capture more granular traits at the Model level (for example: Heavy Weapon, Medic, Pilot). They modify how Models interact with their Unit, equipment, and battlefield actions while still rolling up into the Unit’s overall behavior.

## Equipment Costs
Equipment Costs express how much it “costs” to equip Models and Units with weapons, armour, and other gear when building an Army. At this overview level it is enough to know that:

- Each option has an associated cost.
- Battleforces and Rosters can impose caps or bands on total cost.
- The system is designed so different Campaigns can reinterpret or tweak costs without changing the underlying data structures.

# Combat Resolution
Simple War simulates combat at the model level. Individual models make attacks against individual target models, with the engine resolving each interaction transparently. Units serve as groupings that determine which models attack which targets (closest models in the target unit), but resolution happens model-by-model.

The combat resolution process is separated into two independent stages: **Making Attacks** and **Being Attacked**. The attack side produces damage instances; the defense side consumes them. Morale, abilities, and other reactive effects observe combat results externally and are not part of the core resolution pipeline.

A model's datasheet shows its baseline combat characteristics, determined by its default items before any options are chosen for it.

## Combat Characteristics

- **Baseline Competence**: derived from Endurance. Represents the model's general effectiveness when making attacks.
- **Evasion Rating**: derived from Reflex, Speed, and situational modifiers. Represents how difficult the model is to hit.
- **Armour Value**: provided by equipped armour items. Reduces incoming damage after a hit is confirmed.
- **Armour Resistances**: per-damage-type modifiers on armour (for example, composite armour may resist kinetic damage but be weak to concussive).

## Making Attacks

Each attacking model resolves its attacks individually:

1. The model selects an attack profile from its equipped weapon(s) based on context (range to target, attack category).
2. The engine distributes the model's attacks to target models in the target unit, closest first.
3. For each attack, hit probability is computed: attacker's baseline competence + weapon modifiers - target's evasion rating. Hit probability has a floor of 5% and a ceiling of 95%, ensuring unlikely outcomes are always possible.
4. On a successful hit, a **damage instance** is produced containing the damage value, damage type, and source metadata.

## Being Attacked

Each target model resolves incoming damage individually:

1. The model receives one or more damage instances.
2. Each instance is mitigated by the model's armour value, adjusted by the armour's resistance to the damage type.
3. If mitigated damage meets or exceeds the model's durability, the model is destroyed.
4. A single damage instance can only destroy one model; overkill does not carry over to the next model.
5. Sub-lethal damage is tracked on the model for future resolution.

## Damage Types

Damage types describe the nature of the damage and interact with armour resistances:

- **Kinetic**: physical impact damage (bullets, blades). Interacts neutrally with most armour.
- **Concussive**: blast and shockwave damage (explosions, grenades). May partially bypass armour.
- **Energy**: directed energy damage (arcane blasts, plasma). May be fully resisted by specialized armour or bypass conventional armour.

Additional damage types can be introduced as needed. Each armour type defines its resistance modifier per damage type.

# Fighting a Battle

Fighting a Battle is how Simple War resolves direct conflict between Armies. The Battle is divided into Stages (Planning, Deployment, Engagement, Consolidation), and within Engagement into Turns and Phases.

## Planning
### Composing Units
### Transports
### Reserves
### Vanguard
## Deployment
### Hidden Areas
### Redeploying
### Pre-Engagement Moves
## Engagement
### The Turn System
#### Rally
#### Issue Orders
#### Execute
#### Resolve Combat

### The Order System

Simple War uses a **true simultaneous turn** system. During the appropriate Phase, Players give hidden Orders to their Units, then reveal and resolve those Orders together. This keeps Battles dynamic and reduces “I-go-you-go” downtime while remaining deterministic and computable for the digital engine.

#### Basic Actions
##### Movement
##### Making Attacks
##### Activating 
#### Reactions
##### Reposition
##### Evade
##### Return Fire
#### Surging
#### Surge Actions
## Consolidation
### Scoring
### Casualties

# The Generic Campaign
## Roster Requirements
### Commander


