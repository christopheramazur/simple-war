# PoC

**Status**: Draft  
**Last Updated**: 2026-02-14  
**Purpose**: High-level overview of PoC intent

---

## 1. Big picture

Players embark on Campaigns. Campaigns are composed of activities on a sector map. The Player takes on the narrative role of various Commanders during a Campaign. Each Commander has access to its own army and tracks its own position and influence on the sector map. 

The primary activities that Commanders engage in are Armybuilding, Battling, and Narrative Events. Campaign Activities are intended to be flexible and can modify a campaign in almost any way.

Players are not inherently limited to a single faction for their commanders or armies during a Campaign. The Roster System creates filters on what armies are allowed to participate in which battles. As well, Commanders and units of different factions may interact poorly when forced into the same battle.

An example Campaign comparison to a game of Warhammer 40k would consist of beginning a Campaign with a single commander, consisting of a single armybuilding activity limited by a generic matched play Roster, followed by a single battle activity against a single opposing commander. The campaign conclusion would score based on number of battles won, and the Player would be awarded the victory or defeat as appropriate.

The Campaign system draws inspiration from games like Dawn of War: Soulstorm, Slay the Spire, Heroes of Might and Magic, and Battlesector. In contrast, the sector map is not intended to be a linear path to follow for the player, though it can be. 

The primary difference between Simple War and other wargames is that it utilizes a simultaneous turn resolution system for its battles, where players pre-commit their units to various orders, and then resolve what happens at the same time. 

- Players take on the role of various Commanders
- Commanders explore and influence the Sector Map, building armies, engaging with events, and fighting battles
- Armies are made from Units, which are configurations of individuals and their equipment
- Battles are fought between two or more Commanders, leading armies that match the Battle's Roster requirements
- Campaigns and Battles both have a variety of objectives and scoring methods which contribute to them

## 2. Tight Scope Digital Prototype

The initial digital prototype will focus on presenting the gameplay flow to the player for the aforementioned Warhammer 40K Comparison. The thing we care most about for this prototype is that it is responsive to typical digital controls where appropriate (examples: double-click to confirm a selection, right click for context menu if available, zooming and scrolling with the scroll wheel, panning with WASD or mouse3, drag-click an empty space to multi-select, or click-and-drag to move something, etc.)

- The Main Menu displays a "Quick Play" option (Other options for now can just be "Quit Game") 
- A "Menu" button in the top right of every screen should allow the player to Return to Main Menu, or Quit Game at any point. 
- Quick Play takes us to a Campaign Planning screen. This screen just has information about the Campaign.
  - For now, this can just say "A single Battle against a single opposing commander, with pre-built armies."
- On the bottom Right of the Campaign Planning Screen, the options for "Back" and "Embark" are available. 
- "Embark" takes us to the Campaign's Sector Map. The Sector Map should be a star chart with two options on it, represented by two circled plots on the map.
  - One of the plots is "Armybuilding" and the other is "Battle" -- they should be connected by a dotted-line arrow. 
    - If the player hovers or right-clicks the arrow for information, it should say "Requirements for travel: Build an army!"
  - There should be a small meeple to represent the player's Commander on the Armybuilding plot. 
  - We will not allow the player to move the Meeple to the Battle plot until it has completed the Armybuilding activity. 
    - Convey this visually by subtly highlighting the Armybuilding plot. 
    - Convey this through text in a note on one side of the Sector Map, saying "We need an army to approach the battle!"
  - The player can do the armybuilding activity by right-clicking its plot and selecting "Begin Activity" from a context menu, double-clicking the plot, hitting enter, or clicking "Begin Activity" in the bottom right. 
    - This takes us to an Armybuilding screen. List a single army "Militia" army and allow the player to highlight and select it with the appropriate controls, returning us to the Sector Map.
  - Once the Armybuilding activity is complete, have the Commander Meeple inherit the highlight
  - Add a small "army" meeple next to the Commander meeple.
  - Update the note to tell the player "Move your Commander to the battle!"
  - Allow the player to go to the Battle activity by moving their Commander's meeple there, double-clicking it, selecting it and hitting enter or "Move Here" in the bottom right, or right-clicking it and selecting "Move Here" from the context menu.
  - Once the commander meeple (with army meeple in tow) is at the Battle activity, 
    - Update the note to tell the player "Better them than us!"
    - the Player can begin the Battle with the same controls they did to begin the Armybuilding activity. 
    - Starting the Battle takes us to the Battle Planning screen
      - Allow the player to "Select Army" from their Commander's Battleforces (should be the same army we just built with that Commander)
        - we aren't going to demo army composition or reserves yet so this is all that's needed in the Planning stage
      - From the Planning Screen, "Deploy" button in the bottom right takes us to the Battlefield. 
        - The Battlefield should be 100 units tall and 200 units wide. One unit of distance corresponds to roughly one meter of in-world scale.
      - The battlefield can just be a generic grassland texture surrounded by grey.
        - Indicate that the top 20 units are the opponent's Deployment zone by tinting them Red, with a dotted line across the board at the 20-unit mark
        - Indicate that the bottom 20 units are the player's Deployment zone by tinting them blue, with a dotted line across the board at the 20-unit mark
        - The player should be able to zoom in on the battlefield 
        - there should be grid markers on the battlefield at appropriate zoom levels
          - When zoomed all the way in, the markers should be every 1 unit
          - as they zoom out the markers should be replaced by 3-unit and 6-unit grid markers, and vice versa
          - The player should not be able to zoom in further than a 6x6 grid of 1-unit markers, or further out than being able to see the entire battlefield and 6 units of surrounding grey area
      - The Army that the player selected should be available to the side in the grey
        - 5 units of "riflemen", each consisting of 10 circles, arranged in a rectangle. 
          - For now, these circles simply maintain their position within the unit's rectangle.
        - allow the player to click and drag, multi-select-and-drag, and drop the units onto the battlefield, but only wholly within their deployment zone
        - once they have done so, a button on the bottom right that says "Engage Enemy" becomes available to click
          - The player can also hit enter, or right-click the battlefield for a context menu that should include "Engage Enemy"
        - The Deployment activity is complete, and now the battle begins. The deployment zone indicators go away and the game displays the text, "Engagement Stage: Turn 1" which fades after 3 seconds.
        - The player should be able to plan the movement and pivoting of their units with click and drag movement controls
          - display the plans using a translucent copy of the unit at the end of a dotted-line path
        - Once the player has given unit an order, they can issue by clicking "Execute Orders" in the bottom right
          - if a unit doesn't have an order, the player can still execute orders, but they should be prompted to review their remaining units without orders

# the rest of this is just going through turns of battle. There should be basic enemy behaviors, such as deploying their premade army on the line, moving it forward, and attacking the closest enemy to them when they are in effective range.