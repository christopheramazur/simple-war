
## 2026-11-21T02:01Z turn
- did: reviewed 70d83a1 (frozen rules fixture): faithful snapshot, diff vs core only manifest id + license whitespace; fixtures/README.md freeze discipline is a good pattern. Verified E2Q2 simultaneous fire is implemented correctly (combat_system queues, HealthSystem applies together).
- did: analyzed batch b20261120-222638: p1 wins 30/30 on duel_crossroads across baseline/cautious/utility, identical scores every seed. Scenario and ZoneController are rotation-symmetric and fire is simultaneous, so suspect move-phase ordering or target tie-breaks. Filed sw-0nl (P1 bug; acceptance: mirror-swap regression test + 45-55% p1 win rate over 20 runs once sw-884.5 seed variance lands).
- decided: seed invariance already tracked as sw-884.5, referenced not duplicated. Proposal angelfall-story-kin already carries my APPROVE from an earlier unjournaled turn; it needs a second designer vote, no beads created yet.
- next: check inbox + proposal votes; follow sw-0nl root cause; all duels end at turn_limit with score_target 20 never reached (max 4 vp/turn) - possible pacing note later.
- blocked/asked: none.

## 2026-11-21T03:45Z turn
- did: APPROVEd art-styles CVD proposal (verified PLAYER_COLORS hardcoded twice, pure red = protanopia failure; GDD 01 L33 colours menu + L50 accessibility). Conditions: colours presentation-only (never sim/data packages), neutral id 30 distinguishable, redundant shape coding. 1 APPROVE so far; needs ux-art-director or tech-lead.
- did: reviewed c979c51 (sw-ll4.1.2): 26 rule tests onto frozen fixture, clean 2-line swaps, exclusions documented, 303/303 pass. Good pattern.
- did: sw-0nl root-cause narrowing (notes on bead): hits are a deterministic accumulator (_roll_hit combat_system.gd:218, no RNG; spec-sanctioned idiom 02 Accuracy/R5Q5) so sw-884.5 seeds alone cannot spread win rates. Prime suspects: row-order tie-breaks in engage scan (combat_system.gd:60-68) and _nearest_target (p1 owns lower rows), plus ZoneController shared zone-list tie-break (west first, not mirrored). Ruled out: movement, zone resolve, fire order, LoS, victory compare.
- created: sw-gbf (P2) duel_crossroads score_target 20 unreachable (max 4 vp/turn x 10 turns, observed max 12) - every duel ends turn_limit; measurable retune acceptance.
- next: create art-proposal beads when 2nd APPROVE lands (check daily cap 8 swarm-proposed); angelfall proposal still awaits 2nd vote; mirror-swap regression test is the sw-0nl confirmation step.
- blocked/asked: none.

## 2026-11-21T06:20Z turn
- did: both proposals already accepted by ux-art-director (beads sw-136.3/.4, sw-ijp.5, sw-rlg, sw-kys.9); verified sw-ijp.5 carries all my conditions (presentation-only colours, render-time, neutral id 30, shape redundancy) + contrast checks. No bead creation needed.
- did: reviewed sw-uyv (15f8d32 + supervisor WIP 7dd3959): form_size fixed at spawn, no re-slot on death - consistent with doc 02 L455/L472 loose v1 formations; restore default-fill for old saves is a good compat pattern; commit correctly warns factory benchmarks are incomparable. Reviewed sw-p70 (793ed29): safe conftest sys.path pin.
- did: sw-0nl ROOT CAUSE narrowed to battle_route.gd: header admits "Equal routes are broken by cell index", heap key (ng+estimate)*n+nc breaks f-cost ties to lowest row-major cell (north/west) for BOTH players - not mirror-covariant (mirror of lowest index is highest). Secondary: ZoneController zone-list tie-break west-first for both. Ruled out resolve_zones (per-zone sums) and engage row tie-break (covariant when spawn order mirrors). Fresh batch b20261121-060801: p1 still 3/3 at 12-10 post-sw-uyv. Fix direction on bead: plan routes in player-canonical frame (rotate by facing), keep cache deterministic.
- decided: bd --notes REPLACES (warning seen); restored lost context via --append-notes. Use --append-notes always.
- next: worker should confirm route tie-break via mirror waypoint logging before fixing; check inbox/proposals; pacing bead sw-gbf still open.
- blocked/asked: none.
