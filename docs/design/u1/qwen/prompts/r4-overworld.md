You are a strategy-game map and systems designer. Simple War's overworld is a hex map (HoMM-like features: mines, barracks, villages, roads, guards) with commanders that move on routes, convoys that carry produced squads along supply lines, fog of war with sight radii in hexes, and simultaneous turns. The owner wants:
- much larger hexes that are composable entities holding and displaying the feature entities on them, with a default auto-arrangement of features inside a hex, overridable in the map editor but not during play; roads crossing a hex nudge features out of the road's way while keeping the arrangement;
- each feature selectable on the map and from the hex sidebar, highlighted in both;
- some owned features usable without a commander present: buying items and squads, updating rally points;
- slower overworld movement (caravans especially) and more vision: owned hexes see themselves; features add radius (mine 1, barracks 2, village or caravan 3, more with scouts in a caravan), as configurable defaults;
- a caravan entity whose payload is components that systems read to grant capabilities.

From your knowledge, write a compact research note:
1. Prior art: HoMM 3/5/7 map objects and adventure map scale, Civilization V/VI tile improvements and vision, Humankind/Old World tile composition, Endless Legend, Battle Brothers/Mount & Blade caravans. What made these readable.
2. A deterministic layout algorithm for 1-6 features in a hex (slot sets by count, priority by kind), with road-aware offsets (road edges -> keep-out band -> shift slots perpendicular), and how an editor override is stored compactly.
3. Which feature actions should be remote "owner actions" vs commander-only, and the strategic consequences (does it reduce the value of commanders? exploit risks?).
4. A light, data-only entity/component model for caravans (and maybe features) for a game with a packed-array (struct-of-arrays) deterministic simulation and moddable JSON content; pitfalls (save versioning, component explosion).
5. Movement/vision tuning principles (should vision exceed one turn of enemy movement? ratios) with suggested numbers.

Be concrete. Under 1600 words.
