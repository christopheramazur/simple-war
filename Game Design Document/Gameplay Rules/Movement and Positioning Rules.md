# Movement and Positioning Rules

**Status**: Draft
**Last Updated**: 2026-03-18
**Purpose**: Formalizes how Squad and Unit Entities are positioned, move, and face on the Battlefield using the ECS architecture — defining the spatial Components the Movement System reads and writes, the coordinate system, distance measurement, deployment positioning, reinforcement entry, cohesion, and movement restrictions.

---

## Overview

Movement and Positioning rules govern where Entities exist on the Battlefield and how they change location. The **Movement System** (see rule 200.4 in Entity System Rules) is the primary System that operates on these rules: it reads the Speed value from an Entity's Statline Component, the current position from the Entity's PositionComponent, and the Entity's Zone Component, then writes updated position data back to the PositionComponent. The **Deployment System** handles initial placement of Entities onto the Battlefield during the Deployment Stage.

These rules define the coordinate system, the distance metric, Squad footprints and Unit cohesion, facing and pivoting, and the constraints that limit movement. They complement the Order-based movement specified in Battle Rules (rules 132.2a–132.2h) by providing the spatial foundations those Orders rely on.

This document does not redefine Order movement distances — those are specified in the Battle Rules. Instead, it defines the spatial Components and spatial system in which all movement occurs and the restrictions that constrain it.

---

## 300 Battlefield Geometry

### 300.1 Coordinate System

The Battlefield is an Entity with spatial Components defining a two-dimensional rectangular area. Positions on the Battlefield are expressed as (x, y) coordinates, where x is the horizontal axis and y is the vertical axis. Both x and y are continuous (floating-point) values, not limited to integer grid positions.

The origin (0, 0) is the bottom-left corner of the Battlefield. The x-axis increases toward the right; the y-axis increases upward.

### 300.2 Battlefield Dimensions

The default Battlefield for a two-Player Battle is 200 distance squads wide (x-axis: 0 to 200) and 100 distance squads tall (y-axis: 0 to 100). One distance squad corresponds to one meter of in-world scale.

Campaign or scenario rules may define Battlefields with different dimensions. The Battlefield's width and height must each be an integer number of distance squads and must each be at least 20 distance squads.

### 300.3 Distance Measurement

All distances in Simple War are measured as **Euclidean distance** (straight-line distance) between two points (x₁, y₁) and (x₂, y₂):

**Distance = √((x₂ − x₁)² + (y₂ − y₁)²)**

When a rule specifies a distance threshold (such as "within 3 distance squads"), the condition is met if the Euclidean distance between the two reference points is less than or equal to the threshold.

When a rule specifies a maximum movement distance, the total path length — not the straight-line displacement — must not exceed the allowed value (see rule 310.3).

### 300.4 Battlefield Grid

The Battlefield grid is a visual aid; it does not constrain movement or positioning. Squads may occupy any valid continuous position.

The grid is displayed at different granularities depending on the Player's view zoom level:

| Zoom Level | Grid Spacing |
|---|---|
| Close (most zoomed in) | 1 distance squad |
| Medium | 3 distance squads |
| Far (most zoomed out) | 6 distance squads |

The maximum zoom-in level shows a 6×6 area of 1-squad grid cells. The maximum zoom-out level shows the entire Battlefield plus 6 distance squads of surrounding area on each side.

### 300.5 Battlefield Boundary

The Battlefield boundary is the rectangle defined by x ∈ [0, width] and y ∈ [0, height], stored in the Battlefield Entity's dimension Components. No part of a Squad's footprint (see rule 320.1) may extend beyond the Battlefield boundary, except during Reinforcement entry (see rule 340.1), where the Deployment System transitions Squads from off-Battlefield to on-Battlefield.

A Squad that would be forced beyond the Battlefield boundary by a rule or collision (see rule 310.6) stops at the nearest valid position inside the boundary instead.

### Examples

#### Example 1: Distance Calculation
**Setup**: Squad A is at position (10, 20). Squad B is at position (13, 24).
**Calculation**: Distance = √((13 − 10)² + (24 − 20)²) = √(9 + 16) = √25 = 5 distance squads.

#### Example 2: Threshold Check
**Setup**: A rule requires "within 3 distance squads." Squad A is at (0, 0) and Squad B is at (2, 2).
**Calculation**: Distance = √(4 + 4) = √8 ≈ 2.83. Since 2.83 ≤ 3, the condition is met.

---

## 310 Movement

### 310.1 Movement Overview

Movement is the process by which the Movement System updates a Squad's PositionComponent on the Battlefield. All movement originates from an Order, a Reaction, a Pre-Engagement Move, or a rule that explicitly grants movement. The Movement System may not update a Squad's PositionComponent outside of these contexts.

The Order system (see rules 132.2a–132.2h in Battle Rules) specifies the maximum distance each Order type allows. This section defines how the Movement System executes that movement spatially.

### 310.2 Movement Origin and Destination

A movement action has:

- **Origin**: The Squad's PositionComponent value at the start of the movement (the snapshot position during the Execute Phase; see rule 133.4 in Battle Rules).
- **Destination**: The intended final position, determined by the Order's target point or target Squad.

If the straight-line distance from the Origin to the Destination exceeds the allowed movement distance, the Movement System moves the Squad along the direct path toward the Destination and stops at the maximum allowed distance from the Origin (see rule 310.3).

### 310.3 Path and Path Length

A Squad's movement path is the trajectory from Origin to Destination. The default path is a straight line. If an obstruction (Battlefield boundary, terrain Entity with the `Blocking` marker Component, or another Squad) lies along the straight-line path, the Movement System calculates the shortest valid path around the obstruction (see rule 310.5).

The **path length** is the total distance traveled along the path, measured as the sum of Euclidean distances between consecutive path segments. The path length must not exceed the Order's allowed movement distance. If the shortest valid path around an obstruction exceeds the allowed distance, the Movement System moves the Squad as far as possible along that path and stops.

### 310.4 Movement Speed by Order

The maximum path length a Squad may travel is determined by the Speed value from the Squad's Statline Component (see rule 210.5 in Entity System Rules) and the Order type. The Movement System reads Speed from the Statline Component to compute maximum path length. These distances are defined in Battle Rules and summarized here for reference:

| Order / Action | Maximum Path Length | Reference |
|---|---|---|
| Advance | Speed | Rule 132.2b |
| Run | 2 × Speed | Rule 132.2d |
| Charge | floor(1.5 × Speed) | Rule 132.2e |
| Fall Back | Speed (or 2 × Speed if Broken Morale) | Rule 132.2g |
| Reposition (Reaction) | floor(Speed / 2) | Rule 133.3a |
| Pre-Engagement Move | As specified by granting rule | Rule 120.4 |

A Squad with a Hold or Dig In Order does not move (path length = 0).

### 310.5 Obstruction and Pathfinding

When a Squad's straight-line path is blocked by an obstruction, the Movement System calculates the shortest valid path around the obstruction that does not pass through any invalid position (see rule 310.7 for invalid positions).

Obstructions include:
- **Battlefield boundary** (see rule 300.5)
- **Blocking Terrain**: Terrain Entities with the `Blocking` marker Component (see rule 310.7b; to be fully defined in Terrain rules, 600-series)
- **Other Squads** from opposing Players that are not the target of a Charge (see rule 310.6)

Friendly Squads (Squads belonging to the same Player) are not obstructions; a Squad may move through Friendly Squads' footprints but may not end its movement overlapping a Friendly Squad's footprint.

If no valid path to the Destination exists, the Movement System moves the Squad as far as possible along the shortest partially valid path toward the Destination.

### 310.6 Collision and Separation

When two or more Squads from opposing Players would occupy overlapping positions at the end of simultaneous movement resolution:

1. If one or both Squads issued a Charge Order targeting the other, both Squads are placed in Melee at the point of contact (see rule 132.2e in Battle Rules).
2. Otherwise, each Squad stops at the closest valid position before the overlap, maintaining a minimum separation of 1 distance squad between their footprint edges.

The Movement System resolves collisions during step 5 of rule 133.4 in Battle Rules.

### 310.7 Invalid Positions

A position is invalid for a Squad if any of the following apply:

#### 310.7a Boundary Violation
Any part of the Squad's footprint (see rule 320.1) extends beyond the Battlefield boundary.

#### 310.7b Blocking Terrain
Any part of the Squad's footprint overlaps a position occupied by a terrain Entity with the `Blocking` marker Component. The `Blocking` marker Component on a terrain Entity prevents movement through the positions that terrain Entity occupies. Squads with the `Flying` marker Component ignore terrain Entities with the `Blocking` marker Component for movement purposes, unless the terrain Entity also has the `Grounded` marker Component (which specifically restricts Squads with the `Flying` marker Component).

The full definition of terrain archetypes, terrain Components (including spatial extent, marker Components, and interaction data), and terrain interaction rules will be specified in the Terrain rules (600-series).

#### 310.7c Overlapping Enemy Squads
Any part of the Squad's footprint overlaps an Enemy Squad's footprint, except when the Squad is entering Melee via a Charge Order.

#### 310.7d Overlapping Friendly Squads at Rest
Any part of the Squad's footprint overlaps a Friendly Squad's footprint at the end of movement. Friendly Squads may pass through each other during movement but may not end in an overlapping position.

### Examples

#### Example 1: Simple Advance
**Setup**: Squad A has Speed 10 and is at position (50, 30). The Player issues an Advance Order to target point (55, 42).
**Calculation**: Distance to target = √(25 + 144) = √169 = 13. This exceeds Speed (10). The Squad moves 10 distance squads along the straight-line path toward (55, 42), stopping at (50 + 5×(10/13), 30 + 12×(10/13)) = (53.85, 39.23) (rounded to two decimal places).

#### Example 2: Run to Destination Within Range
**Setup**: Squad B has Speed 8 and is at (20, 20). The Player issues a Run Order to target point (30, 24).
**Calculation**: Distance = √(100 + 16) = √116 ≈ 10.77. Maximum Run distance = 2 × 8 = 16. Since 10.77 ≤ 16, Squad B reaches (30, 24).

#### Example 3: Obstruction Pathing
**Setup**: Squad C has Speed 10, is at (40, 50), and issues an Advance to (60, 50). A Blocking Terrain feature occupies positions (48, 48) to (52, 52), blocking the straight-line path.
**Result**: The Movement System calculates the shortest path around the terrain Entity. If the detour path length exceeds 10 distance squads, Squad C stops partway along the detour.

---

## 320 Squad Footprint and Unit Cohesion

### 320.1 Squad Footprint

A Squad occupies space on the Battlefield defined by its **FootprintComponent**. The FootprintComponent describes a rectangular area centered on the Squad's PositionComponent value (x, y). The footprint dimensions are derived from the Squad's Composition Component and FormationComponent:

- **Width**: Determined by the number of Units arranged in file (side to side).
- **Depth**: Determined by the number of ranks (front to back).

Each Unit occupies a circular area with a diameter of 1 distance squad. Units within the footprint are spaced according to the Squad's FormationComponent (see rule 320.3).

The Movement System recalculates the FootprintComponent when the Squad's Composition Component changes (e.g., the Combat System destroys a Unit). When Units are destroyed, the footprint may shrink as the remaining Units consolidate.

### 320.2 Unit Cohesion

All Units in a Squad must remain within the Squad's footprint at all times. A Unit may not be separated from the nearest Unit in the same Squad by more than **2 distance squads** (measured center-to-center). This is the **Cohesion Distance**.

If a rule or effect would place a Unit outside the Cohesion Distance from all other Units in its Squad, that Unit is instead placed at the nearest valid position that satisfies the Cohesion Distance requirement.

When a Unit is destroyed, the Squad's remaining Units are not required to immediately consolidate. The Squad's footprint adjusts to the positions of surviving Units. During the next movement by the Squad, Units reposition to maintain the formation (see rule 320.3).

### 320.3 Formations

The FormationComponent defines how Units are arranged within a Squad's footprint. The default FormationComponent value is **rectangular_block**: Units are arranged in rows and columns, evenly spaced by 1 distance squad center-to-center.

The number of ranks and files in the default formation is determined by:

- **Files** (columns, side to side): min(Unit count, 5) for Squads with the `Infantry` marker Component; min(Unit count, 3) for Squads with the `Vehicle` marker Component.
- **Ranks** (rows, front to back): ceil(Unit count / files).

The front rank faces the Squad's facing direction (see rule 330.1).

Custom FormationComponent values may be introduced by Ability Components, Squad Keyword marker Components, or scenario rules. All formations must satisfy the Cohesion Distance requirement (rule 320.2).

### Examples

#### Example 1: Standard Infantry Footprint
**Setup**: A Riflemen Squad has 10 Units and the `Infantry` marker Component.
**Formation**: 5 files × 2 ranks.
**Result**: Units arranged in a 5×2 block centered on the Squad's position. Footprint is 5 distance squads wide × 2 distance squads deep.

#### Example 2: Reduced Squad
**Setup**: The Riflemen Squad loses 3 Units, leaving 7.
**Formation**: 5 files × 2 ranks (second rank has 2 Units instead of 5). Footprint width is 5 distance squads; second rank has 3 empty slots.

#### Example 3: Vehicle Squad
**Setup**: A Tank Squad has 3 Units and the `Vehicle` marker Component.
**Formation**: 3 files × 1 rank. Footprint is 3 distance squads wide × 1 distance squad deep.

---

## 330 Facing and Pivoting

### 330.1 Facing

Every Squad has a **FacingComponent** holding a facing direction expressed as an angle in degrees from 0 to 359, measured clockwise from the positive y-axis (north = 0°, east = 90°, south = 180°, west = 270°). The Movement System reads and writes the FacingComponent during movement resolution.

Facing determines:
- The direction of the Squad's front rank (see rule 320.3).
- Line of sight arcs for ranged attacks (to be defined in Combat Resolution, 400-series).
- The direction of Fall Back movement (away from the nearest Enemy Squad, not dependent on the FacingComponent value).

At Deployment, the Deployment System sets each Squad's initial FacingComponent value based on the Player's choice. During the Engagement Stage, the Movement System updates the FacingComponent through pivoting (see rule 330.2) or as a consequence of movement toward a target point.

### 330.2 Pivoting

A pivot changes a Squad's FacingComponent value without changing the Squad's PositionComponent value. Pivoting costs movement distance from the Squad's current Order:

**Pivot Cost = (Angle Change / 360) × (Footprint Diagonal / 2)**

Where Angle Change is the absolute angular difference (0–180°) and Footprint Diagonal is the diagonal length of the Squad's footprint rectangle.

A pivot of 0° costs nothing. A 180° turn (about-face) costs the most. The pivot cost is subtracted from the Squad's available movement distance for the current Order before calculating how far the Squad can travel.

A Squad that is not moving (Hold, Dig In) may pivot freely at no cost, because these Orders have no movement component to deduct from.

### 330.3 Automatic Facing Adjustment

When a Squad moves toward a target point via an Advance, Run, or Charge Order, the Movement System automatically updates the Squad's FacingComponent to point from the Squad's final PositionComponent value toward the target point (or toward the target Squad for Charge). The cost of this adjustment is included in the path length — the Movement System routes the pivot into the movement path.

When a Squad performs a Fall Back, the Movement System does not update the FacingComponent (the Squad retreats but does not turn around).

When a Squad performs a Reposition Reaction, the Movement System does not update the FacingComponent.

### Examples

#### Example 1: Free Pivot on Hold
**Setup**: Squad A has a Hold Order and is currently facing north (0°). The Player designates attack targets to the east.
**Result**: Squad A pivots to face east (90°) at no cost, since Hold has no movement component.

#### Example 2: Pivot During Advance
**Setup**: Squad B has Speed 10, a 5×2 footprint (diagonal = √(25 + 4) = √29 ≈ 5.39 distance squads), and needs to pivot 90° before advancing.
**Calculation**: Pivot cost = (90 / 360) × (√29 / 2) = 0.25 × 2.69 = 0.67 distance squads. Remaining movement = 10 − 0.67 = 9.33 distance squads.

#### Example 3: About-Face and Advance
**Setup**: Squad C has Speed 10, a 5×2 footprint (diagonal = √29 ≈ 5.39), and needs to turn 180°.
**Calculation**: Pivot cost = (180 / 360) × (√29 / 2) = 0.5 × 2.69 = 1.35 distance squads. Remaining movement = 10 − 1.35 = 8.65 distance squads.

---

## 340 Deployment Positioning and Reinforcements

### 340.1 Deployment Zones

Deployment Zones are spatial regions stored as Components on the Battlefield Entity, defining where the Deployment System may place Squads during the Deployment Stage (see rule 120.2 in Battle Rules). Each Deployment Zone Component specifies a rectangular area and the Player it belongs to. The default configuration for a two-Player Battle on a 200×100 Battlefield:

- **Player A (bottom)**: The rectangular area x ∈ [0, 200], y ∈ [0, 20].
- **Player B (top)**: The rectangular area x ∈ [0, 200], y ∈ [80, 100].

The area between the Deployment Zones (y ∈ [20, 80]) is No Man's Land — no Squad may be placed there during Deployment unless a rule explicitly permits it.

Campaign or scenario rules may define alternative Deployment Zone layouts, including asymmetric zones, multiple zones per Player, or zones that are not aligned to the Battlefield edges.

### 340.2 Deployment Constraints

During the Deployment Stage, the Deployment System enforces the following constraints:

1. A Squad must be placed **wholly within** the owning Player's Deployment Zone Component. No part of the Squad's FootprintComponent may extend outside the zone boundary.
2. A Squad's FootprintComponent may not overlap another Squad's FootprintComponent at Deployment.
3. The Deployment System sets each Squad's initial PositionComponent and FacingComponent values based on the Player's choices.
4. Squads with the `Vanguard` marker Component deploy first (see rule 120.3a in Battle Rules). After all Vanguard Squads are placed, remaining Squads deploy (see rule 120.3b).

If a Squad's FootprintComponent is too large to fit within the Deployment Zone, the Player must adjust the Squad's position, or scenario rules must expand the zone. A Squad that cannot be legally placed remains in Reserves (its Zone Component stays set to Reserves).

### 340.3 Reinforcement Entry

Squads whose Zone Component is set to Reserves and that have met their entry conditions (see rule 131.1, step 4 in Battle Rules) enter the Battlefield via the Deploy from Reserves Order (see rule 132.2c in Battle Rules). The Deployment System processes Reinforcement entry using the following procedure:

1. The Deployment System places the entering Squad at a position along the owning Player's **Reinforcement Edge** — the Battlefield edge closest to the Player's Deployment Zone — and sets its PositionComponent accordingly.
2. The Squad must be placed wholly within the Battlefield boundary.
3. The Squad's FootprintComponent must not overlap any other Squad's FootprintComponent.
4. The Deployment System transitions the Squad's Zone Component from Reserves to Battlefield. The Squad may not move further or make attacks during the Turn the Squad enters (per rule 132.2c in Battle Rules).

The default Reinforcement Edge:
- **Player A**: The bottom edge (y = 0, x ∈ [0, 200]).
- **Player B**: The top edge (y = 100, x ∈ [0, 200]).

Specific Reserves rules (such as deep strike or flanking maneuvers) may designate alternative entry points, including positions within the Battlefield interior. These rules specify the entry position constraints and any restrictions.

### 340.4 Vanguard Deployment

Squads with the `Vanguard` marker Component (see rule 110.5 in Battle Rules) deploy before other Squads during the Deployment Stage. Vanguard deployment follows all standard Deployment Constraints (rule 340.2). Squads with the `Vanguard` marker Component do not receive an extended Deployment Zone by default — they deploy within the same zone as other Squads but are placed first.

Specific Ability Components may grant extended deployment areas (e.g., the Forward Positions Passive Ability Component allows deployment up to 6 distance squads beyond the Deployment Zone boundary; see rule 250.2 in Entity System Rules).

### 340.5 Pre-Engagement Moves

After all Squads are deployed and before the Engagement Stage begins, Squads with Pre-Engagement Movement rules may execute those moves simultaneously (see rule 120.4 in Battle Rules). Pre-Engagement Moves follow all standard movement rules defined in this document (distance measurement, obstruction, cohesion, facing). The maximum distance and any restrictions are defined by the granting rule.

### Examples

#### Example 1: Standard Deployment
**Setup**: Player A deploys a Riflemen Squad (5×2 footprint) at position (100, 10) facing north.
**Validation**: Footprint extends from (97.5, 9) to (102.5, 11). All within y ∈ [0, 20]. Valid.

#### Example 2: Reinforcement Entry
**Setup**: Turn 3. A Reserves Squad belonging to Player A is flagged as eligible. Player A issues a Deploy from Reserves Order.
**Result**: The Squad is placed along the bottom edge (y = 0 + half the footprint depth so the Squad is wholly on the Battlefield). The Squad cannot move or attack this Turn.

#### Example 3: Deployment Zone Too Small
**Setup**: A large Vehicle Squad has a footprint 8 distance squads deep, but the Deployment Zone is only 20 deep.
**Result**: The Squad can be placed (8 < 20). If the zone were smaller than the footprint depth, the Squad would remain in Reserves until the zone is adjusted.

---

## 350 Movement Restrictions

### 350.1 Minimum Movement

A Squad is never required to move its full allowed distance. A Squad may move any distance from 0 up to its maximum allowed path length. Choosing to move 0 distance squads is always valid (the Squad remains at its current position).

### 350.2 Endurance and Movement

Orders that tax Endurance (Run, Charge) require the Squad's EnduranceRemainingComponent value to be at least 1 at the time the Order is issued. If a Squad's EnduranceRemainingComponent reaches 0, that Squad may not receive Run or Charge Orders (see rule 132.4 in Battle Rules). The Endurance cost is deducted from the EnduranceRemainingComponent when the Order executes, not when issued.

### 350.3 Morale and Movement

A Squad whose MoraleStateComponent is Broken may not receive a Charge Order (see rule 132.4 in Battle Rules). A Squad whose MoraleStateComponent is Broken that receives a Fall Back Order moves up to 2 × Speed (from the Statline Component) instead of the standard Speed (see rule 132.2g in Battle Rules).

### 350.4 Melee and Movement

A Squad in Melee may only receive Hold, Charge (targeting a Squad already in the same Melee), or Fall Back Orders (see rule 132.4 in Battle Rules).

A Fall Back from Melee provokes no attacks by default. If a rule grants the ability to attack Squads disengaging from Melee (such as an Overwatch or Pursue Ability), that rule specifies the trigger, timing, and restrictions.

### 350.5 Movement Does Not Provoke Attacks

Movement does not provoke attacks by default (see rule 133.4 in Battle Rules). If a rule grants the ability to attack Squads that move through a specified area, that rule specifies the trigger, the timing within the Execute Phase, and the attack profile restrictions.

### Examples

#### Example 1: Partial Movement
**Setup**: Squad A has Speed 10 and an Advance Order to a target 3 distance squads away.
**Result**: Squad A moves 3 distance squads and stops. The remaining 7 squads of allowed movement are unused.

#### Example 2: Broken Morale Fall Back
**Setup**: Squad B has Broken Morale and Speed 6. The Player issues a Fall Back Order.
**Result**: Squad B may move up to 12 distance squads (2 × 6) away from the nearest Enemy Squad.

---

## Glossary Additions

- **Battlefield Boundary**: The rectangular perimeter of the Battlefield Entity defined by x ∈ [0, width] and y ∈ [0, height] from its dimension Components. Squads may not extend beyond the boundary. (Rule 300.5)
- **Blocking** (marker Component): A marker Component on a terrain Entity that prevents movement through the positions the terrain Entity occupies. The Movement System reads this marker Component during pathfinding. (Rule 310.7b)
- **Cohesion Distance**: The maximum allowed distance (2 distance squads) between any Unit and the nearest other Unit in the same Squad. (Rule 320.2)
- **Deployment System**: The System that handles initial placement of Entities onto the Battlefield during the Deployment Stage and Reinforcement entry. Reads and writes PositionComponent, FacingComponent, ZoneComponent. (Rules 340.1–340.5)
- **Deployment Zone** (Component): A Component on the Battlefield Entity defining a rectangular area where a Player may place Squads during the Deployment Stage. (Rules 120.2, 340.1)
- **Distance Squad**: The base squad of measurement in Simple War; one distance squad equals one meter of in-world scale. (Rule 300.2)
- **Euclidean Distance**: The straight-line distance between two points, used for all distance measurement in Simple War. (Rule 300.3)
- **FacingComponent**: A data Component on a Squad Entity holding the Squad's orientation as an angle in degrees (0–359) clockwise from north. Read and written by the Movement System. (Rule 330.1)
- **Flying** (marker Component): A marker Component on a Squad Entity indicating the Squad can ignore terrain Entities with the `Blocking` marker Component, unless the terrain also has the `Grounded` marker Component. (Rule 310.7b)
- **FootprintComponent**: A data Component on a Squad Entity describing the rectangular area the Squad occupies on the Battlefield, derived from Unit count and FormationComponent. (Rule 320.1)
- **FormationComponent**: A data Component on a Squad Entity defining how Units are arranged within the footprint; default value is rectangular_block. (Rule 320.3)
- **Grounded** (marker Component): A marker Component on a terrain Entity that specifically restricts Squads with the `Flying` marker Component from entering terrain that would otherwise be passable for them. (Rule 310.7b)
- **No Man's Land**: The area between opposing Players' Deployment Zones. Squads may not be placed there during Deployment unless a rule permits it. (Rule 340.1)
- **Path Length**: The total distance traveled along a movement path, measured as the sum of Euclidean distances along path segments. Computed by the Movement System. (Rule 310.3)
- **Pivot**: A change in a Squad's FacingComponent value without changing the PositionComponent, costing movement distance proportional to the angle change and footprint size. (Rule 330.2)
- **Pivot Cost**: The movement distance consumed by a pivot: (Angle Change / 360) × (Footprint Diagonal / 2). Computed by the Movement System. (Rule 330.2)
- **PositionComponent**: A data Component on a Squad or Unit Entity holding the (x, y) coordinates on the Battlefield. Read and written by the Movement System and Deployment System. (Rules 310.1, 340.2)
- **Reinforcement Edge**: The Battlefield edge closest to a Player's Deployment Zone, where the Deployment System places Reserves Squads entering the Battlefield. (Rule 340.3)

---

## Implementation Notes

### Component Definitions

The following Components are defined or extended by this document. These augment the Component catalog in Entity System Rules (see Appendix A.2).

**Battlefield Entity Components**:

| Component | Type | Description |
|---|---|---|
| `BattlefieldDimensionsComponent` | `{ width: int, height: int }` | Default: 200 × 100. Defines the coordinate space bounds. |
| `DeploymentZonesComponent` | `list<{ player_id: string, x_min: float, x_max: float, y_min: float, y_max: float }>` | Rectangular areas per Player for Squad placement. |
| `ReinforcementEdgesComponent` | `map<player_id, edge_descriptor>` | Battlefield edges per Player for Reserves entry. |
| `TerrainIndexComponent` | Spatial index of terrain Entity references | Referenced by the Movement System during pathfinding. Terrain Entities carry their own marker Components (`Blocking`, `Grounded`, etc.). |

**Squad Spatial Components** (in addition to Entity System Components):

| Component | Type | Description |
|---|---|---|
| `PositionComponent` | `{ x: float, y: float }` | The Squad's center position on the Battlefield. Read and written by the Movement System and Deployment System. |
| `FacingComponent` | `{ angle: float }` | Degrees (0.0–359.9), clockwise from north. Read and written by the Movement System. |
| `FootprintComponent` | `{ width: float, depth: float }` | Derived from Composition Component + FormationComponent. Recalculated when Units are destroyed. |
| `FormationComponent` | `{ type: enum(rectangular_block, ...), files: int, ranks: int }` | Default: rectangular_block. Files determined by `Infantry`/`Vehicle` marker Component. |

**Unit Spatial Components**:

| Component | Type | Description |
|---|---|---|
| `RelativePositionComponent` | `{ x: float, y: float }` | Offset from Squad center, determined by FormationComponent slot assignment. |

### System Responsibilities (Movement and Deployment)

| System | Reads | Writes |
|---|---|---|
| **Movement System** | StatlineComponent (Speed), PositionComponent, FacingComponent, FootprintComponent, ZoneComponent, terrain Entity marker Components (`Blocking`, `Grounded`, `Flying`), EnduranceRemainingComponent | PositionComponent, FacingComponent |
| **Deployment System** | ZoneComponent, FootprintComponent, DeploymentZonesComponent, ReinforcementEdgesComponent | PositionComponent, FacingComponent, ZoneComponent |

### Digital Implementation Considerations

- **Pathfinding**: The Movement System requires a pathfinding algorithm capable of computing shortest paths around convex and concave obstacles on a continuous 2D plane. A navigation mesh or visibility graph approach is recommended over grid-based A* for accuracy with continuous coordinates.
- **Collision Detection**: During simultaneous movement resolution, the Movement System must detect and resolve overlaps between all moving Squads' FootprintComponents. A spatial hash or broadphase sweep-and-prune can reduce pairwise checks.
- **Pivot Integration**: The Movement System computes pivot cost before path length. It subtracts pivot cost from the Order's allowed movement distance, then pathfinds with the remaining budget.
- **Footprint Caching**: FootprintComponent values change only when the Composition Component changes (Units destroyed) or the FormationComponent changes. Recalculate only on composition/formation change events.
- **Movement Preview**: The PoC specifies translucent Squad copies at the end of dotted-line paths for movement planning (see PoC.md). The Movement System must support real-time path preview during the Issue Orders Phase, showing the path, destination, and pivot cost deduction.
- **Zoom-Level Grid**: Grid rendering is a display concern. The Movement System does not snap PositionComponent values to grid; the grid overlay is rendered at the appropriate spacing based on the camera's zoom factor.
- **Terrain Entity Queries**: The Movement System queries terrain Entities by spatial position and checks their marker Components (`Blocking`, `Grounded`) to determine passability. The `Flying` marker Component on the moving Squad modifies terrain interaction rules.

### Relationship to Existing Data

| Rule Concept | Existing Reference | Notes |
|---|---|---|
| Speed (rule 310.4) | `Squads.json` → `characteristics.speed` | Integer value in StatlineComponent; read by Movement System |
| Battlefield dimensions (rule 300.2) | PoC.md: "100 squads tall and 200 squads wide" | Default BattlefieldDimensionsComponent values codified here |
| Deployment Zones (rule 340.1) | Battle Rules 120.2; PoC.md: "top/bottom 20 squads" | Default DeploymentZonesComponent values codified here |
| Squad position + facing | Battle Rules 120.3b: "(x, y) and facing direction (angle in degrees, 0–359)" | PositionComponent + FacingComponent formalized here |
| Movement preview | PoC.md: "translucent copy... dotted-line path" | UX requirement; Movement System must support path computation during planning |

---

## Dependencies

This document defines spatial Components and foundations referenced by:

- **Battle Rules** (100-series): Orders specify movement distances; Execute Phase invokes the Movement System. Rules 120.2, 132.2a–h, 133.4.
- **Entity System Rules** (200-series): StatlineComponent / Speed (rule 210.5), Squad archetype (rule 240.1), Unit archetype (rule 230.1), ZoneComponent (rule 200.4), Movement System (rule 200.4). This document extends the Component catalog (Appendix A.2) with PositionComponent, FacingComponent, FootprintComponent, FormationComponent, and Battlefield-level Components.
- **Combat Resolution** (400-series, not yet drafted): Line of sight, range measurement, and attack arc calculations use PositionComponent, FacingComponent, and the coordinate system defined here.
- **Terrain Rules** (600-series, not yet drafted): Terrain Entity archetypes, terrain Components, `Blocking` and `Grounded` marker Components, and terrain interaction with the Movement System — defined here as forward references.
- **Abilities and Effects** (500-series, not yet drafted): Pre-Engagement Moves, Vanguard extended deployment, `Flying` marker Component interaction with terrain.

---

## Version History

| Version | Date | Changes |
|---|---|---|
| 0.1 | 2026-03-17 | Initial draft: Battlefield geometry, movement mechanics, footprints, facing, deployment, reinforcements, restrictions |
| 0.2 | 2026-03-18 | ECS alignment: replaced tag-based terrain references with terrain Entity marker Components (`Blocking`, `Grounded`, `Flying`); introduced PositionComponent, FacingComponent, FootprintComponent, FormationComponent, and Battlefield-level Components; framed Movement System and Deployment System as the Systems operating on spatial data; updated glossary and implementation notes to Component/System terminology |
