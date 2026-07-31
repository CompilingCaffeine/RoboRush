extends Node
## Global signal hub for events that cross system boundaries.
##
## Deliberately small (spec section 26: "Keep the EventBus small and intentional").
## A signal belongs here only when two systems that should not know about each other
## need to communicate — the classic case being that an enemy dying must produce a
## particle burst, a sound, screen shake, and a room-clear check, none of which the
## enemy should have heard of.
##
## Anything happening inside a single actor's own scene tree uses a local signal on
## that actor instead. HealthComponent emits `damaged` locally; the actor decides
## whether that is worth telling the world about.
##
## Spec section 14's event list is now fully represented except for the boss and shop events,
## which arrive with the systems that emit them.

# --- Player ---

## `direction` is normalised.
signal player_dash_started(direction: Vector2)

signal player_dash_ended()

signal player_damaged(info: DamageInfo, remaining: float)

signal player_died()

# --- Weapons and projectiles ---

## `team` is a Teams.Id. Typed as int because GDScript cannot use another script's
## enum in a signal signature.
signal shot_fired(team: int, muzzle: Vector2, direction: Vector2)

## `target` is null for impacts against level geometry. `normal` points back out of
## whatever was hit, so effects can be oriented.
signal projectile_hit(projectile: Node, target: Node, point: Vector2, normal: Vector2)

## Reached the end of its lifetime without hitting anything.
signal projectile_expired(projectile: Node)

signal projectile_bounced(point: Vector2, normal: Vector2)

# --- Pickups ---

## `kind` is a PickupConfig.Kind. Typed as int because GDScript cannot use another script's
## enum in a signal signature.
signal pickup_collected(kind: int, amount: float, position: Vector2)

# --- Enemies and rooms ---

signal enemy_damaged(enemy: Node, info: DamageInfo, remaining: float)

## `position` is passed separately because the enemy frees itself immediately after.
signal enemy_killed(enemy: Node, position: Vector2)

signal room_cleared()

## `type` is a RoomTemplate.Type. Fires on every entry, including re-entering a cleared room.
signal room_entered(type: int, room_id: int)

## The current room's doors sealed or opened.
signal doors_changed(are_locked: bool)
