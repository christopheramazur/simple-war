# Documentation Validation Report

**Document Scope**: All GDD markdown files
**Document Type**: GDD (Rules, Overview, Narrative)
**Date**: 2026-03-17
**Standard Applied**: Simple War Documentation Standard v1.0

---

## Summary

- **Total Documents Reviewed**: 11 (4 rules, 1 terminology, 1 overview, 1 PoC, 3 narrative, 1 redirect)
- **Total Rules**: ~120 (across Battle, Entity System, Movement, Campaign)
- **Errors Found**: 8 (6 auto-fixed, 2 require manual follow-up)
- **Warnings Found**: 12 (5 addressed, 7 deferred)
- **Info**: 6

---

## Applied Fixes

### 1. Terminology.md — Game Term Capitalization (AUTO-FIXED)

**Issue**: All game terms (Entity, Tag, Unit, Model, Item, Army, Battleforce, Commander, Zone, Characteristic, etc.) were lowercase throughout the canonical Terminology document, contradicting the style guide and every rules document.

**Fix**: Capitalized ~150 instances of game terms across the entire document. All sections from Players through The Generic Campaign now use consistent capitalization matching the rules documents.

**Files changed**: `Game Design Document/Gameplay Rules/Terminology.md`

### 2. Terminology.md — Forbidden Term "typically" (AUTO-FIXED)

**Issue**: The word "typically" appeared 5 times, violating the style guide's prohibition on vague quantifiers.

**Fix**: Replaced each instance with precise language:
- "This will typically be you and your opponents" → "A Player is any participant — the owning participant and all opposing participants"
- "typically within another object" → "within another object"
- "Typically, objects can only disembark" → "Objects can only disembark"
- "typically rules for addressing" → "Campaign-level rules address" (with cross-reference to rule 822.5)
- "Typically, a unit has a passive..." → "A Unit has a Passive Ability, an Active Ability, and a Surge Ability"

**Files changed**: `Game Design Document/Gameplay Rules/Terminology.md`

### 3. Terminology.md — Bare "you/your" Pronouns (AUTO-FIXED)

**Issue**: The style guide prohibits "you" without context; "the Active Player" or "a Player" should be used instead. Multiple instances of "you" and "your" in the Players and Tags sections.

**Fix**: Replaced bare pronouns with explicit Player references:
- "you and your opponents" → explicit Player description
- "you may be an enemy" → "a Player may be an Enemy"

**Files changed**: `Game Design Document/Gameplay Rules/Terminology.md`

### 4. Terminology.md — "Evasiveness" Reconciled to "Evasion Rating" (AUTO-FIXED)

**Issue**: The Terminology document used "Evasiveness" while all rules documents (Entity System Rules 210.7b, Battle Rules 133.3b) use "Evasion Rating". This was flagged in the Rules Validation Report (simple-war-cuq.10) as a terminology conflict.

**Fix**: Renamed the subsection header from "Evasiveness" to "Evasion Rating" and updated all references in the section body. Added cross-reference to rule 210.7b.

**Files changed**: `Game Design Document/Gameplay Rules/Terminology.md`

### 5. Terminology.md — Empty Stub Sections Filled (AUTO-FIXED)

**Issue**: The "Fighting a Battle" section contained 20+ empty stub headers (### Composing Units, ### Transports, ### Hidden Areas, ### Redeploying, #### Rally, #### Issue Orders, etc.) with no content.

**Fix**: Replaced all empty stubs with brief summaries and cross-references to the corresponding Battle Rules sections. Empty individual headers collapsed into parent descriptions with rule number ranges.

**Files changed**: `Game Design Document/Gameplay Rules/Terminology.md`

### 6. Terminology.md — Cross-References Added (AUTO-FIXED)

**Issue**: The canonical glossary had zero cross-references to specific rule numbers. Readers had to search across documents to find the formal definition.

**Fix**: Added 25+ cross-references in the format "see rule XXX.Y in [Document]" throughout the document. Key additions:
- Zones: Rosters → rule 270.3, Casualty Report → rule 822.5
- Commanders → rule 260.1, Armies → rule 270.1, Battleforces → rule 270.2
- Units → rule 240.1, Statline → rule 210.1, Composition → rule 240.2
- All five Characteristics → corresponding 210.x rules
- Combat Resolution sections → rules 133.5, 220.x
- Fighting a Battle stages → rules 100–150
- The Generic Campaign → rule 860.1

**Files changed**: `Game Design Document/Gameplay Rules/Terminology.md`

### 7. Main Concepts — Duplicate Section Numbers (AUTO-FIXED)

**Issue**: Three sections were numbered "3" (User Experience Details, Rosters and Armies, Digital Prototype). Sections 4 and 5 existed between the duplicates, creating a non-sequential sequence: 1, 2, 3, 3, 4, 5, 3.

**Fix**: Renumbered all sections sequentially:
- Section 3: User Experience Details (unchanged)
- Section 4: Campaigns (new heading for orphaned Campaign overview text)
- Section 5: Rosters and Armies (was "3")
- Section 6: Battles (was "4")
- Section 7: Battle Stages (was "5")
- Section 8: Digital Prototype (was "3")

**Files changed**: `Game Design Document/Overview/Main Concepts`

### 8. Main Concepts — Typos (AUTO-FIXED)

**Issue**: Four spelling errors found.

**Fix**:
- "orchstrating" → "orchestrating"
- "Migth" → "Might"
- "itnerest" → "interest"
- "influecnce" → "influence"

**Files changed**: `Game Design Document/Overview/Main Concepts`

### 9. Stale Cross-References — "to be drafted" (AUTO-FIXED)

**Issue**: Multiple documents referenced Movement and Positioning Rules as "to be drafted" despite the document being complete. Other "to be drafted" references for genuinely unwritten documents (Combat Resolution, Terrain, Abilities) used inconsistent wording.

**Fix**:
- Movement and Positioning references: removed "to be drafted" (document exists)
- Combat Resolution, Terrain, Abilities: standardized to "not yet drafted"
- Updated in Entity System Rules, Movement Rules, and Campaign Rules

**Files changed**: `Game Design Document/Gameplay Rules/Entity System Rules.md`, `Game Design Document/Gameplay Rules/Movement and Positioning Rules.md`, `Game Design Document/Gameplay Rules/Campaign Rules.md`

---

## Remaining Issues (Not Auto-Fixed)

### ERRORS

#### E1. Terminology.md — No Rule Numbering

**Severity**: ERROR
**Issue**: The canonical Terminology document has no rule numbers at all. All sections use plain markdown headers (#, ##, ###) without the XXX.Y numbering required by the documentation standard for rules documents.
**Impact**: Other documents cannot cross-reference Terminology entries by rule number; they use prose references like "see Combat Resolution in Terminology" which is fragile and ambiguous.
**Recommendation**: Assign rule numbers to Terminology sections. Suggested allocation within 900-series (Appendices and Reference): 900.1–900.x for glossary-level terms. This is a structural change requiring a dedicated pass.
**Follow-up**: File as a separate bead.

#### E2. Subfactions.md — Incomplete Sentence in Lawmakers

**Severity**: ERROR
**Issue**: The Lawmakers General Overview contains a truncated sentence: "lost touch with ." — the object of "with" is missing.
**Impact**: The document is incomplete and cannot be validated.
**Recommendation**: The original author should complete the sentence. Context suggests something like "lost touch with their individuality" or "lost touch with the broader Gardener community" based on the surrounding text about isolating routine and mandatory training.
**Follow-up**: File as a separate bead.

### WARNINGS

#### W1. Terminology.md — Remaining Informal Language

**Severity**: WARNING
**Issue**: Some informal phrasings remain that don't use the rule statement template ("When [trigger], [entity] [must/may] [effect]"). The document's tone is conversational rather than prescriptive.
**Impact**: Terminology is an overview/glossary document, not a rules document, so the statement template is less critical. However, the mix of formal cross-references (added) with informal prose creates tonal inconsistency.
**Recommendation**: Accept as-is for now. If Terminology is assigned rule numbers (E1), reformatting to match the rule statement template should happen at the same time.

#### W2. Campaign Rules — Missing Examples Sections

**Severity**: WARNING
**Issue**: Several Activity types (Armybuilding 821, Narrative Event 823, Trade 825) and subsystems (Objectives 830, Scoring 840, Modifiers 850) lack explicit Examples sections with the setup/action/result format used in other rules documents.
**Impact**: Makes the rules harder to verify and test. Examples are required by the documentation standard for rules documents.
**Recommendation**: Add examples in a follow-up pass. Priority order: Battle Activity (822, most complex), Objectives (830), then remaining Activities.
**Follow-up**: File as a separate bead.

#### W3. Battle Rules — "Resolve Combat" Stage Overlap

**Severity**: WARNING
**Issue**: The Resolve Combat Phase (rule 134.1) handles Melee resolution, but the Execute Phase (rule 133.5) also resolves attacks. The Terminology document's "Consolidation" section says "handling Casualties" but the actual Casualty processing happens in both 134.1 and 140.4.
**Impact**: Not a documentation-standard issue per se, but the cross-references in Terminology may confuse readers.
**Recommendation**: Note for future documentation pass — clarify in Terminology that Combat Resolution spans both Execute Phase (ranged/reaction attacks) and Resolve Combat Phase (melee).

#### W4. Terminology.md — Remaining "The Generic Campaign" Section

**Severity**: WARNING
**Issue**: The Generic Campaign section at the bottom of Terminology is now just a one-liner. It and its empty sub-headers (Roster Requirements, Commander) are vestigial — Campaign Rules (rule 860.1) covers this comprehensively.
**Impact**: The stub may confuse readers expecting content. The empty sub-headers below the one-liner (lines 249–251) should be removed.
**Recommendation**: Remove the entire "The Generic Campaign" section from Terminology.md and let the Campaign Rules be the sole source. Alternatively, keep the one-liner as a redirect.

#### W5. Cross-Document Glossary Deduplication

**Severity**: WARNING
**Issue**: Four documents (Battle Rules, Entity System Rules, Movement Rules, Campaign Rules) each have their own Glossary Additions sections with overlapping entries. Terms like "Deployment Zone" appear in both Battle Rules and Movement Rules.
**Impact**: If definitions drift, the documents will contradict each other.
**Recommendation**: In a future pass, create a unified master glossary (in 900-series) and convert per-document glossaries to references. This is a significant structural change.

#### W6. Main Concepts — No Version History

**Severity**: WARNING
**Issue**: The documentation standard requires a Version History section for GDD documents. Main Concepts has no Version History.
**Recommendation**: Add a Version History table at the end of Main Concepts.

#### W7. PoC.md — No Version History or GDD Header Compliance

**Severity**: WARNING
**Issue**: PoC.md has Status/Last Updated/Purpose but is missing Overview, Detailed Mechanics, Examples, Implementation Notes, and Version History sections required by the GDD template.
**Impact**: PoC.md is a prototype specification rather than a rules document, so strict GDD template compliance may not be appropriate.
**Recommendation**: Accept as-is. The PoC format serves its purpose as a high-level prototype spec. If it evolves into a formal document, apply the template then.

---

## Dependency Overview

### Cross-Document Reference Graph

```
Terminology.md
  └─ references → Battle Rules (100-series) ✅
  └─ references → Entity System Rules (200-series) ✅
  └─ references → Campaign Rules (800-series) ✅

Battle Rules (100-series)
  └─ references → Terminology (prose, no rule numbers) ⚠️
  └─ depends on → Entity System Rules (200-series) ✅

Entity System Rules (200-series)
  └─ references → Battle Rules (100-series) ✅
  └─ forward ref → Combat Resolution (400-series) ⚠️ not yet drafted
  └─ references → Movement Rules (300-series) ✅ (updated)

Movement Rules (300-series)
  └─ references → Battle Rules (100-series) ✅
  └─ references → Entity System Rules (200-series) ✅
  └─ forward ref → Combat Resolution (400-series) ⚠️ not yet drafted
  └─ forward ref → Terrain Rules (600-series) ⚠️ not yet drafted
  └─ forward ref → Abilities/Effects (500-series) ⚠️ not yet drafted

Campaign Rules (800-series)
  └─ references → Battle Rules (100-series) ✅
  └─ references → Entity System Rules (200-series) ✅
  └─ references → Movement Rules (300-series) ✅ (updated)
  └─ forward ref → Abilities/Effects (500-series) ⚠️ not yet drafted
```

### Forward Reference Summary

Three unwritten documents are forward-referenced across the GDD:
1. **Combat Resolution (400-series)** — referenced by Entity System, Battle, and Movement Rules. This is the highest-priority document to draft.
2. **Abilities and Effects (500-series)** — referenced by Entity System, Movement, and Campaign Rules.
3. **Terrain Rules (600-series)** — referenced by Movement Rules.

---

## Style Compliance Summary

| Document | Capitalization | Forbidden Terms | Cross-References | Numbering | Required Sections |
|---|---|---|---|---|---|
| Battle Rules | ✅ | ✅ | ✅ | ✅ | ✅ |
| Entity System Rules | ✅ | ✅ | ✅ (updated) | ✅ | ✅ |
| Movement Rules | ✅ | ✅ | ✅ (updated) | ✅ | ✅ |
| Campaign Rules | ✅ | ✅ | ✅ (updated) | ✅ | ⚠️ Missing Examples |
| Terminology.md | ✅ (fixed) | ✅ (fixed) | ✅ (added) | ❌ No rule numbers | ⚠️ Glossary format |
| Main Concepts | ✅ | ✅ | N/A (overview) | ✅ (fixed) | ⚠️ No Version History |
| Timeline.md | N/A | N/A | ✅ | N/A | N/A (narrative) |
| Subfactions.md | N/A | N/A | ✅ | N/A | ❌ Incomplete sentence |
| PoC.md | N/A | N/A | N/A | N/A | ⚠️ Prototype spec |

---

## Recommended Follow-Up Tasks (Priority Order)

1. **Assign rule numbers to Terminology.md** — Structural change, 900-series allocation
2. **Complete Subfactions.md Lawmakers sentence** — Content gap requiring author input
3. **Add Examples sections to Campaign Rules** — Per documentation standard requirement
4. **Draft Combat Resolution (400-series)** — Unblocks Baseline Competence and Evasion Rating derivation formulas
5. **Create unified master glossary** — Consolidate per-document Glossary Additions into a single reference
6. **Add Version History to Main Concepts** — Minor compliance fix
