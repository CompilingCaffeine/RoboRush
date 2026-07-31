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


## The layer a team's bodies live on.
static func body_layer(team: Id) -> int:
	return LAYER_PLAYER if team == Id.PLAYER else LAYER_ENEMY


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
