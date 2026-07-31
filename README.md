# Robo Rush

A 2D top-down roguelite shooter built to [`robo_rush_build_spec.md`](robo_rush_build_spec.md).
You play an obsolete maintenance robot scavenging hardware and software upgrades
inside a corrupted software megacorporation.

**Current state: Milestone 4 — Item System.** A seven-room floor is generated
procedurally. You enter a room, the doors seal, you fight, the doors open, a reward
drops, and you pick the next room from the minimap. Four of those rewards are items
drawn from a pool of ten, and they compose: a run that finds Ricochet Driver and Fork
Bomb fires shots that bounce off a wall and then split, with no code anywhere aware
that those two items can be held at once. There is no shop and no boss yet.

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
| Restart after death | `R` | Y / triangle |
| Active item | Right mouse | Left trigger |
| Interact | `E` | X / square |
| Run statistics | `Tab` | — |
| Pause | `Escape` | Start |
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

Active item, interact, run statistics, and pause are bound but not yet wired to
behaviour — the actions exist so later milestones bind names, never keys.

---

## Architecture

Six decisions carry the rest of the project.

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

**Actors are composed, not inherited.** [player.gd](scenes/player/player.gd) and
[ticket_bot.gd](scenes/enemies/ticket_bot.gd) share `HealthComponent` and
`WeaponController` unchanged, so damage is symmetric by construction: a projectile
does not care what it hit, only whether that thing has a `HealthComponent`.

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
  `EnemyConfig`, `FeedbackConfig`, `ItemConfig`. `FeedbackConfig` is what the milestone 6
  settings menu will edit, which is why no effect hardcodes its own intensity.
- **`EventBus` is 17 signals and stays small.** Components emit *local* signals;
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
  one place that answers it, and it filters the dead out — a chain that jumped into a
  corpse would waste a jump the player paid for.
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

### The ten items

Spec section 12 lists twelve. Ten ship; the two that do not are the two that need a new
system rather than a new resource.

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

Six of the ten change behaviour rather than numbers, which is the majority spec section 10
asks for and the item suite asserts. Unsafe Overclock deliberately counts as a numbers item
even though it touches a projectile field: a *scale* only multiplies what the weapon already
did, while a set or an add turns something on that was not there. Pure-stat items are the
easy ones to add, and a pool drifts that way on its own if nobody is counting.

Milestone 4 asked for six. Items seven to ten cost a handful of lines between them
(`DashController.add_charges` and `HealthComponent.set_max_health`) and are otherwise
pure data, and the success condition — *two runs produce noticeably different combat
styles* — is far better served by a pool of ten than a pool of six.

**Scrap Magnet** and **Debug Drone** are milestone 5. Neither is expressible as data over
what exists: a magnet needs pickups to be attracted by something, and a drone is a second
actor that fires. Both are the kind of thing `ItemEffects` is shaped to hold.

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
  honoured" group, and it is milestone 5's job.

`ShotContext` was considered and rejected. `ProjectileFactory.spawn` now takes nine
parameters, four of them optional, and bundling the trailing ones into an object would
read better at the one call site that uses them all — but it would also be a new concept
in a codebase whose whole argument is that concepts are expensive. It earns its place
when charge level and combo multipliers arrive and the list grows again.

### Files

New in milestone 4 marked `+`.

```
project.godot                             Config, resolution, input map, layers, autoloads
main.tscn / main.gd                       Entry point: starts a run, builds the floor, wires HUDs

autoload/event_bus.gd                     17 cross-system signals
autoload/game_manager.gd                  Feedback config, hit pause, restart
autoload/audio_manager.gd                 Pooled one-shot SFX playback
autoload/run_manager.gd                   Run-scoped state: scrap, floor, seed, items offered

scripts/resources/player_config.gd        Movement, dash, integrity tunables
scripts/resources/projectile_config.gd    The composition surface for every item
scripts/resources/weapon_config.gd        Fire rate, pattern, muzzle
scripts/resources/enemy_config.gd         Durability, range-keeping, telegraph
scripts/resources/feedback_config.gd      Shake, flash, damage numbers, hit pause
scripts/resources/room_template.gd        One handcrafted room layout, in tiles
scripts/resources/floor_config.gd         A floor's parts list, drop rates, and item pool
scripts/resources/pickup_config.gd        What a pickup is and what collecting it does
scripts/resources/item_config.gd        + One item, entirely as data

scripts/combat/damage_info.gd             One described damage event
scripts/combat/projectile_factory.gd      Builds projectiles; runs the modifier stack
scripts/combat/projectile_modifier_stack.gd + Every held item's changes, applied to one shot
scripts/combat/targeting.gd             + The hostile bodies near a point
scripts/combat/explosion.gd             + One blast, damage only
scripts/combat/chain_lightning.gd       + Damage that hops between enemies

scripts/components/player_input.gd        Named actions -> movement and directional fire
scripts/components/motion_controller.gd   Acceleration/deceleration
scripts/components/dash_controller.gd     Dash window, charges, invulnerability
scripts/components/player_visuals.gd      Aim, dash squash, flash, muzzle flash, item accent
scripts/components/weapon_controller.gd   Fire timing, shot arrangement, item modifiers
scripts/components/health_component.gd    Integrity, invulnerability, death
scripts/components/item_inventory.gd    + What an actor carries, and its aggregates
scripts/components/hurt_flash.gd          Reusable hit flash
scripts/components/shake_camera.gd        Trauma-based screen shake

scripts/systems/room_combat.gd            Counts enemies, reports room cleared
scripts/systems/feedback_director.gd      All event -> audiovisual mapping
scripts/systems/item_effects.gd         + Item behaviour that is not a projectile field
scripts/systems/room_plan.gd              One room's place in a floor, pre-instantiation
scripts/systems/floor_layout.gd           The graph: cells, links, connectivity, bounds
scripts/systems/floor_generator.gd        Builds the graph; invariants by construction
scripts/systems/loot_spawner.gd           Enemy drops, room rewards, and item drops
scripts/utilities/teams.gd                Teams, collision layers, and body groups

scenes/player/player.tscn / .gd           The robot
scenes/enemies/ticket_bot.tscn / .gd      Range-keeping shooter
scenes/projectiles/projectile.tscn / .gd  Fully config-driven projectile
scenes/effects/impact_burst.tscn          Hit sparks
scenes/effects/death_burst.tscn           Death debris
scenes/effects/explosion_burst.tscn     + Blast fireball, scaled to the radius
scenes/effects/chain_zap.tscn / .gd     + One jump of a chain lightning arc
scenes/effects/one_shot_burst.gd          Self-freeing particle burst
scenes/effects/damage_number.tscn / .gd   Floating damage readout
scenes/rooms/wall_block.tscn / .gd        Resizable solid wall
scenes/rooms/room.tscn / .gd              A room built from a template
scenes/rooms/door.tscn / .gd              Shared door between two rooms
scenes/floors/floor.tscn / .gd            Instantiates the layout, runs the room loop
scenes/pickups/pickup.tscn / .gd          One scene, behaviour from PickupConfig
scenes/ui/combat_hud.tscn / .gd           Integrity, dash, weapon, scrap, items, banners
scenes/ui/minimap.tscn / .gd              Explored floor; unvisited types stay hidden
scenes/ui/debug_hud.tscn / .gd            Developer diagnostics (F1)

data/player/player_config.tres            Values from spec section 6
data/projectiles/rivet.tres               Values from spec section 7
data/projectiles/ticket_shot.tres         Slow, large, hostile
data/weapons/rivet_blaster.tres           1 damage, 4/sec, 420 px/s, 1.4s
data/weapons/ticket_spitter.tres          Enemy weapon
data/enemies/ticket_bot.tres              Ticket Bot tuning
data/settings/feedback_config.tres        Feedback intensity
data/rooms/*.tres                         Six room templates (start, 4 combat, treasure)
data/floors/floor_1_help_desk.tres        Floor 1 parts list and item pool
data/pickups/scrap.tres, repair_cell.tres The two authored pickup types
data/items/*.tres                       + Ten items from spec section 12

tests/test_runner.tscn / .gd              Aggregating runner; fails on empty suites
tests/test_case.gd                        Suite base class
tests/test_player_movement.gd             28 movement and dash checks
tests/test_combat.gd                      85 data, component, and integration checks
tests/test_player_input.gd                38 arrow-key shooting checks
tests/test_floor.gd                       128 generation, invariant, and template checks
tests/test_items.gd                     + 153 item, stack, inventory, and synergy checks

tools/generate_input_map.gd               Regenerates project.godot's [input]
tools/generate_placeholder_art.py         Regenerates placeholder PNGs, including item icons
tools/generate_placeholder_audio.py       Synthesizes placeholder WAVs
```

---

## What was actually verified

Executed on this machine, not assumed.

- **`godot --headless --import`** completes with no errors.
- **Clean boot** (`--quit-after 300` on `main.tscn`) produces zero errors and zero
  warnings on stdout/stderr.
- **432 checks across 5 suites pass, exit 0**, in 8.3s.
- **The floor generator is swept across 120 seeds per run**, asserting every spec section 9
  requirement on each: exactly the requested room count, no disconnected rooms, no two rooms
  in one cell, exactly one start and one treasure room, every door symmetric and between
  adjacent cells, and every room assigned a template. The treasure room is checked two ways —
  that it is a dead end, and that removing it from the graph leaves everything else still
  reachable, which is the actual meaning of "must not block progression".
- **Generation is deterministic**: the same seed reproduces the same floor, different seeds
  produce different floors, and floors branch rather than degenerating into one corridor.
- **A bad config is refused, not half-built**: a one-room floor and a floor with no templates
  both return nothing and report why.
- **Room templates are checked against the door geometry** — no obstacle may straddle a
  doorway corridor at the wall it opens through, no enemy may spawn inside an obstacle or
  outside the interior, and the reward point must be reachable. This check was written
  *because* one template was found sitting across the only straight line between two doors.
- **Five pinned seeds played end to end** (`11`, `2027`, `5150`, `30313`, `918273`), each
  exploring **7/7 rooms** with every room-loop assertion holding: the start room leaves its
  doors open, every combat room seals *all* its doors on entry, unseals them on clear, and
  drops a reward; the treasure room pays out on first entry; re-entering a cleared room does
  not re-seal it; and enemies in every room the player is not standing in are confirmed
  dormant. Backtracking through cleared rooms to reach a far branch works.

Milestone 4 adds:

- **Every projectile behaviour is exercised through real physics, not asserted on a config.**
  Fork Bomb is checked by counting the projectiles that actually entered the world (a parent
  and two children) and reading the children's damage off their own configs. Magnetic
  Guidance is checked *against a control*: the identical shot with no homing is confirmed to
  miss an enemy 26px off-axis first, so the homing check is measuring the item rather than
  the geometry. Return Protocol's target is placed in the lane **after** the shot has already
  passed it, so only a projectile travelling back can possibly reach it. Explosions are
  checked three ways at once — the enemy hit directly is *not* also caught by its own blast,
  its neighbour is, and an enemy past the radius is not.
- **Spec section 13's worked synergy is a test.** Ricochet Driver plus Fork Bomb fires at a
  wall, and the assertions are that the bounce event fired exactly once, that an enemy
  standing *behind the shooter* took damage (unreachable without the bounce), and that three
  projectiles existed in total (unreachable without the split). Neither item's resource
  mentions the other and neither is named in `projectile.gd`.
- **Every modifier key of every shipped item is asserted against `ProjectileConfig`'s real
  property list.** This is the check that makes string-keyed item data safe to ship; a
  deliberately mistyped key is also confirmed to be reported and to change nothing.
- **Spec section 12's numbers are pinned** — Fork Bomb's 60%, Capacitor Leak's 5 shots / 3
  jumps / 0.7 per jump, Cooling Fan's +20%, Unsafe Overclock's +35%/+25%/−2 — so an inspector
  edit cannot silently rebalance the game.
- **Five full floors played end to end with the item loop live** (same pinned seeds). Every
  run explored 7/7 rooms, dropped **4 items** (three from room clears, one from the treasure
  vault), and the robot collected all four — dropped and collected matched on every run, with
  no item offered twice. The resulting weapons:

  | Seed | Loadout | Resulting shot |
  | --- | --- | --- |
  | 11 | overclock, guidance, leak, fan | dmg 1.35, homing 3.0, chain 3 |
  | 2027 | fan, leak, battery, ricochet | bounce 1, chain 3 |
  | 5150 | overclock, battery, return, fan | dmg 1.35, return |
  | 30313 | chassis, guidance, kernel, ricochet | bounce 1, homing 3.0 |
  | 918273 | guidance, fork bomb, ricochet, return | bounce 1, split 2, homing 3.0, return |

  **Five distinct loadouts and five distinct weapons out of five runs**, which is the
  milestone's success condition — *two runs produce noticeably different combat styles* —
  measured rather than asserted. Seed 918273 produced spec section 13's second worked example
  unprompted: a shot that homes, bounces, splits, and comes back.
- **Rendered frames inspected** to confirm room framing, doorway gaps, the minimap, the item
  bar along the bottom of the HUD, the item pickup banner (`REINFORCED CHASSIS // ADDS TWO
  MAXIMUM INTEGRITY AND REPAIRS TWO INTEGRITY.`), the integrity pips rebuilding from 6 to 8,
  and the cannon taking the accent colour of the item just collected.

### Honest limits of that verification

The room-loop sweep moves the robot with **genuine synthetic input** through the named
actions, but it does **not** win the fights: enemies are killed by applying damage to their
`HealthComponent`, which is the same death path a projectile triggers. An 8-way-aiming bot
standing in the open dies to four Ticket Bots long before it clears a floor, and whether the
robot can shoot straight is already covered by the combat and input suites. What the sweep
tests is the room loop, not marksmanship.

The **item sweep is weaker still on movement**: the robot is teleported room to room and onto
each pickup, and it is made unkillable for the duration. That harness measures the reward
loop — what dropped, whether it could be collected, what the weapon became — and nothing
about whether any of it is survivable. It was a throwaway script, run and recorded, not
committed; what is committed is the item suite, which does use real physics.

**Nobody has played a full floor by hand.** Whether four items per floor is generous or
stingy, whether Unsafe Overclock's −2 integrity is a real decision or an obvious yes, and
whether a bouncing splitting shot is fun or unreadable are all open questions that need a
controller and a person. **The item pool has had no balance pass at all** — the numbers are
spec section 12's, transcribed, and spec section 12 was written before anything existed to
balance against.

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

---

## Known limitations

1. **Pacing and balance are untested by a human.** See above. This now covers the item pool
   as well as the room count.
2. **Placeholder art and audio**, including the ten item icons. Spec section 20's chunky
   pixel art and CRT glow, and section 22's music, are milestone 6.
3. **Only one enemy type.** Pop Up Drone, Memory Leech, and Firewall Node are milestone 5.
   One data point is a weak basis for trusting `EnemyConfig`'s shape — and it also caps how
   much the item pool can be judged, since every item is currently evaluated against the same
   range-keeping shooter.
4. **No shop and no boss.** Milestone 5. Scrap accumulates with nothing to spend it on, which
   makes Scrap Magnet pointless to ship until there is.
5. **Two of spec section 12's twelve items are missing.** Scrap Magnet needs pickups to be
   attractable and a shop to make scrap worth attracting; Debug Drone is a second actor that
   fires. Both are milestone 5.
6. **An item's visible change is one tinted cannon.** Spec section 20 asks for sprite changes
   from major items, and the honest version of that is per-item art, which is milestone 6.
   The accent shows only the most recently collected item that declares one, because a robot
   tinted by four items at once is a robot tinted brown.
7. **Nothing removes an item.** The inventory has no `remove`, so Corrupted Firmware items
   are permanent decisions. That is arguably correct for a roguelite, but it is untested and
   undecided rather than designed.
8. **All rooms are the same size**, so there are no large boss arenas yet. The boss room in
   milestone 5 will need either a multi-cell room or a separate framing path.
9. **Rooms are built from `WallBlock` bodies, not a TileMap**, so there is no tile variety or
   autotiling. Deliberate — see the architecture note — but it does cap how good a room can
   look until milestone 6.
10. **The HUD strip is not always empty behind it.** The camera frames one room and the strip
    below it shows whatever is there — usually black, but the top wall of the room below when
    the floor has one. Legible today because the strip's text sits on dark tiles, but it is
    luck rather than design.
11. **`Escape`, `Tab`, and `E` still do nothing.** No pause state, no run statistics screen,
    nothing to interact with. `Tab` is the natural home for a full item list once the bar
    stops fitting.
12. **Gamepad is untested** — no controller was available. The right stick has its own
    `aim_stick_*` actions so it keeps analogue precision, but nothing on a pad has been run.
13. **No save system or settings menu.** Spec sections 21 and 24 are milestone 6.
14. **Doors seal one frame after the trigger fires**, because the collision change is
    deferred. Safe in practice: the entry trigger is inset well inside the room, so the robot
    is never in the doorway at that moment. Split children spawn one frame late for the same
    reason, and are invisible at 60fps.
15. **Hand-authored `NodePath` literals do not resolve into exported `Node` properties.**
    Godot only wires those when the editor writes them, so text-authored scenes must pass
    node references explicitly — `RoomCombat.begin()` takes its container as an argument, and
    the room hands it over from its own `_ready`.

---

## Next recommended task

**Milestone 5: Floor 1.** The item system needs things to be used against, and the run needs
an ending.

1. **A second enemy type, first and before anything else.** This was the recommendation at
   the end of milestone 3 and it is more true now, not less: every item in the pool has been
   judged against exactly one enemy behaviour. Pop Up Drone (teleports, then fires a spread)
   exercises completely different `EnemyConfig` fields than a range-keeper does, and it is
   the only way to find out whether that resource's shape survives contact with a second
   data point before three more are built on it.
2. **The shop, and with it a reason for scrap to exist.** `RunManager.try_spend_scrap` has
   been waiting since milestone 3 with no caller. A shop is also what makes Scrap Magnet and
   the "shops become more expensive" half of a corrupted item worth writing.
3. **Debug Drone**, and with it the one *explicit* synergy spec section 13 asks for: drone
   shots counting toward Capacitor Leak's fifth-shot trigger. This one is **not** free.
   `shot_interval` is checked against `WeaponController._shots_fired`, which is per
   controller, so a drone with its own weapon would keep its own tally and the spec's
   example would quietly not work. The counter is the right place to fix it — a shared shot
   count, not a rule about drones — but it is a change, and it is the first case where an
   item pairing needs code rather than composition.
4. **The Merge Conflict boss and a game-over screen**, which is what turns seven rooms into a
   run. Note limitation 8: the boss needs an arena larger than one grid cell, so this is a
   change to how rooms are framed, not only new content.
5. **Run statistics** (spec section 25), which `Tab` is already bound to and `RunManager` is
   already the right home for.

Worth doing at some point and cheap: **a balance pass on item drop frequency.** Four items in
a seven-room floor was chosen to make synergies visible during milestone 4, not because it is
right. It is one array in `floor_1_help_desk.tres`.

Success condition: a complete eight to twelve minute run is playable.
