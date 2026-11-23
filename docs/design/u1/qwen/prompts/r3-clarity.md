You are a UX designer for tactics/RTS games and a game-testing tools engineer. Simple War is a deterministic simultaneous-turn tactics game (plan, then a real-time autobattler execution of ~15 s per turn, viewed in 2D top-down). Topics:

A) During execution playback, players should pan/zoom, select squads, and hover or right-click an enemy (or ally) squad with their own squad selected to see the live relationship: in/out of range, has line of fire, targeting it, being targeted by it, fleeing from it, closing in, suppressing, spotted only by allies. Must never leak hidden enemy intent (fog of war). Propose the relation vocabulary, a priority order when several apply, the hover vs context-menu split, and visual language (lines, rings, badges) from games that do this well (name them: e.g. XCOM, Company of Heroes, Total War, Into the Breach, Frozen Synapse, Door Kickers).

B) A start-of-battle deployment step (simultaneous, hidden): what the best games do (Total War, CoH, Frozen Synapse, Battle Brothers), what's placeable, defaults and auto-deploy, time limits, and pitfalls.

C) A framework to assess battle readability automatically: capturing stills and frame strips at fixed battle stages from deterministic replays, asking a local vision-language model rubric questions (who is shooting whom, which squad is out of range, what is each squad doing), grading its answers against simulation ground truth, and using the score as a clarity regression signal. Pitfalls of VLMs for this (small text, counting, spatial relations), and how to design prompts, rubrics and image annotations so a 27B local VLM is useful. Also a "behaviour workshop" sandbox for isolating unit behaviours with shared visual and API scenarios.

Be concrete. Under 1800 words.
