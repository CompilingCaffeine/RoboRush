class_name ChainLightning
extends RefCounted
## Damage that hops from one hostile body to the next.
##
## Resolved instantly rather than as a travelling projectile: a chain that took time to
## arrive would let the player walk away from their own hit, and spec section 12's
## Capacitor Leak reads as a discharge, not as a second volley.
##
## Each jump starts from where the last one landed, not from the original impact, so a
## chain follows a line of enemies rather than picking the three nearest to one point.
## Nothing is hit twice, which is what makes "maximum jumps: 3" a real ceiling.

const TAG := &"electric"


## Runs the chain and returns how many bodies were hit. `already_hit` seeds the exclusion
## list — the enemy the projectile struck directly is normally passed in, so the chain
## spreads outward instead of hitting the same target again.
static func strike(
	source: Node,
	origin: Vector2,
	jumps: int,
	radius: float,
	damage: float,
	team: Teams.Id,
	attributed_to: Node = null,
	already_hit: Array[Node] = [],
) -> int:
	if jumps <= 0 or radius <= 0.0 or damage <= 0.0:
		return 0

	var struck: Array[Node] = already_hit.duplicate()
	var point := origin
	var hits := 0

	for _jump: int in jumps:
		var target := Targeting.nearest_hostile(source, point, radius, team, struck)
		if target == null:
			break

		var health := HealthComponent.find_on(target)
		if health == null:
			break

		struck.append(target)
		var direction := (target.global_position - point).normalized()
		var info := DamageInfo.new(
			damage, attributed_to, direction, 0.0, false, [TAG] as Array[StringName]
		)
		if health.apply_damage(info):
			hits += 1
		EventBus.chain_jumped.emit(point, target.global_position)
		point = target.global_position

	return hits
