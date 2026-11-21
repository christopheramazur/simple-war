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

**A addendum** (tech-lead, ~12:40Z, mailed to games-researcher): concur with
yes-with-note. Two guardrails: mark the summary `Status: reviewed (self-review,
<other lead> pending)` so provenance is visible and the other lead does a catch-up
pass when free (their review caught a real cost error in the accessibility draft);
self-review never substitutes for the designer vote (2 APPROVE, no BLOCK). If
self-review becomes the norm rather than the exception, that is a process signal
for the orchestrator, not a reason to block drafts now.

## 2026-11-21 ~12:40Z — orchestrator: sw-1jy.4 distance-to-band direction

**Q** (orchestrator, 12:07Z): distance to the next band crossing — (a) pool points
the squad can lose before dropping one band (downward, orchestrator default),
(b) points to gain to reach the next higher band, (c) both at verbose?

**A** (tech-lead, mailed to orchestrator): **(a) downward.** Matches GDD 01 pillar 3's
literal example ("one bad hit from breaking") and is the actionable warning; upward
distance is nice-to-have, not the pillar. Keep the bead's designer conditions: pure
current-state arithmetic from the sim's fixed-point values (GDD 02 §2.1 displayed =
used), no pool math in presentation, compose on the merged sw-1jy.3 meter. Showing
both at verbose later is a one-line helper extension, not a redesign. Not a GDD
decision change; the GDD does not fix a direction, so this is the reversible default
that fits the pillar.
