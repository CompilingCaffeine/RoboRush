class_name ProjectileFactory
extends RefCounted
## Turns a WeaponConfig into live projectiles.
##
## The one place that knows how a projectile comes into the world, so weapons never
## touch the scene tree and projectiles never learn who fired them beyond a
## reference. Milestone 4's ProjectileModifierStack slots in here: it will run over
## the config copy between `spawn_copy()` and instantiation, which is exactly why
## that copy exists.

const PROJECTILE_SCENE := preload("res://scenes/projectiles/projectile.tscn")

## Projectiles are parented to a container in the level, never to the shooter — a
## projectile must not move when the thing that fired it moves. The room registers
## itself in this group.
const CONTAINER_GROUP := &"projectile_container"


## Spawns one projectile. `damage_multiplier` comes from the shooter's item stack and is
## baked into this projectile's own config copy.
##
## `spawner` is the node used to reach the tree; `attributed_to` is who the damage is
## credited to and defaults to the spawner. They differ because a weapon component
## spawns the shot but the actor owning it should be named as the source.
static func spawn(
	spawner: Node,
	weapon: WeaponConfig,
	direction: Vector2,
	muzzle: Vector2,
	team: Teams.Id,
	damage_multiplier := 1.0,
	attributed_to: Node = null,
) -> Projectile:
	if weapon.projectile == null:
		push_error("WeaponConfig '%s' has no projectile assigned." % weapon.display_name)
		return null

	var container := _resolve_container(spawner)
	if container == null:
		push_error("No projectile container available; projectile discarded.")
		return null

	# Each projectile owns its config so it can spend its own pierce and bounce
	# counters without touching the shared resource.
	var config := weapon.projectile.spawn_copy()
	config.damage *= damage_multiplier

	var projectile: Projectile = PROJECTILE_SCENE.instantiate()
	projectile.configure(
		config, team, attributed_to if attributed_to != null else spawner, muzzle, direction
	)
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
