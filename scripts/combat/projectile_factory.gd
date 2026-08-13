class_name ProjectileFactory
extends RefCounted
## Turns a WeaponConfig into live projectiles.
##
## The one place that knows how a projectile comes into the world, so weapons never
## touch the scene tree and projectiles never learn who fired them beyond a
## reference.
##
## This is also where items take effect. `spawn` copies the weapon's projectile config,
## runs the shooter's ProjectileModifierStack over the copy, and only then builds
## anything — so every item in the game reaches the projectile through one function, and
## the projectile itself never learns that items exist.

const PROJECTILE_SCENE := preload("res://scenes/projectiles/projectile.tscn")

## Projectiles are parented to a container in the level, never to the shooter — a
## projectile must not move when the thing that fired it moves. The floor's `FloorSession`
## holds the node in this group, which is what makes a shot die with the floor it was fired
## on; a test arena registers its own.
const CONTAINER_GROUP := &"projectile_container"


## Spawns one projectile from a weapon. `damage_multiplier` is the shooter's flat scaling
## and is baked into this projectile's own config copy.
##
## `spawner` is the node used to reach the tree; `attributed_to` is who the damage is
## credited to and defaults to the spawner. They differ because a weapon component
## spawns the shot but the actor owning it should be named as the source.
##
## `modifiers` is the shooter's item stack, or null for anything without items — every
## enemy in the game. `shot_index` is the weapon's lifetime shot count, which is what
## lets an item apply only every Nth shot.
static func spawn(
	spawner: Node,
	weapon: WeaponConfig,
	direction: Vector2,
	muzzle: Vector2,
	team: Teams.Id,
	damage_multiplier := 1.0,
	attributed_to: Node = null,
	modifiers: ProjectileModifierStack = null,
	shot_index := 0,
) -> Projectile:
	if weapon.projectile == null:
		push_error("WeaponConfig '%s' has no projectile assigned." % weapon.display_name)
		return null

	# Each projectile owns its config so it can spend its own pierce and bounce
	# counters, and carry its own item modifiers, without touching the shared resource.
	var config := weapon.projectile.spawn_copy()
	config.damage *= damage_multiplier
	if modifiers != null:
		modifiers.apply(config, shot_index)

	# The one place a shot's direction is allowed to disagree with where it was aimed. Applied here
	# rather than inside `spawn_configured`, which splits also go through: a child inheriting an
	# already-rotated config would be rotated again, and a 45 degree item would bend further with
	# every generation instead of once.
	var launched := direction
	if not is_zero_approx(config.aim_offset_degrees):
		launched = direction.rotated(deg_to_rad(config.aim_offset_degrees))

	return spawn_configured(
		spawner,
		config,
		launched,
		muzzle,
		team,
		attributed_to if attributed_to != null else spawner,
	)


## Spawns a projectile from a config that is already final. Used for children that no
## weapon fired — split fragments — where re-running the modifier stack would apply every
## item a second time and let a splitting shot split again.
##
## `deferred` adds the projectile on the next idle frame instead of immediately. Splits
## need it because they happen inside a physics callback, where Godot refuses to register
## a new body's collision shape; ordinary shots do not, and adding them immediately keeps
## the frame they were fired on the frame they exist on.
static func spawn_configured(
	spawner: Node,
	config: ProjectileConfig,
	direction: Vector2,
	origin: Vector2,
	team: Teams.Id,
	attributed_to: Node = null,
	excluded_bodies: Array[Node] = [],
	deferred := false,
) -> Projectile:
	var container := _resolve_container(spawner)
	if container == null:
		push_error("No projectile container available; projectile discarded.")
		return null

	var projectile: Projectile = PROJECTILE_SCENE.instantiate()
	projectile.configure(
		config,
		team,
		attributed_to if attributed_to != null else spawner,
		origin,
		direction,
		excluded_bodies,
	)

	if deferred:
		# Through the session where there is one, so a split fired on the frame a floor is
		# released is refused rather than landing on the next floor — see
		# `FloorSession.add_deferred`. Falls back to the plain deferral in a test arena, which has
		# no session and therefore no generation to be stale against.
		var session := FloorSession.owning(container)
		if session != null:
			session.add_deferred(container, projectile)
		else:
			container.add_child.call_deferred(projectile)
	else:
		container.add_child(projectile)
	return projectile


## Prefers the registered container, falling back to the current scene so a test
## scene without a room still works rather than silently dropping every shot.
static func _resolve_container(spawner: Node) -> Node:
	if not spawner.is_inside_tree():
		return null
	var tree := spawner.get_tree()
	var container := tree.get_first_node_in_group(CONTAINER_GROUP)
	return container if container != null else tree.current_scene
