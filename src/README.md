# Simple War - Godot 4.6 Project Setup

This document provides instructions for setting up the Simple War project in Godot 4.6.

## Project Structure

```
src/
├── campaigns/
│   ├── campaign_definition.gd      # Campaign resource
│   ├── campaign_generator.gd       # Campaign factory and configurator
│   ├── campaign_state.gd           # Campaign state persistence for save/load
│   └── campaign_validator.gd       # Campaign state validation
│
├── activities/
│   ├── activity_definition.gd      # Campaign progress component resource
│   └── activity_generator.gd       # Campaign progress component factory and configurator
│
├── armies/
│   ├── rosters/
│   │   ├── roster_definition.gd        # Army filter resource
│   │   └── roster_generator.gd         # Army filter factory and configurator
│   │
│   ├── battleforce/
│   │   ├── battleforce_definition.gd     # Army composition resource
│   │   ├── battleforce_generator.gd      # Army composition factory and configurator
│   │   ├── battleforce_state.gd          # Army composition persistence for save/load
│   │   └── battleforce_validator.gd      # Army composition validation
│   │
│   ├── units/
│   │   ├── unit_definition.gd          # Unit resource
│   │   ├── unit_generator.gd           # Unit factory and configurator
│   │   └── unit_validator.gd           # Unit validation
│   │
│   ├── army_definition.gd              # Available forces resource
│   ├── army_generator.gd               # Available forces factory and configurator
│   ├── army_builder_definition.gd      # Armybuilding activity resource
│   └── army_builder_generator.gd       # Armybuilding activity factory and configurator
│   
├── battles/
│   ├── battlefield/
│   │   ├── battlefield_definition.gd       # Battle area resource
│   │   ├── battlefield_generator.gd        # Battle area factory and configurator
│   │   ├── battlefield_pathfinding.gd      # Battle area navmesh updates
│   │   └── battlefield_validator.gd        # Battle area validation
│   │
│   ├── participants/
│   │   ├── participant_definition.gd       # Battle participant resource
│   │   ├── participant_generator.gd        # Battle participant factory and configurator
│   │   └── participant_validator.gd        # Battle participant validation
│   │
│   ├── scoring/
│   │   ├── scoreboard_definition.gd        # Score tracking resource
│   │   ├── scoreboard_generator.gd         # Score tracking factory and configurator
│   │   └── scoreboard_validator.gd         # Score tracking validation
│   │
│   ├── actions/
│   │   ├── action_definition.gd            # Unit context-aware interaction resource          
│   │   ├── action_generator.gd             # Unit context-aware interaction factory and configurator
│   │   └── action_validation.gd            # Unit context-aware interaction validation
│   │
│   ├── preparation/
│   │   ├── preparation_definition.gd       # Battle preparation resource
│   │   ├── preparation_generator.gd        # Battle preparation factory and configurator
│   │   └── preparation_validator.gd        # Battle preparation validation
│   │
│   ├── reserves/
│   │   ├── reserves_definition.gd          # Reserves zone resource
│   │   ├── reserves_generator.gd           # Reserves zone factory and configurator
│   │   └── reserves_validator.gd           # Reserves zone validation
│   │
│   ├── casualties/
│   │   ├── casualties_definition.gd        # Casualty report resource
│   │   ├── casualties_generator.gd         # Casualty report factory and configurator
│   │   └── casualties_validator.gd         # Casualty report validation
│   │
│   ├── deployment/
│   │   ├── deployment_definition.gd        # Deployment stage resource
│   │   ├── deployment_generator.gd         # Deployment stage factory and configurator
│   │   └── deployment_validator.gd         # Deployment stage validation
│   │
│   ├── engagement/
│   │   ├── engagement_definition.gd        # Engagement stage resource
│   │   ├── engagement_generator.gd         # Engagement stage factory and configurator
│   │   └── engagement_validator.gd         # Engagement stage validation
│   │
│   ├── consolidation/
│   │   ├── consolidation_definition.gd     # Consolidation stage resource
│   │   ├── consolidation_generator.gd      # Consolidation stage factory and configurator
│   │   └── consolidation_validator.gd      # Consolidation stage validation
│   │
│   ├── zones/
│   │   ├── zone_definition.gd              # Abstract non-battlefield unit state resource
│   │   ├── zone_generator.gd               # zone factory and configurator
│   │   └── zone_validator.gd               # zone validation
│   │
│   ├── battle_definition.gd                # Battle activity resource
│   ├── battle_generator.gd                 # Battle activity factory and configurator
│   ├── battle_state.gd                     # Battle activity state persistence for save/load
│   └── battle_validator.gd                 # Battle activity validation
│
├── bots/
│   ├── bot_definition.gd           # Computer player resource
│   ├── bot_generator.gd            # Computer player factory and configurator
│   ├── bot_vision.gd               # Computer player representation of battle state
│   └── bot_thinking.gd             # Computer player decisionmaking
│
├── commanders/
│   ├── commander_definition.gd     # Commander resource
│   ├── commander_generator.gd      # Commander factory and configurator
│   └── commander_validator.gd      # Commander validation
│
├── events/
│   ├── event_definition.gd         # Event activity resource
│   ├── event_generator.gd          # Event activity factory and configurator
│   ├── event_state.gd              # Event activity state persistence for save/load
│   └── event_validator.gd          # Event activity validation
│
├── player/
│   ├── player_definition.gd        # Player resource class
│   ├── player_generator.gd         # Player factory and configurator
│   └── player_state.gd             # Player state persistence for save/load
│
├── ui/     ## Needs to be structured
│
├── config/
│   ├── feature_flags.cfg
│   └── game_settings_defaults.cfg
│
├── data/
│   ├── Campaigns.json
│   ├── Rosters.json
│   ├── Armies.json
│   ├── Battleforces.json
│   ├── Commanders.json
│   ├── Units.json
│   ├── Models.json
│   ├── Items.json
│   ├── Actions.json
│   ├── Bots.json
│   └── Battles.json
│
└── project.godot                  # Project configuration
```


**Project Version**: Initial Framework
**Last Updated**: 2026-02-09