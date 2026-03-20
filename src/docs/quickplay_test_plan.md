# Quickplay End-to-End Test Plan

## Manual Flow Checklist

1. Launch game into `main_menu.tscn`.
2. Click `Quick Play`.
3. Confirm `campaign_planning.tscn` appears with Back/Embark.
4. Click `Embark` and verify Sector Map note requests army building.
5. Click `Begin Activity` and select `Militia`.
6. Return to Sector Map and verify commander can move to Battle.
7. Click `Move Here` then `Start Battle`.
8. In Battle Planning, confirm selected army and click `Deploy`.
9. On Battlefield, confirm:
   - 200x100 board representation
   - Top/bottom deployment zones visible in Deployment stage
   - Grid spacing changes with mouse wheel zoom (1/3/6)
10. Click `Engage Enemy`.
11. Select a player unit, click destination, and verify movement preview.
12. Click `Execute Orders`; verify unit movement, enemy movement, and simple combat resolution.
13. Continue until one side is eliminated and verify Consolidation status text.

## Automated Smoke Script

- Script: `test/integration/quickplay_flow_smoke.gd`
- Purpose: ensure each scene in the quickplay path can be loaded and instantiated.
- Example command:
  - `godot --headless --script res://test/integration/quickplay_flow_smoke.gd`
