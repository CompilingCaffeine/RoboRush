# Robo Rush

A 2D top-down roguelite shooter built to [`robo_rush_build_spec.md`](robo_rush_build_spec.md).
You play an obsolete maintenance robot scavenging hardware and software upgrades
inside a corrupted software megacorporation.

**Current state: Milestone 5 — Floor 1.** A complete run exists. A ten-room floor is
generated procedurally with a start, six combat rooms, a treasure vault, a shop, and a
boss arena. You fight through it against four enemy types, spend scrap on items you
cannot all afford, and finish against the Merge Conflict — a boss that splits into two
incompatible versions of itself and heals one when you damage the other, until you stop
shooting it and go break the terminals keeping them in sync. Beating it offers a choice
of three rare items, and the run ends on a statistics screen.

Items compose: a run that finds Ricochet Driver and Fork Bomb fires shots that bounce
off a wall and then split, with no code anywhere aware those two items can be held at
once.

Engine: **Godot 4.7.1**, GDScript, GL Compatibility renderer.

---

## Running it

```bash
godot --path . res://main.tscn
```

Or open the project folder in the Godot editor and press F5.

Run the tests (exits non-zero on failure):

```bash
godot --headless res://tests/test_runner.tscn
```

If assets show as missing after a fresh clone, import them once:

```bash
godot --headless --import
```

To replay one specific floor layout — the seed is shown in the debug overlay (`F1`):

```bash
godot --path . res://main.tscn -- --seed=918273
```

### Controls

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Move | `WASD` | Left stick |
| Aim and fire | Arrow keys | Right stick |
| Dash | `Space` | A / cross |
| Buy / take | `E` | X / square |
| Run statistics | `Tab` (hold) | — |
| Pause | `Escape` | Start |
| Restart | `R` | Y / triangle |
| Active item | Right mouse | Left trigger |
| Toggle debug overlay | `F1` | — |

**There is no fire button.** Holding an arrow key points the cannon and fires it;
release every arrow and the weapon stops. Movement and shooting are fully independent,
so you can run one way while firing the other. Two perpendicular arrows fire
diagonally, and pressing the *opposite* arrow reverses fire on the same frame without
needing the first key released.

This deviates from spec section 5, which maps mouse aim, left-click fire, and a right
trigger. Directional shooting is the scheme *The Binding of Isaac* uses — the game
section 1 names as the inspiration — and section 7's "the player should directly aim and
fire" still holds. Once the direction is the trigger, a separate fire button can only
fire where the player is already firing, so `fire_primary` was removed rather than left
as a dead binding.

`Escape` pauses, `Tab` peeks at the run statistics while held, `E` buys from a shop
stand or takes a boss reward, and `R` restarts. Only the active item remains bound
without behaviour, because there are no active items yet.

---

## Architecture

Seven decisions carry the rest of the project.

**One room is one grid cell, and every room is the same size.** That single choice makes
two of spec section 9's requirements true by construction instead of by checking:
rooms can never overlap, because a cell is claimed exactly once; and the camera can
frame a whole room with no scrolling, which is what makes a bullet-dodging game
readable. [floor_generator.gd](scripts/systems/floor_generator.gd) grows the graph by
attaching each new room to one that already exists, so the floor is a connected graph
the moment it is built — there is no "generate, test, discard" loop. The treasure room
is attached *last*, to a single room, which makes it a dead end; a dead end can never
be a cut vertex, so no route to anywhere can run through it.

**Every projectile behaviour is a field in `ProjectileConfig`, never a branch in
code.** This is the most important type in the game.
[projectile_config.gd](scripts/resources/projectile_config.gd) holds damage, speed,
lifetime, pierce, bounce, split, homing, chaining, explosions — and
[projectile.gd](scenes/projectiles/projectile.gd) contains no weapon-specific or
item-specific conditional anywhere. That single constraint is what makes spec
section 13's synergies free rather than combinatorial, and milestone 4 is where the
bill came due and was paid: Ricochet Driver raises `bounce_count`, Fork Bomb raises
`split_count`, and "bounces once, then splits" works with nothing aware those two
items can co-occur. That exact combination is now a test that fires a real projectile
at a wall and checks it hits an enemy standing *behind the shooter* and then splits.

**An item names the projectile field it changes; it does not own a field of its own.**
[item_config.gd](scripts/resources/item_config.gd) carries three dictionaries —
`projectile_set`, `projectile_add`, `projectile_scale` — keyed by `ProjectileConfig`
property name. The alternative, one typed field per behaviour, means every new
projectile behaviour edits two resources and a stack; this way an item is a `.tres` and
nothing else. The cost is that a mistyped field name silently does nothing, and it is
paid in two places: [projectile_modifier_stack.gd](scripts/combat/projectile_modifier_stack.gd)
refuses keys `ProjectileConfig` does not have and reports them, and the item suite
asserts every key of every shipped item against its real property list.

The stack applies **all sets, then all adds, then all scales, across every item** —
not each item in turn. That makes the result independent of the order items were picked
up in, which is asserted, and it is why two `+1 bounce` items would be two bounces
rather than one.

**A boss has one health pool and several bodies.** Spec section 16 has the Merge Conflict
*duplicating* into two versions of itself, and two copies of one thing share what it has
left. So [merge_conflict.gd](scenes/bosses/merge_conflict.gd) owns the fight and the
things the player shoots at are [boss_part.gd](scenes/bosses/boss_part.gd)s that carry a
`HealthComponent` purely as a *receiver* — it is what makes a projectile register a hit at
all — and forward every hit to the controller. The alternative was teaching projectiles
about bosses, which would put a boss-specific branch in the one file that has never had
one. It also means there is exactly one place the fight can end, which is why it cannot
end twice.

**Actors are composed, not inherited — with one deliberate exception.**
[player.gd](scenes/player/player.gd) and [ticket_bot.gd](scenes/enemies/ticket_bot.gd)
share `HealthComponent` and `WeaponController` unchanged, so damage is symmetric by
construction: a projectile does not care what it hit, only whether that thing has a
`HealthComponent`.

The exception is [enemy.gd](scenes/enemies/enemy.gd), the project's one actor base class,
added in milestone 5 when the roster went from one enemy to four. Spec section 15 asks for
enemies that differ in exactly one thing — *how they create a movement problem* — and
everything else about them is identical: the same collision layers, the same health
wiring, the same knockback model, the same death announcement. Four copies of that
lifecycle is four places for it to drift, and the drift would be invisible until one enemy
quietly stopped emitting `enemy_killed` and its rooms stopped clearing. What is inherited
is only the wiring *between* components, which is the part that has no business differing.
A subclass implements `_act` and nothing else.

Immunity that a component does not own is *registered* with it rather than copied into it.
`HealthComponent.add_immunity_source` takes a `Callable`, and the player hands it
`DashController.is_invulnerable` — so there is exactly one dash window, read by both the
damage path and the flash that tells the player they are safe. The alternative, a second
timer here mirroring the dash's, is how those two came to disagree in the first place.

**Presentation is separated from gameplay.**
[feedback_director.gd](scripts/systems/feedback_director.gd) subscribes to the
EventBus and owns the *entire* mapping from "what happened" to "what the player sees
and hears". No gameplay script plays a sound, spawns a particle, or shakes the
camera. Two things follow: milestone 6's polish pass is a change to one file, and
"do not overuse screen shake" (spec section 7) stays enforceable because every shake
in the game is one of six constants in that file.

**Friendly fire is impossible by construction, not by a runtime check.**
[teams.gd](scripts/utilities/teams.gd) derives every collision layer and mask, and a
projectile's mask contains only the opposing team's bodies. No scene contains a magic
bitmask and no `if target.team == my.team` exists anywhere.

Supporting decisions:

- **The camera is pinned by its own limits.** `Player.frame_room` sets the camera's limit
  rectangle to something exactly viewport-sized, which leaves the camera nowhere to move.
  A fixed frame per room with nothing following anything — and screen shake still works,
  because `Camera2D.offset` is applied after limits rather than clamped by them.
- **Physics changes that happen inside physics callbacks are deferred.** Doors lock from a
  room's entry trigger and loot drops from a damage callback, both while the physics server
  is flushing queries. Godot refuses shape and layer changes there outright, so the door
  would never seal and kills would drop nothing. Both are `set_deferred` /
  `call_deferred`, and both are commented as to why.
- **All tuning is in resources.** `PlayerConfig`, `WeaponConfig`, `ProjectileConfig`,
  `EnemyConfig`, `FeedbackConfig`, `ItemConfig`, `BossConfig`, `ShopConfig`. `FeedbackConfig` is what the milestone 6
  settings menu will edit, which is why no effect hardcodes its own intensity.
- **`EventBus` is 20 signals and stays small.** Components emit *local* signals;
  the owning actor decides what the wider game hears. `WeaponController` therefore has
  no autoload dependency at all, which is why it can be tested in isolation. Milestone 4
  added three, each passing the same test: explosions and chain jumps are damage resolved
  in combat code that must never draw anything, and the item banner is a HUD that must
  never know what an inventory is.
- **Area effects find their targets by scene-tree group, not by shape query.** Homing,
  explosions, and chain lightning all ask "which hostile bodies are near this point", and
  two of the three ask it from inside an `Area2D` callback while the physics server is
  flushing. A group walk is legal from anywhere and, at a handful of enemies per room,
  cheaper than the query it replaces. [targeting.gd](scripts/combat/targeting.gd) is the
  one place that answers it, and it filters on two things that a group membership does not
  imply. The dead: an enemy is freed a frame or two after reaching zero, and a chain that
  jumped into a corpse would waste a jump the player paid for. And the *dormant*: Godot
  pulls a disabled node's collision body out of the physics space, so a projectile cannot
  touch an enemy in a room the player has not entered, and neither may a blast or a chain.
  Testing `can_process()` is what keeps group targeting and physics targeting agreeing by
  construction rather than by coincidence.
- **An item's inventory holds state and nothing else.**
  [item_inventory.gd](scripts/components/item_inventory.gd) never touches a weapon, a
  health component, or a sprite; the player reads its aggregates and pushes them into its
  own components, and recomputes *all* of them on every pickup rather than adjusting for
  the new item. Recomputing is what leaves no path where an effect outlives its item.
- **Items that are not projectile fields hang off events, in one file.**
  [item_effects.gd](scripts/systems/item_effects.gd) turns Volatile Kernel's "enemies
  explode when they die" into a listener on `enemy_killed`. It reads the inventory for
  *which held items detonate*, never a hardcoded id, so a second on-kill item is a `.tres`.
- **Projectiles detect walls by ray query, not by their Area2D.** A ray returns a
  surface *normal*; `body_entered` does not. Bounce direction and impact-spark
  orientation both need it.
- **Fixed 480x270 logical resolution**, `viewport` stretch, `keep` aspect, nearest
  filtering. Every pixel stays square.
- **Input actions are generated**, not hand-written, by
  [generate_input_map.gd](tools/generate_input_map.gd) — `.godot` InputEvent literals
  are how typos get shipped.
- **Rooms are still built from `WallBlock` bodies, not a TileMap.** A Godot
  `TileMapLayer`'s cell data is a binary blob that cannot be authored or reviewed as
  text, so room layouts would stop being diffable. A template's `Array[Rect2i]` of
  obstacles stays readable in a pull request.
- **Placeholder art and audio are generated** by two stdlib-only Python scripts in
  `tools/`. Neither is needed to build or run the game; they exist so placeholders are
  reproducible. Sound is square waves and noise — the two voices a 1990s arcade
  cabinet actually had.

### The four enemies

Spec section 15 asks for four enemies that each pose a different movement problem, so the
roster is checked for being four *problems* rather than four names.

| Enemy | Integrity | Its one behaviour | The problem it poses |
| --- | --- | --- | --- |
| Ticket Bot | 3 | Holds its preferred range and fires single shots | Basic pressure; teaches reading a telegraph |
| Pop Up Drone | 2 | Teleports to a room edge, pauses, fires a three-shot spread | Forces you to find it again and re-aim |
| Memory Leech | 4 | Stops, commits to a direction, charges; hurts on contact | Forces movement — read the tell and step out of it |
| Firewall Node | 6 | Never moves; sweeps rotating beams that stop at walls | Denies space; asks where you are allowed to stand |

The Memory Leech's charge deliberately does not steer, and that is asserted: a homing
charge is the same enemy with none of the interest. The Firewall Node's beams are measured
against the same line that is drawn, so there is no invisible hazard and no decorative
beam.

Which enemies a room may draw is a weighted roster gated on `RoomTemplate.difficulty`,
declared in milestone 3 and unread until now. Uniform selection puts three Firewall Nodes
in the second room of a run as readily as anything else, and a ten-room floor needs a
curve.

### The twelve items

Spec section 12's full pool ships.

| Item | Rarity | What it does | How |
| --- | --- | --- | --- |
| Ricochet Driver | Common | Bounces off walls once | `bounce_count +1` |
| Fork Bomb | Uncommon | Splits into two on impact, 60% damage | `split_count +2` |
| Magnetic Guidance | Uncommon | Curves toward nearby enemies | `homing_strength +3` |
| Return Protocol | Uncommon | Reverses once at the end of its life | `return_enabled` |
| Capacitor Leak | Rare | Every fifth shot chains 3 times for 0.7 | `chain_count +3`, `shot_interval 5` |
| Volatile Kernel | Rare | Enemies explode when they die | `kill_explosion_radius` |
| Cooling Fan | Common | +20% fire rate | `fire_rate_scale` |
| Reinforced Chassis | Common | +2 maximum integrity, repairs 2 | `max_integrity_delta`, `heal_on_pickup` |
| Backup Battery | Common | +1 dash charge | `dash_charges_delta` |
| Unsafe Overclock | Corrupted | +35% damage, +25% fire rate, −2 maximum integrity | all three at once |
| Scrap Magnet | Common | Pulls nearby pickups toward you | `pickup_magnet_radius` |
| Debug Drone | Rare | An orbiting drone fires whenever you do | `drone_count` |

Six of the ten change behaviour rather than numbers, which is the majority spec section 10
asks for and the item suite asserts. Unsafe Overclock deliberately counts as a numbers item
even though it touches a projectile field: a *scale* only multiplies what the weapon already
did, while a set or an add turns something on that was not there. Pure-stat items are the
easy ones to add, and a pool drifts that way on its own if nobody is counting.

Eight of the twelve change behaviour rather than numbers, which is the majority spec
section 10 asks for and the item suite asserts. Unsafe Overclock deliberately counts as a
numbers item even though it touches a projectile field: a *scale* only multiplies what the
weapon already did, while a set or an add turns something on that was not there.

**Debug Drone is where spec section 13's one explicit synergy lives.** The design names
exactly one combination that should need a rule beyond ordinary composition — drone shots
counting toward Capacitor Leak's fifth-shot trigger — and the obvious implementation is a
check asking whether a drone fired the shot, which is precisely the item-specific
conditional section 14 forbids. Instead the player hands its drones the same
[shot_counter.gd](scripts/combat/shot_counter.gd) its own weapon counts into, so the fifth
shot is the fifth shot whichever barrel it left. The suite measures it rather than
asserting it: the chain arrives on the fifth trigger pull alone and on the *third* with a
drone.

### The floor, the shop, and the boss

**A floor is a start room, some combat, and three dead ends.** The generator has always
protected the treasure vault with one argument — a dead end cannot be a cut vertex, so no
route to anywhere can run through it — and milestone 5 applies it twice more. The shop and
the boss arena are attached the same way, so none of the three can block progression, and
all three are asserted that way across 120 seeds. The boss takes the cell furthest from the
start, because the end of a floor should be somewhere the player walked *to*.

**A shop is a room, not a state.** Spec section 23 warns against input leaking between UI
and gameplay states, and the cheapest way to honour that is to have no second state: the
player walks in, the stands advertise their prices permanently, and the interact key they
already had does the rest. The robot goes looking for whatever it is standing next to
rather than stands registering themselves with it, so a stand is a plain object in a group
with an `interact` method.

The boss reward reuses those same stands in an *exclusive* mode — three rare items, free,
and taking one closes the others. The interaction is identical to shopping, so a second
almost-identical pedestal would be a second thing to keep working.

**The boss arena is one room, and that was re-examined rather than assumed.** Milestone 4's
README listed "the boss needs an arena larger than one grid cell" as a limitation. It was
speculation, not a spec requirement: section 16 asks for a *rectangular server room with
four destructible terminals*, and a 26x12-tile room is one. Keeping it to a single cell
preserves the decision the whole project is built on — the camera frames a whole room with
no scrolling — and a single-screen boss is what a bullet-dodging arcade game wants anyway.

### Deliberate non-abstractions

Spec section 14 lists `FirePattern`, `ProjectileModifierStack`, `DamageResolver`, and
`StatusEffectController` as components. `ProjectileModifierStack`
[now exists](scripts/combat/projectile_modifier_stack.gd) and runs exactly where the copy
in `ProjectileFactory.spawn` was left for it. The other three still do not, because each
would have exactly one implementation:

- **FirePattern** — `projectiles_per_shot` + `spread_degrees` on `WeaponConfig` is the
  whole pattern today. It earns its own resource when charge shots and beams arrive.
- **DamageResolver** — [damage_info.gd](scripts/combat/damage_info.gd) is already the
  thing it would resolve, including an unused `is_critical` and a tag list that
  explosions and chain lightning now actually populate (`explosion`, `electric`).
- **StatusEffectController** — `ProjectileConfig.status_effects` is declared and
  carried; nothing reads it yet. It is the last field left in the "declared, not yet
  honoured" group, and no shipped item needs it: freezing and burning are milestone 6's
  polish pass or a second floor's item pool, and building the controller before either
  exists would be building it for one imaginary caller.

`ShotContext` was considered and rejected. `ProjectileFactory.spawn` now takes nine
parameters, four of them optional, and bundling the trailing ones into an object would
read better at the one call site that uses them all — but it would also be a new concept
in a codebase whose whole argument is that concepts are expensive. It earns its place
when charge level and combo multipliers arrive and the list grows again.

### Files

New in milestone 5 marked `+`.

```
project.godot                             Config, resolution, input map, layers, autoloads
main.tscn / main.gd                       Entry point: starts a run, builds the floor, wires HUDs

autoload/event_bus.gd                     20 cross-system signals
autoload/game_manager.gd                  Feedback config, hit pause, game state
autoload/audio_manager.gd                 Pooled one-shot SFX playback
autoload/run_manager.gd                   Run state: scrap, floor, seed, items, statistics

scripts/resources/player_config.gd        Movement, dash, integrity tunables
scripts/resources/projectile_config.gd    The composition surface for every item
scripts/resources/weapon_config.gd        Fire rate, pattern, muzzle
scripts/resources/enemy_config.gd         Durability, range-keeping, contact, telegraph
scripts/resources/pop_up_drone_config.gd  + Teleport interval, arrival pause, placement
scripts/resources/memory_leech_config.gd  + Windup, charge speed, recovery
scripts/resources/firewall_node_config.gd + Beam count, reach, sweep, damage
scripts/resources/enemy_spawn.gd        + One roster entry: what, how often, how early
scripts/resources/boss_config.gd        + The Merge Conflict's phases and attacks
scripts/resources/shop_config.gd        + Spec section 17's prices
scripts/resources/feedback_config.gd      Shake, flash, damage numbers, hit pause
scripts/resources/room_template.gd        One handcrafted room layout, in tiles
scripts/resources/floor_config.gd         A floor's parts list, rosters, rewards, shop
scripts/resources/pickup_config.gd        What a pickup is and what collecting it does
scripts/resources/item_config.gd          One item, entirely as data

scripts/combat/damage_info.gd             One described damage event
scripts/combat/projectile_factory.gd      Builds projectiles; runs the modifier stack
scripts/combat/projectile_modifier_stack.gd Every held item's changes, applied to one shot
scripts/combat/shot_counter.gd          + A shot tally several weapons can share
scripts/combat/targeting.gd               The hostile bodies near a point
scripts/combat/explosion.gd               One blast, damage only
scripts/combat/chain_lightning.gd         Damage that hops between enemies

scripts/components/player_input.gd        Named actions -> movement, fire, dash, interact
scripts/components/motion_controller.gd   Acceleration/deceleration
scripts/components/dash_controller.gd     Dash window, charges, invulnerability
scripts/components/player_visuals.gd      Aim, dash squash, flash, muzzle, item accent
scripts/components/weapon_controller.gd   Fire timing, shot arrangement, item modifiers
scripts/components/health_component.gd    Integrity, invulnerability, immunity sources
scripts/components/item_inventory.gd      What an actor carries, and its aggregates
scripts/components/hurt_flash.gd          Reusable hit flash
scripts/components/shake_camera.gd        Trauma-based screen shake

scripts/systems/room_combat.gd            Counts enemies, reports room cleared
scripts/systems/feedback_director.gd      All event -> audiovisual mapping
scripts/systems/item_effects.gd           Item behaviour that is not a projectile field
scripts/systems/run_stats.gd            + Spec section 25's tracked statistics
scripts/systems/room_plan.gd              One room's place in a floor, pre-instantiation
scripts/systems/floor_layout.gd           The graph: cells, links, connectivity, bounds
scripts/systems/floor_generator.gd        Builds the graph; invariants by construction
scripts/systems/loot_spawner.gd           Enemy drops, room rewards, and item drops
scripts/utilities/teams.gd                Teams, collision layers, and body groups

scenes/player/player.tscn / .gd            The robot
scenes/player/player_drone.tscn / .gd    + Debug Drone's orbiting companion
scenes/enemies/enemy.gd                  + What every enemy has in common
scenes/enemies/ticket_bot.tscn / .gd       Range-keeping shooter
scenes/enemies/pop_up_drone.tscn / .gd   + Teleports, pauses, fires a spread
scenes/enemies/memory_leech.tscn / .gd   + Commits to a charge it will not steer
scenes/enemies/firewall_node.tscn / .gd  + Stationary; sweeps rotating beams
scenes/bosses/merge_conflict.tscn / .gd  + The Floor 1 boss and its three phases
scenes/bosses/boss_part.tscn / .gd       + A shootable body that forwards its hits
scenes/bosses/boss_terminal.tscn / .gd   + A synchronization terminal
scenes/shop/shop_room.tscn / .gd         + A shop's stock, rerolls, and exclusive choices
scenes/shop/shop_stand.tscn / .gd        + One thing for sale
scenes/projectiles/projectile.tscn / .gd   Fully config-driven projectile
scenes/effects/*.tscn                      Impact, death, explosion, chain zap, numbers
scenes/rooms/wall_block.tscn / .gd         Resizable solid wall
scenes/rooms/room.tscn / .gd               A room built from a template
scenes/rooms/door.tscn / .gd               Shared door between two rooms
scenes/floors/floor.tscn / .gd             Instantiates the layout, runs the room loop
scenes/pickups/pickup.tscn / .gd           One scene, behaviour from PickupConfig
scenes/ui/combat_hud.tscn / .gd            Integrity, dash, weapon, scrap, items, boss bar
scenes/ui/run_summary.tscn / .gd         + Game over, victory, pause, and the Tab peek
scenes/ui/minimap.tscn / .gd               Explored floor; unvisited types stay hidden
scenes/ui/debug_hud.tscn / .gd             Developer diagnostics (F1)

data/player, data/projectiles, data/weapons    Player, shot, and weapon tuning
data/enemies/*.tres                        Four enemies, each its own config type
data/spawns/*.tres                       + The floor's weighted enemy roster
data/bosses/merge_conflict.tres          + The boss's phases and attacks
data/rooms/*.tres                          Eight templates (start, combat, treasure, shop, boss)
data/floors/floor_1_help_desk.tres         Floor 1: parts, rosters, rewards, item pool
data/items/*.tres                          Twelve items from spec section 12
data/settings/feedback_config.tres         Feedback intensity
data/settings/shop_config.tres           + Spec section 17's prices

tests/test_runner.tscn / .gd               Aggregating runner; fails on a vanished suite
tests/test_case.gd                         Suite base class
tests/test_player_movement.gd              28 movement and dash checks
tests/test_combat.gd                       101 data, component, and integration checks
tests/test_player_input.gd                 38 arrow-key shooting checks
tests/test_floor.gd                        135 generation, invariant, and template checks
tests/test_items.gd                        172 item, stack, inventory, and synergy checks
tests/test_enemies.gd                    + 57 checks that each enemy poses its problem
tests/test_run.gd                        + 64 statistics, state, and summary checks
tests/test_shop.gd                       + 47 price, purchase, and refusal checks
tests/test_boss.gd                       + 43 phase, terminal, and defeat checks

tools/generate_input_map.gd                Regenerates project.godot's [input]
tools/generate_placeholder_art.py          Regenerates every placeholder PNG
tools/generate_placeholder_audio.py        Synthesizes placeholder WAVs
```

---

## What was actually verified

Executed on this machine, not assumed.

- **`godot --headless --import`** completes with no errors.
- **Clean boot** (`--quit-after 300` on `main.tscn`) produces zero errors and zero
  warnings on stdout/stderr.
- **685 checks across 9 suites pass, exit 0**, in 42s.
- **The floor generator is swept across 120 seeds per run**, asserting every spec section 9
  requirement on each: exactly the requested room count, no disconnected rooms, no two rooms
  in one cell, exactly one of each special room, every door symmetric and between adjacent
  cells, and every room assigned a template. **All three special rooms — treasure, shop, and
  boss — are checked two ways**: that each is a dead end, and that removing it from the graph
  leaves everything else still reachable, which is the actual meaning of "must not block
  progression". The boss room is separately confirmed to be the furthest room from the start
  on every seed.
- **Generation is deterministic**: the same seed reproduces the same floor, different seeds
  produce different floors, and floors branch rather than degenerating into one corridor.
- **Room templates are checked against the door geometry** — no obstacle may straddle a
  doorway corridor, no enemy may spawn inside an obstacle, and the reward point must be
  reachable.
- **Every projectile behaviour is exercised through real physics**, including spec section
  13's worked synergy: Ricochet Driver plus Fork Bomb fired at a wall must hit an enemy
  standing *behind the shooter* (unreachable without the bounce) and leave three projectiles
  in the world (unreachable without the split). Neither item's resource mentions the other.
- **Every modifier key of every shipped item is asserted against `ProjectileConfig`'s real
  property list**, which is what makes string-keyed item data safe to ship.
- **Spec section 12's and section 17's numbers are pinned** — Fork Bomb's 60%, Capacitor
  Leak's 5 shots / 3 jumps / 0.7, common 12 / uncommon 20 / rare 32, heal 6, reroll 4 +2 —
  so an inspector edit cannot silently rebalance the game.
- **Each of the four enemies is checked for posing its own problem**, not for running. The
  Pop Up Drone must actually appear somewhere else, never within the player's guard and
  never inside a wall — verified in a real room against real geometry. The Memory Leech must
  hold still through its windup and must *not* steer once committed, checked by moving the
  target mid-charge. The Firewall Node's beams must sweep, must damage a player standing in
  one, and must never reach a player behind a wall.
- **The boss's phases trip where the spec says**, its synchronisation rule is confirmed to
  cost the player damage until the terminals are down and to stop the moment they are, and
  the fight is confirmed to end exactly once under overkill delivered twice.
- **Spec section 17's "the player should not be able to buy everything" is asserted against
  the floor's own reward numbers**, computed rather than typed in, so rebalancing the drops
  re-runs the argument. It failed when first written, which is how milestone 3's drop rates
  came to be lowered.
- **Five pinned seeds played end to end, start room to victory screen** (`11`, `2027`,
  `5150`, `30313`, `918273`). Every run explored **10/10 rooms**, made shop purchases,
  fought the boss through **all three phases**, took a reward, and finished in the
  **VICTORY** state with 5–6 items and 26–28 kills:

  | Seed | Rooms | Items | Scrap held/collected | Buys | Kills |
  | --- | --- | --- | --- | --- | --- |
  | 11 | 10/10 | 6 | 11 / 43 | 1 | 28 |
  | 2027 | 10/10 | 5 | 29 / 33 | 1 | 27 |
  | 5150 | 10/10 | 6 | 0 / 36 | 2 | 28 |
  | 30313 | 10/10 | 6 | 21 / 37 | 2 | 27 |
  | 918273 | 10/10 | 5 | 37 / 41 | 1 | 26 |

- **Rendered frames inspected** of the shop (four stands showing `COOLING FAN 12`,
  `RICOCHET DRIVER 12`, `REPAIR 6`, `REROLL 4`, amber because affordable), the boss arena
  mid-phase-two (two versions, four corner terminals, sealed door, health bar at ~62%), and
  the run summary. Looking at those frames is how the placement bug below was found.

### Honest limits of that verification

**Nobody has played this by hand.** That is the important one, and it now covers more
ground than it did: whether four enemy types produce interesting rooms together, whether
the Memory Leech's 0.42-second windup is enough warning, whether the boss's phase two is a
puzzle or a wall, and whether the shop's prices bite are all open questions that need a
controller and a person.

**The end-to-end harness proves the loop closes, not that the game is good.** It teleports
the robot between rooms, kills enemies by applying damage to their `HealthComponent`, and
makes the player unkillable. What it measures is that a floor can be walked from the start
room to a victory screen, that the shop takes money and hands over goods, that the boss
reaches all three phases and dies, and that the statistics add up. It measures nothing
about difficulty.

**Spec section 28's success condition for this milestone is "a complete eight to twelve
minute run is playable", and only the first half of that is verified.** The run is
complete and it is playable. Whether it takes eight minutes or three is unknown, because
nothing in the harness moves at human speed.

**The item pool and the economy have had one balance pass between them**, and it was
arithmetic rather than play: the drop rates were lowered until a typical floor could no
longer afford the whole shop. Whether the result is *tense* rather than merely *stingy* is
untested.

**Enemy suites drive a stand-in for the player** — a Node2D in the player group with a
HealthComponent — rather than the real robot, because everything an enemy asks of the
player is "where is it" and "hurt it". Real-robot behaviour is covered by the combat and
input suites instead.

### Bugs found during verification

From milestone 3:

1. **Doors never actually sealed.** `Door.lock()` was called from a room's entry trigger,
   which runs while the physics server is flushing queries; Godot refuses shape and layer
   changes there outright. Now deferred.
2. **Kills dropped nothing.** Same cause — `LootSpawner` added a pickup's Area2D from inside
   a damage callback. Now `add_child.call_deferred`.
3. **A room template blocked its own doorways.** `combat_ring` was one solid 4x4 block dead
   centre — not a ring at all, and squarely across the only straight line between its top and
   bottom doors. Replaced with four blocks around an open cross, and the template test above
   now makes that class of mistake impossible to reship.

From milestone 4, one real failure and three near-misses that milestone 3 had already
paid for:

4. **Typed-array literals silently became untyped, and the first item test run caught it.**
   `[body] if body != null else []` produces a plain `Array`, which GDScript refuses to pass
   to an `Array[Node]` parameter — so every split and every impact explosion aborted with a
   runtime type error and three checks failed. Fixed by building the exclusion list
   explicitly. This is the only milestone-4 bug that was found rather than avoided.
5. **Three hazards were designed around rather than discovered**, because milestone 3 had
   already hit each of them once and written down why. Splitting happens inside an `Area2D`
   callback, so it uses the same deferred `add_child` that doors and loot were forced into.
   A split child spawned overlapping the enemy its parent just struck would register a fresh
   `body_entered` and let Fork Bomb double-dip, so `Projectile.configure` takes an exclusion
   list. An enemy at zero integrity is not freed until the end of the frame, so `Targeting`
   filters on `HealthComponent.is_alive()` rather than tree membership, and chain lightning
   cannot spend a jump on a corpse. None of these cost a debugging session; they are listed
   because "we already know this trap exists" is the return on milestone 3 having documented
   it, and because each is now covered by a test that would catch a regression.

### Three bugs found by review after milestone 4

All three were reported as review findings, reproduced here as failing checks first, then
fixed. Each now has a regression check in the combat suite.

6. **Dash invulnerability was cosmetic.** `PlayerVisuals` flashed the robot from
   `DashController.is_invulnerable()`, but `HealthComponent.apply_damage` consulted only
   its own timer and had no way to hear about immunity it did not own — so a projectile
   took the robot from 6 integrity to 5 while it was mid-dash and visibly flashing. The
   worst shape a bug can have: the game telling the player they are safe while they are
   not. `HealthComponent` now takes registered `Callable` immunity sources and the player
   hands it the dash's own predicate, so there is one window rather than two that agree by
   luck. `Player._is_invulnerable` reads the same call the damage path does.

7. **A spent projectile kept hitting things.** `queue_free` does not take effect until the
   end of the frame, so a zero-pierce rivet that had already been consumed still received
   `body_entered` for every other body it was overlapping. Two Ticket Bots standing on each
   other took a full rivet each from one shot — and with items on, a full set of splits,
   chains, and explosions each. A `_is_spent` flag set in `_despawn` now closes the window;
   `queue_free` was never going to, because the free is the thing that is late.

8. **Area effects reached into rooms the player had never entered.** The finding named
   collision shapes on dormant enemies, but that half does not reproduce: Godot pulls a
   disabled node's body out of the physics space, so a rivet already passes straight
   through. What did reproduce was milestone 4's own group-based targeting, which walks a
   scene-tree group and never consults the physics server at all — a chain lightning
   discharge (76px) or a Volatile Kernel blast near a shared wall damaged enemies across
   it, and enough of them would empty a room the player never walked into, unlock its
   doors, and drop its reward. `Targeting` now skips bodies that cannot process, which is
   the same condition Godot uses to remove them from the space. The regression check covers
   both halves, so neither can drift into the other's blind spot.

### Bugs found during milestone 5

9. **Nodes positioned before `add_child`.** Shop stands, boss bodies, and boss terminals
   were all given a `global_position` while still parentless, which sets a *local* offset —
   so every one of them landed displaced by its room's place on the floor grid, in practice
   outside the room. **Every automated check passed throughout**, because the fixtures built
   their shops and bosses at the origin, where local and global agree. It took a rendered
   frame of a visibly empty shop to see it. Both suites now build an *offset* shop and an
   *offset* arena; reverting the fix with those checks in place fails five of them.
10. **A free item could never be taken.** `RunManager.try_spend_scrap` refuses a zero
    charge — correctly, since spending nothing is not a transaction — and the boss reward
    was gated on it, so the reward was unclaimable and the run could never be won. Found by
    the end-to-end harness, which is exactly the class of bug a unit test does not reach.
11. **Two edits that silently did nothing.** `FloorConfig.templates_for` never gained its
    SHOP and BOSS branches and `FloorController` never gained its shop-stocking call,
    because both patches were written against the wrong indentation and applied to nothing.
    The first meant shop and boss rooms were being built from the *combat* template pool,
    complete with enemy spawns in the shop. Caught by writing the shop suite and by probing
    the built floor's contents, respectively.
12. **Destroyed terminals kept protecting the boss** until `queue_free` landed at the end of
    the frame, refunding damage the player had already earned.
13. **A drone claimed the player's `%Weapon`.** A drone instantiated into the player at
    runtime has no owner of its own, so its unique node name was claimed in the *player's*
    scene scope and taken off the player's own weapon.
14. **A flaky enemy check.** The Firewall Node was allowed to sweep before the wall it was
    meant to be blocked by had entered the physics space, so whether the check passed
    depended on the random angle its beams started at.

The pattern worth naming: **four of these were invisible to the test suite and visible the
moment something actually ran.** The suite is 685 checks and it did not catch a shop whose
stands were in another room. Rendered frames and a harness that plays the game are not
redundant with unit tests; they fail differently.

---

## Known limitations

1. **Nobody has played this by hand.** See above. This is the limitation that matters and
   it now covers difficulty, pacing, the enemy mix, the boss, and the economy.
2. **Placeholder art and audio throughout.** Spec section 20's chunky pixel art and CRT
   glow, and section 22's music, are milestone 6. The Merge Conflict in particular is a
   24x24 placeholder that does not read as a boss so much as a slightly larger enemy.
3. **One floor.** Spec section 8's remaining floors, and the run structure that spans them,
   are beyond milestone 5. Winning means clearing Floor 1, and `RunManager.floor_number`
   has only ever been 1.
4. **No elite modifiers.** Spec section 15 lists six and says not to add them until the
   base enemies feel good, which is a judgement nobody has been in a position to make yet.
5. **No risk-and-reward rooms.** Spec section 19's Challenge Room, Corrupted Terminal,
   Repair Bay, Compiler Shrine, and Debug Room are all explicitly optional for the
   prototype, and none exist. The generator's `_attach_dead_end` is the hook they would use.
6. **`ProjectileConfig.status_effects` is still declared and unread.** No shipped item needs
   it; freezing and burning belong to a second floor's pool.
7. **An item's visible change is one tinted cannon**, showing only the most recently
   collected item that declares an accent. Spec section 20 asks for sprite changes from
   major items, and the honest version of that is per-item art in milestone 6.
8. **Nothing removes an item**, so Corrupted Firmware choices are permanent. Arguably right
   for a roguelite, but undecided rather than designed.
9. **No save system or settings menu.** Spec sections 21 and 24 are milestone 6, which is
   also where `FeedbackConfig` finally gets a UI.
10. **Four of spec section 23's twelve game states exist** — run, paused, game over,
    victory. Boot, main menu, item selection, and the rest have nothing to show yet.
11. **All rooms are the same size**, including the boss arena. Deliberate — see the
    architecture note — but it does mean the boss fight is a single screen.
12. **Rooms are built from `WallBlock` bodies, not a TileMap**, so there is no tile variety
    or autotiling. Deliberate, and it caps how good a room can look until milestone 6.
13. **The HUD strip is not always empty behind it.** The camera frames one room and the
    strip below shows whatever is there — usually black, sometimes the top wall of the room
    below. Legible today by luck rather than design.
14. **Gamepad is untested** — no controller was available.
15. **Physics changes made during physics callbacks must be deferred**, and this project has
    now been bitten by it four times (doors, loot, split projectiles, boss spawning). Every
    site is deferred and commented; the trap is Godot's, but the count is worth recording.
16. **Hand-authored `NodePath` literals do not resolve into exported `Node` properties**, so
    text-authored scenes pass node references explicitly.

---

## Next recommended task

**Milestone 6: Polish.** Spec section 28's last milestone, and the first one whose success
condition is about a person rather than a system: *a new player can understand and enjoy
the game without developer explanation.*

Before any of it, though:

1. **Play the game.** Every milestone since the third has ended with "nobody has played
   this by hand", and the list of open questions that only a controller can answer is now
   longer than the list of features. Is the Memory Leech's windup readable? Is the boss's
   phase two a puzzle or a wall? Does the shop bite? None of these are answerable by adding
   more checks, and several of the numbers in `data/` are placeholders wearing the
   confidence of tested code.
2. **Then balance**, with what playing teaches. The economy, the enemy roster weights, the
   boss's health, and the item drop schedule are all one `.tres` edit each — that is by
   design, and it is the payoff for putting tuning in resources.
3. **Pixel art and audio** (spec sections 20 and 22). The boss most of all: it is the one
   thing in the game that should look like an event.
4. **The settings menu** (spec section 21), which is what `FeedbackConfig` has been shaped
   for since milestone 2 — screen shake, flash intensity, damage numbers, and volume all
   already read from it.
5. **Save data** (spec section 24): settings, unlocks, bosses defeated, and best run
   statistics. `RunStats` is already the shape the last of those wants.

Worth doing whenever, and cheap: **a second floor.** `FloorConfig` was built so that a new
floor is a `.tres` and not new code, and nothing has ever tested that claim. Floor 2 would
be the first evidence either way, and finding out that it needs code is much better news
now than in milestone 6.

Success condition: a new player can understand and enjoy the game without developer
explanation.
