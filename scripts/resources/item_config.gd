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

## What the item actually does, written as the effect rather than as the numbers.
##
## Not shown to the player anywhere, deliberately: an item explains itself by being used, and the
## pickup banner gives the name only. This is the design record — the one place a reader can find
## out what an item is supposed to do without reading `ItemEffects` — and it is required of every
## shipped item for that reason, not for the player's benefit.
@export_multiline var description: String = ""

@export var rarity: Rarity = Rarity.COMMON

@export var category: Category = Category.PROJECTILE_MODIFIER

@export_group("Offer policy")

## How many copies of this item one run may hold.
##
## 1 — the default, and what every item authored before the chips is — makes it *unique*: offered
## once, taken once, and never seen again that run. That is what a build-defining item has to be.
## An item whose whole identity is "projectiles bounce" says nothing new the second time.
##
## Above 1 makes it *repeatable*: it may be offered again after it has been taken, and the copies
## stack. This is the second reward class the six-floor economy needs. Six floors ask for 48
## offers; the unique pool is finite, and a run that out-draws it — through rerolls, or through
## being longer than the budget assumed — used to answer with nothing at all, because
## `RunManager.draw_item` returns null on an exhausted pool and every caller has a quiet fallback.
## A stack of small upgrades is a worse reward than a new mechanic and a much better one than a
## treasure room containing a repair cell.
##
## Stacking is additive and falls out of `ItemInventory`'s existing aggregates: they already sum
## across everything held, so two copies of a +damage chip are +2 damage with no code that knows
## chips exist. Only the duplicate guard had to learn the difference.
@export var max_stacks: int = 1

## The tag marking an item that gives the player nothing back for what it costs. Read by
## `is_hindrance`, which the boss reward uses to guarantee one choice worth taking.
##
## A tag rather than a `bool` beside it, because the three items this describes already carry it
## and a second field saying the same thing is a second field to forget. `tests/test_items.gd`
## checks the tag against `has_upside`, so it cannot drift into a decoration.
const HINDRANCE_TAG := &"hindrance"

## Projectile fields that are a cost at any value, so `has_upside` must not read them as a benefit
## simply because the item touches a projectile. Off-By-One's forty-five degree swing is worse in
## either direction, which is what makes it different from a negative amount of something good.
const PENALTY_KEYS: Array[StringName] = [&"aim_offset_degrees"]

## The mirror of `PENALTY_KEYS`: fields that are a benefit at any value, so the sign test must not
## read a negative amount of them as a cost.
##
## `knockback` is the case. A shove keeps enemies off the robot and a *pull* drags them into an
## explosion, a compile lane, or each other's chain range — Tractor Beam's whole effect is a negative
## amount of it, and the sign test would have called the item a pure cost. That would be a quiet
## misclassification rather than a loud one: `is_hindrance` is a tag, so nothing would have broken
## today, and `has_upside` exists precisely to be the reality the tag is checked against.
const BENEFIT_KEYS: Array[StringName] = [&"knockback"]

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

## Lethal hits this item can survive, once each. Failover grants one. Zero for everything else.
##
## What surviving costs is not a knob here, and deliberately: the pool collapses to
## `HealthComponent.MINIMUM_MAX_HEALTH` — one point — for the rest of the run. Maximum integrity, not
## current: the robot is not patched up, it is running degraded, and every hit from then on is lethal
## until the player rebuilds the ceiling with the items that raise it. A second, gentler failover
## item would be a different `death_save_charges` count, not a different floor, because "the least
## integrity the game allows" is a rule about the game rather than a property of an item.
##
## The debt lives on `RunManager` rather than in the health component, for the same reason Tech Debt's
## enemy scaling does: `Player._apply_item_stats` recomputes the maximum from the config and the
## inventory on every pickup, so anything written straight onto the component is erased by the next
## item the player collects. It also has to survive a floor boundary, and the run is what does that.
@export var death_save_charges: int = 0

## Seconds of immunity granted the moment a death is averted. Without it the save is a formality:
## the shot that would have killed the player is rarely alone, and the next one in the volley arrives
## into a one-point pool.
@export var death_save_grace_seconds: float = 3.0

## Hits absorbed whole, refilled on entering a room. Faraday Cage grants one.
##
## Charges rather than seconds of immunity, because what makes a shield readable is that it is spent
## by a blow rather than by a clock: the player sees one hit blocked and knows the next one is not.
## Refilled per room rather than per run so it is a rhythm the player can plan a fight around.
@export var shield_charges_per_room: int = 0

## Multiplies the damage of the first shot fired after entering a room. Cache Warmer. One disables it.
##
## The pool's first *conditional* damage item: everything else that multiplies damage does it always
## or on a shot count. This one is worth exactly as much as the player's opening decision, which
## makes walking into a room a moment rather than a transition.
@export var first_shot_damage_scale: float = 1.0

## Radius of a status burst released where an enemy dies, and what it applies. Garbage Collector.
## Both are required, for the reason the dash pulse's pair is: a radius with no effects is an
## invisible circle.
@export var kill_pulse_radius: float = 0.0

@export var kill_pulse_effects: Array[StringName] = []

## Radius and damage of a blast released when the *player* is hit. Interrupt Handler.
##
## The pool's first reactive payoff. Every other defensive item reduces what a hit costs; this one
## makes being hit do something, which is a different answer to the same pressure and the only one
## that rewards standing in the fight.
@export var retaliation_radius: float = 0.0

@export var retaliation_damage: float = 0.0

## Fire rate multiplier applied while the robot has been still for `stillness_seconds`. Mutex Lock.
##
## Deliberately the mirror of Blocking I/O, which forbids firing on the move and gives nothing back.
## The same condition, paid rather than charged: standing still is a choice with an upside instead of
## a tax, and the two items in one build is a weapon that only works planted.
@export var stillness_fire_rate_scale: float = 1.0

@export var stillness_seconds: float = 0.6

## Fire rate multiplier applied while integrity is at or below `low_integrity_points`. Adrenal Loop.
##
## Points rather than a fraction of the maximum, and that is the whole design. A fraction would never
## trigger for a run that has spent a Failover — the pool collapses to one point, so the player sits
## at 100% of a maximum of one, permanently unhurt by that measure and permanently one hit from over.
## An absolute floor reads the situation the player is actually in.
@export var low_integrity_fire_rate_scale: float = 1.0

@export var low_integrity_points: float = 1.0

## Fraction of held scrap paid out on every room cleared. Compound Interest.
##
## The first item that makes *not* spending a decision. Scrap has only ever flowed one way — the shop
## is a sink, and a hoarded pile does nothing but wait — so an item that pays interest turns every
## shelf into "buy this, or let it compound".
@export var scrap_interest_fraction: float = 0.0

## Fraction of the damage a room dealt the player, repaid when that room is cleared. Swap Space.
##
## Repaid on the clear rather than continuously, so it is a reason to finish a fight rather than a
## reason to leave one: damage taken and not paid for is damage the player is owed, and walking out
## of the room forfeits it.
@export var room_damage_refund: float = 0.0

## Radius of a status pulse emitted when the player dashes. Breakpoint. Zero disables it.
##
## A radius and an effect id rather than a `dash_pulse: bool` for the same reason the
## projectile modifiers are dictionaries: a second dash item that burns instead of chilling
## is then a `.tres`, and nothing here has to learn the word "Breakpoint".
@export var dash_pulse_radius: float = 0.0

## Status effect ids the pulse applies. Empty means the pulse does nothing, which is why
## `dash_pulse_radius` alone is not enough to switch one on.
@export var dash_pulse_effects: Array[StringName] = []

@export_group("Corrupted firmware")

## The weapon refuses to fire while the robot is moving. Blocking I/O.
##
## The first item in the pool with no upside whatsoever. Everything else that costs the
## player something buys them something — Unsafe Overclock trades integrity for damage,
## Stack Overflow trades speed for size. These three trade nothing, and are in the pool for
## the reason a shop with only good stock is not a shop: an offer the player should refuse
## is what makes the offers they accept a decision.
@export var fire_requires_stillness: bool = false

## Multiplies the dash cooldown. Legacy Runtime uses 3.0. Below 1.0 would be a *good* item
## and nothing stops one being authored, which is deliberate — this is a knob, not a curse.
@export var dash_cooldown_scale: float = 1.0

## Added to a multiplier on every future enemy's maximum integrity, once per room cleared.
## Tech Debt uses 0.12, so the eighth room's enemies carry nearly twice what the first
## room's did. Zero for every item that does not accrue.
@export var enemy_health_growth_per_room: float = 0.0

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


## Whether this item may be offered again once the player already has one.
func is_repeatable() -> bool:
	return max_stacks > 1


## Whether this item is a pure cost.
##
## Three shipped items qualify: Blocking I/O, Legacy Runtime, and Tech Debt. They are in the pool
## because a shop with only good stock is not a shop — an offer the player should refuse is what
## makes the offers they accept a decision. Unsafe Overclock and Stack Overflow are *not*
## hindrances despite being corrupted: they trade something for something, which is a bargain
## rather than a tax.
##
## Read by the boss reward, which guarantees at least one choice that is not one of these. Three
## hindrances on one set of stands is not a decision, and it is exactly what the shipped game
## offered after every first boss — see `FloorController._draw_boss_reward`.
func is_hindrance() -> bool:
	return has_tag(HINDRANCE_TAG)


## Whether this item does anything for the player at all.
##
## Computed from the fields rather than declared, so `is_hindrance` can be checked against reality
## instead of being trusted — an item flagged as a pure cost that quietly grants +1 integrity is a
## flag nobody would notice was wrong. `tests/test_items.gd` holds the two together.
func has_upside() -> bool:
	return (
		_changes_a_projectile_for_the_better()
		or fire_rate_scale > 1.0
		or max_integrity_delta > 0.0
		or heal_on_pickup > 0.0
		or dash_charges_delta > 0
		or kill_explosion_radius > 0.0
		or pickup_magnet_radius > 0.0
		or drone_count > 0
		or death_save_charges > 0
		or shield_charges_per_room > 0
		or first_shot_damage_scale > 1.0
		or emits_kill_pulse()
		or retaliates()
		or stillness_fire_rate_scale > 1.0
		or low_integrity_fire_rate_scale > 1.0
		or scrap_interest_fraction > 0.0
		or room_damage_refund > 0.0
		or emits_dash_pulse()
		or dash_cooldown_scale < 1.0
	)


## Whether any of the projectile modifiers make the shot better rather than worse.
##
## "Touches a projectile field" is not the same question, though this used to ask it. Off-By-One's
## whole effect is a projectile modifier and every bit of it is a punishment, so a bare
## `not projectile_add.is_empty()` called it beneficial and quietly broke the boss reward's promise
## that one choice is worth taking. The direction of the change is what matters:
##
## - **set** turns a behaviour on — an explosion, a return arc — so its presence is a gain.
## - **add** accumulates, so a positive amount is a gain and a negative one is a cost.
## - **scale** multiplies, so above one is a gain and below one is a cost.
##
## `PENALTY_KEYS` is the exception the sign test cannot make: a shot fired off-aim is worse at
## 45 degrees and worse still at -45, so the field is a cost at any value.
func _changes_a_projectile_for_the_better() -> bool:
	for key: StringName in projectile_set:
		if key not in PENALTY_KEYS:
			return true
	for key: StringName in projectile_add:
		if key in BENEFIT_KEYS:
			return true
		if key not in PENALTY_KEYS and typeof(projectile_add[key]) != TYPE_FLOAT:
			return true
		if key not in PENALTY_KEYS and float(projectile_add[key]) > 0.0:
			return true
	for key: StringName in projectile_scale:
		if key in BENEFIT_KEYS:
			return true
		if key not in PENALTY_KEYS and float(projectile_scale[key]) > 1.0:
			return true
	return false


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
		and death_save_charges <= 0
		and shield_charges_per_room <= 0
		and not emits_kill_pulse()
		and not retaliates()
		and scrap_interest_fraction <= 0.0
		and room_damage_refund <= 0.0
		# The conditions are the behaviour. A fire-rate item that only pays while the robot is
		# standing still, or down to its last point, is not the same kind of thing as one that
		# always pays — the player has to *do* something to collect it.
		and first_shot_damage_scale <= 1.0
		and stillness_fire_rate_scale <= 1.0
		and low_integrity_fire_rate_scale <= 1.0
		and not emits_dash_pulse()
		and not fire_requires_stillness
		and enemy_health_growth_per_room <= 0.0
	)


## Whether this item turns a dash into a status pulse. Both halves are required: a radius
## with no effects would be an invisible circle, and effects with no radius would be a list
## nothing reads.
func emits_dash_pulse() -> bool:
	return dash_pulse_radius > 0.0 and not dash_pulse_effects.is_empty()


## Whether this item vents a status burst over whatever is standing near a kill. Both halves
## required, for the same reason the dash pulse needs both.
func emits_kill_pulse() -> bool:
	return kill_pulse_radius > 0.0 and not kill_pulse_effects.is_empty()


## Whether being hit costs the attacker something. Both halves again: a blast with no damage is a
## light show, and damage with no radius reaches nothing.
func retaliates() -> bool:
	return retaliation_radius > 0.0 and retaliation_damage > 0.0
