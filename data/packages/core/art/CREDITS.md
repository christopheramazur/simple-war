# Core package art

Placeholder pixel art for the vertical slice (sw-kys.3), drawn by
`src/tools/placeholder_art.py` (original work, CC0 with the project).
Re-run it from the repo root to regenerate. Replace any PNG with real art of
the same name, or point a template's `icon`/`tile`/`texture` at another asset
id in `manifest.json`.

Third-party art added here must be CC0 (or another licence that allows
redistribution) and listed below with its source and licence.

## Third-party art

| Files | Source | Licence |
|---|---|---|
| `kenney/hex/*.png` (plains, forest, hills, ore deposit, village, barracks, depot, mine, shrine, bandit camp) | Kenney, *Hexagon Pack* 1.0, https://kenney.nl/assets/hexagon-pack | CC0 1.0 (`kenney/hexagon-pack-License.txt`) |
| `kenney/ground/*.png` (open ground, water) | Kenney, *Tiny Battle* 1.0, https://kenney.nl/assets/tiny-battle | CC0 1.0 (`kenney/tiny-battle-License.txt`) |

Imported by `src/tools/import_kenney_art.py` (picks the tiles, mutes their
colour per GDD 01's desaturated terrain). Credit is not required by CC0;
we give it anyway. Lake and road hexes, caches, the angel host, all units
and commanders, and road/forest/ruins/wall battle ground are still the
placeholders above.
