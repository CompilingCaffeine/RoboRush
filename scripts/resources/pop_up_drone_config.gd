class_name PopUpDroneConfig
extends EnemyConfig
## Tuning specific to the Pop Up Drone.
##
## A subclass rather than more fields on `EnemyConfig`, because a teleport interval is not
## a property of "an enemy" — it is a property of *this* enemy, and piling every enemy's
## knobs into one resource would make three quarters of that resource dead weight on every
## enemy that reads it. `Enemy.config` is typed as the base, so a scene can hand it one of
## these and the base never notices.

## Seconds the drone stays put before relocating.
@export var teleport_interval: float = 2.6

## Seconds it takes to fade back in after arriving. It is shootable throughout — a drone
## that could not be hit while blinking would be a drone the player is told to ignore.
@export var arrival_fade: float = 0.2

## Seconds between finishing the fade and firing. This is the window the player has to
## move, and it is the whole reason the drone forces aim changes rather than just being
## annoying.
@export var arrival_pause: float = 0.45

## How far inside the room's walls it appears. Far enough that its spread has somewhere to
## go, close enough that "room edges" (spec section 15) is still true.
@export var edge_inset: float = 26.0

## It will not reappear closer than this to the player. Materialising in the player's face
## is a hit they could not have avoided.
@export var min_teleport_distance: float = 96.0

## How many candidate points to try before giving up and staying put. A room full of
## obstacles should make the drone predictable, not make it teleport into a wall.
@export var placement_attempts: int = 12
