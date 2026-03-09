# Simple War Code Generator — Godot/GDScript Reference

Concrete patterns for mapping GDD concepts (Campaigns, Armies, Units, Zones, Timings, Orders) into Godot 4.6+ / GDScript.

Use these as templates; always adapt field names and comments to match the specific rule text.

---

## 1. Unit & Army definitions (Resources)

Source: `Terminology – Units, Models, Statline, Unit Abilities`, `Main Concepts – Rosters and Armies`.

### 1.1 UnitDefinition (data only)

```gdscript
extends Resource
class_name UnitDefinition

@export var id: String
@export var display_name: String

## Faction and role keywords (see Faction Keywords, Unit Keywords, Model Keywords)
@export var faction_keywords: Array[StringName] = []
@export var unit_keywords: Array[StringName] = []   # e.g. "Infantry", "Vehicle"

## Core statline (Endurance, Durability, Morale, Speed, Reflex)
@export var endurance: int = 0
@export var durability: int = 0
@export var morale: int = 0
@export var speed: int = 0
@export var reflex: int = 0

## Composition and equipment (simplified; detailed rules live in datasheets)
@export var base_models: int = 0
@export var max_models: int = 0
@export var allowed_items: Array[Resource] = []   # ItemDefinition resources

## Army-building information
@export var points_cost: int = 0   # see Equipment Costs, Army value
```

### 1.2 ArmyDefinition and simple validation

```gdscript
extends Resource
class_name ArmyDefinition

@export var name: String
@export var units: Array[UnitDefinition] = []

func get_total_points() -> int:
	var total := 0
	for u in units:
		total += u.points_cost
	return total
```

Validation helpers can then implement “Army can be used in this Battle / Campaign” as per `Main Concepts – Rosters and Armies`.

---

## 2. Zones & state

Source: `Terminology – Zones`, `In Play`, `Removed from Play`, `Casualty Report`, `Confirmed KIA`, `Rosters`.

```gdscript
extends Resource
class_name Zones

enum Zone {
	IN_PLAY,
	BATTLEFIELD,
	RESERVES,
	EMBARKED,
	CASUALTY_REPORT,
	CONFIRMED_KIA,
	ROSTER,
}

static func can_change_zone(from_zone: Zone, to_zone: Zone) -> bool:
	# Rule: Removed from Play objects never change zones
	if from_zone == Zone.CONFIRMED_KIA:
		return false
	# Add explicit exceptions and transitions as rules are written
	return true
```

Use small helpers like this to encode the invariants from the Zones section (e.g. “objects removed from play can no longer reference or be referenced”).

---

## 3. Battle stages, turns, and phases

Source: `Main Concepts – Battle stages`, `Terminology – Timings`, `Fighting a Battle`.

```gdscript
extends Node
class_name BattleState

enum BattleStage { PLANNING, DEPLOYMENT, ENGAGEMENT, CONSOLIDATION }
enum TurnPhase { RALLY, ISSUE_ORDERS, EXECUTE, RESOLVE_COMBAT }

var stage: BattleStage = BattleStage.PLANNING
var turn_index: int = 0
var phase: TurnPhase = TurnPhase.RALLY

func advance_stage() -> void:
	# Follow fixed order: Planning → Deployment → Engagement → Consolidation
	match stage:
		BattleStage.PLANNING:
			stage = BattleStage.DEPLOYMENT
		BattleStage.DEPLOYMENT:
			stage = BattleStage.ENGAGEMENT
		BattleStage.ENGAGEMENT:
			stage = BattleStage.CONSOLIDATION
		BattleStage.CONSOLIDATION:
			# Campaign decides what happens after this
			pass

func advance_phase() -> void:
	# Simple Turn loop for Engagement; can be extended later
	if stage != BattleStage.ENGAGEMENT:
		return

	match phase:
		TurnPhase.RALLY:
			phase = TurnPhase.ISSUE_ORDERS
		TurnPhase.ISSUE_ORDERS:
			phase = TurnPhase.EXECUTE
		TurnPhase.EXECUTE:
			phase = TurnPhase.RESOLVE_COMBAT
		TurnPhase.RESOLVE_COMBAT:
			phase = TurnPhase.RALLY
			turn_index += 1
```

Tests for this module should assert:
- Stages follow the documented order.
- Engagement has a repeating Turn/phase cycle.
- Campaign rules can override when Engagement stops (e.g. max turn count).

---

## 4. Orders & actions (true simultaneous turns)

Source: `Terminology – Fighting a Battle`, Order System, Basic Actions, Reactions, Surging.

```gdscript
extends Resource
class_name OrderData

enum OrderType { MOVE, ATTACK, ACTIVATE, SURGE, REPOSITION, EVADE, RETURN_FIRE }

@export var unit_id: String
@export var order_type: OrderType
@export var parameters: Dictionary = {}   # e.g. { "target_position": Vector2i(3, 4) }
```

An `OrderResolver` script can then:
- Collect hidden orders during the appropriate Phase.
- Reveal and resolve them together according to Basic Actions, Reactions, and Surging rules.

---

## 5. Test patterns (GDScript)

For any generated script, add a minimal test file under `generated/tests/` (using GUT or a similar framework), for example:

```gdscript
extends GutTest

func test_battle_flow_advances_stages_in_order() -> void:
	var battle := BattleState.new()
	assert_eq(battle.stage, BattleState.BattleStage.PLANNING)

	battle.advance_stage()
	assert_eq(battle.stage, BattleState.BattleStage.DEPLOYMENT)

	battle.advance_stage()
	assert_eq(battle.stage, BattleState.BattleStage.ENGAGEMENT)

	battle.advance_stage()
	assert_eq(battle.stage, BattleState.BattleStage.CONSOLIDATION)
```

Name tests after the relevant sections in the GDD (e.g. “Timings – Battle stages”, “Zones – In Play / Removed from Play”) so designers can easily cross-reference rules and engine behavior.
