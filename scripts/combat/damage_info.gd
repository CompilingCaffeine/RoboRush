class_name DamageInfo
extends RefCounted
## One damage event, passed from whatever dealt it to whatever receives it.
##
## Exists so damage is a *described* event rather than a bare float. Knockback
## direction, criticals, and effect tags all need to travel with the number, and a
## DamageResolver (spec section 14) needs something to resolve. Adding a field here
## is how critical hits, elemental damage, and armour arrive later without changing
## a single call signature.

## Integrity to remove, after weapon and item multipliers.
var amount: float

## What dealt the damage — a player, an enemy, a hazard. May be null.
var source: Node

## Direction the damage travelled in, used for knockback and hit-spark orientation.
var direction: Vector2

## Knockback impulse in pixels per second, before the receiver's resistance.
var knockback: float

## Set by the processor upgrades that add criticals. Presentation reads this to
## emphasise the damage number.
var is_critical: bool

## Free-form tags such as &"explosion" or &"electric", so defence modules and
## on-hit effects can filter without knowing the source.
var tags: Array[StringName]


func _init(
	p_amount: float,
	p_source: Node = null,
	p_direction := Vector2.ZERO,
	p_knockback := 0.0,
	p_is_critical := false,
	p_tags: Array[StringName] = [],
) -> void:
	amount = p_amount
	source = p_source
	direction = p_direction
	knockback = p_knockback
	is_critical = p_is_critical
	tags = p_tags
