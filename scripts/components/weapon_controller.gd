class_name WeaponController
extends Node
## Fire timing and shot arrangement. Used unchanged by the player and by enemies.
##
## Spec section 14: "The weapon controller should not directly contain all projectile
## behaviour." It contains none. It decides *when* and *in what direction*; the
## ProjectileConfig decides everything that happens afterwards.
##
## The multipliers below are the item hooks. Cooling Fan raises fire_rate_multiplier,
## Unsafe Overclock raises both. Neither item will need a line of code in here.

## Emitted after a shot leaves the muzzle. Local only: the owning actor decides
## whether the wider game should hear about it, the same way dashes are rebroadcast.
## Keeping the EventBus out of here also means this component has no autoload
## dependency and can be exercised in isolation.
signal shot_fired(muzzle: Vector2, direction: Vector2)

@export var config: WeaponConfig

## Scales fire rate. 1.2 is Cooling Fan's +20%.
var fire_rate_multiplier := 1.0

## Scales projectile damage at spawn time.
var damage_multiplier := 1.0

var team := Teams.Id.PLAYER

var _cooldown_left := 0.0

## Lifetime shot count. Capacitor Leak's "every fifth shot" reads this rather than
## keeping its own tally, so drone shots can be made to count toward it.
var _shots_fired := 0


func setup(weapon: WeaponConfig, owning_team: Teams.Id) -> void:
	config = weapon
	team = owning_team
	_cooldown_left = 0.0


## Call once per physics frame before try_fire.
func step(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)


func can_fire() -> bool:
	return config != null and _cooldown_left <= 0.0


## Fires the configured pattern from `origin` toward `direction`. Returns false when
## on cooldown or unconfigured, so callers can simply ask every frame.
func try_fire(origin: Vector2, direction: Vector2) -> bool:
	if not can_fire() or direction.is_zero_approx():
		return false

	_cooldown_left = get_fire_interval()
	_shots_fired += 1

	var aim := direction.normalized()
	var muzzle := origin + aim * config.muzzle_offset
	for index: int in maxi(config.projectiles_per_shot, 1):
		ProjectileFactory.spawn(
			self, config, _pattern_direction(aim, index), muzzle, team, damage_multiplier,
			get_attributed_shooter(),
		)

	shot_fired.emit(muzzle, aim)
	return true


## Seconds between shots, after fire-rate items.
func get_fire_interval() -> float:
	return config.get_fire_interval() / maxf(fire_rate_multiplier, 0.01)


## Damage is attributed to the actor that owns this weapon, not to the component, so a
## kill reads as "the Ticket Bot did it" rather than naming an internal node. `owner` is
## the scene root for a component placed in a scene, and null for one created in code.
func get_attributed_shooter() -> Node:
	return owner if owner != null else self


func get_shots_fired() -> int:
	return _shots_fired


func get_cooldown_remaining() -> float:
	return _cooldown_left


## Spread means two different things depending on shot count, and both are needed:
## an arc for shotgun-style patterns, and inaccuracy for a single projectile (which
## is how Unsafe Overclock's growing spread is expressed).
func _pattern_direction(aim: Vector2, index: int) -> Vector2:
	if is_zero_approx(config.spread_degrees):
		return aim

	if config.projectiles_per_shot <= 1:
		return aim.rotated(deg_to_rad(randf_range(-0.5, 0.5) * config.spread_degrees))

	# Evenly spaced and centred: 3 projectiles across 30 degrees gives -15, 0, +15.
	var step_degrees := config.spread_degrees / float(config.projectiles_per_shot - 1)
	var offset := -config.spread_degrees * 0.5 + step_degrees * index
	return aim.rotated(deg_to_rad(offset))
