# Test fixtures

## rules/ — frozen rules-test package (`rules-fixture`)

A snapshot of `data/packages/core` (taken at `1a0cf6f5`, 2026-11-20, bead
sw-ll4.1.1) so rule tests keep passing when live content is rebalanced.

- **Frozen:** do not edit these defs to follow content changes. Rule tests
  assert exact numbers (damage, zones, routing); they test the rules engine
  against known content, not the current balance.
- Manifest id is `rules-fixture`, distinct from `core`, so the loader never
  reports a package-id collision. Load it **instead of** `core`, not
  alongside: the snapshot defines the same template ids. All data and asset
  paths are relative to this folder; the package has no dependency on `core`.
- Tests load it with
  `PackageLoader.load_dirs(PackedStringArray(["res://tests/fixtures/rules"]))`.
- `defs/workshop.json` is the one addition (sw-pd2l.2): `bare_*` templates (rifle squad, sergeant, trooper, scout team, scout) with `no_armour` in place of flak, for the fire-range workshop scenarios (`data/sim/workshop/fire_range_*.json`). It adds new ids only; no existing template changed.
- If a rule test needs *new* content behaviour, add a small template or
  patch in the test itself (see `test_battle_map.gd`), not here.
- `defs/ruleset.json` pins `fire.policy` to `nearest` (sw-pd2l.7): the live ruleset defaults to `prowess`, and the rule tests' numbers were measured under `nearest`. Values otherwise as before.
