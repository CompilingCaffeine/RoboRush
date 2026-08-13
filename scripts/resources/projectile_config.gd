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

## Degrees the shot actually leaves at, measured from where it was aimed. Zero for everything
## anybody fires on purpose.
##
## Applied in `ProjectileFactory.spawn` and deliberately *not* in `spawn_configured`. The two are
## the same call for an ordinary shot, but split children go through the second one with a config
## their parent has already been rotated by — offsetting there too would turn one 45 degree item
## into a shot that veers further with every generation of splits, which is not what the item says
## it does and is impossible to aim around.
##
## A projectile field rather than a weapon or player one because it belongs to the *shot*: it
## travels through `ProjectileModifierStack` like every other item effect, so an item that causes
## it composes with bounces, homing and splits without any of them knowing it exists.
@export var aim_offset_degrees: float = 0.0

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

## Fraction of a target's maximum integrity at or below which a hit finishes it outright. Zero for
## every shot that does not execute, which is all of them until an item says otherwise.
##
## A projectile field rather than an item hook, for the reason every other behaviour here is one: it
## then composes with the rest for free. A split child executes, a chain jump executes, a bounced
## shot executes — none of that is written anywhere, it falls out of the child carrying its parent's
## config. Threshold rather than flat damage because what makes an execute feel different from more
## damage is that it ignores how much integrity the enemy *had*: on a floor where Tech Debt has
## quadrupled everything's pool, a fifth of a very large number is still a fifth.
@export var execute_threshold: float = 0.0

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


## Status effect ids applied to whatever this hits, resolved by that body's
## `StatusEffectController`. Cold Cache appends `chill` and Hot Reload appends `burn`; a
## shot carrying both applies both, which is why items *append* here rather than assigning.
##
## Unknown ids are reported by the controller rather than ignored, the same guard
## `ProjectileModifierStack` puts on field names and for the same reason: a typo that
## silently does nothing is the failure mode a string-keyed design is most exposed to.
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
##
## `status_effects` is re-created rather than left to `duplicate()`, which is shallow and
## would hand every copy the *same* array. Items append to that field, so the shared array
## would have grown by one entry per shot fired for the rest of the run — a Cold Cache build
## reaching a hundred stacked chills a few rooms in. Deep-duplicating the whole resource
## would fix it and also clone the texture on every shot, which is the wrong trade sixty
## times a second.
func spawn_copy() -> ProjectileConfig:
	var copy := duplicate() as ProjectileConfig
	copy.status_effects = status_effects.duplicate()
	return copy
