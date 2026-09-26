class_name CombatCaps
extends Resource
## Hard ceilings on how much a build can put into one room at once. Roadmap ENG-10.
##
## A safety net, not a balance tool. `DiminishingReturns` is the balance tool, and it is a soft knee
## for a reason its own notes give: a hard ceiling makes every item past it worthless, and the item
## that crossed the line is the one the player blames. That argument holds here too, which is why
## every number below sits well above anything a shipped build reaches. The worst legal build is held
## under every one of them — by `test_economy` for the caps the item data bounds, and by
## `test_combat_caps` firing it in a closed room for the ones it cannot — so a cap that starts
## binding in ordinary play is a failing check rather than a quiet change to how an item feels.
##
## What the caps are for is the multiplication item data cannot bound on its own. Splits used to be
## one generation and a shot's count was fixed by what the player held, so a formula over the pool
## bounded everything. Split depth makes that formula geometric, and copies on a kill, a missed
## shot's retarget and trail hazards depend on what is *in the room*, which no formula over item stats
## can see. These limits are enforced at the point each thing is created, while the game runs.
##
## Status stacks are not here, deliberately. They are capped per effect already, in
## `StatusEffectController.DEFINITIONS`, and nothing an item can hold raises them.
##
## One instance is active at a time: the shipped resource, unless a check has swapped in its own
## through `use` to make a cap small enough to reach.

const SHIPPED_PATH := "res://data/settings/combat_caps.tres"

## Player projectiles alive at once, across the whole floor. A new shot past the limit retires the
## oldest one that does not pierce, or the oldest of all if every shot does. The newest shot always
## appears, because it is the one the player just asked for.
##
## Enemy projectiles are not counted. They are authored, one boss attack at a time, and a limit on
## them would be a limit on a pattern somebody designed.
@export var max_player_projectiles: int = 160

## Generations of splitting one fired shot may go through, whatever `ProjectileConfig.split_depth`
## asks for. One is a parent that splits into children that do not.
@export var max_split_depth: int = 3

## Children one impact may spawn, from splitting or from duplicating on a kill.
@export var max_children_per_impact: int = 8

## Drones orbiting the robot at once, however many drone items are held.
@export var max_drones: int = 4

## Player hazard patches on the floor at once. Past the limit the oldest one goes.
@export var max_player_hazards: int = 32

## Explosions resolved in one physics frame. The excess waits for the next frame rather than being
## dropped: a blast delayed by a sixtieth of a second still lands, and a chain of on-kill blasts
## still clears the pack, it just does it over two frames instead of one.
@export var max_explosions_per_frame: int = 32

static var _active: CombatCaps


## The caps in force: whatever `use` last installed, or the shipped resource.
static func active() -> CombatCaps:
	if _active == null:
		_active = load(SHIPPED_PATH) as CombatCaps
		if _active == null:
			push_error("CombatCaps: '%s' did not load; using the script defaults." % SHIPPED_PATH)
			_active = CombatCaps.new()
	return _active


## Installs `caps` in place of the shipped resource. Null goes back to the shipped one. For checks
## that need a cap small enough to reach in a few frames; nothing in the game calls it.
static func use(caps: CombatCaps) -> void:
	_active = caps
