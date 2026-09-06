class_name ElderRecursion
extends Recursion
## A Recursion one rung up: a larger, slower, red body that breaks into two ordinary Recursions,
## each of which goes on to break into two fragments exactly as it always has.
##
## The floor that *introduces* Recursion never spawns one of these. The whole value of the enemy
## is the sentence it teaches — killing this converts one slow problem into two quick ones, so
## when you kill it is a decision — and a player meeting that sentence for the first time should
## meet it at its smallest. The elder is what the sentence becomes once they know it: the same
## trade, one level deeper, on a body that takes long enough to open that they have to choose the
## moment in advance rather than notice it afterwards. One elder is seven bodies before the room
## is clear, and the player can see all seven coming from the sprite.
##
## It is a subclass and a second scene, but not a second *enemy*: the children it makes are the
## floor's own `recursion.tscn`, loaded from the same file the roster spawns, and its numbers are
## the elder rung of the one `RecursionConfig` the family shares. Nothing here can drift out of
## step with what a Recursion is, because nothing here restates it.
##
## Everything else — the chase, the split's timing against the room's alive count, the deferred
## add, the tracking — is inherited unchanged. Two methods differ, and they are the two that
## answer "how big is this" and "what comes out of it".

## What an elder breaks into. The scene the floor's roster spawns, so an elder's children are
## indistinguishable from the Recursions the player has already learned — including in what they
## then do when killed, which is the point of putting an elder above them rather than beside them.
const RECURSION_SCENE := preload("res://scenes/enemies/recursion.tscn")


## Grown before the base class can do anything with `generation`. An elder is always generation
## zero — it is the root of a family, not a rung inside one — so the inherited `can_split` is
## already true here and `max_generation` still bounds the two rungs below.
func _on_ready() -> void:
	super()
	_become_elder()


## The mirror image of `_become_fragment`, and written the same way for the same reasons: the
## config is duplicated before anything is written to it, because the shared `.tres` is one
## resource instance handed to every Recursion in the run; and health is re-`configure`d rather
## than assigned, because the base class has already sized this body from `config.max_health` by
## the time `_on_ready` runs.
##
## `move_speed` is written into the duplicate rather than handled in `_speed`, so that everything
## reading this body's config — knockback, contact, anything added later — sees one consistent
## description of an elder rather than a Recursion with a special case attached.
func _become_elder() -> void:
	var own_config := config.duplicate() as RecursionConfig
	own_config.max_health = _tuning.elder_health
	own_config.contact_damage = _tuning.elder_contact_damage
	own_config.move_speed = config.move_speed * maxf(_tuning.elder_speed_scale, 0.05)
	own_config.contact_radius = config.contact_radius * maxf(_tuning.elder_scale, 0.1)
	config = own_config
	_tuning = own_config

	get_health_component().configure(scaled_max_health(_tuning.elder_health), 0.0)

	var factor := maxf(_tuning.elder_scale, 0.1)
	_sprite.scale = Vector2.ONE * factor
	_resize_body(factor)


## Full Recursions, not smaller elders. `_instantiate_sibling` would hand back this scene, which
## is the one thing an elder must never produce: a family that could grow another elder at every
## rung is a room whose enemy count is no longer arithmetic the player can do while looking at it.
##
## Generation zero and the shared config, so what comes out is precisely the enemy the roster
## spawns — it splits once more, into fragments that do not split, and the bound is still
## `max_generation`.
func _make_fragment() -> Recursion:
	return RECURSION_SCENE.instantiate() as Recursion


## Wider than a Recursion's, in proportion to the body doing the splitting. Two full-size children
## dropped at the standard spread would appear inside the elder's own silhouette.
func _split_spread() -> float:
	return _tuning.fragment_spread * maxf(_tuning.elder_scale, 1.0)
