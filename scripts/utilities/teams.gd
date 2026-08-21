class_name Teams
extends RefCounted
## Who is hostile to whom, and which physics layers express that.
##
## Every collision layer/mask in the game is derived here rather than typed into a
## scene, so adding a team or reshuffling layers is a one-file change and no scene
## carries a magic bitmask. Layer names are declared in project.godot.

enum Id {
	PLAYER,
	ENEMY,
}

const LAYER_WORLD := 1 << 0
const LAYER_PLAYER := 1 << 1
const LAYER_ENEMY := 1 << 2
const LAYER_PLAYER_PROJECTILE := 1 << 3
const LAYER_ENEMY_PROJECTILE := 1 << 4
const LAYER_PICKUP := 1 << 5

## Level geometry that stops a chassis and not a shot: `CableDuct`. Its own layer rather than a
## flag on the world layer, because the whole mechanic is the difference between what a *body*
## collides with and what a *bullet* traces against — and that difference is a mask, which is the
## one thing the physics server already knows how to express. See `body_mask`.
const LAYER_DUCT := 1 << 6

## Scene-tree groups every actor of a team joins. Homing, explosions, and chain lightning
## all need "the hostile bodies near this point", and a group walk answers that from
## anywhere — including from inside a physics callback, where the space state is being
## flushed and a shape query is not guaranteed to be available. A room holds a handful of
## enemies, so walking the group is cheaper than the query it replaces.
const GROUP_PLAYER := &"player"
const GROUP_ENEMY := &"enemy"


## The layer a team's bodies live on.
static func body_layer(team: Id) -> int:
	return LAYER_PLAYER if team == Id.PLAYER else LAYER_ENEMY


## What anything that walks on the floor collides with, whichever team it is on.
##
## One function rather than `LAYER_WORLD` typed into six scripts, because the day a second kind of
## geometry was added is the day five of those six were wrong. It also has to answer for more than
## bodies: the Pop Up Drone picks somewhere to reappear and the loot spawner picks somewhere to
## drop, and both are asking "is this floor a robot could stand on" — which is this mask and not
## the world layer alone. A repair cell dropped into a cable duct is a repair cell nobody can pick
## up.
##
## Deliberately *not* what a projectile traces against. `Projectile` rays against `LAYER_WORLD` on
## its own, and that omission is the mechanic rather than an oversight — see `LAYER_DUCT`.
static func body_mask() -> int:
	return LAYER_WORLD | LAYER_DUCT


## The scene-tree group a team's actors belong to.
static func body_group(team: Id) -> StringName:
	return GROUP_PLAYER if team == Id.PLAYER else GROUP_ENEMY


## The layer a team's projectiles live on.
static func projectile_layer(team: Id) -> int:
	return LAYER_PLAYER_PROJECTILE if team == Id.PLAYER else LAYER_ENEMY_PROJECTILE


## The bodies a team's projectiles are hostile to. Used directly as a projectile's
## collision mask, which makes friendly fire impossible by construction rather than
## by a runtime check. Level geometry is handled separately, by ray query against
## LAYER_WORLD, because bouncing needs a surface normal.
static func opposing_body_layer(team: Id) -> int:
	return LAYER_ENEMY if team == Id.PLAYER else LAYER_PLAYER


static func opposing(team: Id) -> Id:
	return Id.ENEMY if team == Id.PLAYER else Id.PLAYER
