# Round U1 brief (owner, 2026-11-23)

The owner's request, verbatim. Every U1 draft and bead traces back to this file.

> I want to flesh out some features that accomplish the following, to be picked up by swarm or autopilot later. [...] These features may required updates to the GDD and documentation.
>
> These features will likely need refinement. Work on them with some research and review delegates to the qwen4 and opus 5.5 high to come up with solid GDD entries for them.

## Battles

It's still unclear whether using attack move, run, or hold affects unit dps output; it seems that doing anything other than moving directly toward the enemy dramatically lowers damage output but this is also difficult to confirm. Selecting a target and retargeting both seem to diminish damage output, again difficult to confirm.

Creating a framework for visually assessing battles at various stages for clarity -- especially if the local bonsai model can be used for assessing still images or short recordings, as there will likely be a lot of visual work -- is a priority. A workshop of some sort for working through individual components of unit behavior both visually and through api is desirable.

Further along this line of providing clarity to the player, during the execution phase, a player should still be able to zoom and move the map (this may already be a bead), to select squads, and to get an understanding via hover-tooltip or right-click comparison to bring up a context menu what those squads current and possible interactions are, e.g. if I select my mortar squad and then over an enemy squad, I should get a quick "in/out of range", "targeting with attacks" / "fleeing from" etc. depending on what's actually going on.

A start of battle deployment step is still desired.

Movement and commands need to have their functionality refined; we should flesh out the coherency and collision rules for pathfinding and clustering, as well as smarter autobattler behaviours -- the default behaviour for an infantry squad that is attack-moving, has an enemy that's visible but not in range / attackable, and that still has movement, should be for the squad to find a position with its remaining movement that it can make attacks from, similar to a group of marines making an attack-move command in starcraft 2. Other squads may have other types of default behaviours for various commands, and we'll want to build behaviours in a composable way if possible, but nailing the feel here is integral to building the rest out.

Longterm SIMPL idea for Prowess:
There exists a mathematical optimal distribution of attacks against an enemy squad that kills the most units. Optimal prowess conditions should result in the attacking squad performing this way. Less optimal arrangements include multiple attacks "overkilling" a single unit, or attacks being too distributed across the squad's units to kill any of them. A squad with neutral Prowess should generally be attempting to focus their fire on a few units in a target squad, with some amount of fuzziness, depending on how good their prowess is to begin with. A high prowess squad is better at distribution, a low prowess squad is worse. A squad that's surging will overkill less (more reactive target swapping), while a squad that's fraying will overkill more.

this sounds like and is likely a difficult system to implement in my opinion, but it would go a long way to creating distinct gameplay modes and feels.

## Overworld Map

Hex tiles should be much larger; the vision is for them to be composable entities that in turn hold and display the feature entities they're composed of.

They should have a default method of arranging themselves in a hex that can be overridden in map creation but not readily accessible during gameplay.

If a road is present, sensible offsets should keep features arranged the same way, just slightly out of the road's way depending on the road's direction.

Multiple features on a tile should be selectable individually from both the overworld map and the selected tile's sidebar, and highlighted when they are.

Some features a player controls should be able to be activated without a commander present, such as purchasing items and squads, and updating rally points from already owned features.

Overall overworld movement speed could come down a bit, especially for caravans. overworld vision could go up a bit. Controlled tiles should provide self-vision at least, with some features providing additional e.g. a mine would provide 1 tile of vision, a barracks 2, a village or caravan 3 (or more, if scouts are in the caravan -- a caravan itself should be an entity, and its payload is components that can be read and used by systems to provide different behaviours and capabilities); sensible configurable defaults based on the entity.
