# Robo Rush

A 2D top-down roguelite shooter built to [`robo_rush_build_spec.md`](robo_rush_build_spec.md).
You play an obsolete maintenance robot scavenging hardware and software upgrades
inside a corrupted software megacorporation.

**Current state: Milestone 3 — Room Loop.** A seven-room floor is generated
procedurally. You enter a room, the doors seal, you fight, the doors open, a reward
drops, and you pick the next room from the minimap. There are no items, no shop, and
no boss yet.

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

Five decisions carry the rest of the project.

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
section 13's synergies free rather than combinatorial: Ricochet Driver will raise
`bounce_count`, Fork Bomb will raise `split_count`, and "bounces once, then splits"
already works with nothing aware those two items can co-occur. The verified bounce
and pierce tests exercise exactly that path today.

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
in the game is one of five constants in that file.

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
  `EnemyConfig`, `FeedbackConfig`. `FeedbackConfig` is what the milestone 6 settings
  menu will edit, which is why no effect hardcodes its own intensity.
- **`EventBus` is 14 signals and stays small.** Components emit *local* signals;
  the owning actor decides what the wider game hears. `WeaponController` therefore has
  no autoload dependency at all, which is why it can be tested in isolation.
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

### Deliberate non-abstractions

Spec section 14 lists `FirePattern`, `ProjectileModifierStack`, `DamageResolver`, and
`StatusEffectController` as components. None exist yet, because each would currently
have exactly one implementation:

- **FirePattern** — `projectiles_per_shot` + `spread_degrees` on `WeaponConfig` is the
  whole pattern today. It earns its own resource when charge shots and beams arrive.
- **ProjectileModifierStack** — will run over the config copy inside
  `ProjectileFactory.spawn`, between `spawn_copy()` and instantiation. That copy exists
  now precisely so the stack has somewhere to go.
- **DamageResolver** — [damage_info.gd](scripts/combat/damage_info.gd) is already the
  thing it would resolve, including an unused `is_critical` and a tag list.
- **StatusEffectController** — `ProjectileConfig.status_effects` is declared and
  carried; nothing reads it yet.

Fields marked "not yet honoured" in `ProjectileConfig` are declared on purpose: the
*shape* of that resource is the contract milestone 4 composes over, and adding a field
later is a smaller change than adding a behaviour later.

### Files

New in milestone 3 marked `+`.

```
project.godot                             Config, resolution, input map, layers, autoloads
main.tscn / main.gd                       Entry point: starts a run, builds the floor, wires HUDs

autoload/event_bus.gd                     14 cross-system signals
autoload/game_manager.gd                  Feedback config, hit pause, restart
autoload/audio_manager.gd                 Pooled one-shot SFX playback
autoload/run_manager.gd                 + Run-scoped state: scrap, floor, progress, seed

scripts/resources/player_config.gd        Movement, dash, integrity tunables
scripts/resources/projectile_config.gd    The composition surface for every item
scripts/resources/weapon_config.gd        Fire rate, pattern, muzzle
scripts/resources/enemy_config.gd         Durability, range-keeping, telegraph
scripts/resources/feedback_config.gd      Shake, flash, damage numbers, hit pause
scripts/resources/room_template.gd      + One handcrafted room layout, in tiles
scripts/resources/floor_config.gd       + A floor's parts list and drop rates
scripts/resources/pickup_config.gd      + What a pickup is and what collecting it does

scripts/combat/damage_info.gd             One described damage event
scripts/combat/projectile_factory.gd      Builds projectiles; where modifiers will hook

scripts/components/player_input.gd        Named actions -> movement and directional fire
scripts/components/motion_controller.gd   Acceleration/deceleration
scripts/components/dash_controller.gd     Dash window, charges, invulnerability
scripts/components/player_visuals.gd      Aim, dash squash, flash, muzzle flash, death
scripts/components/weapon_controller.gd   Fire timing and shot arrangement
scripts/components/health_component.gd    Integrity, invulnerability, death
scripts/components/hurt_flash.gd          Reusable hit flash
scripts/components/shake_camera.gd        Trauma-based screen shake

scripts/systems/room_combat.gd            Counts enemies, reports room cleared
scripts/systems/feedback_director.gd      All event -> audiovisual mapping
scripts/systems/room_plan.gd            + One room's place in a floor, pre-instantiation
scripts/systems/floor_layout.gd         + The graph: cells, links, connectivity, bounds
scripts/systems/floor_generator.gd      + Builds the graph; invariants by construction
scripts/systems/loot_spawner.gd         + Enemy drops and room-clear rewards
scripts/utilities/teams.gd                Teams and every collision layer

scenes/player/player.tscn / .gd            The robot
scenes/enemies/ticket_bot.tscn / .gd     + Range-keeping shooter
scenes/projectiles/projectile.tscn / .gd + Fully config-driven projectile
scenes/effects/impact_burst.tscn           Hit sparks
scenes/effects/death_burst.tscn            Death debris
scenes/effects/one_shot_burst.gd           Self-freeing particle burst
scenes/effects/damage_number.tscn / .gd  + Floating damage readout
scenes/rooms/wall_block.tscn / .gd         Resizable solid wall
scenes/rooms/room.tscn / .gd             + A room built from a template
scenes/rooms/door.tscn / .gd             + Shared door between two rooms
scenes/floors/floor.tscn / .gd           + Instantiates the layout, runs the room loop
scenes/pickups/pickup.tscn / .gd         + One scene, behaviour from PickupConfig
scenes/ui/combat_hud.tscn / .gd           Integrity, dash, weapon, scrap, banners
scenes/ui/minimap.tscn / .gd             + Explored floor; unvisited types stay hidden
scenes/ui/debug_hud.tscn / .gd             Developer diagnostics (F1)

data/player/player_config.tres             Values from spec section 6
data/projectiles/rivet.tres                Values from spec section 7
data/projectiles/ticket_shot.tres          Slow, large, hostile
data/weapons/rivet_blaster.tres            1 damage, 4/sec, 420 px/s, 1.4s
data/weapons/ticket_spitter.tres           Enemy weapon
data/enemies/ticket_bot.tres               Ticket Bot tuning
data/settings/feedback_config.tres         Feedback intensity
data/rooms/*.tres                        + Six room templates (start, 4 combat, treasure)
data/floors/floor_1_help_desk.tres       + Floor 1 parts list
data/pickups/scrap.tres, repair_cell.tres + The two milestone-3 pickup types

tests/test_runner.tscn / .gd             + Aggregating runner; fails on empty suites
tests/test_case.gd                         Suite base class
tests/test_player_movement.gd              28 movement and dash checks
tests/test_combat.gd                       85 data, component, and integration checks
tests/test_player_input.gd                 38 arrow-key shooting checks
tests/test_floor.gd                      + 128 generation, invariant, and template checks
tests/test_player_input.gd                 38 arrow-key shooting checks

tools/generate_input_map.gd                Regenerates project.godot's [input]
tools/generate_placeholder_art.py          Regenerates placeholder PNGs
tools/generate_placeholder_audio.py        Synthesizes placeholder WAVs
```

---

## What was actually verified

Executed on this machine, not assumed.

- **`godot --headless --import`** completes with no errors.
- **Clean boot** (`--quit-after 300` on `main.tscn`) produces zero errors and zero
  warnings on stdout/stderr.
- **279 checks across 4 suites pass, exit 0**, in 3.0s.
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
- **Rendered frames inspected** to confirm room framing, doorway gaps, the minimap, and that
  the HUD does not cover playable floor.

### Honest limits of that verification

The room-loop sweep moves the robot with **genuine synthetic input** through the named
actions, but it does **not** win the fights: enemies are killed by applying damage to their
`HealthComponent`, which is the same death path a projectile triggers. An 8-way-aiming bot
standing in the open dies to four Ticket Bots long before it clears a floor, and whether the
robot can shoot straight is already covered by the combat and input suites. What the sweep
tests is the room loop, not marksmanship.

**Nobody has played a full floor by hand.** Whether a seven-room run is paced well, whether
five combat rooms is too many or too few, and whether the reward trickle feels worth the
detour to the treasure room are all open questions that need a controller and a person.

### Three bugs found during verification

1. **Doors never actually sealed.** `Door.lock()` was called from a room's entry trigger,
   which runs while the physics server is flushing queries; Godot refuses shape and layer
   changes there outright. Now deferred.
2. **Kills dropped nothing.** Same cause — `LootSpawner` added a pickup's Area2D from inside
   a damage callback. Now `add_child.call_deferred`.
3. **A room template blocked its own doorways.** `combat_ring` was one solid 4x4 block dead
   centre — not a ring at all, and squarely across the only straight line between its top and
   bottom doors. Replaced with four blocks around an open cross, and the template test above
   now makes that class of mistake impossible to reship.

---

## Known limitations

1. **Pacing and balance are untested by a human.** See above.
2. **Placeholder art and audio.** Spec section 20's chunky pixel art and CRT glow, and
   section 22's music, are milestone 6.
3. **Only one enemy type.** Pop Up Drone, Memory Leech, and Firewall Node are milestone 5.
   One data point is a weak basis for trusting `EnemyConfig`'s shape.
4. **No items, shop, or boss.** Milestones 4 and 5. A treasure room currently pays out a
   repair cell and scrap, standing in for the item it will eventually hold.
5. **All rooms are the same size**, so there are no large boss arenas yet. The boss room in
   milestone 5 will need either a multi-cell room or a separate framing path.
6. **Rooms are built from `WallBlock` bodies, not a TileMap**, so there is no tile variety or
   autotiling. Deliberate — see the architecture note — but it does cap how good a room can
   look until milestone 6.
7. **`Escape`, `Tab`, and `E` still do nothing.** No pause state, no run statistics screen,
   nothing to interact with.
8. **Gamepad is untested** — no controller was available. The right stick has its own
   `aim_stick_*` actions so it keeps analogue precision, but nothing on a pad has been run.
9. **No save system or settings menu.** Spec sections 21 and 24 are milestone 6.
10. **Doors seal one frame after the trigger fires**, because the collision change is
    deferred. Safe in practice: the entry trigger is inset well inside the room, so the robot
    is never in the doorway at that moment.
11. **Hand-authored `NodePath` literals do not resolve into exported `Node` properties.**
    Godot only wires those when the editor writes them, so text-authored scenes must pass
    node references explicitly — `RoomCombat.begin()` takes its container as an argument, and
    the room hands it over from its own `_ready`.

---

## Next recommended task

**Milestone 4: Item System.** The whole point of the projectile data model is about to be
cashed in.

1. **`ItemConfig` and `ProjectileModifierStack`.** An item is data: stat modifiers, tags, and
   which `ProjectileConfig` fields it adjusts. The stack runs inside
   `ProjectileFactory.spawn`, between `spawn_copy()` and instantiation — that copy exists now
   precisely so the stack has somewhere to go. If an item ever needs a branch in
   `projectile.gd`, the design has gone wrong.
2. **Wire up the fields already declared but unread**: `split_count`, `homing_strength`,
   `explosion_radius`, `chain_count`, `return_enabled`. Each is one item from spec section 12
   and each should be implemented in `projectile.gd` once, generically.
3. **Item pickup and inventory**, reusing the `Pickup` scene — a third `PickupConfig.Kind`,
   not a new scene. The treasure room already has a reward point waiting for it.
4. **Six items first, not twelve**, and verify the *combinations*: Ricochet Driver plus Fork
   Bomb must produce "bounces, then splits" with no code aware those two can co-occur. That
   is the success condition worth testing, and it is testable headlessly the same way pierce
   and bounce already are.
5. **Player sprite changes for major items** (spec section 20) where practical.

Worth doing first, and cheap: **a second enemy type.** Ticket Bot alone cannot show whether
`EnemyConfig` is the right shape, and the four-enemy roster in milestone 5 will be built on
whatever shape it has by then. Pop Up Drone (teleports, then fires a spread) exercises
completely different fields than a range-keeper does.

Success condition: two runs produce noticeably different combat styles.
