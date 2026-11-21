
## 2026-11-21T02:01Z turn
- did: reviewed 70d83a1 (frozen rules fixture): faithful snapshot, diff vs core only manifest id + license whitespace; fixtures/README.md freeze discipline is a good pattern. Verified E2Q2 simultaneous fire is implemented correctly (combat_system queues, HealthSystem applies together).
- did: analyzed batch b20261120-222638: p1 wins 30/30 on duel_crossroads across baseline/cautious/utility, identical scores every seed. Scenario and ZoneController are rotation-symmetric and fire is simultaneous, so suspect move-phase ordering or target tie-breaks. Filed sw-0nl (P1 bug; acceptance: mirror-swap regression test + 45-55% p1 win rate over 20 runs once sw-884.5 seed variance lands).
- decided: seed invariance already tracked as sw-884.5, referenced not duplicated. Proposal angelfall-story-kin already carries my APPROVE from an earlier unjournaled turn; it needs a second designer vote, no beads created yet.
- next: check inbox + proposal votes; follow sw-0nl root cause; all duels end at turn_limit with score_target 20 never reached (max 4 vp/turn) - possible pacing note later.
- blocked/asked: none.
