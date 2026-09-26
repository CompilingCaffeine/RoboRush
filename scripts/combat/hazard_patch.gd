class_name HazardPatch
extends Node2D
## A small patch of ground a shot leaves behind, applying one status to enemies standing in it.
## Roadmap SYS-2's trail hazards: `ProjectileConfig.trail_hazard_interval` and its three siblings.
##
## Owned by a team and hostile to the other, like everything else a shot does. It lives in the
## projectile container, so it dies with the floor it was dropped on, and it stops at the edge of the
## room it was dropped in, so a patch against a wall never reaches through into the next room.
##
## Player patches count against `CombatCaps.max_player_hazards`. The oldest goes first: a patch near
## the end of its life is doing the least.

## Seconds between the patch's applications of its status. Each is one stack, so a patch is a steady
## source rather than a burst, and standing in one for its whole life is three stacks.
const TICK_SECONDS := 0.5

## Opacity of the drawn patch at the start of its life. It fades to nothing as it runs out, which is
## the only clock it needs: nobody has to read a number to know one is nearly gone.
const ALPHA := 0.35

## Player patches alive now, oldest first. Pruned lazily, like `ProjectileFactory`'s shots.
static var _live_player: Array[HazardPatch] = []

var team := Teams.Id.PLAYER
var radius := 8.0
var effect: StringName = &""
var lifetime := 1.5

var _left := 0.0
var _tick_left := 0.0
var _within := Rect2()
var _color := Color.WHITE


## Leaves a patch at `at` for `seconds`, or does nothing when there is nowhere to put one. `within`
## is the room the dropping shot belongs to, as a global rect; empty means no room, as everywhere.
static func drop(
	spawner: Node,
	at: Vector2,
	patch_radius: float,
	seconds: float,
	status: StringName,
	owning_team: Teams.Id,
	within := Rect2(),
) -> HazardPatch:
	if spawner == null or not spawner.is_inside_tree() or patch_radius <= 0.0 or seconds <= 0.0:
		return null
	var definition: Dictionary = StatusEffectController.DEFINITIONS.get(status, {})
	if definition.is_empty():
		push_error("HazardPatch: unknown status effect '%s'." % status)
		return null

	var tree := spawner.get_tree()
	var container := tree.get_first_node_in_group(ProjectileFactory.CONTAINER_GROUP)
	if container == null:
		container = tree.current_scene
	if container == null:
		return null

	if owning_team == Teams.Id.PLAYER:
		_make_room()

	var patch := HazardPatch.new()
	patch.team = owning_team
	patch.radius = patch_radius
	patch.effect = status
	patch.lifetime = seconds
	patch._left = seconds
	patch._within = within
	patch._color = definition.get("color", Color.WHITE)
	container.add_child(patch)
	patch.global_position = at
	if owning_team == Teams.Id.PLAYER:
		_live_player.append(patch)
	return patch


## Player patches alive now. For the cap's checks.
static func live_player_count() -> int:
	_prune()
	return _live_player.size()


static func _make_room() -> void:
	_prune()
	var limit := maxi(CombatCaps.active().max_player_hazards, 1)
	while _live_player.size() >= limit:
		_live_player.pop_front().queue_free()


static func _prune() -> void:
	var kept: Array[HazardPatch] = []
	for patch: HazardPatch in _live_player:
		if is_instance_valid(patch) and not patch.is_queued_for_deletion():
			kept.append(patch)
	_live_player = kept


func _physics_process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0:
		queue_free()
		return

	_tick_left -= delta
	if _tick_left <= 0.0:
		_tick_left += TICK_SECONDS
		_apply()
	queue_redraw()


func _apply() -> void:
	for body: Node2D in Targeting.hostiles_near(self, global_position, radius, team, [], _within):
		var status := StatusEffectController.find_on(body)
		if status != null:
			status.apply(effect)


func _draw() -> void:
	var fade := clampf(_left / maxf(lifetime, 0.001), 0.0, 1.0)
	draw_circle(Vector2.ZERO, radius, Color(_color, ALPHA * fade))
