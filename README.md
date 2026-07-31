# Robo Rush

A 2D top-down roguelite shooter built to [`robo_rush_build_spec.md`](robo_rush_build_spec.md).
You play an obsolete maintenance robot scavenging hardware and software upgrades
inside a corrupted software megacorporation.

**Current state: Milestone 2 — Basic Combat.** You can enter a room, shoot Ticket
Bots, take damage, clear the room, die, and restart. There is no procedural
generation, no items, no shop, and no boss yet.

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

Four decisions carry the rest of the project.

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

- **All tuning is in resources.** `PlayerConfig`, `WeaponConfig`, `ProjectileConfig`,
  `EnemyConfig`, `FeedbackConfig`. `FeedbackConfig` is what the milestone 6 settings
  menu will edit, which is why no effect hardcodes its own intensity.
- **`EventBus` is 11 signals and stays that way.** Components emit *local* signals;
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

New in milestone 2 marked `+`.

```
project.godot                             Config, resolution, input map, layers, autoloads
main.tscn / main.gd                       Entry point: places player, fits camera, wires HUDs

autoload/event_bus.gd                     11 cross-system signals
autoload/game_manager.gd                + Feedback config, hit pause, restart
autoload/audio_manager.gd               + Pooled one-shot SFX playback

scripts/resources/player_config.gd        Movement, dash, integrity tunables
scripts/resources/projectile_config.gd  + The composition surface for every item
scripts/resources/weapon_config.gd      + Fire rate, pattern, muzzle
scripts/resources/enemy_config.gd       + Durability, range-keeping, telegraph
scripts/resources/feedback_config.gd    + Shake, flash, damage numbers, hit pause

scripts/combat/damage_info.gd           + One described damage event
scripts/combat/projectile_factory.gd    + Builds projectiles; where modifiers will hook

scripts/components/player_input.gd        Named actions -> movement and directional fire
scripts/components/motion_controller.gd   Acceleration/deceleration
scripts/components/dash_controller.gd     Dash window, charges, invulnerability
scripts/components/player_visuals.gd      Aim, dash squash, flash, muzzle flash, death
scripts/components/weapon_controller.gd + Fire timing and shot arrangement
scripts/components/health_component.gd  + Integrity, invulnerability, death
scripts/components/hurt_flash.gd        + Reusable hit flash
scripts/components/shake_camera.gd      + Trauma-based screen shake

scripts/systems/room_combat.gd          + Counts enemies, reports room cleared
scripts/systems/feedback_director.gd    + All event -> audiovisual mapping
scripts/utilities/teams.gd              + Teams and every collision layer

scenes/player/player.tscn / .gd            The robot
scenes/enemies/ticket_bot.tscn / .gd     + Range-keeping shooter
scenes/projectiles/projectile.tscn / .gd + Fully config-driven projectile
scenes/effects/impact_burst.tscn         + Hit sparks
scenes/effects/death_burst.tscn          + Death debris
scenes/effects/one_shot_burst.gd         + Self-freeing particle burst
scenes/effects/damage_number.tscn / .gd  + Floating damage readout
scenes/rooms/wall_block.tscn / .gd         Resizable solid wall
scenes/rooms/test_room.tscn / .gd          Arena, pillars, enemies, room combat
scenes/ui/combat_hud.tscn / .gd          + Integrity pips, dash pips, banners
scenes/ui/debug_hud.tscn / .gd             Developer diagnostics (F1)

data/player/player_config.tres             Values from spec section 6
data/projectiles/rivet.tres              + Values from spec section 7
data/projectiles/ticket_shot.tres        + Slow, large, hostile
data/weapons/rivet_blaster.tres          + 1 damage, 4/sec, 420 px/s, 1.4s
data/weapons/ticket_spitter.tres         + Enemy weapon
data/enemies/ticket_bot.tres             + Ticket Bot tuning
data/settings/feedback_config.tres       + Feedback intensity

tests/test_runner.tscn / .gd             + Aggregating runner; fails on empty suites
tests/test_case.gd                       + Suite base class
tests/test_player_movement.gd              28 movement and dash checks
tests/test_combat.gd                     + 85 data, component, and integration checks
tests/test_player_input.gd               + 38 arrow-key shooting checks

tools/generate_input_map.gd                Regenerates project.godot's [input]
tools/generate_placeholder_art.py        + Regenerates placeholder PNGs
tools/generate_placeholder_audio.py      + Synthesizes placeholder WAVs
```

---

## What was actually verified

Executed on this machine, not assumed.

- **`godot --headless --import`** completes with no errors.
- **Clean boot** (`--quit-after 300` on `main.tscn`) produces zero errors and zero
  warnings on stdout/stderr.
- **151 checks across 3 suites pass, exit 0**, in 2.9s.
- **The test suite was mutation-tested.** Changing `ProjectileConfig.spawn_copy()` to
  return `self` — the exact bug that would let one shot permanently spend a weapon's
  bounces — made the run exit 1 with 4 named failures. Reverting restored the pass.
  The suite catches the regression it was written for.
- **The runner fails on a suite that runs zero checks**, so a suite that crashes before
  asserting cannot be reported as a pass. This was not hypothetical: an earlier
  `--script`-based harness reported "PASS 45 checks" while three suites silently did
  nothing, because `--script` mode does not register autoloads.
- **Integration checks fire real projectiles through real physics**: pierce carries a
  shot through a near enemy into a far one; a `bounce_count` of 1 sends a shot back past
  its own origin; an enemy-team projectile passed straight through an enemy does zero
  damage; `RoomCombat` reports cleared exactly once.
- **Full combat loop** — 4 Ticket Bots killed, `room_cleared` fired, player integrity
  fell from enemy fire. **Partly human-driven:** the automated harness's aim was not
  good enough to win the fight unaided, so the room clear was completed by hand at the
  keyboard. The synthetic portion verified input handling, damage, and kills; it did not
  verify that the room can be cleared without help.
- **Arrow-key shooting verified live** by recording the heading of every player
  projectile at spawn (filtered by team, since enemy shots share the container): right
  arrow fires right; pressing left while right is *still held* reverses fire on the same
  frame; releasing left resumes the still-held right; releasing every arrow fires
  nothing at all; two perpendicular arrows fire diagonally. Worst angular error across
  every phase was 0.0 degrees.
- **Death and restart**: player died at frame 566 while standing still, HUD banner read
  `SYSTEM FAILURE    PRESS R TO REBOOT`, the robot froze. After
  `GameManager.restart_run()`: integrity 6/6, death flag cleared, 4 enemies respawned,
  and `Engine.time_scale` back to exactly 1.00 — confirming hit pause cannot leave the
  game stuck in slow motion.
- **Presentation asserted, not eyeballed**: live counts of `DamageNumber` and
  `OneShotBurst` nodes under the FeedbackDirector confirmed damage numbers and impact
  bursts spawn during combat. Rendered frames were then inspected to confirm projectile
  trails, hostile/friendly projectile colour separation, the death slump, and both HUD
  banners.

### One bug found and fixed during verification

Enemy dies while its projectile is still in flight → `shooter` dangles → constructing
`DamageInfo` with a freed Object raises a type error and **that hit silently deals no
damage**. Only the live run surfaced it; every unit test passed throughout. Fixed by
attributing damage to the owning actor rather than the weapon component, and reading
the reference through `Projectile.get_shooter()`, which returns null if it has been
freed.

Not verified: how it *feels*. That needs your hands on the keyboard.

---

## Known limitations

1. **Feel and balance are untested by a human.** Standing still, the player loses 3 of
   6 integrity clearing four Ticket Bots in under 4 seconds. Whether that is the right
   pressure is a judgement call for a play session, not a test.
2. **Placeholder art and audio.** Legible and readable, not final. Spec section 20's
   chunky pixel art and CRT glow, and section 22's music, are milestone 6.
3. **No music at all**, and no sounds yet for door opening, item pickup, or boss phase
   transitions — those events do not exist.
4. **The status banner sits just below the player** and can slightly overlap the robot
   sprite. It also sits under the debug overlay's footprint when F1 is on.
5. **The test room is not a room template.** No doors, spawn points, difficulty score,
   or floor tags (spec section 9). Enemies are placed by hand, not spawned. It is built
   from resizable `WallBlock` bodies rather than a TileMap, because a Godot TileMap's
   cell data is a binary blob and cannot be authored as text outside the editor.
6. **`Escape`, `Tab`, and `E` do nothing.** No pause state, no run statistics screen,
   nothing to interact with.
7. **Gamepad is untested** — no controller was available. The right stick has its own
   `aim_stick_*` actions so it keeps analogue precision instead of being quantised to
   the keyboard's eight directions, but nothing on a gamepad has been exercised.
8. **No game state machine, save system, settings menu, or scrap economy.** Spec
   sections 17, 21, 23, and 24 are later milestones.
9. **Enemy variety is one type.** Pop Up Drone, Memory Leech, and Firewall Node are
   milestone 5.
10. **Hand-authored `NodePath` literals do not resolve into exported `Node`
    properties.** Godot only wires those up when the editor writes them, so scenes
    authored as text must pass node references explicitly — `RoomCombat.begin()` takes
    its container as an argument for this reason.

---

## Next recommended task

**Milestone 3: Room Loop.** The goal is a small multi-room run.

1. **A real `TileSet` and room templates.** This needs the Godot editor, since
   `TileMapLayer` cell data is not text-authorable. Define the `RoomTemplate` resource
   from spec section 9 first (id, type, door locations, enemy spawn points, obstacles,
   reward point, difficulty score, floor range) so templates are data from the start.
2. **Doors and locking.** `RoomCombat` already knows when a room is clear; doors
   subscribe to `cleared` and unlock. Add `room_entered` to the EventBus when there is
   a second room to enter.
3. **Enemy spawning from template spawn points**, replacing hand-placed enemies.
   `RoomCombat.track()` already accepts enemies registered after the room starts.
4. **Floor generation** as a connected room graph, with the spec's hard guarantees
   asserted in tests rather than trusted: boss room reachable, no disconnected rooms,
   no overlaps, treasure never blocking progression. This is graph code with exact
   invariants — much cheaper to test than to debug by playing.
5. **Minimap**, with unexplored room types hidden.

Worth doing before milestone 4 regardless: a second enemy type. Ticket Bot alone
cannot show whether `EnemyConfig` is the right shape, and one data point is a weak
basis for the four-enemy roster in milestone 5.

Success condition: the player can complete a small multi-room run.
