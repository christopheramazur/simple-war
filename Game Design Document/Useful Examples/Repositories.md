# ECS

## https://github.com/nilpunch/massive-ecs
Using and ECS is the most straight-forward and reliable method of creating modular, component-driven actors and behaviors. We should look at alternatives if there are any but many projects reference this.

# RTS

## https://github.com/beyond-all-reason/Beyond-All-Reason
There may be useful structural or organizational information for structuring largescale battles with many moving units. 

## https://github.com/lampe-games/godot-open-rts
There may be useful structural or organizational information specific to godot.

# Movement 

## https://github.com/LeProfesseurStagiaire/rtsSelectionMoveDemo
This demo repo shows off unit selection and movement in a way that would be very useful to adapt to Simple War. The formations and pathfinding especially lend themselves to the style of simultaneous-turnbased game we're trying to create. 

Unlike a realtime example, Simple War is turn based, but from the demo video in this repo, this code should be able very desirable in our processes determining where the models and units will end up, their facing, their formation, and their pathfinding, especially if we can also use it to show movement previews. And just because simple war is turn based doesnt mean the resolution of its turns and functions cant have animations. 

# Projectiles

## https://github.com/nikoladevelops/godot-blast-bullets-2d
Emphasis on performance, if we end up using any sort of real collision/accuracy for projectiles and other interactive elements, this may be useful.

# Multiplayer

## https://github.com/tatisgordon/Godot-Lobby
A simple multiplayer lobby. May be able to work on top of or around this to implement our own multiplayer.

# Modding

## https://github.com/KoBeWi/Godot-Universal-Mod-Manager
Unsure if this is how we will want to approach modding or not. Asset and content creation is not high on PoC priority list but it should be considered.