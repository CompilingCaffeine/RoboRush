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
## Fields marked "not yet honoured" are declared because the shape of this resource
## is the contract that milestone 4 composes over, and because a field appearing
## later is a smaller change than a behaviour appearing later. Each one is wired up
## as its milestone arrives; none of them are read yet.

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

@export_group("Composition (declared, not yet honoured)")

## Children spawned on impact. Fork Bomb sets this. Milestone 4.
@export var split_count: int = 0

## Child damage as a fraction of the parent's. Fork Bomb uses 0.6.
@export var split_damage_scale: float = 0.6

## Curve strength toward nearby enemies. Magnetic Guidance sets this. Milestone 4.
@export var homing_strength: float = 0.0

## Radius of an impact explosion. Volatile Kernel and Fork Bomb use this. Milestone 4.
@export var explosion_radius: float = 0.0

## Lightning jumps on hit. Capacitor Leak sets this. Milestone 4.
@export var chain_count: int = 0

## Whether the projectile reverses once at the end of its life. Return Protocol.
@export var return_enabled: bool = false

## Status effect ids applied on hit, resolved by a StatusEffectController. Milestone 4.
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
