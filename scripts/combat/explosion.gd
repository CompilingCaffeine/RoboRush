class_name Explosion
extends RefCounted
## One blast: damage every hostile body within a radius, once.
##
## A static function rather than a scene because an explosion has no lifetime — the
## damage is instantaneous and the fireball belongs to FeedbackDirector, which is why
## nothing here loads a particle or plays a sound. It only announces that a blast
## happened at a place with a size.
##
## Two callers, which is the reason this is not inlined into either: a projectile with
## `explosion_radius` detonates on impact, and Volatile Kernel detonates on every enemy
## death. Both must behave identically, including "cannot hurt its own team" — which is
## free here, because the radius search only ever returns the opposing team.

## Damage tag carried on the DamageInfo, so armour and resistances can filter for blasts
## without knowing what caused this one.
const TAG := &"explosion"

## Knockback at the centre of the blast, falling off to zero at the edge.
const KNOCKBACK := 130.0


## Applies the blast and returns how many bodies it hit. `attributed_to` is credited with
## the damage; `excluded` skips bodies already damaged by whatever caused the blast, so a
## direct hit is not also caught by its own explosion.
static func detonate(
	source: Node,
	centre: Vector2,
	radius: float,
	damage: float,
	team: Teams.Id,
	attributed_to: Node = null,
	excluded: Array[Node] = [],
) -> int:
	if radius <= 0.0:
		return 0

	EventBus.explosion_triggered.emit(centre, radius)
	if damage <= 0.0:
		return 0

	var hits := 0
	for body: Node2D in Targeting.hostiles_near(source, centre, radius, team, excluded):
		var health := HealthComponent.find_on(body)
		if health == null:
			continue
		var offset := body.global_position - centre
		var direction := offset.normalized() if not offset.is_zero_approx() else Vector2.RIGHT
		var falloff := 1.0 - clampf(offset.length() / radius, 0.0, 1.0)
		var info := DamageInfo.new(
			damage, attributed_to, direction, KNOCKBACK * falloff, false, [TAG] as Array[StringName]
		)
		if health.apply_damage(info):
			hits += 1
	return hits
