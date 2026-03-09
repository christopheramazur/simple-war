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
Rosters are a certain type of zone that help to organize Armies. Armies can be listed in a roster if they meet that roster's requirements. An army can be listed in as many rosters as it meets the criteria for. The default roster has no requirements. Campaigns, tournaments, and companion rules may add rosters with specific requirements and restrictions that armies must be validated against in order to be listed in.

## Zones and State
Zones validate state. If a unit becomes destroyed, part of the rules involved in that state change will list that unit in the casualty report. If a unit is not destroyed, it shouldn't be listed in the casualty report. Exceptions to this management of state will be explicit and specific. 

# Armies
Armies are entities that keep track of the units a player has chosen. Armies inherit all of the tags of the units in them.

# Units
Units are entities that group models, providing the interface that defines how those models collectively engage with zones and other entities. Units inherit all of the tags of the models in them. Units can also inherit states from models, if all of the models in that unit are in that state. An example of this is "destroyed" -- a unit is not destroyed until every model in that unit is destroyed. 

## Statline
The primary interface of the unit is its statline. The statline is composed of the basic unit characteristics, from which we derive engagement resolution formulas. these characteristics are things that are typically innate to the models in the unit: Endurance, Durability, Morale, Speed, and Reflex. Models in a unit may have different values for these, but unless something is singling out a model (such as damage against a specific model), the unit typically uses the best value available during an interaction.

The statline can be affected by the objects and rules affecting the unit. The statline is used in combination with keywords and abilities to inform the game of the unit's capabilities. An example might be movement speed; a with a speed of 6 might normally move 6 tiles, but if it has access to jet packs, that speed of 6 is not fully indicative of its maneuverability. Similarly, a unit with low endurance but powerful armour may take a long time to die. 

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
Some of the most important items a model can equip. Weapons and armour interact to determine how effective the unit is during combat resolution. Typically, models in a unit will be equipped with the same weapons and armour, but it is not uncommon to encounter variety in loadouts. The models that take damage 


# Timings

Timings describe **when** things happen in Simple War and in what order. At this level we care about the order of Stages, Phases, and Turns rather than the detailed rules of each action.

- **Stage**: A large section of a Battle (Planning, Deployment, Engagement, Consolidation). Stages always happen in this order.
- **Turn**: A repeating slice of time inside the Engagement stage. Each Turn is resolved using the true simultaneous turn system.
- **Phase**: A sub-part of a Turn (for example: Rally, Issue Orders, Execute, Resolve Combat). Phases give structure to what Players can do on each Turn.

In the barebones implementation, the engine needs to:

- Know which Stage the Battle is in.
- Advance from one Stage to the next in order.
- Run a simple Turn loop during Engagement, with a fixed set of Phases that we can refine later.

# Building an Army

Building an Army is the process of assembling a legal force that a Player can bring to a Battle or Campaign. This section stays high level; detailed construction rules live in the Army and faction documents.

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
- Army lists and Rosters can impose caps or bands on total cost.
- The system is designed so different Campaigns can reinterpret or tweak costs without changing the underlying data structures.

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


