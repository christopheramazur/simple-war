
## 2026-11-21 13:5x UTC turn (worker-sw-1jy.4, attempt 2)
- did: implemented downward points-to-drop: BattleRules.band_for/points_to_drop (pure static, same FPDR mapping as band_of), squad_card verbose text "· N to <band>", 4 new GUT tests; commits f23b59b + 3337c5c on swarm/sw-1jy.4.
- decided: distance = smallest loss that drops one band; Broken/no-cap = -1 (no text); FPDR tie-rounding gives up to 0.5% headroom at a floor (displayed = used).
- tests: hx godot check 0 errors; full suite 480/480 (7809 asserts).
- next: orchestrator review/merge; upward/both directions = one-line helper extension later.
