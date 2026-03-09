---
name: simple-war-documentation-standard
description: Enforces consistent documentation standards for Simple War. Use when writing, editing, or reviewing any Simple War document including rules, GDD sections, entity data sheets, or design documents. Trigger on "check documentation", "format this rule", "validate cross-references", "update glossary", or when working with any Simple War markdown. Ensures consistent terminology, proper cross-referencing, glossary maintenance, and adherence to style guide.
---

# Simple War Documentation Standard

Enforces documentation consistency across all Simple War materials: rule numbering, cross-references, glossary, dependencies, and style guide.

## Documentation Workflow

When working with Simple War documents:

1. **Parse Document** — Extract structure, cross-references, terms
2. **Validate Format** — Check numbering, headers, required sections
3. **Check Cross-References** — Verify all references are valid
4. **Update Glossary** — Add new terms, flag inconsistencies
5. **Generate Dependency Graph** — Visual representation of rule relationships (see [reference.md](reference.md))
6. **Apply Style Guide** — Enforce terminology and formatting
7. **Generate Report** — List issues with fix suggestions (template in [reference.md](reference.md))

## Core Standards

### Rule Numbering

**Format**: `XXX.Y[a-z]` — Section (100s–900s), rule number, optional sub-rule letter.

**Examples**: `100`, `100.1`, `100.1a`, `100.1b`, `100.2`

**Section allocation**:

| Range    | Topic                        |
|----------|------------------------------|
| 100–199  | Game Foundations             |
| 200–299  | Entity System                |
| 300–399  | Movement and Positioning     |
| 400–499  | Combat and Resolution        |
| 500–599  | Special Abilities and Effects|
| 600–699  | Advanced Mechanics           |
| 700–799  | Multiplayer and Teams        |
| 800–899  | Variants and Scenarios       |
| 900–999  | Appendices and Reference     |

### Cross-Reference Format

- **Rules**: `rule XXX.Y` or `see rule XXX.Y` (e.g. "Units move according to rule 300.1")
- **Glossary terms**: Capitalize defined terms on first use in a section (e.g. "A Unit with the Flying tag...")
- **Internal links**: Markdown links to sections, e.g. `[Entity System](#200-entity-system)`

### Required Sections

**Rules documents**: Section heading, Overview, rule blocks with `## [Rule Number] [Rule Name]`, Examples, Edge Cases, Glossary Additions.

**Entity data sheets**: Entity Type, Tags, Attributes, Composed Of, Rules, State (JSON schema).

**GDD sections**: Status, Last Updated, Purpose, Overview, Detailed Mechanics, Examples, Implementation Notes, Version History.

### Style Guide

**Capitalization**: Game terms (glossary) and Tags/Attributes — capitalize (Unit, Model, Flying, Movement). Common words — lowercase (player, turn, game, card, die).

**Forbidden terms** (use approved alternatives):

| Forbidden | Use Instead |
|-----------|-------------|
| "approximately", "about", "roughly" | Exact numbers |
| "some", "most", "usually" | "all", "any", or numeric amounts |
| "you" without context | "the Active Player", "a player" |
| "it", "them", "this" (ambiguous) | Repeat the noun |
| "when", "after" (vague timing) | Specific phase/step |
| "near", "close", "adjacent" | Exact distance in units |

**Rule statement template**: `When [trigger condition], [affected entity] [must/may] [action/effect].`

**Required per rule**: Clear trigger, explicit effect, affected entities by name, timing (phase/step/trigger), rule number.

## Validation Checks

### 1. Numbering

- Format `XXX.Y` or `XXX.Ya`; sequential within section; no duplicates; sub-rules a,b,c in order.
- **Errors**: Duplicate rule number, invalid format. **Warnings**: Non-sequential, rule in wrong section range. **Auto-fix**: Renumber to fix sequence.

### 2. Cross-References

- Every `rule XXX.Y` points to an existing rule; glossary terms defined; internal links valid; capitalization matches glossary.
- **Errors**: Non-existent rule, undefined term. **Warnings**: Forward reference, inconsistent capitalization. **Auto-fix**: Generate glossary entries from context.

### 3. Glossary

- Consistent use, single definition per term, alphabetical order, definition + rule reference, related terms cross-referenced.
- **Errors**: Same term, different definitions. **Warnings**: Term defined but unused, inconsistent capitalization. **Format**: `**[Term]**: [Definition]. (Rule XXX.Y)` with "See also" where needed.

### 4. Style

- No forbidden terms; approved phrasings; correct capitalization; clear antecedents; explicit timing; precise measurements.
- **Errors**: Forbidden term, ambiguous pronoun, vague measurement. **Warnings**: Passive voice, overly complex sentence.

### 5. Dependencies

- Rules reference only defined concepts; no circular dependencies; prerequisites first; deep chains (depth ≥ 4) flagged.
- **Errors**: Circular dependency, unjustified forward dependency. **Warnings**: Deep or wide dependency. **Output**: Mermaid diagram and dependency matrix (see [reference.md](reference.md)).

## Auto-Fix Capabilities

- **Renumber rules** — Fix non-sequential numbering (e.g. 100.1, 100.3, 100.4 → 100.1, 100.2, 100.3).
- **Generate glossary entries** — From repeated capitalized terms and context; add rule reference and "See also".
- **Fix capitalization** — e.g. "unit with the flying tag" → "Unit with the Flying tag".
- **Add cross-references** — Insert "see rule XXX.Y" where a concept is used.
- **Update links** — Fix broken internal markdown links to match actual section IDs.

## Integration

- **With Rules Validator**: Documentation Standard handles format/style; Rules Validator handles logic/computability; both before approval.
- **With Code Generator**: Documentation Standard defines terms; Code Generator uses them; cross-refs become comments; dependency graph informs modules.

**Workflow**: Write Rule → Documentation Standard (format/style) → Rules Validator (logic) → Code Generator (implementation) → Approve.

## Additional Reference

- Full validation report template, style examples, glossary format, dependency graph examples, and usage scenarios: [reference.md](reference.md)
