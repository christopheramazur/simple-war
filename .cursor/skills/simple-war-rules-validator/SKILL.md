---
name: simple-war-rules-validator
description: Validates Simple War game rules for logical consistency, computability, and digitization readiness. Use when analyzing, reviewing, writing, or editing Simple War rules; when the user asks to check rules for ambiguities, conflicts, or whether mechanics can be coded; or when reviewing markdown that contains game rules. Trigger on "validate rules", "check rules", "rules consistency", or "can this be coded".
---

# Simple War Rules Validator

## Overview

Validates Simple War game rules for logical consistency, unambiguous language, computability, and digital implementation readiness. Checks rule conflicts, ambiguous language, timing/priority issues, and mechanics that cannot be digitized.

## Validation Workflow

1. **Parse the document** - Extract rules, identify dependencies and references
2. **Run validation checks** - Apply all validation categories
3. **Generate report** - Structured findings with severity tags
4. **Provide recommendations** - Specific suggestions for fixing issues

## Core Validation Principles

### Rules Build Sequentially
Rules should introduce concepts in order. A rule should only reference:
- Concepts defined earlier in the same document
- Concepts from foundational/prerequisite documents
- Self-contained concepts defined within the rule itself

**Red flag**: References to undefined terms, forward references, or concepts that should have been introduced at a higher level earlier.

### Rules Are Self-Explanatory
Rule text must be complete and unambiguous without relying on player interpretation of intent, physical judgment calls, or unstated conventions from other games. Explanatory text (e.g. quote boxes) supplements rules but does not replace precision in the rule itself.

### Compositional Complexity is Allowed but Tracked
Rules can reference other rules. **Deep compositions** (rule chains 4+ levels) and **wide compositions** (rule references 5+ other rules) are flagged for review—not as errors, but as complexity warnings.

## Validation Categories

### 1. Determinism & Computability

All mechanics must be implementable in code without human judgment.

**ERROR:** Ambiguous measurements ("near", "close to"), undefined randomness ("random amount"), physical dexterity, unmeasurable states ("appears threatening").
**PASS:** Explicit numerical values/ranges, well-defined randomness (dice, deck draws), grid/zone positioning, enumerable game states.

```
❌ "Place the model within a few inches of the objective"
✅ "Place the model within 3 inches of the objective"

❌ "Roll a die for each model. High rolls succeed."
✅ "Roll a die for each model. Results of 4+ succeed."
```

### 2. Rule Interactions & Priority

Check timing conflicts, circular dependencies, unclear precedence.

**ERROR:** Multiple effects "at the same time" without priority; circular rule references; contradictory rules without resolution; ambiguous timing ("after", "when", "immediately").
**WARNING:** Complex trigger chains; multiple simultaneous effects where order might matter; meta-rules.
**PASS:** Clear priority (e.g. "resolve in turn order"), defined phases/steps, explicit conflict resolution.

```
❌ "When a unit dies, both players draw a card" (who draws first?)
✅ "When a unit dies, players draw a card in turn order, starting with the active player"
```

### 3. State Representation

All game elements must be trackable in a digital state machine.

**ERROR:** Honor-system hidden information; analog-only positioning; unmeasurable quantities; states depending on physical components (sleeve color, base size).
**PASS:** Discrete positions (grid, zones, integer distances); enumerable entity states; hidden info with verification; serializable/restorable game state.

```
❌ "Line of sight is blocked if you can't see the model from your viewing angle"
✅ "Line of sight is blocked if a straight line from the center of the firing model's base to the center of the target's base passes through terrain with the Blocking tag"

❌ "Remember which units activated this turn"
✅ "Track each unit's activation status with the Activated tag. Remove all Activated tags at the end of the turn"
```

### 4. Language Precision

Check ambiguous language, undefined terms, inconsistent usage.

**ERROR:** Undefined terms; ambiguous pronouns ("it", "them"); inconsistent terminology; modal ambiguity ("may" vs "must"); vague quantifiers ("some", "most").
**WARNING:** Jargon from other games undefined; complex sentences; terms only in explanatory text.
**PASS:** Terms defined before use; consistent terminology; clear modals; precise quantifiers ("all", "each", "exactly 3").

```
❌ "Units with the Fast keyword can move further. They get bonuses when advancing."
✅ "Units with the Fast tag add 2 to their Movement value. When a unit with Fast makes a Run action, add an additional 2 to their Movement value for that action."

❌ "When it is destroyed, remove it from play"
✅ "When this unit is destroyed, remove this unit from play"
```

### 5. Dependency Ordering

Rules must reference only previously-defined concepts.

**ERROR:** Forward references; concepts used before definition; circular concept definitions; specific applications before general principles.
**WARNING:** Deep or wide concept dependencies.

Define foundational concepts (e.g. player relationships: Own, Allied, Enemy, Other, Any) before terms that use them (e.g. Commander, Campaign).

### 6. Compositional Complexity Tracking

Flag for manual review (not error): **Deep** = rule chains 4+ levels; **Wide** = rule references 5+ other rules. For each rule note direct dependencies, depth, and width. Flag depth ≥ 4 or width ≥ 5 as "High Compositional Complexity - Review Recommended".

## Validation Report Structure

Use this template:

```markdown
# Rules Validation Report
**Document**: [filename]
**Date**: [validation date]

## Summary
- Total Rules Analyzed: [count]
- Errors Found: [count]
- Warnings Found: [count]
- High Complexity Rules: [count]

## Errors
### [Rule Name or Section]
**Issue Type**: [Determinism | Priority | State Representation | Language Precision | Dependency Ordering]
**Severity**: ERROR
**Location**: [section/paragraph]
**Problem**: [Clear description]
**Failing Text**: > [Quote problematic text]
**Recommendation**: [Specific fix]
**Corrected Example**: > [If applicable]

---

## Warnings
[Same structure as Errors, Severity: WARNING]

## High Complexity Rules
### [Rule Name]
**Complexity Type**: [Deep | Wide]
**Depth**: [number] | **Width**: [number]
**Dependencies**: [List]
**Note**: Not erroneous but may need extra testing.

---

## Passed Rules
[Summary or count]

## Recommendations
[High-level suggestions]
```

## Usage

- **Single rule:** Parse rule → check all categories → mini-report with findings and fix recommendations.
- **Full document:** Parse into sections/rules → build dependency graph → run all checks → full report, critical issues first.
- **"Can this be coded?":** Focus on Determinism & State Representation; call out analog-only elements; suggest digital-friendly alternatives.
