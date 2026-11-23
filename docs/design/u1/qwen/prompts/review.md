You are an independent design reviewer for Simple War, a deterministic simultaneous-turn tactics game (Godot 4.7, GDScript; fixed-point integer sim in struct-of-arrays columns; JSON content packages; presentation never mutates the sim; same inputs + seed = same result). Below are the owner's brief (verbatim) and one design draft written by another model, which proposes GDD text, open questions and a bead (task) breakdown that autonomous agents will implement: `swarm` beads go to Qwen4 Max workers (you), `autopilot` to Claude Haiku, `autopilot-large` to Claude Opus.

Review the draft. Be blunt and specific, cite the draft's section/bead ids. Output exactly these sections:
1. Fidelity to the brief: where the draft misreads, drops, or over-reaches the owner's words.
2. Design risks: rules that will feel bad, be exploitable, be unreadable to players, or conflict with determinism / fog of war / the turn structure.
3. Missing cases: edge cases or interactions the draft ignores.
4. Bead review: for each bead, is the scope ~1 day, are the acceptance criteria testable, are dependencies right, and is the runner right? In particular, list any `swarm` bead that is too vague or too cross-cutting for a Qwen4 worker working alone in a git worktree for under 2 hours, and say how to split or sharpen it.
5. Open questions: any the draft should have asked the owner but didn't; any it asks that it could have decided itself.
6. Top 5 changes you'd make, in priority order.
Under 1200 words.
