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
##
## Three signals were added in milestone 4 and each earns its place by the same test: two
## systems that should not know about each other. Explosions and chain jumps are damage
## resolved in combat code that must never draw anything, and the item banner is a HUD that
## must never know what an inventory is.

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

## The projectile changed direction at a point. Emitted for wall rebounds and for Return
## Protocol's reversal, which are the same event as far as anything watching is concerned.
signal projectile_bounced(point: Vector2, normal: Vector2)

## A blast went off. Damage is already resolved by the time this fires; it exists so the
## fireball is drawn in one place instead of by whatever caused the blast.
signal explosion_triggered(position: Vector2, radius: float)

## One hop of a chain lightning discharge.
signal chain_jumped(from: Vector2, to: Vector2)

# --- Pickups ---

## `kind` is a PickupConfig.Kind. Typed as int because GDScript cannot use another script's
## enum in a signal signature.
signal pickup_collected(kind: int, amount: float, position: Vector2)

## An item was added to the player's inventory. Carries the resource rather than an id,
## because both listeners — the HUD banner and the item bar — want its name and icon.
signal item_collected(item: ItemConfig)

# --- Shop ---

## Scrap changed hands. Earns its place by the usual test: buying something has to sound
## different from finding it, and the shop must not know what a sound is. `cost` is zero for
## the boss reward, which is a stand the player takes from without paying.
signal purchase_made(cost: int)

# --- Enemies and rooms ---

signal enemy_damaged(enemy: Node, info: DamageInfo, remaining: float)

## `position` is passed separately because the enemy frees itself immediately after.
signal enemy_killed(enemy: Node, position: Vector2)

signal room_cleared()

## The floor's boss was destroyed. Distinct from `enemy_killed`, which a boss also emits:
## one of them means "a thing died", the other means "the run is over".
signal boss_defeated(boss: Node)

## Boss health changed, for the boss bar. `ratio` is 0..1.
signal boss_health_changed(ratio: float)

## The boss entered a new phase. `phase` is a one-based index.
signal boss_phase_changed(phase: int)

## `type` is a RoomTemplate.Type. Fires on every entry, including re-entering a cleared room.
signal room_entered(type: int, room_id: int)

## The current room's doors sealed or opened.
signal doors_changed(are_locked: bool)
