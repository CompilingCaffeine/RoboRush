# Robo Rush

A 2D top-down roguelite shooter built to [`robo_rush_build_spec.md`](robo_rush_build_spec.md).
You play an obsolete maintenance robot scavenging hardware and software upgrades
inside a corrupted software megacorporation.

**Current state: Milestone 1 — Movement Sandbox.** Per spec section 32, this
milestone deliberately contains no enemies, items, procedural generation, menus,
or bosses. It exists to make movement feel good before anything is built on it.

Engine: **Godot 4.7.1**, GDScript, GL Compatibility renderer.

---

## Running it

```bash
godot --path . res://main.tscn
```

Or open the project folder in the Godot editor and press F5.

Run the headless movement tests (exits non-zero on failure):

```bash
godot --headless --script res://tests/test_player_movement.gd
```

If textures show as missing after a fresh clone, import them once:

```bash
godot --headless --import
```

### Controls

| Action | Keyboard / Mouse | Gamepad |
| --- | --- | --- |
| Move | `WASD` | Left stick |
| Aim | Mouse | Right stick |
| Dash | `Space` | A / cross |
| Fire primary | Left mouse | Right trigger |
| Active item | Right mouse | Left trigger |
| Interact | `E` | X / square |
| Run statistics | `Tab` | — |
| Pause | `Escape` | Start |
| Toggle debug overlay | `F1` | — |

Fire, active item, interact, run statistics, and pause are bound but not yet
wired to behaviour — the actions exist so later milestones bind names, never keys.

---

## Architecture

The shape of the code matters more than its size at this stage, so the two rules
below are worth keeping as the project grows.

**The player is composed, not inherited.** `Player` (`scenes/player/player.gd`)
does almost nothing itself. Each frame it asks `PlayerInput` for intent, asks
either `MotionController` or `DashController` for a velocity, calls
`move_and_slide()`, and hands presentation state to `PlayerVisuals`. Weapons,
integrity, and item hooks become additional components rather than additions to
this script, which is how spec section 26.5 ("avoid giant manager scripts") is
kept true by construction.

**Gameplay maths is separated from the engine.** `MotionController` and
`DashController` take a config in and return values out. They never touch the
scene tree, a physics body, or a viewport. That is what makes
`tests/test_player_movement.gd` possible without a running game, and it is why
`PlayerInput.poll()` is handed the player position and cursor position rather
than reaching for a viewport itself.

Supporting decisions:

- **All tunable values live in `PlayerConfig`**, a Resource serialised to
  `data/player/player_config.tres`. Movement feel can be tweaked in the inspector
  mid-play, and an alternate tuning is just another `.tres`.
- **`EventBus` is one autoload with two signals.** Dash events go through it so
  the debug overlay can react without reaching into the player's component
  subtree. Local signals are used inside an actor; the EventBus is only for
  crossing system boundaries. The rest of the spec section 14 combat events land
  here as the systems that emit them get built.
- **Fixed 480x270 logical resolution** with `viewport` stretch mode and `keep`
  aspect, so every pixel stays square and the framing never changes. Nearest
  neighbour filtering is set project-wide.
- **Scenes own their root script** (`scenes/player/player.gd`), while reusable
  components live in `scripts/components/`.
- **Input actions are generated**, not hand-written. `.godot`-format InputEvent
  literals are error-prone by hand, so `tools/generate_input_map.gd` builds them
  as real objects and prints the `[input]` section to paste into `project.godot`.
- **Physics layers are named** in `project.godot` (`world`, `player`, `enemy`,
  `player_projectile`, `enemy_projectile`, `pickup`) so no scene hardcodes a
  layer number.

### Files

```
project.godot                             Config, fixed resolution, input map, layer names
main.tscn / main.gd                       Entry point: places the player, fits the camera, binds the HUD
.gitignore

autoload/event_bus.gd                     Two dash signals; grows deliberately

scripts/resources/player_config.gd        Every movement/dash/integrity tunable
data/player/player_config.tres            The values from spec section 6

scripts/components/player_input.gd        Named actions -> movement + aim intent, dash buffering
scripts/components/motion_controller.gd   Acceleration/deceleration toward a target velocity
scripts/components/dash_controller.gd     Dash window, charges, recharge, invulnerability
scripts/components/player_visuals.gd      Aim rotation, dash squash, invulnerability flash

scenes/player/player.tscn / player.gd     The robot: body, components, camera
scenes/rooms/wall_block.tscn / .gd        Resizable solid wall, collision and sprite in lockstep
scenes/rooms/test_room.tscn / .gd         Sandbox arena; border generated, pillars hand-placed
scenes/ui/debug_hud.tscn / .gd            Diagnostics overlay (F1)

art/characters/player_placeholder.png     16x16 robot: round head, screen eye, tracked base
art/characters/player_cannon_placeholder.png
art/environments/wall_placeholder.png     16x16 tiling panel
art/environments/floor_placeholder.png    16x16 tiling floor

tests/test_player_movement.gd             27 headless checks on movement and dash maths
tools/generate_input_map.gd               Regenerates the [input] section of project.godot
```

Empty directories from the spec's suggested layout (`scenes/enemies/`, `data/items/`,
`shaders/`, `audio/`, ...) exist so later milestones have an obvious home.

---

## What was actually verified

Executed on this machine, not assumed:

- **`godot --headless --import`** completes with no errors.
- **Clean boot** (`--quit-after 240` on `main.tscn`) produces zero errors and
  zero warnings on stdout/stderr.
- **`tests/test_player_movement.gd`: 27 checks pass, exit 0.** Covers reaching
  `move_speed` without overshoot, diagonals not being faster, deceleration to a
  full stop, `dash_speed * dash_duration == dash_distance`, the dash lifecycle,
  invulnerability closing before the dash ends, charge spend and recharge, and
  direction reuse when no direction is held.
- **Measured in a running instance** driven by synthetic input: spawn at
  `(320, 320)`; top speed `160.0 px/s`; dash speed `500.0 px/s` (= 70/0.14);
  diagonal velocity `(+113, +113)` for a `160 px/s` magnitude; velocity clamped
  back to `160` on dash exit; charge spent and recharged.
- **Collision robustness:** 1800 physics frames (30 s) of pseudo-random movement
  with 27 dashes into walls, corners, and pillars produced **0 out-of-bounds
  frames** — nothing tunnelled at dash speed, and the robot was never pinned
  while movement was held (5 isolated frames of near-zero speed, all pressing
  directly into a wall).
- **Rendered frames inspected** to confirm the dash squash, the invulnerability
  flash, cannon aim rotation, and correct texture tiling.

Not verified: how it *feels*. The spec's success condition for this milestone is
"movement feels responsive for five minutes of continuous play", and that needs
your hands on the keyboard. Everything above only proves it is not broken.

---

## Known limitations

1. **Feel is untested by a human.** All numbers are the spec's suggested starting
   values. Expect to tune `acceleration`, `deceleration`, and
   `position_smoothing_speed` on the camera once you have played it.
2. **Placeholder art**, generated programmatically. Legible, not final. Spec
   section 20's chunky pixel art and CRT glow are a Milestone 6 concern.
3. **No audio at all** — no dash sound, no footsteps. Milestone 2 onward.
4. **The test room is not a room template.** It has no doors, spawn points,
   difficulty score, or floor tags (spec section 9). It is a walled box with
   pillars, built from resizable `WallBlock` bodies rather than a TileMap,
   because a Godot TileMap's cell data is a binary blob and cannot be authored
   as text outside the editor. Milestone 3 should introduce a real TileSet.
5. **`Escape`, `Tab`, `E`, and the fire buttons do nothing yet.** Actions are
   bound; there is no pause state or weapon to hang off them.
6. **Gamepad support is untested** — no controller was available. The actions and
   right-stick aim path are implemented per spec section 5 but unexercised.
7. **No game state machine, save system, or settings.** Spec sections 21, 23, and
   24 are later milestones.
8. **Camera smoothing can show sub-pixel-free motion at high refresh rates.** The
   `viewport` stretch mode snaps rendering to the 480x270 grid, which is correct
   for the retro look but means fast camera movement steps rather than glides.

---

## Next recommended task

**Milestone 2: Basic Combat**, in this order:

1. `WeaponController` + `FirePattern` as components on the player, driven by the
   already-bound `fire_primary` action, configured by a `WeaponConfig` resource
   holding the Rivet Blaster values from spec section 7 (1 damage, 4 shots/sec,
   420 px/s, 1.4 s lifetime).
2. A `Projectile` scene whose behaviour comes entirely from a `ProjectileConfig`
   passed in at spawn — `damage`, `speed`, `lifetime`, `pierce_count`,
   `bounce_count`, `homing_strength` and the rest of the spec section 13 state.
   **Get this data structure right before writing any item**, because Milestone 4's
   synergies are composition over exactly these fields. Items that instead add
   conditionals to the weapon will not compose.
3. One enemy (Ticket Bot) with a `HealthComponent`, plus the same component on
   the player so damage is symmetric.
4. Hit feedback from spec section 7: hit flash, impact particle, knockback, brief
   hit pause. Add `on_projectile_hit`, `on_enemy_damaged`, and `on_enemy_killed`
   to the EventBus as they are needed, not before.
5. Room clear detection, emitting `on_room_cleared`.

Success condition: the player can enter a room, defeat enemies, and survive or die.
