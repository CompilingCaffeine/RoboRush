class_name WeaponController
extends Node
## Fire timing and shot arrangement. Used unchanged by the player and by enemies.
##
## Spec section 14: "The weapon controller should not directly contain all projectile
## behaviour." It contains none. It decides *when* and *in what direction*; the
## ProjectileConfig decides everything that happens afterwards.
##
## The multipliers below are the item hooks. Cooling Fan raises fire_rate_multiplier,
## Unsafe Overclock raises both. Neither item will need a line of code in here. Items that change
## the pattern itself — more projectiles, a rear shot, a charged trigger — do it by handing this
## component a different `config`; see `WeaponModifierStack`.

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

## The shooter's item modifiers, rebuilt by its inventory whenever an item is collected.
## Null for anything that cannot hold items, which is every enemy — and the reason this
## component still has no idea what an item is.
var modifiers: ProjectileModifierStack

var team := Teams.Id.PLAYER

var _cooldown_left := 0.0

## Seconds of charge held, for a `CHARGE` weapon. Built in `step` while `_charging`.
var _charge := 0.0
var _charging := false

## Shots this weapon has fired itself, for `alternate_rear`. Not the shared counter below: the
## robot and its drones share that one, and alternating on it would hand every backward shot to
## whichever of them happened to fire second.
var _volleys := 0

## The direction the last shot was asked for, before `alternate_rear` turned it round, and the charge
## it left with. The robot hands both to its drones, which fire their own pattern from them.
var _last_request := Vector2.RIGHT
var _last_charge := 0.0

## Lifetime shot count, in an object rather than an int so several weapons can share one.
## Capacitor Leak's "every fifth shot" reads this, and the player hands its drones this
## same counter — which is how spec section 13's one explicit synergy works without any
## code knowing that drones and chain lightning have anything to do with each other.
var shots := ShotCounter.new()


func setup(weapon: WeaponConfig, owning_team: Teams.Id) -> void:
	config = weapon
	team = owning_team
	_cooldown_left = 0.0


## Call once per physics frame before try_fire.
func step(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	if _charging and config != null:
		_charge = minf(_charge + delta, maxf(config.charge_seconds, 0.0))


func can_fire() -> bool:
	return config != null and _cooldown_left <= 0.0


## The trigger is held this frame. An `AUTO` weapon fires as its cooldown allows; a `CHARGE` weapon
## builds its charge and fires nothing until `release_trigger`. Returns whether a shot left.
func hold_trigger(origin: Vector2, direction: Vector2) -> bool:
	if config == null:
		return false
	if config.fire_mode == WeaponConfig.FireMode.CHARGE:
		_charging = true
		return false
	return try_fire(origin, direction)


## The trigger is not held this frame. Fires a `CHARGE` weapon's built charge once its cooldown
## allows, and does nothing for an `AUTO` weapon or one with nothing built. Callers ask every frame
## the trigger is up, so a release that lands during the cooldown fires the moment it ends rather
## than being lost. Returns whether a shot left.
func release_trigger(origin: Vector2, direction: Vector2) -> bool:
	if not _charging or not can_fire():
		return false
	var charge := get_charge_fraction()
	cancel_charge()
	return try_fire(origin, direction, charge)


## Drops whatever charge has been built without firing it.
func cancel_charge() -> void:
	_charging = false
	_charge = 0.0


## How much of a full charge is held, from 0.0 to 1.0. Always 0.0 for a weapon not charging.
func get_charge_fraction() -> float:
	if not _charging or config == null:
		return 0.0
	if config.charge_seconds <= 0.0:
		return 1.0
	return clampf(_charge / config.charge_seconds, 0.0, 1.0)


func is_charging() -> bool:
	return _charging


## Fires the configured pattern from `origin` toward `direction`. Returns false when
## on cooldown or unconfigured, so callers can simply ask every frame.
##
## `charge` is how much of a full charge the shot carries, from 0.0 to 1.0: its damage and radius
## are raised along the line from 1.0 to `charge_max_scale` and `charge_radius_scale`. Zero for
## every shot that was not charged, which is every shot an `AUTO` weapon fires.
func try_fire(origin: Vector2, direction: Vector2, charge := 0.0) -> bool:
	if not can_fire() or direction.is_zero_approx():
		return false

	_cooldown_left = get_fire_interval()
	var shot_index := shots.next()
	_volleys += 1

	var aim := direction.normalized()
	_last_request = aim
	_last_charge = clampf(charge, 0.0, 1.0)
	if config.alternate_rear and _volleys % 2 == 0:
		aim = -aim

	var damage := damage_multiplier * lerpf(1.0, config.charge_max_scale, _last_charge)
	var size := lerpf(1.0, config.charge_radius_scale, _last_charge)
	var muzzle := origin + aim * config.muzzle_offset
	var count := maxi(config.projectiles_per_shot, 1)
	for index: int in count:
		ProjectileFactory.spawn(
			self, config, _pattern_direction(aim, index), muzzle + _lateral(aim, index, count), team,
			damage, get_attributed_shooter(), modifiers, shot_index, size,
		)

	shot_fired.emit(muzzle, aim)
	return true


## The direction the last shot was asked for, before any rear shot turned it round. The robot's
## drones fire from this rather than from the shot that left, so each of them turns round on its own
## count rather than undoing the robot's.
func get_last_request() -> Vector2:
	return _last_request


## How much charge the last shot carried, from 0.0 to 1.0.
func get_last_charge() -> float:
	return _last_charge


## Seconds between shots, after fire-rate items.
func get_fire_interval() -> float:
	return config.get_fire_interval() / maxf(fire_rate_multiplier, 0.01)


## Damage is attributed to the actor that owns this weapon, not to the component, so a
## kill reads as "the Ticket Bot did it" rather than naming an internal node. `owner` is
## the scene root for a component placed in a scene, and null for one created in code.
func get_attributed_shooter() -> Node:
	return owner if owner != null else self


func get_shots_fired() -> int:
	return shots.count


func get_cooldown_remaining() -> float:
	return _cooldown_left


## Where projectile `index` of `count` leaves, sideways of the aim line. Centred, so two parallel
## rivets straddle the line the player aimed down rather than one of them sitting on it.
func _lateral(aim: Vector2, index: int, count: int) -> Vector2:
	if count <= 1 or is_zero_approx(config.lateral_offset):
		return Vector2.ZERO
	return aim.orthogonal() * config.lateral_offset * (float(index) - float(count - 1) * 0.5)


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
