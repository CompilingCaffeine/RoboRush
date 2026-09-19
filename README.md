# Robo Rush

Robo Rush is a 2D top-down roguelite shooter built with Godot 4 and GDScript. Play an obsolete maintenance robot fighting through a corrupted software megacorporation, collecting upgrades that combine into new projectile behaviours.

The complete campaign has six procedural floors. Each floor has a start room, combat rooms, a treasure vault, a shop, and a boss arena. The game supports keyboard and gamepad controls, persistent settings and records, deterministic seeded runs, desktop exports, and a browser build with Wavedash leaderboard support.

For the original design requirements, see [robo_rush_build_spec.md](robo_rush_build_spec.md). The detailed six-floor plan is in [SIX_FLOOR_SCALING_GAMEPLAN.md](SIX_FLOOR_SCALING_GAMEPLAN.md).

## Run

Open the project in the Godot editor and press `F5`, or run:

```bash
godot --path .
```

To start a run directly, bypassing the title screen:

```bash
godot --path . res://main.tscn
```

Replay a run with a fixed seed, optionally starting on a specific floor:

```bash
godot --path . res://main.tscn -- --seed=918273
godot --path . res://main.tscn -- --seed=918273 --floor=2
```

Use `--manifest` to print the derived floor seeds and content fingerprint for a seeded run.

If assets are missing after a fresh clone, import once:

```bash
godot --headless --import
```

## Controls

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Move | `WASD` | Left stick |
| Aim and fire | Arrow keys | Right stick |
| Dash | `Space` | A / cross |
| Buy / take reward | `E` | X / square |
| View run statistics | Hold `Tab` | Hold L1 / LB |
| Pause | `Escape` | Start |
| Restart | `R` | Y / triangle |
| Active item | Right mouse | Left trigger |
| Toggle debug overlay | `F1` | — |

Holding an arrow key aims and fires in that direction. Movement and firing are independent, so you can move and shoot in different directions. The game shows its controls on first launch and from the title and pause menus.

## Test

Run the complete suite with a fixed physics rate:

```bash
godot --headless --fixed-fps 60 res://tests/test_runner.tscn
```

`--fixed-fps 60` is required: the tests assert on physics frames, and the fixed rate keeps the suite fast and deterministic.

Focused campaign checks are also available:

```bash
godot --headless --fixed-fps 60 res://tests/executive_runner.tscn
godot --headless --fixed-fps 60 res://tests/finale_runner.tscn
```

## Build

Export presets for macOS, Windows, Linux, and Web are defined in [export_presets.cfg](export_presets.cfg). They require the Godot 4.7.1 export templates matching the pinned engine in [tools/engine.lock](tools/engine.lock); install them from **Editor > Manage Export Templates**.

```bash
godot --headless --export-release "Linux" build/linux/robo_rush.x86_64
godot --headless --export-release "Windows" build/windows/robo_rush.exe
godot --headless --export-release "macOS" build/macos/robo_rush.zip
godot --headless --export-release "Web" build/web/index.html
```

For the qualified browser artifact, use:

```bash
tools/ci/build_web.sh
```

It verifies the pinned toolchain, imports the project, runs the test suite, exports the Web build, and produces a checked artifact in `build/web-artifact/`. Verify an exported Web build independently with:

```bash
tools/ci/verify_web.sh build/web
```

## Release

Build all release targets from a clean version tag:

```bash
tools/release.sh v0.3.0
```

The release script runs tests, verifies the pinned engine and export templates, builds every target into `build/0.3.0/`, and writes checksums and a manifest. After an intentional Godot upgrade, refresh the pins with:

```bash
tools/release.sh --relock
```

## Project notes

- Projectile behaviour is data-driven, so upgrades such as ricochet, splitting, homing, chaining, and explosions compose without item-pair-specific code.
- Procedural floor generation uses a connected room graph; treasure, shop, and boss rooms are dead ends so they never block progress.
- Generated art, audio, music, and UI font assets are committed. Regenerate them only when changing source generators:

  ```bash
  python3 tools/generate_art.py .
  python3 tools/generate_audio.py .
  python3 tools/generate_music.py .
  python3 tools/generate_ui_font.py .
  ```

- The browser build provides an ascending fastest-victory leaderboard. Desktop builds do not expose hosted leaderboard features.

## Current limitations

- The final two floors still need additional hands-on pacing and readability playtests.
- Windows and Linux exports have not received the same hands-on coverage as macOS and Web, and release signing is not configured in this repository.
- Gamepad bindings have automated coverage but need broader hardware playtesting.
