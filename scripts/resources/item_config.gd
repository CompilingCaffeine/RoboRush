class_name ItemConfig
extends Resource
## One item, entirely as data. Spec section 10's required fields, plus the hooks that
## make section 13's synergies fall out of composition instead of pairing rules.
##
## The three projectile dictionaries are the important part, and they are dictionaries
## rather than a mirrored field per behaviour on purpose. `ProjectileConfig` already
## names every behaviour a projectile can have; if this resource copied those names into
## its own typed fields, adding one projectile behaviour would mean editing two
## resources, a stack, and a factory. Instead an item names the field it adjusts and by
## how much, which is why Ricochet Driver and Fork Bomb compose into "bounces once, then
## splits" with nothing anywhere aware that those two items can co-occur.
##
## The obvious cost of dictionaries is that a mistyped field name does nothing at all
## and says nothing about it. That is paid for in two places: ProjectileModifierStack
## refuses unknown keys and reports them, and the item suite asserts every key of every
## shipped item against `ProjectileConfig`'s real property list.
##
## Spec section 10 also asks for a pickup sound and an icon, both below, and warns that
## the majority of items should change behaviour rather than numbers. Eight of the ten
## shipped items do.

enum Rarity {
	COMMON,
	UNCOMMON,
	RARE,
	PROTOTYPE,
	CORRUPTED,
}

enum Category {
	WEAPON_CORE,
	PROJECTILE_MODIFIER,
	PROCESSOR,
	MOBILITY,
	DEFENSE,
	UTILITY,
	CORRUPTED_FIRMWARE,
}

## Stable identifier. Used for "already offered this run" and for save data later, so it
## must never change once an item ships.
@export var id: StringName = &"unnamed_item"

@export var display_name: String = "Unnamed Item"

## Shown on the pickup banner. Written as the effect, not as the numbers.
@export_multiline var description: String = ""

@export var rarity: Rarity = Rarity.COMMON

@export var category: Category = Category.PROJECTILE_MODIFIER

## Spec section 10's tags and synergy tags are one list: a tag is only useful because
## something else can look for it, which is what a synergy tag is.
@export var tags: Array[StringName] = []

@export_group("Projectile modifiers")

## Fields assigned outright, by `ProjectileConfig` property name. For behaviours that are
## switched on rather than accumulated (`return_enabled`) or configured once
## (`chain_radius`). Untyped values because both bools and floats belong here.
@export var projectile_set: Dictionary = {}

## Amounts added to a field, by property name. Additive so two copies of the same effect
## stack: `{&"bounce_count": 1}` twice is two bounces.
@export var projectile_add: Dictionary = {}

## Factors a field is multiplied by, by property name. `{&"damage": 1.35}` is +35%.
@export var projectile_scale: Dictionary = {}

## Applies this item's projectile modifiers only every Nth shot. 0 or 1 means every shot.
## Capacitor Leak's "every fifth shot" is this and nothing else, counted against the
## weapon's lifetime shot count — which is why spec section 13's explicit Debug Drone
## synergy ("drone shots count toward the trigger") will need no code when drones arrive.
@export var shot_interval: int = 0

@export_group("Actor modifiers")

## Multiplies the weapon's fire rate. 1.2 is Cooling Fan's +20%.
@export var fire_rate_scale: float = 1.0

## Change to maximum integrity, positive or negative. Applied without refilling.
@export var max_integrity_delta: float = 0.0

## Integrity restored once, on collection. Separate from the maximum so raising the
## ceiling is not silently a free full repair.
@export var heal_on_pickup: float = 0.0

@export var dash_charges_delta: int = 0

@export_group("Behaviour hooks")

## Radius of an explosion at each enemy's death. Volatile Kernel. Zero disables it.
@export var kill_explosion_radius: float = 0.0

## Damage that explosion deals to everything else in range.
@export var kill_explosion_damage: float = 0.0

## How far pickups are dragged toward the player from. Scrap Magnet. Zero disables it.
@export var pickup_magnet_radius: float = 0.0

## How fast they are dragged, in pixels per second.
@export var pickup_magnet_speed: float = 130.0

## Orbiting drones that fire when the player fires. Debug Drone adds one.
@export var drone_count: int = 0

@export_group("Presentation")

@export var icon: Texture2D

## Tints the robot's cannon while held, so spec section 20's "visible item changes" costs
## nothing per item. Fully transparent means the item makes no visible change.
@export var accent_color := Color(0.0, 0.0, 0.0, 0.0)

@export var pickup_sound: StringName = &"item_pickup"


## Whether this item's projectile modifiers apply to a given shot. `shot_index` is the
## weapon's lifetime shot count, which starts at 1.
func applies_on_shot(shot_index: int) -> bool:
	if shot_interval <= 1:
		return true
	return shot_index > 0 and shot_index % shot_interval == 0


func has_tag(tag: StringName) -> bool:
	return tag in tags


## True for items whose whole effect is a number. Used by the suite that asserts spec
## section 10's "most items should change behaviour, not numbers" still holds.
##
## `projectile_scale` deliberately does not count as a behaviour. A set or an add turns
## something on or accumulates it — a bounce that was not there, a jump that was not
## there — while a scale only multiplies what the weapon already did. Unsafe Overclock is
## the case that forces the distinction: it touches a projectile field, and it is still
## the plainest numbers item in the pool.
func is_stat_only() -> bool:
	return (
		projectile_set.is_empty()
		and projectile_add.is_empty()
		and kill_explosion_radius <= 0.0
		and pickup_magnet_radius <= 0.0
		and drone_count <= 0
	)
