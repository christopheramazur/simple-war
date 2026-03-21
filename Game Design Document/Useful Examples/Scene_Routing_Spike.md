# Spike: Scene routing — GodotSceneManager vs lightweight router

**Status**: Complete (spike)  
**Date**: 2026-03-21  
**Issue**: `simple-war-ri0`  
**Related**: [Tooling Suitability Matrix](./Tooling%20Suitability%20Matrix.md)

---

## 1. Recommendation (for current Simple War scope)

- **Keep** `SceneTree.change_scene_to_file()` (or `change_scene_to_packed`) as the primitive.
- **Add a thin project-owned helper** when duplication or campaign-aware rules appear—e.g. a static `SceneRoutes` class or small autoload that:
  - centralizes `res://…` path constants;
  - optionally logs / asserts campaign preconditions before changing scenes;
  - stays **data-driven** (routes keyed by intent or `CampaignRuntime` projection), not a second graph of truth.
- **Defer [GodotSceneManager](https://github.com/esdg/GodotSceneManager)** until you want **visual transition graphs** (editor workflow) or **rich built-in transition UX** (fades, stacks) enough to justify a plugin dependency and editor lock-in.

Rationale: campaign flow is still low-branching and already driven by `CampaignRuntime` intents; the pain today is **scattered string paths**, not missing graph tooling.

---

## 2. Current call sites (audit)

| Location | Target / behavior |
|----------|-------------------|
| `src/ui/main_menu.gd` | `campaign_planning.tscn` |
| `src/ui/campaign_planning.gd` | `main_menu.tscn`, `sector_map.tscn` |
| `src/ui/menu_overlay.gd` | `main_menu.tscn` |
| `src/ui/sector_map.gd` | `route_target` from projection → activity scene; `battle_planning.tscn` |
| `src/ui/armybuilding.gd` | `sector_map.tscn` (×2) |
| `src/ui/battle_planning.gd` | `battlefield.tscn` |

No transitions API is shared; paths are duplicated literals or come from `CampaignRuntime.get_sector_projection()`.

---

## 3. Option A — [GodotSceneManager](https://github.com/esdg/GodotSceneManager) (esdg)

**What it is**: Editor-centric **visual graph** for defining transitions between scenes (workflow emphasis: author transitions in a graph rather than only in code).

**Pros**

- Good when many screens and transition types (fade, duration, parallel audio) are authored by designers.
- Central place to see **topology** of the flow without reading every UI script.

**Cons**

- **Dependency**: version alignment with Godot 4.x, maintenance, and import into `addons/`.
- **Overlap** with campaign logic: branching is already partly in **data + intents**; a second graph can drift from `CampaignRuntime` unless disciplined.
- **Heavier** than needed while route count stays small and transitions are instant cuts.

**When to revisit**

- Branching screens grow past “a handful of obvious hops,” or
- You need **first-class transition assets** (timed fades, loading masks) shared across many scenes without copy-paste.

---

## 4. Option B — Lightweight in-repo router (no third-party plugin)

**Shape** (illustrative only):

- `SceneRoutes` (or `CampaignSceneRouter`): `const` paths + one method `go_to_main_menu(tree)`, `go_to_sector_map(tree)`, etc., or `go(tree, SceneRoutes.Id.SECTOR_MAP)`.
- Optional: wrap `change_scene_to_file` to assert `CampaignRuntime` invariants in debug builds.

**Pros**

- Zero plugin surface; full control; trivial to test.
- Aligns with “single progression source of truth” (matrix §5): router calls **data**, not the reverse.

**Cons**

- No visual graph; transitions (fade) are DIY (tween + `CanvasLayer`, or a tiny shared `SceneChangeEffect` scene).
- Discipline required to avoid a “god” autoload—keep it thin.

---

## 5. Other addons (context only)

Community “scene manager” addons (e.g. glass-brick Scene-Manager, YASM, fade-only SceneChanger) optimize for **animated transitions** and stacks. Same tradeoff: adopt when transition UX is a product requirement, not when the only problem is string duplication.

---

## 6. Follow-ups (optional)

| Item | Trigger |
|------|--------|
| Introduce `SceneRoutes` / thin router | Third duplicate path or second bug from typo |
| Prototype GodotSceneManager in a branch | Designer-driven transition graph + >~10–12 distinct screen hops |
| Document scene + intent matrix | When `battleplanning.start` and siblings multiply |

---

## 7. Compatibility note

Before any GodotSceneManager adoption, confirm **plugin compatibility** with the engine version pinned in `project.godot` (currently Godot 4.6 feature tag).
