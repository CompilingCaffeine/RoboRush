# Robo Rush

Robo Rush is a 2D top-down roguelite shooter built with Godot 4 and GDScript. Play an obsolete maintenance robot fighting through a corrupted software megacorporation, collecting upgrades that combine into new projectile behaviours.

The complete campaign has six procedural floors. Each floor has a start room, combat rooms, a treasure vault, a shop, and a boss arena. The game supports keyboard, mouse, and gamepad controls, persistent settings and records, deterministic seeded runs, desktop exports, and a browser build with Wavedash leaderboard support.

For the original design requirements, see [robo_rush_build_spec.md](robo_rush_build_spec.md). The detailed six-floor plan is in [SIX_FLOOR_SCALING_GAMEPLAN.md](SIX_FLOOR_SCALING_GAMEPLAN.md). The current prioritized execution plan is [NEXT_STEPS_GAMEPLAN.md](NEXT_STEPS_GAMEPLAN.md); the larger backlog of fixes, feature upgrades, and new content is in [ROADMAP.md](ROADMAP.md). What changed in each build, for playtesters, is in [CHANGELOG.md](CHANGELOG.md).

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
| Fire at the pointer | Hold left mouse | — |
| Dash | `Space` | A / cross |
| Buy / take reward | `E` | X / square |
| View run statistics | Hold `Tab` | Hold L1 / LB |
| Pause | `Escape` | Start |
| Restart | `R` | Y / triangle |
| Toggle debug overlay | `F1` | — |

Holding an arrow key aims and fires in that direction. Movement and firing are independent, so you can move and shoot in different directions. With **Mouse aim** on (the default; see Settings), the robot also aims at the mouse pointer when it moves, and holding the left button fires towards it. Whichever you used last, the arrows, the stick or the mouse, sets the aim. The game shows its controls on first launch and from the title and pause menus.

## Test

Run the complete suite with a fixed physics rate:

```bash
godot --headless --fixed-fps 60 res://tests/test_runner.tscn
```

`--fixed-fps 60` is required: the tests assert on physics frames, and the fixed rate keeps the suite fast and deterministic.

To run only some suites while working on them, name them after `--`:

```bash
godot --headless --fixed-fps 60 res://tests/test_runner.tscn -- --suite=Items,Floor
```

Or leave some out with `-- --skip=Performance`. The build scripts do this on the stripped engine's run, whose timings don't describe the engine that ships.

Focused campaign checks and the six-floor performance probe are also available:

```bash
godot --headless --fixed-fps 60 res://tests/executive_runner.tscn
godot --headless --fixed-fps 60 res://tests/finale_runner.tscn
godot --headless --fixed-fps 60 res://tests/profile_executive.tscn
```

Static checks (GDScript lint, design notes, script UIDs, and the Python and shell tooling) need no engine and run on every pull request:

```bash
python3 -m pip install gdtoolkit==4.5.0 ruff==0.15.8 shellcheck-py==0.11.0.1
tools/ci/lint.sh
```

## Build

Export presets for macOS, Windows, Linux, and Web are defined in [export_presets.cfg](export_presets.cfg). They require the Godot 4.7.1 export templates matching the pinned engine in [tools/engine.lock](tools/engine.lock); install them from **Editor > Manage Export Templates**.

```bash
godot --headless --export-release "Linux" build/linux/robo_rush.x86_64
godot --headless --export-release "Windows" build/windows/robo_rush.exe
godot --headless --export-release "macOS" build/macos/robo_rush.zip
godot --headless --export-release "Web" build/web/index.html
```

The plain Web export above uses Godot's stock Web template. The browser build that ships runs on an engine compiled for this game instead, with everything it does not use switched off in [tools/engine/profile.py](tools/engine/profile.py): 22.9 MB of WebAssembly against the stock 39.5 MB (3.7 MB against 6.9 MB with brotli). Build it once, and again whenever the profile or the pinned engine changes:

```bash
tools/engine/build_template.sh web      # the Web export template
tools/engine/build_template.sh native   # the same engine for this machine, which the suite also runs on
```

Each takes a few minutes. They need git, Python 3 and a C++ compiler; the script fetches the pinned Godot source, SCons and Emscripten itself, into `build/engine/work/`. CI builds both and caches them, so this only matters locally.

For the qualified browser artifact, use:

```bash
tools/ci/build_web.sh
```

It verifies the pinned toolchain and that the stripped engine was built from the current recipe, imports the project, runs the test suite on the editor and again on the stripped engine, exports the Web build, and produces a checked artifact in `build/web-artifact/`. Verify an exported Web build independently with:

```bash
tools/ci/verify_web.sh build/web
```

## Release

Build all release targets from a clean version tag:

```bash
tools/release.sh v0.3.0
```

The release script runs tests, verifies the pinned engine and export templates and the stripped Web engine (build it first, as above), builds every target into `build/0.3.0/`, and writes checksums and a manifest. After an intentional Godot upgrade, refresh the pins with:

```bash
ENGINE_SOURCE_COMMIT=<full commit of the new release tag> EMSCRIPTEN_VERSION=<version the stock Web template reports> tools/release.sh --relock
```

The two variables are needed only when the engine changes; a relock without them keeps the recorded values.

## Project notes

- Projectile behaviour is data-driven, so upgrades such as ricochet, splitting, homing, chaining, and explosions compose without item-pair-specific code.
- Design rationale for data lives in `metadata/design_notes` on the resource, scene node, or sub-resource it explains (the inspector's Metadata section), not in `;` comments: the Godot editor deletes comments from `.tres` and `.tscn` files whenever it saves them. `tools/ci/check_design_notes.py` enforces this.
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
