class_name Recursion
extends Enemy
## Chases at a middling pace and, when killed, returns two smaller and faster copies of
## itself. Those do not split again.
##
## Every other enemy in the game is a problem that shrinks when you shoot it. This is the
## one where killing is a *choice with a cost*: the moment you pop it, one slow body two
## rooms' worth of reaction time away becomes two quick ones right where you were aiming.
## The interesting decision is therefore not "can I hit it" but "do I want it dead now, or
## after I have dealt with the Compiler lane that is about to execute", which is a decision
## no other enemy on the floor asks for.
##
## The fragments are this same scene with `generation` raised, not a second enemy. One scene
## and one config means a Recursion and its children cannot drift into being two unrelated
## things, and it makes `max_generation` an honest bound rather than a promise about a file
## somebody has to remember to keep in step.
##
## `ElderRecursion` sits one rung above this and is the only reason `_make_fragment` is a
## method rather than three lines inside `_split`: the elder's children are full Recursions,
## which is a different *scene* from the elder but the same split, the same tracking, and the
## same deferred add. What a split produces is the one thing that varies; everything about how
## it happens does not, and it is written once here.

## Set before the fragment enters the tree. Zero is what the floor spawns; anything higher
## came out of another Recursion.
@export var generation: int = 0

var _tuning: RecursionConfig


func _on_ready() -> void:
	_tuning = config as RecursionConfig
	assert(_tuning != null, "Recursion.config must be a RecursionConfig.")
	if generation > 0:
		_become_fragment()


func _act(_delta: float) -> Vector2:
	if _player == null:
		return Vector2.ZERO
	var offset := _player.global_position - global_position
	if offset.is_zero_approx():
		return Vector2.ZERO
	return offset.normalized() * _speed()


func can_split() -> bool:
	return generation < _tuning.max_generation


func get_generation() -> int:
	return generation


func _speed() -> float:
	if generation <= 0:
		return config.move_speed
	return config.move_speed * _tuning.fragment_speed_scale


## Rewrites this instance into a fragment. Health is re-`configure`d rather than set,
## because the base class has already sized it from `config.max_health` by the time
## `_on_ready` runs and a fragment's pool is not the parent's.
##
## `config` is duplicated first: the shared `.tres` is one resource instance handed to every
## Recursion in the run, so writing `contact_damage` on it directly would quietly weaken
## every full-size Recursion in the room, including ones already fighting.
func _become_fragment() -> void:
	var own_config := config.duplicate() as RecursionConfig
	own_config.contact_damage = _tuning.fragment_contact_damage
	own_config.max_health = _tuning.fragment_health
	config = own_config
	_tuning = own_config

	get_health_component().configure(scaled_max_health(_tuning.fragment_health), 0.0)

	var factor := maxf(_tuning.fragment_scale, 0.1)
	_sprite.scale = Vector2.ONE * factor
	_resize_body(factor)


## Resizes the collision circle to match the sprite, so what the player shoots at is the
## size it looks. Used in both directions — a fragment shrinks, an `ElderRecursion` grows —
## which is why it multiplies rather than assigning a radius: one call site cannot then hold
## a number the other one has to remember to keep in step with.
##
## The radius is changed on a *duplicate* of the shape: a `[sub_resource]` in a scene is
## shared by every instance of that scene unless it is marked local, so scaling the original
## would resize every Recursion in the room, full-size ones included.
func _resize_body(factor: float) -> void:
	var shape := get_node_or_null("Shape") as CollisionShape2D
	if shape == null:
		return
	var circle := shape.shape as CircleShape2D
	if circle == null:
		return
	var own := circle.duplicate() as CircleShape2D
	own.radius *= factor
	shape.shape = own


## Splits before announcing the death, so the room's alive count never touches zero on the
## way through. `RoomCombat` decrements on `HealthComponent.died`, which is connected after
## this override — the fragments are registered first, the parent is subtracted second, and
## a door therefore cannot unlock for the frame in between.
func _on_died() -> void:
	if can_split():
		_split()
	super()


func _split() -> void:
	var container := get_parent()
	if container == null:
		return
	var combat := _find_room_combat()
	# One roll for the whole split, not one per fragment. Rolling inside the loop made each
	# fragment's angle independent, which meant two of them could — and regularly did — come
	# out on the same side and overlap into what looks like a single body.
	var base_angle := randf() * TAU

	for index: int in maxi(_tuning.fragment_count, 0):
		var fragment := _make_fragment()
		if fragment == null:
			return
		# Local rather than global: the fragment is not in the tree yet, so it has no global
		# transform to set, and it is going into the same container this node already sits
		# in — where `position` is already the right coordinate space.
		fragment.position = position + _fragment_offset(index, base_angle)

		# Deferred for LootSpawner's reason: this runs inside a damage callback, with the
		# physics server mid-flush, and registering a new body's collision shape at that
		# moment is refused outright — the fragments would silently never appear.
		container.add_child.call_deferred(fragment)

		# Registered immediately rather than deferred, even though the body arrives later.
		# `RoomCombat.track` only needs the fragment's HealthComponent, which exists from
		# instantiation, and counting it now is precisely what stops the room reading as
		# clear in the frames between this death and those children arriving.
		if combat != null:
			combat.track(fragment)


## Fragments are spaced evenly around `base_angle`, which is rolled once per split. The
## rotation is random but the *spacing* is not, so two fragments are always two targets; and
## it is not aimed at the player, so a split never doubles as a lunge.
func _fragment_offset(index: int, base_angle: float) -> Vector2:
	var count := maxi(_tuning.fragment_count, 1)
	var angle := base_angle + TAU * float(index) / float(count)
	return Vector2.RIGHT.rotated(angle) * _split_spread()


## How far out a split throws its children. Scaled by the body doing the splitting rather than
## fixed, so an `ElderRecursion` — half again as wide as what comes out of it — does not drop two
## full-size Recursions inside its own silhouette, where they read as one body until they separate.
func _split_spread() -> float:
	return _tuning.fragment_spread


func _find_room_combat() -> RoomCombat:
	var room := find_room()
	return room.get_room_combat() if room != null else null


## One child of a split, configured and ready to be placed. Overridden by `ElderRecursion`,
## which returns a full Recursion instead of a smaller copy of itself.
##
## The generation is raised here rather than in `_split` because it is part of *what* a child
## is: a Recursion's child is the next generation down of the same body, and an elder's child
## is a fresh generation zero of a different one. A `_split` that raised the number itself
## would be a `_split` that had an opinion about that.
func _make_fragment() -> Recursion:
	var fragment := _instantiate_sibling()
	if fragment == null:
		return null
	fragment.config = config
	fragment.generation = generation + 1
	return fragment


## Instantiates another copy of whatever scene this node came from. Reads `scene_file_path`
## rather than `preload("recursion.tscn")`, so this script does not hold a load-time
## reference to the scene whose root holds a load-time reference back to this script.
##
## It also means a fragment splits into its own scene rather than into a hardcoded one,
## which is what keeps `max_generation` the only thing standing between one Recursion and a
## room full of them.
func _instantiate_sibling() -> Recursion:
	if scene_file_path.is_empty():
		return null
	var packed := load(scene_file_path) as PackedScene
	if packed == null:
		return null
	return packed.instantiate() as Recursion
