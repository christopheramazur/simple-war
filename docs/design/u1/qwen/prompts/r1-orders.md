You are a senior RTS/tactics game designer. Simple War is a deterministic, simultaneous-turn tactics game: players plan orders for squads (groups of 5-10 units), then a turn executes in real time (about 10-20 s) as an autobattler. Squad orders today: HOLD, MOVE, ATTACK_MOVE, ATTACK (explicit target squad), FALL_BACK, WITHDRAW, plus running. Units have weapons with range, moving and standing fire modes, magazine, reload and cooldown. Today an attack-moving squad stops as soon as ONE unit has a shot, so the rest may stand out of range; units have no collision with each other; squads route a formation anchor on a 1 m grid and units steer to formation slots.

The owner wants: the default for an infantry squad that is attack-moving and sees an enemy it can't yet attack, with movement left, is to use that movement to reach positions it can attack from — like StarCraft 2 marines on attack-move. Other squads (mortars, melee, snipers) may have different defaults. Behaviours should be composable. Coherency and collision rules for pathfinding and clustering need fleshing out.

From your knowledge (name the games and mechanisms precisely; say when unsure), write a compact research note:
1. How SC2/Brood War attack-move works per unit (acquisition, leashing, separation/push, "marine ball" clumping and spreading) and what makes it feel good.
2. How Company of Heroes, Dawn of War, Total War and Men of War handle squad coherency, cover seeking, and squad-vs-squad collision.
3. A proposed composable behaviour vocabulary for squads (8-15 components with inputs and outputs) that is deterministic, cheap, and data-driven (no code in mods), with which components each archetype (rifle infantry, LMG, mortar, sniper, melee) would use per order.
4. Unit separation/collision and clustering rules suitable for a fixed-point deterministic sim on a 1 m grid with ~200 units, and their pitfalls (jitter, deadlock, oscillation at range boundaries) with standard fixes (hysteresis, leash, ring-slot assignment).
5. How orders should trade damage output for safety/speed by design (hold vs attack-move vs run vs explicit target), so damage loss is a readable choice, not an accident.

Be concrete. Under 1500 words.
