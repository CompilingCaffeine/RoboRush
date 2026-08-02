class_name ProjectileConfig
extends Resource
## Everything a projectile is, as data.
##
## This is the single most important type in the game and the reason it exists
## early. Spec section 13 requires emergent synergies from *reusable modifiers*
## rather than hard-coded item pairings, and section 14 forbids item-specific
## conditionals like `if has_item_a and has_item_b`. Both fall out for free if — and
## only if — every projectile behaviour is a field here that anything may adjust.
##
## So the rule is: an item never teaches the weapon a new trick. An item raises
## `bounce_count`, or `split_count`, or `homing_strength`, and the projectile
## already knows what to do. Ricochet Driver plus Fork Bomb then produces "bounces
## once, then splits" with no code aware that those two items can co-occur.
##
## Every field below is read by `projectile.gd` except `status_effects`, which waits on
## the StatusEffectController from spec section 14. Items reach these fields by name
## through `ProjectileModifierStack`, so no field here knows which item adjusts it.

@export_group("Core")

## Integrity removed per hit, before any multipliers.
@export var damage: float = 1.0

## Travel speed in pixels per second.
@export var speed: float = 420.0

## Seconds before the projectile expires on its own.
@export var lifetime: float = 1.4

## Collision radius in pixels. Spec section 13 calls this `size`; named for what it
## actually drives.
@export var radius: float = 2.0

## Impulse applied to whatever it hits, in pixels per second.
@export var knockback: float = 55.0

@export_group("Composition")

## Extra bodies the projectile passes through before expiring. 0 = stops on first hit.
@export var pierce_count: int = 0

## Wall rebounds before expiring. Ricochet Driver adds one.
@export var bounce_count: int = 0

## Children spawned when the projectile is consumed. Fork Bomb adds two.
@export var split_count: int = 0

## Child damage as a fraction of the parent's. Fork Bomb uses 0.6.
@export var split_damage_scale: float = 0.6

## Total arc the children are fanned across, centred on the parent's last direction.
@export var split_spread_degrees: float = 70.0

## Turn rate toward the nearest enemy, in radians per second. Magnetic Guidance adds to
## it. Zero disables homing entirely, including the per-frame search for a target.
@export var homing_strength: float = 0.0

## How far the homing search looks. A projectile with no target in range flies straight.
@export var homing_radius: float = 96.0

## Radius of an explosion on impact. Zero means the projectile does not explode. Note
## that Volatile Kernel's explosions are triggered by enemy deaths, not by impacts, so
## they come from ItemEffects rather than from here.
@export var explosion_radius: float = 0.0

## Explosion damage as a fraction of the projectile's own.
@export var explosion_damage_scale: float = 1.0

## Lightning jumps on hitting a body. Capacitor Leak adds three.
@export var chain_count: int = 0

## Damage per jump, as a fraction of the projectile's own. Spec section 12 gives 0.7.
@export var chain_damage_scale: float = 0.7

## How far each jump may reach for its next target.
@export var chain_radius: float = 72.0

## Whether the projectile turns around once instead of dying. Return Protocol switches this on.
##
## It reverses when it has definitively *missed*: on hitting a wall once its bounces are spent,
## or on running out of lifetime in open air. Triggering only on lifetime — which is what the
## spec's wording literally describes — meant it never fired at all, because a rivet's lifetime
## is 588 pixels of travel and a room's interior is 416 by 192, so a missed shot always died on
## a wall first.
##
## Capping how far it flies before turning was tried and is worse: it would turn the item into a
## range *downgrade*, since a shot that turns around at 140 pixels can never reach an enemy at
## 300. "Missed" is the whole point — a shot that is still going has not missed yet.
@export var return_enabled: bool = false


@export_group("Composition (declared, not yet honoured)")

## Status effect ids applied on hit, resolved by a StatusEffectController. Milestone 5.
@export var status_effects: Array[StringName] = []

@export_group("Presentation")

@export var texture: Texture2D

## Trail tint. Also used for the impact spark burst, so a weapon reads as one colour.
@export var trail_color: Color = Color(1.0, 0.82, 0.24, 0.7)

## Trail sample count. 0 disables the trail.
@export var trail_length: int = 8


## Projectiles decrement their own pierce and bounce counters as they travel, so
## each one must own its config. Handing a projectile the shared resource would let
## the first shot permanently spend the weapon's bounces.
func spawn_copy() -> ProjectileConfig:
	return duplicate() as ProjectileConfig
