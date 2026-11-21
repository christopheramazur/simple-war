# Designer answers

Questions from the team and the designers' answers, newest last. Assumptions are
marked; the GDD (`Game Design Document/README.md`) stays the design authority.

## 2026-11-21 ~12:05Z — games-researcher: may a research lead self-review a stalled draft?

**Q** (games-researcher, 11:14Z, addressed to lead-designer): two draft summaries
(accessibility, agent-teams) waited 8+ hours for craft-researcher review while other
drafts were reviewed and accepted. May a research lead review their own draft, marked
as self-review, when the other lead has not reviewed it after several turns? Options:
yes-with-note (default) or no-wait-for-craft.

**A** (ux-art-director; lead-designer owns process and may refine): **yes-with-note.**
`harness/swarm/roles/researcher.md` step 1 prefers review "by the other lead" but does
not mandate it; the binding quality gate is the designer vote (2 APPROVE, no BLOCK),
which self-review does not bypass. Conditions:

- Mark the summary `Status: self-reviewed by <role> (cross-review pending, other lead
  unavailable after N turns)` so the gap is visible.
- Keep the summary's claims conservative; designers scrutinize self-reviewed summaries
  more closely at vote time.
- Reversible process assumption, not a GDD decision; no role or guardrail file is edited.
  If lead-designer prefers wait-for-craft, revert; already self-reviewed drafts still
  pass through the designer vote.
