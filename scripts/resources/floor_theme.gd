class_name FloorTheme
extends Resource
## What one floor looks and sounds like.
##
## Split out of `FloorConfig` rather than added to it as four more fields, for the reason the
## Development plan gives for `FloorConfig` existing at all: a floor's *content* — its rooms,
## its roster, its item pool, its boss — and a floor's *presentation* are edited by different
## people at different times, and a theme is the half that a second floor can reuse wholesale.
## The Help Desk and Development share a shop, a treasure room, and a boss arena template
## while looking nothing alike; they could equally have shared a look while differing in
## everything else.
##
## Music is ids rather than streams. `AudioManager` owns the library and the crossfade, and a
## floor naming a track it does not have should be a warning at load rather than a second
## copy of a stream loaded per floor. It also keeps `FeedbackDirector` deciding *when* music
## changes — the boss arena gets the boss loop, everywhere else gets the explore loop — while
## the floor decides only *which* tracks those two are.

@export_group("Environment")

## Tiled across every room's interior. A 64x64 sheet of sixteen different 16x16 panels, so
## the repeat period is four tiles rather than one — see the tile sheet note in
## `tools/generate_art.py` for why that matters.
@export var floor_texture: Texture2D

## Tiled across every wall block and every obstacle. Obstacles deliberately share it: a
## server rack in the middle of a Development room should be made of the same stuff as the
## room's walls, and a floor that themed only its perimeter would look half-finished.
@export var wall_texture: Texture2D

@export_group("Music")

## Played in every room that is not the boss arena.
@export var explore_music: StringName = &"explore"

@export var boss_music: StringName = &"boss"
