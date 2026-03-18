# Ralph Progress Log

This file tracks progress across iterations. Agents update this file
after each iteration and it's included in prompts for context.

## Codebase Patterns (Study These First)

- **ECS Terminology Mapping**: In Terminology.md, Entity=ID, Tags=marker Components, Zones=state Components managed by the Zone System, game object types (Unit, Model, Item, Commander, Army, Battleforce)=archetypes with characteristic Component sets. Combat Resolution is described as the Combat System pipeline with Attack Pipeline (reads attacker Components, produces Damage Instances) and Defense Pipeline (reads target Components, consumes Damage Instances).
- **Cross-reference style**: Rule references use the format "see rule NNN.N in [Document Name]" consistently throughout GDD documents.
- **Entity System Rules numbering (post-ECS rewrite)**: Section 200 now has rules 200.1 Entity, 200.2 Components, 200.3 Marker Components (Tags), 200.4 Systems, 200.5 Archetypes, 200.6 Object References. External references to old 200.2 (Tags) and 200.3 (Object References) must update to 200.3 and 200.6 respectively.
- **Movement & Positioning spatial Components**: PositionComponent, FacingComponent, FootprintComponent, FormationComponent are defined in Movement Rules (300-series) and extend the Entity System Rules Component catalog (Appendix A.2). Battlefield-level Components (BattlefieldDimensionsComponent, DeploymentZonesComponent, ReinforcementEdgesComponent, TerrainIndexComponent) are also defined there. The Movement System and Deployment System are the two Systems that operate on spatial data.
- **Campaign Modifiers as Component modifications**: Campaign Modifiers (850-series) work by modifying Components on Battle-level Entities (e.g., overriding BattlefieldDimensionsComponent, setting TurnLimitComponent, injecting Roster requirements) or overriding System parameters — not by defining freeform rule text. The Campaign System layers active Modifiers by precedence before passing control to Activity resolution Systems.
- **Tabletop holdover detection heuristic**: A concept is a tabletop holdover if it: (1) introduces named relationships that duplicate standard ECS reference semantics (Bearer), (2) propagates state between Entity levels to avoid runtime queries (Tag/State Inheritance), (3) defines rules-level concepts that no System reads or writes (Datasheets, Armour Type), (4) conflates orthogonal concerns for physical-play convenience (Roster-as-Zone), or (5) leaves constraints in prose rather than structured data (Equipment constraints). See Appendix B in Entity System Rules for the full catalog.
- **Battle archetype and Battle System**: The Battle Entity has 12 characteristic Components (BattleStageComponent, TurnCounterComponent, PhaseComponent, BattlefieldRefComponent, BattleforceRefsComponent, VictoryConditionsComponent, ScoringComponent, TurnLimitComponent, OrderQueueComponent, ReactionQueueComponent, CasualtyReportComponent, RandomSeedComponent). The **Battle System** orchestrates Battle flow by advancing BattleStageComponent through Stages and PhaseComponent through Phases, delegating to Combat/Morale/Movement/Deployment/Zone/Ability Systems during specific Phases. "The engine" → specific System name.

---

## 2026-03-18 - simple-war-cuq.11
- Added Appendix A: ECS Architecture Reference to Entity System Rules.md
- Files changed: `Game Design Document/Gameplay Rules/Entity System Rules.md`
- **Learnings:**
  - The existing document already had ECS content spread across rules (200.1–200.6), Implementation Notes (Component structs, System table), and the glossary — the appendix consolidates these into a single quick-reference
  - Campaign-level Entities (Campaign, Sector Map, Plot, Connection, Activity) were defined in Campaign Rules but never mapped as ECS archetypes in Entity System Rules; the appendix bridges that gap
  - PositionComponent is referenced by the Movement System ("writes Position data") but was not previously listed in the Component Definitions — now explicitly cataloged
  - Deployment System and Campaign System were not in the original Systems table (rule 200.4) — added to the appendix catalog without modifying the existing rules section, since those Systems' details are owned by Battle Rules and Campaign Rules respectively
  - Non-Entity objects (Campaign Resource, Score, Deployment process, Damage Instance) are worth cataloging explicitly to prevent confusion about what is/isn't an Entity
  - The appendix format (A.1–A.5 with tables) keeps the reference concise while covering all five deliverables from the bead: Entity=ID, Component catalog, System catalog, Tag mapping, archetype mapping
---

## 2026-03-18 - simple-war-cuq.14
- Updated Gameplay Rules/Terminology.md to use ECS terminology consistently
- Files changed: `Game Design Document/Gameplay Rules/Terminology.md`, `Game Design Document/Overview/Terminology.md`
- **Learnings:**
  - The ECS architecture section was added as a new top-level section after Players, defining Entity (ID), Component (data), System (logic), and archetype (common Component combination)
  - Tags are reframed as "marker Components" throughout — Components that carry no data beyond their presence
  - Zones are reframed as state Components managed by the Zone System, not "used like Tags"
  - Combat Resolution is reframed as the Combat System with Attack Pipeline and Defense Pipeline stages describing data flow through Components
  - All game object types (Commander, Army, Battleforce, Unit, Model, Item) are described as "archetypes" with their characteristic Component sets listed
  - Entity System Rules (section 200-270) has NOT yet been rewritten for ECS (bead .12 is still open) — Terminology.md now leads the way on ECS framing
  - StrReplace can be finicky with long multi-paragraph blocks on Windows; shorter, more targeted replacements work more reliably
---

## 2026-03-18 - simple-war-cuq.12
- Rewrote Entity System Rules.md top-to-bottom with ECS architecture
- Files changed: `Game Design Document/Gameplay Rules/Entity System Rules.md`, `Game Design Document/Gameplay Rules/Terminology.md`
- **Learnings:**
  - Added new rules 200.2 (Components), 200.4 (Systems), 200.5 (Archetypes) to section 200; old 200.2 (Tags) → 200.3, old 200.3 (Object References) → 200.6
  - Introduced Systems table (Zone, Combat, Morale, Ability, Movement) with reads/writes columns in Implementation Notes
  - Every Component is now named explicitly (StatlineComponent, MoraleStateComponent, ZoneComponent, etc.) in both rules and implementation notes
  - All archetypes (Model, Unit, Item, Commander, Army, Battleforce) are defined in a summary table at 200.5 and detailed in their own sections with Component lists
  - Glossary expanded with ECS-specific entries: Component, Data Component, Marker Component, System, Archetype, Destruction State Component, Morale State Component, Value Component, Zone Component, Attack Pipeline, Defense Pipeline, Damage Instance
  - Implementation Notes refactored from per-entity-type state lists to explicit Component definitions and a System Responsibilities table
  - Cross-references in Terminology.md updated for renumbered rules (200.2→200.3, 200.3→200.6)
  - Sections 210–270 kept same numbering — no downstream breakage for Battle Rules, Movement Rules, etc.
---

## 2026-03-18 - simple-war-cuq.17
- Updated Movement and Positioning Rules.md for full ECS alignment
- Files changed: `Game Design Document/Gameplay Rules/Movement and Positioning Rules.md`
- **Learnings:**
  - Replaced all tag-based terrain references (`Blocking tag`, `Flying tag`, `Grounded tag`) with terrain Entity marker Components (`Blocking` marker Component, `Flying` marker Component, `Grounded` marker Component)
  - Introduced new spatial Components: PositionComponent, FacingComponent, FootprintComponent, FormationComponent for Units; RelativePositionComponent for Models; BattlefieldDimensionsComponent, DeploymentZonesComponent, ReinforcementEdgesComponent, TerrainIndexComponent for the Battlefield Entity
  - The Movement System and Deployment System are now explicitly identified as the two Systems operating on spatial data, with reads/writes tables in Implementation Notes
  - "engine" references throughout the original document were replaced with the specific System responsible (Movement System or Deployment System) — aligns with ECS principle that Systems contain all logic
  - Implementation Notes restructured from per-entity state lists to Component definition tables matching the format in Entity System Rules
  - Keyword references like "Infantry-keyword Units" became "Units with the `Infantry` marker Component" — consistent with the ECS pattern established in Entity System Rules and Terminology.md
  - Created follow-up beads: simple-war-ox9 (Terrain Rules 600-series) and simple-war-smx (FormationComponent expansion beyond rectangular_block)
  - The existing footprint ambiguity bead (simple-war-d57) already covers the "may shrink" wording in 320.1
---

## 2026-03-18 - simple-war-cuq.16
- Updated Campaign Rules.md for full ECS alignment
- Files changed: `Game Design Document/Gameplay Rules/Campaign Rules.md`
- **Learnings:**
  - Replaced "Entity with the X tag" patterns for all 5 campaign-level archetypes (Campaign, Sector Map, Plot, Connection, Activity) with archetype + Component definitions matching the format established in Entity System Rules
  - Replaced all "the engine" references with "the Campaign System" — the Campaign System was already cataloged in Entity System Rules Appendix A.3 but never referenced from Campaign Rules
  - Campaign Modifiers (section 850) were reframed from "rule statements" to "Component modifications and System parameter overrides" — this is the key ECS insight for how Campaigns create variety: they modify Components on Battle Entities (BattlefieldDimensionsComponent, DeploymentZonesComponent, TurnLimitComponent) and inject System hooks rather than defining freeform rule text
  - Implementation Notes restructured from flat state-per-object lists to proper Component definitions with types, matching the Entity System Rules format; added a Campaign System reads/writes table
  - Property tables in Plot (810.2), Connection (810.3), and Narrative Event (823.2) updated from "Tags: set of strings" to "Marker Components: set of strings"
  - Created 3 follow-up beads for tabletop holdovers: simple-war-bpx (board-game Sector Map → digital-native alternatives), simple-war-c30 (manual Commander movement → digital alternatives), simple-war-aqh (Campaign Rounds → digital time model)
  - The Campaign Rules document had no references to old rule numbers (200.2, 200.3) that needed updating — it was written after the Entity System Rules ECS rewrite
  - Several Campaign Modifier subcategories (850.2d Battlefield Modifications, 850.2f Additional Battle Rules) now explicitly reference spatial Components from Movement Rules (BattlefieldDimensionsComponent, TerrainIndexComponent, DeploymentZonesComponent), creating a tighter cross-document dependency
---

## 2026-03-18 - simple-war-cuq.15
- Updated Battle Rules.md for full ECS alignment
- Files changed: `Game Design Document/Gameplay Rules/Battle Rules.md`
- **Learnings:**
  - Defined the **Battle archetype** with 12 characteristic Components (BattleStageComponent, TurnCounterComponent, PhaseComponent, BattlefieldRefComponent, BattleforceRefsComponent, VictoryConditionsComponent, ScoringComponent, TurnLimitComponent, OrderQueueComponent, ReactionQueueComponent, CasualtyReportComponent, RandomSeedComponent) — this is the most Component-heavy archetype so far because Battles carry so much runtime state
  - Introduced the **Battle System** as the orchestrating System that delegates to Combat, Morale, Movement, Deployment, Zone, and Ability Systems during specific Phases — Terminology.md already referenced "the engine's Battle System" so this was a natural formalization
  - All 15+ "the engine" references mapped to specific Systems: Battle System (orchestration, Turn/Phase advancement, Order reveal, cleanup), Zone System (Roster validation, Zone transitions, Reserves checks), Deployment System (Unit placement), Movement System (movement resolution), Combat System (attack resolution, Melee), Morale System (Morale Tests, recovery)
  - The CasualtyReportComponent on the Battle Entity is distinct from the Casualty Report Zone on Units — the Zone is a ZoneComponent value on destroyed Units, while the Component on the Battle Entity is the ordered log with metadata (Turn, cause, remaining Models)
  - TurnLimitComponent was already referenced in Campaign Rules (Campaign Modifiers set it on Battle Entities) — maintaining that cross-document dependency
  - Order and Reaction structs defined as nested data structures within OrderQueueComponent and ReactionQueueComponent, following the pattern of embedding struct definitions in Implementation Notes
  - **Tabletop holdovers flagged** as follow-up beads: (1) Melee as implicit proximity state with no Component representation (simple-war-tva), (2) Line of Sight referenced but never defined (simple-war-xzd), (3) Pre-Engagement Movement as vague prose rather than Ability Component (simple-war-beo)
  - The Glossary section expanded significantly (~15 new entries) because Battle Rules introduces many Battle-specific concepts (Battle System, OrderQueueComponent, PhaseComponent, etc.) that other documents will cross-reference
  - Section 133.5 attack resolution now explicitly labels Attack Pipeline and Defense Pipeline steps, matching the Combat System pipeline description in Terminology.md
---

## 2026-03-18 - simple-war-cuq.13
- Reviewed Entity System Rules for tabletop-derived concepts, added Appendix B: Tabletop Holdover Review with 8 identified holdovers and digital-native alternative proposals
- Created 8 follow-up beads: simple-war-6ey (Datasheets), simple-war-8hx (Bearer), simple-war-bnd (Tag Inheritance), simple-war-l4b (State Inheritance), simple-war-jbn (Armour Type), simple-war-nx8 (Equipment Constraints), simple-war-2vz (Roster as Zone), simple-war-6wu (Model-Unit hybrid)
- Files changed: `Game Design Document/Gameplay Rules/Entity System Rules.md`
- **Learnings:**
  - Datasheets (240.5) are purely a UI/presentation concern — no System reads or writes them, making them the clearest example of a tabletop artifact in the rules
  - Tag Inheritance (240.3) and State Inheritance (240.4) are both tabletop shortcuts for what should be System-level queries in digital; they create implicit state propagation that crosses System boundaries on Model destruction
  - The Bearer relationship (230.2) is standard ECS reference semantics dressed in tabletop language — all four "Bearer rules" are already implied by EquippedItemsComponent being a reference list
  - Armour Type is dead data: required field with zero System consumers; needs either removal, promotion to marker Component, or defined mechanical interactions
  - Equipment constraints are the only concept in Entity System Rules that remains prose-defined rather than structured data — every other concept has been formalized into Components, but equipment slot limits and mutual exclusions are still natural-language footnotes
  - Roster-as-Zone is a semantic conflation: Zones answer "where is this Entity?" while Rosters answer "does this Battleforce meet requirements?" — these are orthogonal concerns in a digital system
  - The Model-Unit resolution hybrid is likely an intentional design choice (tactical depth from per-Model casualties + manageable cognitive load from Unit-level Orders) but needs explicit rationale documentation rather than being an inherited tabletop assumption
  - Priority assignments: Tag Inheritance, State Inheritance, Equipment Constraints, and Roster-as-Zone are P2 (affect System design directly); Datasheets, Bearer, Armour Type, and Model-Unit hybrid are P3 (lower structural impact)
---

## 2026-03-18 - simple-war-cuq.19
- Aligned src/data/*.json and src/data/loaders/*.gd with ECS terminology
- Files changed:
  - `src/data/Models.json` — renamed `items` to `equipped_items` (EquippedItemsComponent)
  - `src/data/loaders/model_data.gd` — renamed `items` var to `equipped_items`, added ECS Component mapping docstring
  - `src/data/loaders/unit_data.gd` — added ECS archetype + Component mapping docstring
  - `src/data/loaders/unit_factory.gd` — reads `equipped_items` from JSON, ECS-aligned comments
  - `src/data/loaders/item_data.gd` — added ECS Item archetype + Component mapping docstring
  - `src/data/loaders/item_factory.gd` — ECS-aligned docstring (AttackProfileComponent, ArmourComponent)
  - `src/data/loaders/armour_data.gd` — docstring references ArmourComponent and Defense Pipeline
  - `src/data/loaders/attack_profile.gd` — docstring references AttackProfileComponent and Attack Pipeline
  - `src/data/loaders/attack_factory.gd` — docstring references Attack Pipeline, AttackProfileComponent
  - `src/data/loaders/game_data.gd` — docstring references ECS archetype Entity construction
  - `src/battles/resolution/attack_resolver.gd` — docstring → "Combat System Attack Pipeline"
  - `src/battles/resolution/defense_resolver.gd` — docstring → "Combat System Defense Pipeline"
  - `src/battles/resolution/combat_orchestrator.gd` — docstring → "Combat System orchestrator"
  - `src/battles/resolution/scenario_runner.gd` — docstring → "Unit archetype Entity instances"
  - `src/battles/resolution/combat_event.gd` — docstring → "Attack Pipeline"
  - `src/battles/resolution/damage_instance.gd` — docstring → "Damage Instance, Defense Pipeline"
  - `src/ui/battlefield.gd` — docstring → "Unit Entities, Combat System pipeline"
  - `test/unit/test_attack_resolver.gd` — `.items` → `.equipped_items` (8 occurrences)
  - `test/unit/test_defense_resolver.gd` — `.items` → `.equipped_items` (4 occurrences)
  - `test/unit/test_combat_orchestrator.gd` — `.items` → `.equipped_items` (2 occurrences)
- **Learnings:**
  - Most JSON field names already mapped cleanly to ECS Component names in snake_case: `faction_keywords` → FactionKeywordsComponent, `composition` → CompositionComponent, `value` → ValueComponent. The only structural rename needed was `items` → `equipped_items` (EquippedItemsComponent)
  - The `weapon_skill` dictionary on Units/Models is a prototype extension not yet formalized in the Entity System Rules Component catalog — documented as "WeaponSkillComponent (prototype extension)" in docstrings to flag it for future formalization
  - The `items` → `equipped_items` rename rippled to 4 downstream files (3 test files + unit_factory) with 14 total occurrence changes — manageable because all access to the field is through the ModelData class (good encapsulation)
  - Items.json's root key `"items"` is the collection name for Item Entities, distinct from the Model-level EquippedItemsComponent field — these are different concepts that happened to share a name before the rename
  - ArmourData.type (Armour Type) is flagged as a tabletop holdover in Entity System Rules Appendix B (dead data with zero System consumers) — left in place since it's not this bead's scope to remove it
  - The Combat System's two pipeline stages (Attack Pipeline → Damage Instances → Defense Pipeline) map directly to the resolver architecture (AttackResolver → DamageInstance → DefenseResolver) — the ECS docstring updates make this explicit
---

## 2026-03-18 - simple-war-cuq.18
- Updated `Game Design Document/Overview/Main Concepts` to describe the game in ECS terms while preserving the player-facing UX framing
- Files changed: `Game Design Document/Overview/Main Concepts`
- **Learnings:**
  - Added new section 2 "Architecture: Entity–Component–System" with archetype table (8 archetypes) and System table (8 Systems) — this provides a single-page bridge between the player-facing overview and the detailed Entity System Rules
  - Section numbering shifted: old sections 2–8 became 3–9 to accommodate the new architecture section
  - Player Activities section (now section 3) gained ECS framing: Commanders described as Commander archetype Entities, Campaign restrictions described as Campaign Modifiers (Component modifications + System parameter overrides), Roster validation attributed to the Zone System, Battles attributed to the Battle System
  - Reinforcements reframed from "Units not Deployed at start" to "Units whose Zone Component is set to Reserves rather than Battlefield" — consistent with the Zone System terminology
  - Campaign section (now section 5) reframed Campaign Modifiers from "modify how Battles work" to "modify Components on Battle Entities and override System parameters" with concrete examples (TurnLimitComponent, BattlefieldDimensionsComponent, VictoryConditionsComponent)
  - Battle Stages section (now section 8) attributes each Stage's operations to specific Systems: Zone System validates in Planning, Deployment System places in Deployment, Battle System delegates to Combat/Movement/Morale/Zone/Ability Systems in Engagement, CasualtyReportComponent and ScoringComponent record in Consolidation
  - Unit Editor's "Datasheet Editor" renamed to "Component Editor" to align with ECS (Datasheets are flagged as a tabletop holdover in Entity System Rules Appendix B)
  - Campaign Editor's Properties Panel now mentions that Campaign Modifiers are configured as Component modifications, not freeform rule text
  - The UX section (section 4) remained largely intact since it describes player-facing screens, but terminology was tightened: "Datasheet" → Component language, structural validity references Component names
  - Cross-references use the established "see rule NNN.N in [Document Name]" format; broader section references use "see section NNN in [Document Name]" when the concept spans multiple rules
---

