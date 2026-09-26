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

## How much of the shot's trail opacity an echo keeps. Half, so an echo reads as the ghost of a
## shot rather than as a second one, while keeping the colour that says whose it is.
const ECHO_TRAIL_ALPHA := 0.5

## Player projectiles that have been created and not yet retired, oldest first. Counted from the
## moment of creation rather than from entering the tree, because a split is deferred to the next
## idle frame and a burst of them would otherwise all see room under the cap. Pruned lazily: an
## entry that has been freed or spent is dropped the next time anything asks.
static var _live_player: Array[Projectile] = []


## Spawns one projectile from a weapon. `damage_multiplier` is the shooter's flat scaling
## and is baked into this projectile's own config copy.
##
## `spawner` is the node used to reach the tree; `attributed_to` is who the damage is
## credited to and defaults to the spawner. They differ because a weapon component
## spawns the shot but the actor owning it should be named as the source.
##
## `modifiers` is the shooter's item stack, or null for anything without items — every
## enemy in the game. `shot_index` is the weapon's lifetime shot count, which is what
## lets an item apply only every Nth shot. `size_multiplier` scales the radius the same way
## `damage_multiplier` scales the damage, before the items: it is how a charged shot is bigger.
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
	size_multiplier := 1.0,
) -> Projectile:
	if weapon.projectile == null:
		push_error("WeaponConfig '%s' has no projectile assigned." % weapon.display_name)
		return null

	# Each projectile owns its config so it can spend its own pierce and bounce
	# counters, and carry its own item modifiers, without touching the shared resource.
	var config := weapon.projectile.spawn_copy()
	config.damage *= damage_multiplier
	config.radius *= size_multiplier
	if modifiers != null:
		modifiers.apply(config, shot_index)

	# The one place a shot's direction is allowed to disagree with where it was aimed. Applied here
	# rather than inside `spawn_configured`, which splits also go through: a child inheriting an
	# already-rotated config would be rotated again, and a 45 degree item would bend further with
	# every generation instead of once.
	var launched := direction
	if not is_zero_approx(config.aim_offset_degrees):
		launched = direction.rotated(deg_to_rad(config.aim_offset_degrees))

	var credited := attributed_to if attributed_to != null else spawner
	var projectile := spawn_configured(spawner, config, launched, muzzle, team, credited)
	if projectile != null and config.echo_delay > 0.0:
		_schedule_echo(spawner, config, launched, muzzle, team, credited)
	return projectile


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
	if team == Teams.Id.PLAYER:
		_make_room_for_player_shot()
		_live_player.append(projectile)
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


## Fires a copy of a weapon's shot `echo_delay` seconds from now, from the same muzzle, the same
## way, at `echo_damage_scale` of its damage. Roadmap SYS-2.
##
## Here rather than in the projectile, because an echo is a second shot rather than something the
## first one does: it must fire whether or not the first is still flying, and a split child or a
## retargeted shot, which never pass through `spawn`, must not echo at all.
##
## The timer pauses with the game. The echo is held against the container the shot was fired into,
## and dropped if that container has left the tree or its floor has been released by the time it is
## due — the same rule a held explosion keeps, for the same reason.
static func _schedule_echo(
	spawner: Node,
	config: ProjectileConfig,
	direction: Vector2,
	origin: Vector2,
	team: Teams.Id,
	attributed_to: Node,
) -> void:
	var container := _resolve_container(spawner)
	if container == null:
		return

	var echo := config.spawn_copy()
	echo.echo_delay = 0.0
	echo.damage *= config.echo_damage_scale
	echo.trail_color.a *= ECHO_TRAIL_ALPHA

	var home: WeakRef = weakref(container)
	var credit: WeakRef = weakref(attributed_to) if attributed_to != null else null
	var timer := container.get_tree().create_timer(config.echo_delay, false, true)
	timer.timeout.connect(func() -> void:
		var target := home.get_ref() as Node
		if target == null or not target.is_inside_tree():
			return
		var session := FloorSession.owning(target)
		if session != null and not session.is_open():
			return
		var shooter: Node = credit.get_ref() as Node if credit != null else null
		spawn_configured(target, echo, direction, origin, team, shooter)
	)


## How many player projectiles are alive, pending ones included. For the cap and for the checks
## that hold it.
static func live_player_count() -> int:
	_prune_live_player()
	return _live_player.size()


## Retires player shots until one more fits under `CombatCaps.max_player_projectiles`.
##
## The oldest shot that does not pierce goes first: it has had the longest to find something, and a
## shot that stops at its first hit is worth the least of anything in flight. A piercing shot is
## still carrying damage through a pack, so it is spent only when every shot in the air pierces.
## Retired quietly, without an expiry: an expiry is what a returning or retargeting shot answers,
## and answering the cap with a new shot would be the cap feeding itself.
static func _make_room_for_player_shot() -> void:
	_prune_live_player()
	var limit := maxi(CombatCaps.active().max_player_projectiles, 1)
	while _live_player.size() >= limit:
		var victim := 0
		for index: int in _live_player.size():
			if _live_player[index].config == null or _live_player[index].config.pierce_count <= 0:
				victim = index
				break
		_live_player[victim].retire()
		_live_player.remove_at(victim)


static func _prune_live_player() -> void:
	var kept: Array[Projectile] = []
	for projectile: Projectile in _live_player:
		if is_instance_valid(projectile) and not projectile.is_spent():
			kept.append(projectile)
	_live_player = kept


## Prefers the registered container, falling back to the current scene so a test
## scene without a room still works rather than silently dropping every shot.
static func _resolve_container(spawner: Node) -> Node:
	if not spawner.is_inside_tree():
		return null
	var tree := spawner.get_tree()
	var container := tree.get_first_node_in_group(CONTAINER_GROUP)
	return container if container != null else tree.current_scene
