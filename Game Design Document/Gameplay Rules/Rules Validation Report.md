# Rules Validation Report

**Documents Validated**: Battle Rules (100-series), Movement and Positioning Rules (300-series), Entity System Rules (200-series), Campaign Rules (800-series)
**Date**: 2026-03-17
**Methodology**: Applied all 6 validation categories from the Simple War Rules Validator skill (Determinism & Computability, Rule Interactions & Priority, State Representation, Language Precision, Dependency Ordering, Compositional Complexity)

---

## Summary

- Total Rules Analyzed: ~120 rules across 4 documents
- Errors Found: 10
- Warnings Found: 14
- High Complexity Rules: 4

---

## Errors

### E01: Combat Resolution Derivations Undefined
**Issue Type**: Determinism & Computability
**Severity**: ERROR
**Location**: Entity System Rules 210.7a/b; Battle Rules 133.5 step 3
**Problem**: Baseline Competence and Evasion Rating — both required by the hit probability formula — defer their derivations to the Combat Resolution rules (400-series), which do not exist. The hit probability formula (133.5 step 3) is therefore uncomputable.
**Failing Text**: > "Baseline Competence is derived from the Unit's Endurance. The exact derivation is specified in the Combat Resolution rules."
**Recommendation**: Either draft Combat Resolution (400-series) rules next, or provide interim formulas in the Entity System Rules so the PoC can implement hit resolution. Suggest: Baseline Competence = Endurance / 2 (percentage), Evasion Rating = (Reflex + Speed) / 4 (percentage) as placeholders.

---

### E02: Sub-lethal Damage Accumulation Undefined
**Issue Type**: Determinism & Computability
**Severity**: ERROR
**Location**: Entity System Rules 210.3
**Problem**: "Sub-lethal damage (damage below Durability) is tracked on the Unit for future resolution." No rule in any document specifies when or how accumulated sub-lethal damage resolves. Does damage accumulate across turns? If a Unit with 10 Durability takes 4 damage in Turn 1 and 6 damage in Turn 2, is it destroyed?
**Failing Text**: > "Sub-lethal damage (damage below Durability) is tracked on the Unit for future resolution."
**Recommendation**: Add explicit damage accumulation rule: "Damage instances accumulate on the Unit. When total accumulated damage on a Unit meets or exceeds that Unit's Durability, the Unit is destroyed." Or specify that each damage instance is resolved independently (no accumulation). The implementation notes already include `damage_taken: integer`, implying accumulation is intended.

---

### E03: Melee State Ambiguity
**Issue Type**: State Representation
**Severity**: ERROR
**Location**: Battle Rules 132.2e, 134.1; Battle Rules Glossary
**Problem**: Melee is defined in the glossary as "A state in which two or more opposing Squads are within 1 distance squad" but it is also described as something Squads are "placed in" (132.2e). It is unclear whether Melee is: (a) a tag/status applied to Squads when a Charge connects, or (b) a spatial condition re-evaluated each Phase. This distinction matters for: Can a Squad exit Melee by being pushed/repositioned away? Is Melee a zone?
**Failing Text**: > "the charging Squad and the target Squad are both placed in Melee"
**Recommendation**: Define Melee explicitly as a tracked state (tag) applied when a Charge makes contact or when Squads begin a Turn within 1 DU. Specify when the Melee tag is removed (e.g., when one Squad Falls Back, when one Squad is destroyed, when separation exceeds 1 DU at the start of a Phase).

---

### E04: Endurance Scope — Unit vs Squad
**Issue Type**: Language Precision
**Severity**: ERROR
**Location**: Entity System Rules 210.1–210.2; Battle Rules 132.4, 131.1
**Problem**: Endurance is defined as a Unit-level Characteristic (210.1: "Every Unit has exactly five Characteristics"), but all Battle Rules operate on Endurance at the Squad level ("Squad's Endurance," 132.4). Implementation notes store `endurance_remaining` per Squad. If Units in a Squad have different Endurance values, the Squad-level Endurance is undefined.
**Failing Text**: > "Endurance is an integer Characteristic representing a Unit's capacity..." (210.2) vs. "A Squad with zero remaining Endurance" (132.4)
**Recommendation**: Clarify that Endurance functions at the Squad level for Order restrictions and tracking (using the lowest Unit Endurance as the Squad's value, or the average, or first Unit's value). State explicitly which resolution applies.

---

### E05: Melee Participation After Ranged Attack
**Issue Type**: Rule Interactions & Priority
**Severity**: ERROR
**Location**: Battle Rules 134.1 step 1; Battle Rules 133.5
**Problem**: Melee Resolution in 134.1 says "Squads in Melee that have not yet attacked this Turn exchange attacks." A Squad that issued a Hold Order and attacked during 133.5 (Resolve Attacks) has "already attacked." If that Squad was then Charged into Melee, it cannot defend itself in the Melee Resolution step. The snapshot-calculate-apply unit means attacks in 133.5 are calculated before Melee is established by Charge movement, creating a paradox.
**Failing Text**: > "Squads in Melee that have not yet attacked this Turn exchange attacks simultaneously using melee weapon profiles."
**Recommendation**: Reword to: "All Squads in Melee exchange melee attacks, regardless of whether they attacked during the Execute Phase. Ranged attacks during the Execute Phase (rule 133.5) and melee attacks during the Resolve Combat Phase (rule 134.1) are independent combat events."

---

### E06: Attack Distribution Tiebreaker
**Issue Type**: Determinism & Computability
**Severity**: ERROR
**Location**: Battle Rules 133.5 step 2
**Problem**: "Distribute attacks from each attacking Unit to the closest Unit in the target Squad." When two or more target Units are equidistant from the attacker, the rule provides no tiebreaker. The result is non-deterministic.
**Failing Text**: > "Distribute attacks from each attacking Unit to the closest Unit in the target Squad."
**Recommendation**: Add tiebreaker: "If multiple target Units are equidistant, distribute attacks to the target Unit with the lowest remaining Durability. If still tied, distribute to the target Unit with the lowest ID (lexicographic)."

---

### E07: Temporary Tag Expiry Undefined
**Issue Type**: Determinism & Computability
**Severity**: ERROR
**Location**: Battle Rules 131.1 step 3
**Problem**: "Remove all expired temporary effects and tags" — but no rule defines how a tag is marked as temporary or when it expires. The Dug In tag (132.2f) says it's removed "when the Squad moves or the tag is otherwise removed by a rule," but there's no general mechanism for expiry tracking.
**Failing Text**: > "Remove all expired temporary effects and tags from all Squads."
**Recommendation**: Define a Temporary Tag as a tag with an associated expiry condition (e.g., "until end of Turn," "until the Squad moves," "for N Turns"). Add this to Entity System Rules 200.2 or a new sub-rule. The implementation notes already include `temporary_tags: set of strings with expiry metadata` — the rule text should match.

---

### E08: Partial Recovery Fractional Handling
**Issue Type**: Determinism & Computability
**Severity**: ERROR
**Location**: Campaign Rules 822.5 option 2
**Problem**: "A percentage of destroyed Squads (defined by the Campaign) are restored." If 3 Squads are destroyed and 50% recovery applies, 1.5 Squads would be recovered. No rounding rule is specified. Additionally, it's unclear whether "restored" means the entire Squad at full strength or each Squad with partial Unit recovery.
**Failing Text**: > "A percentage of destroyed Squads (defined by the Campaign) are restored. The remaining Squads are permanently lost."
**Recommendation**: Specify: (1) rounding rule (round down, so 3 × 50% = 1 Squad recovered); (2) whether recovered Squads are restored to full Unit count or retain their damage state from the Battle. Suggest: "Round down. Recovered Squads are restored to full Unit count."

---

### E09: Reposition Reaction Missing Endurance Gate
**Issue Type**: Rule Interactions & Priority
**Severity**: ERROR
**Location**: Battle Rules 133.3a; Entity System Rules 210.2
**Problem**: Reposition Reaction (133.3a) taxes Endurance by 1, but there is no explicit restriction preventing a Squad with 0 Endurance from declaring a Reposition. Rule 132.4 restricts Orders that tax Endurance but does not mention Reactions. Entity System 210.2 says "When a Squad's remaining Endurance reaches 0, that Squad may not receive Orders that tax Endurance" — Reactions are not Orders.
**Failing Text**: > "Cost: Taxes Endurance by 1." (133.3a) with no Endurance requirement stated.
**Recommendation**: Add to 133.3a Requirements: "The reacting Squad must have at least 1 remaining Endurance." Or add a general rule: "Any action that taxes Endurance requires the Squad to have at least 1 remaining Endurance."

---

### E10: Footprint "May Shrink" Ambiguity
**Issue Type**: Language Precision
**Severity**: ERROR
**Location**: Movement and Positioning Rules 320.1
**Problem**: "When Units are destroyed, the footprint may shrink as the remaining Units consolidate." The word "may" implies this is optional or conditional, but it's unclear who decides and when consolidation occurs. Footprint size directly affects collision, movement, and deployment validity.
**Failing Text**: > "When Units are destroyed, the footprint may shrink as the remaining Units consolidate."
**Recommendation**: Replace with: "When Units are destroyed, the Squad's footprint recalculates based on the remaining Unit count and the current formation (rule 320.3). The footprint dimensions update at the start of the Squad's next movement."

---

## Warnings

### W01: Forward References to Unwritten Rule Series
**Issue Type**: Dependency Ordering
**Severity**: WARNING
**Location**: All four documents
**Problem**: Multiple documents reference Combat Resolution (400-series), Abilities and Effects (500-series), and Terrain Rules (600-series), none of which exist. These are documented as intentional forward references.
**Note**: Expected during incremental drafting. Track as a known gap; prioritize 400-series next since it blocks the hit probability formula.

---

### W02: Floating-Point Precision in Distance Comparisons
**Issue Type**: Determinism & Computability
**Severity**: WARNING
**Location**: Movement Rules 300.3
**Problem**: Euclidean distance uses square roots, producing irrational numbers. Threshold comparisons ("within 3 distance squads") require floating-point comparison (e.g., √8 ≈ 2.8284...). Floating-point equality is error-prone.
**Recommendation**: Specify an epsilon tolerance (e.g., 0.001 DU) for all distance comparisons, or compare squared distances where possible to avoid square roots.

---

### W03: Surging Reset vs Non-Neutral Baseline
**Issue Type**: Rule Interactions & Priority
**Severity**: WARNING
**Location**: Battle Rules 131.1 step 1; Entity System Rules 210.4
**Problem**: "If a Squad's Morale state is currently Surging, the Squad's Morale resets to Neutral instead." But a Squad's Morale Baseline may be something other than Neutral (e.g., Good, if granted by an Ability). The rule always resets Surging to Neutral, even if the baseline is higher.
**Recommendation**: Confirm this is intentional (Surging always costs you by resetting to Neutral, even if your baseline is Good). If so, add a note. If not, change to "resets to the Squad's Morale Baseline."

---

### W04: Fall Back "Directly Away" Ambiguity
**Issue Type**: Language Precision
**Severity**: WARNING
**Location**: Battle Rules 132.2g
**Problem**: "Moves directly away from the nearest enemy Squad." If two enemy Squads are equidistant, "nearest" is ambiguous. Also, "directly away" could be misread as requiring a straight-line path when the path may need to route around obstacles.
**Recommendation**: Add tiebreaker for equidistant enemies (e.g., "away from the centroid of all equidistant nearest enemies"). Clarify that Fall Back follows standard pathfinding (310.5) in the direction away from the target.

---

### W05: Dual-Keyword Formation Tiebreaker
**Issue Type**: Determinism & Computability
**Severity**: WARNING
**Location**: Movement Rules 320.3
**Problem**: Formation defaults are defined per keyword (5 files for Infantry, 3 for Vehicle), but a Squad with both tags has no specified default.
**Recommendation**: Add precedence: "If a Squad has both Infantry and Vehicle keywords, use the Vehicle formation default (3 files)."

---

### W06: Return Fire "−1 Modifier" Ambiguity
**Issue Type**: Language Precision
**Severity**: WARNING
**Location**: Battle Rules 133.3c
**Problem**: "The Return Fire attack uses the reacting Squad's ranged weapon profiles with a −1 modifier to hit probability (representing hasty fire)." It's unclear whether "−1 modifier to hit probability" means −1 percentage point to the final probability or −1 to the additive modifier stack.
**Recommendation**: Reword to: "Apply a −1 additive modifier to the hit probability calculation (rule 133.5 step 3) for all attacks made via Return Fire."

---

### W07: Narrative Flag Value Types Unspecified
**Issue Type**: State Representation
**Severity**: WARNING
**Location**: Campaign Rules 823.4, Implementation Notes
**Problem**: Narrative flags are "key-value pairs" but the value type is not constrained. Can values be strings, integers, booleans, or arbitrary objects?
**Recommendation**: Specify: "Narrative flag values may be boolean, integer, or string. The Campaign definition specifies the type per flag."

---

### W08: Quickplay "Identical" Army Ambiguity
**Issue Type**: Language Precision
**Severity**: WARNING
**Location**: Campaign Rules 860.2
**Problem**: "Battle against an identical AI-controlled Battleforce led by an identical AI Commander." Identical to the Player's selected Army? Or an identical pre-built set?
**Recommendation**: Reword to: "Battle against an AI-controlled Battleforce that mirrors the Player's selected Battleforce, led by an AI Commander with the same Characteristics as the Player's Commander."

---

### W09: Evasiveness vs Evasion Rating Terminology
**Issue Type**: Language Precision (Cross-Document)
**Severity**: WARNING
**Location**: Terminology.md (uses "Evasiveness"), Entity System Rules (uses "Evasion Rating")
**Problem**: Terminology.md describes "Evasiveness" as a concept; Entity System Rules formalize "Evasion Rating" as the derived Characteristic. The terms are not explicitly connected.
**Recommendation**: Update Terminology.md to replace "Evasiveness" with "Evasion Rating" or add a note: "Evasiveness in common usage refers to the Evasion Rating derived Characteristic (see rule 210.7b)."

---

### W10: Pivot Cost Language Inconsistency
**Issue Type**: Language Precision
**Severity**: WARNING
**Location**: Movement Rules 330.2 vs 330.3
**Problem**: Rule 330.2 says "The pivot cost is subtracted from the Squad's available movement distance." Rule 330.3 says "The cost of this adjustment is included in the path length." These are mathematically equivalent but use opposite framing (subtract from budget vs add to cost). This may confuse implementers.
**Recommendation**: Pick one framing consistently. Suggest: "Pivot cost is subtracted from the Squad's available movement distance before calculating the remaining path length."

---

### W11: Campaign Elimination Computability
**Issue Type**: Determinism & Computability
**Severity**: WARNING
**Location**: Campaign Rules 800.5 condition 3
**Problem**: "All of a Player's Commanders are permanently lost and the Player has no means to acquire new Commanders." The engine cannot generally determine whether a Player "has no means" without evaluating all future game states.
**Recommendation**: Replace with an explicit check: "All of a Player's Commanders are permanently lost and no Activity, Objective, or Campaign rule currently available to the Player grants a new Commander."

---

### W12: Endurance-Taxing Actions Not Enumerated
**Issue Type**: Language Precision
**Severity**: WARNING
**Location**: Battle Rules 131.1 step 2
**Problem**: "Each Squad that did not perform an Endurance-taxing action during the previous Turn." The term "Endurance-taxing action" is used but not formally defined as a category. Currently: Run, Charge, and Reposition Reaction tax Endurance.
**Recommendation**: Add a formal definition: "An Endurance-taxing action is any Order or Reaction whose description states that it taxes Endurance."

---

### W13: Player Entity Not Defined in Entity System
**Issue Type**: Dependency Ordering (Cross-Document)
**Severity**: WARNING
**Location**: Terminology.md vs Entity System Rules
**Problem**: Terminology.md says "Players are entities with the Player tag" but Entity System Rules do not define a Player Entity, its properties, or its Tags. The Entity-Type Tags table (200.2) includes "Player" but no section elaborates.
**Recommendation**: Add a brief section (e.g., 280 Players) to Entity System Rules defining the Player Entity, or note that Players are implicit Entities whose only required tag is Player.

---

### W14: Consumable Charges vs Item Count Ambiguity
**Issue Type**: Language Precision
**Severity**: WARNING
**Location**: Entity System Rules 220.10
**Problem**: "The number of charges is defined by the count of the Item in the Unit's equipment list." This conflates Item count with charges. If a Unit has 3 Frag Grenades, does each grenade have 1 use (3 total uses), or does the "Frag Grenade item" have 3 charges?
**Recommendation**: Clarify: "Each instance of a Consumable in the equipment list represents one charge. A Unit equipped with Frag Grenades (count 3) has 3 charges of the Frag Grenade Consumable."

---

## High Complexity Rules

### HC01: Battle Rules 133.5 — Resolve Attacks
**Complexity Type**: Wide
**Depth**: 3 | **Width**: 6
**Dependencies**: 133.3c (Return Fire), 132.2a/b/f (Hold/Advance/Dig In), Combat Resolution (Terminology), 210.7a (Baseline Competence), 210.7b (Evasion Rating), 210.7c (Armour Value)
**Note**: Central combat resolution rule. Width 6 is unavoidable; ensure thorough testing.

---

### HC02: Battle Rules 134.1 — Resolve Combat Phase
**Complexity Type**: Wide
**Depth**: 3 | **Width**: 5
**Dependencies**: 133.5 (attacks), 150.1 (end conditions), 131.1 (rally), 210.4 (morale), 132.2e (melee)
**Note**: Post-combat processing hub. Complexity justified by role.

---

### HC03: Campaign Rules 822 — Battle Activity
**Complexity Type**: Deep
**Depth**: 4 | **Width**: 5
**Dependencies**: Battle Rules (100-150), Entity System (260-270), Campaign Modifiers (850), Objectives (830), Scoring (840)
**Note**: Deepest rule chain in the ruleset. The bridge between Campaign and Battle layers requires all five referenced systems. Consider detailed integration tests.

---

### HC04: Movement Rules 310.5 — Obstruction and Pathfinding
**Complexity Type**: Wide
**Depth**: 3 | **Width**: 4
**Dependencies**: 300.5 (boundary), 310.7b (blocking terrain), 310.6 (collision), external pathfinding system
**Note**: Continuous-space pathfinding is computationally non-trivial. Implementation notes appropriately recommend nav mesh or visibility graph.

---

## Passed Rules (Summary)

The following areas passed all validation categories with no issues:

- **Battle Stages structure** (100.1–100.2): Clear, deterministic, fully enumerable.
- **Planning Stage** (110.1–110.6): Well-ordered steps, no ambiguity.
- **Deployment Stage** (120.1–120.4): Clear constraints, good examples.
- **Turn and Phase structure** (130.1–130.3): Deterministic, sequential, no timing conflicts.
- **Order types** (132.2a–132.2h): Individual Order definitions are precise (except Fall Back tiebreaker, flagged as W04).
- **Simultaneous Resolution unit** (snapshot-calculate-apply): Excellent design. Fully deterministic by construction.
- **Battlefield Geometry** (300.1–300.5): Precise coordinate system, clear boundary rules.
- **Movement mechanics** (310.1–310.7): Path length vs displacement distinction well-handled.
- **Facing and Pivoting** (330.1–330.3): Clear formula with good examples.
- **Deployment Positioning** (340.1–340.5): Thorough, with reinforcement edge rules.
- **Movement Restrictions** (350.1–350.5): Correctly cross-references Battle Rules.
- **Entity and Tag system** (200.1–200.3): Clean, composable, minimal.
- **Characteristics** (210.1–210.6): Well-defined base Characteristics (aside from E04).
- **Items, Weapons, Armour** (220.1–220.10): Thorough type system with good dual-type support.
- **Units** (230.1–230.2): Clear bearer relationship.
- **Squads** (240.1–240.6): Tag inheritance and State inheritance well-specified.
- **Abilities** (250.1–250.4): Clean type taxonomy with rule statement templates.
- **Commanders, Armies, Battleforces** (260–270): Solid command hierarchy.
- **Campaign structure** (800.1–800.6): Well-organized three-stage framework.
- **Sector Map** (810.1–810.6): Clean graph unit with validation constraints.
- **Activities** (820–825): Well-typed Activity system.
- **Objectives** (830.1–830.3): Clear types, evaluation points, assignee scopes.
- **Scoring** (840.1–840.4): Thorough integration methods with tiebreakers.
- **Campaign Modifiers** (850.1–850.4): Good precedence rules.
- **Campaign Templates** (860.1–860.5): Clear hierarchy from Generic to Story.

---

## Recommendations

1. **Priority: Draft Combat Resolution (400-series)** — This unblocks E01, E02, and partially W01. The PoC build depends on hit/damage formulas.
2. **Formalize Melee as a tracked state** (E03) — Critical for the PoC's Engagement loop.
3. **Clarify Endurance scope** (E04) — Decide Squad vs Unit and document the resolution. The PoC implementation needs this for Order validation.
4. **Add general Endurance gate for all taxing actions** (E09) — Small clarification, big impact on consistency.
5. **Define temporary tag expiry mechanism** (E07) — The Dug In tag is used in the PoC; the expiry mechanism must be implementable.
6. **Reconcile Terminology.md** with the four rules documents (W09, W13) — The canonical terminology source should be updated to match the formalized rules.
7. **Consider epsilon-based distance comparisons** (W02) — Important for the digital engine to avoid floating-point edge cases.

---

## Version History

| Version | Date | Changes |
|---|---|---|
| 1.0 | 2026-03-17 | Initial validation of Battle, Movement, Entity System, and Campaign Rules |
