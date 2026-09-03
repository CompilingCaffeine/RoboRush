# Robo Rush

A 2D top-down roguelite shooter built to [`robo_rush_build_spec.md`](robo_rush_build_spec.md).
You play an obsolete maintenance robot scavenging hardware and software upgrades
inside a corrupted software megacorporation.

**Current state: the planned six-floor campaign is complete.** A full run exists and the game
introduces itself: it opens on a title screen, tells a first-time player the one thing they
cannot work out by pressing keys, and remembers their settings and their records between
sessions. Each floor generates ten rooms procedurally — a start, six combat rooms, a
treasure vault, a shop, and a boss arena — and each teaches one idea before combining it
with the ones before; the fifth is a recombination and endurance floor, and the sixth is the
campaign's synthesis and finale.

The Help Desk is the fundamentals. Development adds compile lanes, a stripe of floor that
announces itself and then goes off. The Data Center adds throughput zones that charge for
standing on them and cable ducts that stop a chassis and not a shot. Cloud Operations adds
migration pads: two patches of floor that are the same place, and the first thing in the
game that moves the player. Executive Systems combines those mechanics with coordinated enemy
groups and an advanced Runtime Error rematch, Executive Override. The first four floors shuffle
their four bosses; the fifth has its own fixed, explicitly authored encounter. Core Intelligence
closes the run with every established room language and a fixed final encounter of its own.

Items compose: a run that finds Ricochet Driver and Fork Bomb fires shots that bounce
off a wall and then split, with no code anywhere aware those two items can be held at
once. Stacked multipliers bend rather than compound, so the worst legal build does about
9.4 times the damage the enemies are written for instead of 52.

Engine: **Godot 4.7.1**, GDScript, GL Compatibility renderer.

**The first four floors have been played through by hand, end to end, several times over.**
Executive Systems and Core Intelligence have automated campaign, combat, and UI coverage; their
human playtests are still due.
The earliest of those four-floor passes produced the findings in
[What playing it answered](#what-playing-it-answered): one mild sentence about the Data Center
that turned out to be three bugs, none of them visible in the code, in a test, or on screen.
That is the standing argument for why playing is not optional.

What is missing is the other half. The runs since have not been written up, so every floor's
list of open questions below is a set of questions that *has* now been put in front of a person
and whose answers are not in this file. The gap is no longer the playing; it is the record of
it, which is why that is the first item under [Next recommended
task](#next-recommended-task). See [Known limitations](#known-limitations).

---

## Running it

```bash
godot --path .
```

Or open the project folder in the Godot editor and press F5. Either way you land on the
title screen; the first launch shows the controls card before it.

Run the tests (exits non-zero on failure):

```bash
godot --headless --fixed-fps 60 res://tests/test_runner.tscn
```

`--fixed-fps 60` is required, not an optimisation. The suites assert against real physics
frames and the engine paces those in real time, so without it the run spends almost all its
wall clock asleep — and long enough that the runner's own sixty-second per-suite budget trips,
reporting a passing suite as a hang and abandoning every suite after it. With the flag the
delta is pinned at 1/60, every frame-counting assertion keeps its meaning, and the full run is
about fifteen seconds. `tools/ci/build_web.sh` passes it for the same reason.

If assets show as missing after a fresh clone, import them once:

```bash
godot --headless --import
```

## Cutting a release

```bash
tools/release.sh v0.3.0
```

Builds all four targets from that tag into `build/0.3.0/`, and writes a `manifest.json` and
`SHA256SUMS` recording the commit, engine version, size and hash of everything it produced.

It refuses to run from a dirty tree, from a commit that is not the tag, or with an engine or
export templates that differ from the ones pinned in `tools/engine.lock` — a Godot patch
release changes the binary, so an unpinned engine makes "reproducible" untrue in the one way
nobody checks. It runs the test suite before building anything, and it rewrites the version
fields in `export_presets.cfg` from the tag and puts them back afterwards, so the number
inside the binary and the number on the release cannot disagree.

After upgrading Godot on purpose, re-record the pins so the change is a reviewable diff:

```bash
tools/release.sh --relock
```

Signing is wired but needs credentials the repository does not carry. Without them the script
says so and records `"signing": "unsigned"` in the manifest rather than shipping artifacts as
though they were signed. With them:

```bash
export MACOS_SIGNING_IDENTITY="Developer ID Application: …"
export MACOS_NOTARY_PROFILE=roborush      # xcrun notarytool store-credentials
export WINDOWS_SIGNING_PFX=…/cert.pfx WINDOWS_SIGNING_PASSWORD=…
```

To skip the menu and drop straight into a run — which is what the tests do, and what
`--seed=` debugging wants:

```bash
godot --path . res://main.tscn
```

To replay one specific run — the seed is printed at startup and shown in the debug overlay
(`F1`), which also shows the floor seed derived from it:

```bash
godot --path . res://main.tscn -- --seed=918273
```

Every floor's seed comes from the run seed and that floor's stable id, so a single floor can be
replayed on its own without clearing the ones before it:

```bash
godot --path . res://main.tscn -- --seed=918273 --floor=2
```

A seed only means something against the content it was drawn on. `--manifest` prints what the
seed actually resolves to — every floor's derived seed and a fingerprint of the content that seed
will be spent on — so "this floor stopped generating the way it did in that report" can be
answered with "the content changed, on this floor" rather than a guess:

```bash
godot --path . res://main.tscn -- --seed=918273 --manifest
```

### Building it

Export presets for macOS, Windows, Linux, and Web are in
[`export_presets.cfg`](export_presets.cfg). All four have been built and the macOS app has
been run; see [what was actually verified](#what-was-actually-verified).

Building needs Godot's export templates for this exact engine version — a separate ~1 GB
download that is not in this repository. **There is no CLI flag to install them**
(`--install-export-templates` does not exist; only the Android build template has one).
Either use the editor's *Editor > Manage Export Templates > Download and Install*, or:

```bash
curl -L -o templates.tpz https://github.com/godotengine/godot/releases/download/4.7.1-stable/Godot_v4.7.1-stable_export_templates.tpz
unzip -q templates.tpz -d tpz
mkdir -p "$HOME/Library/Application Support/Godot/export_templates/4.7.1.stable"
cp -R tpz/templates/. "$HOME/Library/Application Support/Godot/export_templates/4.7.1.stable/"
```

Then:

```bash
godot --headless --export-release "Linux" build/linux/robo_rush.x86_64
godot --headless --export-release "Windows" build/windows/robo_rush.exe
godot --headless --export-release "macOS" build/macos/robo_rush.zip
godot --headless --export-release "Web" build/web/index.html
```

The presets exclude `tests/` and `tools/`, `build/` carries a `.gdignore` so exported
output is never re-imported as project content, and the macOS bundle identifier is a
placeholder that needs changing before publishing anywhere that cares.

### Building the browser version

The Web build is the one that ships to Wavedash, and it goes out on every commit rather than on
every tag, so it has its own script:

```bash
tools/ci/build_web.sh
```

It verifies the pinned engine, the pinned Web template and the vendored Wavedash SDK, checks that
the Web preset still has the settings the build is qualified for (single-threaded, no GDExtension,
no PWA, `gl_compatibility`), imports, runs the whole suite, exports into a `build/web` it recreates
from empty, and writes `build/web-artifact/`: the zip that gets uploaded, its SHA-256, a checksum
per file, and the test log.

The suite and the export run against a throwaway copy of Godot's data directory holding nothing
but the template whose hash was just checked, so a build cannot use some other installed template
and cannot overwrite the `user://` save of whoever ran it.

Each build bakes its short commit into the project settings, which is what the main menu shows in
the corner and what `build-info.json` records — a hosted build can be asked which commit it is over
HTTP, which is the difference between qualifying Build B and believing you are looking at Build B.

The contract check is separate, so it can be re-run on an artifact after it has travelled:

```bash
tools/ci/verify_web.sh build/web
```

It fails on a missing file, on anything in the upload that the export does not produce, on test or
tool paths inside the PCK, on an `index.html` whose recorded file sizes disagree with the binaries
beside it, and on a build id that is not actually in the artifact.

Templates install as described above; on Linux the directory is
`~/.local/share/godot/export_templates/4.7.1.stable/` instead. On a machine that has neither the
engine nor the template — a CI runner, a fresh clone on a new laptop — there is a script:

```bash
tools/ci/install_godot.sh --prefix ~/.local/bin
```

It installs the pinned editor and *only* the Web export template, checking both against a hash
before anything uses them. The templates are published as one 1.28 GB bundle of which this build
needs a single 10 MB file, so it reads the bundle's zip directory over HTTP range requests and
pulls out that one entry rather than downloading the rest.

To boot the exported build in a real browser and wait for it to say it started:

```bash
python3 -m pip install playwright && python3 -m playwright install chromium
python3 tools/ci/smoke_web.py build/web --screenshot smoke.png
```

### Continuous integration

`.github/workflows/web-ci.yml` runs the whole of the above on every pull request and every push to
`main`: pinned toolchain, build, artifact contract, browser smoke, and the zip kept as the run's
artifact. It has no credentials, so a pull request from anywhere can run it safely.

`.github/workflows/wavedash-upload.yml` starts when that succeeds on `main` and uploads the exact
artifact it produced — downloaded, digest-checked, extracted, and checked again — as a new
immutable Wavedash build. It never rebuilds: the artifact that passed the tests is the artifact
that gets published, or the testing meant nothing. It is the only place a Wavedash credential
exists, and it needs a GitHub Environment named `wavedash-beta` holding a `WAVEDASH_TOKEN` secret
before it can do anything.

Uploading is not publishing. Each upload is a private build with its own playtest URL; making one
of them the public game stays a deliberate act in the Developer Portal.

### Assets

Every sprite, sound, and music loop in the game is generated by a script in `tools/`, so
the art is reviewable as a diff and the whole set can be rebuilt from text:

```bash
python3 tools/generate_art.py .
python3 tools/generate_audio.py .
python3 tools/generate_music.py .
python3 tools/generate_ui_font.py .
```

None of these are needed to build or run the game — the output is committed.

### Controls

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Move | `WASD` | Left stick |
| Aim and fire | Arrow keys | Right stick |
| Dash | `Space` | A / cross |
| Buy / take | `E` | X / square |
| Run statistics | `Tab` (hold) | L1 / LB (hold) |
| Pause | `Escape` | Start |
| Restart | `R` | Y / triangle |
| Active item | Right mouse | Left trigger |
| Menu: move | Arrows or `WASD` | D-pad or left stick |
| Menu: confirm / back | `Enter` / `Escape` | A / B |
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

The game says all of this itself, on a card shown automatically the first time it is
launched and reachable from the title screen and the pause menu after that — spec section
31.11 wants the controls explained in game, and the firing scheme in particular is not
something a player can discover by experimenting.

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

**A boss has one health pool and several bodies.** Spec section 16 has The Scrap King
*duplicating* into two versions of itself, and two copies of one thing share what it has
left. So [merge_conflict.gd](scenes/bosses/merge_conflict.gd) — the file keeps the name the
boss had before it was renamed, as do the scene, the resource, and `BossConfig.id`, which is
what a save records as beaten — owns the fight and the
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

Spec section 12's full pool ships. Development adds nine more on top of these — see
[Six new items](#six-new-items) and the three that follow it.

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
- **StatusEffectController** — now [built](scripts/components/status_effect_controller.gd),
  on exactly the terms this entry set: it stayed unwritten until Cold Cache and Hot Reload
  needed it, and `ProjectileConfig.status_effects` is no longer a declared-and-unread field.
  It is a `Node2D` rather than a plain `Node` so it can draw its own indicator ring — the
  parent's `modulate` already has two writers in every enemy telegraph and `HurtFlash`, and a
  third is how a telegraph ends up invisible.

`ShotContext` was considered and rejected. `ProjectileFactory.spawn` now takes nine
parameters, four of them optional, and bundling the trailing ones into an object would
read better at the one call site that uses them all — but it would also be a new concept
in a codebase whose whole argument is that concepts are expensive. It earns its place
when charge level and combo multipliers arrive and the list grows again.

### Files

New in milestone 6 marked `+`. (Milestone 5's additions are no longer marked.)

```
project.godot                             Config, resolution, input map, layers, autoloads, theme
export_presets.cfg                      + Desktop and web export targets
main.tscn / main.gd                       A run: builds the floor, wires HUDs
scenes/ui/main_menu.tscn / .gd          + The title screen, and the game's entry point

autoload/event_bus.gd                     21 cross-system signals
autoload/game_manager.gd                  Feedback config, hit pause, game state
autoload/audio_manager.gd                 Pooled one-shot SFX, and crossfaded music
autoload/run_manager.gd                   Run state: scrap, floor, one immutable seed, items,
                                            per-floor records, statistics
autoload/save_manager.gd                + Settings, unlocks, bosses beaten, best runs, the run
                                            in progress; and the one place a setting becomes
                                            behaviour
autoload/scene_router.gd                + The only thing that changes scenes
autoload/screen_effects.gd              + CRT filter and damage vignette, above every layer

scripts/resources/player_config.gd        Movement, dash, integrity tunables
scripts/resources/projectile_config.gd    The composition surface for every item
scripts/resources/weapon_config.gd        Fire rate, pattern, muzzle
scripts/resources/enemy_config.gd         Durability, range-keeping, contact, telegraph
scripts/resources/pop_up_drone_config.gd  + Teleport interval, arrival pause, placement
scripts/resources/memory_leech_config.gd  + Windup, charge speed, recovery
scripts/resources/firewall_node_config.gd + Beam count, reach, sweep, damage
scripts/resources/enemy_spawn.gd        + One roster entry: what, how often, how early
scripts/resources/boss_config.gd        + The Scrap King's phases and attacks
scripts/resources/shop_config.gd        + Spec section 17's prices
scripts/resources/feedback_config.gd      Shake, flash, damage numbers, hit pause
scripts/resources/room_template.gd        One handcrafted room layout, in tiles
scripts/resources/floor_config.gd         A floor's parts list, rosters, rewards, shop
scripts/resources/floor_entry.gd        + One floor's place in a campaign: id and path
scripts/resources/run_definition.gd     + The campaign: which floors a run is made of
scripts/resources/pickup_config.gd        What a pickup is and what collecting it does
scripts/resources/item_config.gd          One item, entirely as data

scripts/combat/damage_info.gd             One described damage event
scripts/combat/projectile_factory.gd      Builds projectiles; runs the modifier stack
scripts/combat/projectile_modifier_stack.gd Every held item's changes, applied to one shot
scripts/combat/diminishing_returns.gd     The knee stacked multipliers bend on
scripts/combat/shot_counter.gd          + A shot tally several weapons can share
scripts/combat/targeting.gd               The hostile bodies near a point
scripts/combat/explosion.gd               One blast, damage only
scripts/combat/chain_lightning.gd         Damage that hops between enemies
scripts/combat/compile_lane.gd             Development: a stripe of floor that announces itself
scripts/combat/thermal_zone.gd             The Data Center: ground that charges for standing on it

scripts/components/player_input.gd        Named actions -> movement, fire, dash, interact
scripts/components/motion_controller.gd   Acceleration/deceleration
scripts/components/dash_controller.gd     Dash window, charges, invulnerability
scripts/components/player_visuals.gd      Aim, dash squash, flash, muzzle, item accent,
                                            + dash afterimages and bolted-on upgrades
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
scripts/systems/campaign_validator.gd   + Refuses a broken campaign before a run starts
scripts/systems/run_rng.gd              + One run seed, derived into named per-floor streams
scripts/systems/run_manifest.gd         + What a seed will build: derived seeds and content
scripts/systems/floor_record.gd         + One floor's duration, boss, and how it ended
scripts/systems/run_checkpoint.gd       + A run frozen at a floor boundary, and what makes
                                            one safe to read back
scripts/systems/loot_spawner.gd           Enemy drops, room rewards, and item drops
scripts/systems/game_settings.gd        + Spec section 21's eight settings, as plain data
scripts/systems/best_run_stats.gd       + What survives a run, and what counts as a record
scripts/utilities/teams.gd                Teams, collision layers, and body groups
scripts/utilities/ui_palette.gd         + The interface's colours, in one place

scenes/player/player.tscn / .gd            The robot
scenes/player/player_drone.tscn / .gd    + Debug Drone's orbiting companion
scenes/enemies/enemy.gd                  + What every enemy has in common
scenes/enemies/ticket_bot.tscn / .gd       Range-keeping shooter
scenes/enemies/pop_up_drone.tscn / .gd   + Teleports, pauses, fires a spread
scenes/enemies/memory_leech.tscn / .gd   + Commits to a charge it will not steer
scenes/enemies/firewall_node.tscn / .gd  + Stationary; sweeps rotating beams
scenes/bosses/merge_conflict.tscn / .gd  + The Scrap King and its three phases
scenes/bosses/boss_part.tscn / .gd       + A shootable body that forwards its hits
scenes/bosses/boss_terminal.tscn / .gd     A synchronization terminal
scenes/bosses/runtime_error.tscn / .gd     Development's boss
scenes/bosses/cascade_failure.tscn / .gd   The Data Center's boss
scenes/bosses/orchestrator.tscn / .gd   + Cloud Operations' boss; migrates, open only after it lands
scenes/bosses/orchestrator_core.tscn    + Its one body
scenes/shop/shop_room.tscn / .gd         + A shop's stock, rerolls, and exclusive choices
scenes/shop/shop_stand.tscn / .gd        + One thing for sale
scenes/projectiles/projectile.tscn / .gd   Fully config-driven projectile
scenes/effects/*.tscn                      Impact, death, explosion, chain zap, numbers
scenes/rooms/wall_block.tscn / .gd         Resizable solid wall
scenes/rooms/room.tscn / .gd               A room built from a template
scenes/rooms/door.tscn / .gd               Shared door between two rooms
scenes/rooms/cable_duct.tscn / .gd         Stops a chassis, passes a shot
scenes/rooms/migration_pad.gd           + Cloud Operations: one end of a link, and the only
                                            thing in the game that moves the player. No scene —
                                            it draws itself, like a thermal zone
scenes/floors/floor.tscn / .gd             Instantiates the layout, runs the room loop
scenes/pickups/pickup.tscn / .gd           One scene, behaviour from PickupConfig
scenes/ui/combat_hud.tscn / .gd            Integrity, dash, weapon, scrap, items, boss bar
scenes/ui/run_summary.tscn / .gd         + Game over, victory, pause, and the Tab peek
scenes/ui/minimap.tscn / .gd               Explored floor; unvisited types stay hidden
scenes/ui/debug_hud.tscn / .gd             Developer diagnostics (F1), off by default
scenes/ui/pause_menu.tscn / .gd         + Resume, settings, controls, abandon, quit
scenes/ui/settings_menu.tscn / .gd      + The eight settings, as a navigable list
scenes/ui/controls_card.tscn / .gd      + What the buttons do; shown on first launch

shaders/crt.gdshader                    + Scanlines and vignette, optional
shaders/damage_vignette.gdshader        + A red frame when the player is hit

data/player, data/projectiles, data/weapons    Player, shot, and weapon tuning
data/enemies/*.tres                        Four enemies, each its own config type
data/spawns/*.tres                       + The floor's weighted enemy roster
data/bosses/*.tres                         Six bosses: tuning, and what the HUD says
scripts/resources/migration_link.gd     + A pair of pads, so half a link is unauthorable
data/rooms/*.tres                          Fifty-two templates across six floors
data/runs/main_campaign.tres               Which floors a run is made of, in order
data/floors/floor_*.tres                   One per floor: rooms, roster, economy, boss pool
data/spawns/<floor>/*.tres                 A floor's own weights for an enemy it shares
data/floors/floor_1_help_desk.tres         Floor 1: parts, rosters, rewards, item pool
data/runs/main_campaign.tres             + The run's floor order, by stable id and path
data/items/*.tres                          54 items: 48 one-time, 6 stackable chips
data/settings/feedback_config.tres         Feedback intensity
data/settings/shop_config.tres             Spec section 17's prices
data/ui/theme.tres                      + One font and palette for every Control
art/ui/font_6x8.fnt / .png              + A 5x8 monospace bitmap face, 95 glyphs
audio/music/*.wav                       + Menu, explore, and boss loops

tests/test_runner.tscn / .gd               Aggregating runner; fails on a vanished suite
tests/test_case.gd                         Suite base class
tests/test_player_movement.gd              32 movement and dash checks
tests/test_combat.gd                       126 data, component, and integration checks
tests/test_player_input.gd                 38 arrow-key shooting checks
tests/test_campaign.gd                     86 campaign, lookup, seed, and injected-fault checks
tests/test_determinism.gd                  183 seed-derivation, stream, manifest, and record checks
tests/test_economy.gd                      57 reward, boss-choice, stacking, and 10k-run checks
tests/test_post_boss.gd                    36 checks that a dead boss's hazards still resolve
tests/test_floor.gd                        974 generation, invariant, template, and floor-advance
                                            checks, including the flood fill that walks every
                                            template in the campaign
tests/test_items.gd                        548 item, stack, inventory, and synergy checks
tests/test_enemies.gd                      200 checks that each enemy poses its problem
tests/test_run.gd                          64 statistics, state, and summary checks
tests/test_shop.gd                         90 price, purchase, and refusal checks
tests/test_boss.gd                         104 phase, terminal, and defeat checks
tests/test_runtime_error.gd                97 checks on Development's boss
tests/test_cascade_failure.gd              108 checks on the Data Center's boss
tests/test_thermal.gd                      198 checks on what may and may not heat a zone
tests/test_migration.gd                 + 334 checks on what a pad moves, and what rearms it
tests/test_orchestrator.gd              + 224 checks on Cloud Operations' boss, including a
                                            brute-force proof that every migration is answerable
tests/test_save.gd                         83 settings, save format, and record checks
tests/test_checkpoint.gd                   198 boundary-checkpoint, resume, refusal, and
                                            file-recovery checks
tests/test_gate.gd                        109 checks of the six-floor plan's per-floor gate,
                                            counted off the campaign rather than hard-coded
tests/test_soak.gd                         100 complete six-floor campaigns, checked for
                                            anything left behind
tests/test_executive.gd                 + 502 checks on Floor 5, carried builds and compact UI
tests/test_core_intelligence.gd         + 502 checks on the finale, its checkpoint and victory
tests/greybox_campaign.gd                  A campaign of any length, for suites needing more
                                            floors than the game has
tests/floor_economy.gd                  +   What a floor pays out in scrap, shared by the two
                                            suites that ask about money
tests/test_audio.gd                        130 library, loop, crossfade, and watchdog checks
tests/test_gamepad.gd                      96 checks driven by a synthesized controller
tests/test_balance.gd                      203 checks on what the tuning numbers mean, the
                                            economy among them measured across the campaign

tools/release.sh                        + Builds every target from a tag, hashed and
                                            manifested
tools/ci/build_web.sh                   + The browser build: pins, suite, export, artifact
tools/ci/verify_web.sh                  + What a publishable web artifact must contain
tools/ci/lib.sh                         + What "pinned" means, shared by both builds
tools/engine.lock                       + The pinned engine, template and SDK hashes
tools/generate_input_map.gd                Regenerates project.godot's [input]
tools/generate_art.py                      Regenerates every sprite and tile sheet
tools/generate_audio.py                    Synthesizes all 20 sound effects
tools/generate_music.py                    A small tracker; the thirteen music loops
tools/generate_ui_font.py               + The UI's bitmap font and its BMFont page
```

---

## What was actually verified

Executed on this machine, not assumed.

- **`godot --headless --import`** completes with no errors.
- **Clean boot on both entry paths** (`--quit-after 300`, on the title screen and directly
  on `main.tscn`) produces zero errors and zero warnings on stdout/stderr.
- **The milestone 6 snapshot's 936 checks across 13 suites passed, exit 0**, in 48s. That
  assertion result was not a clean engine log: the doorway-template diagnostic still emits
  `Rect2i` formatting errors without failing its checks. The Development gate below treats
  removing that noise — and making unexpected engine errors visible as failures — as required
  baseline work.
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
- **A run is reproducible from one seed, and stays reproducible.** Each floor's seed comes from
  the run seed, the campaign's content version, and the floor's stable id — not from the floor
  before it — so renaming, reordering, or inserting a floor leaves every other floor's seed
  alone, and a single floor can be replayed with `--floor=`. Within a floor, layout, boss,
  encounters, shop, loot, and the boss reward each draw from their **own named stream**
  ([run_rng.gd](scripts/systems/run_rng.gd)), so one subsystem taking more numbers than it used
  to cannot move another's results. What is deliberately *not* reproducible is per-frame combat:
  enemies and bosses draw from the engine's global generator, and nothing here promises a replay
  of a fight.
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
- **Each of the eleven enemies is checked for posing its own problem**, not for running. The
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

- **The save file round-trips, and survives being wrong.** Truncated, hand-edited,
  wrong-typed, out-of-range, and newer-than-this-build save data all cost at most the one
  field that is broken. Records only move upwards, a fast *loss* is not a fast run, and a run
  that ends three times in one frame is counted once.
- **Every setting is confirmed to reach the thing it controls** — the mixer bus, the window,
  and the `FeedbackConfig` every effect reads — because a settings screen whose switches are
  wired to nothing looks identical to one that works.
- **Every sound spec section 22 lists as a priority is asserted to exist**, all three music
  loops are confirmed to be set to loop, and the crossfade is confirmed to reach full volume,
  stop the outgoing track, and *not* restart a track that is already playing.
- **A gamepad is synthesized and driven**, since no controller was available: the left stick
  moves, the right stick aims and fires and keeps its diagonals, drift below the takeover
  threshold does not fire, releasing the stick stops the weapon, and the face buttons request
  a dash and an interaction. This is how the menus were found to be unusable on a controller
  (see below).
- **The tuning numbers are computed rather than eyeballed**: time to kill for every enemy,
  the boss fight's real length including the desync refund, and whether one run's scrap can
  buy everything. This is how the boss's terminal mechanic was found to be nearly worthless
  (see below).
- **The interface was driven by synthetic keypresses and screenshotted at every step** —
  first launch, title screen, settings, a setting being changed, pause, pause-settings,
  resume — and the resulting frames looked at. Four of the bugs below were found that way and
  by nothing else.
- **All four targets export clean, and the macOS build was run.** Linux (71 MB), Windows
  (105 MB), macOS (58 MB) and Web (39 MB), each with zero errors. The exported `.app` was
  unzipped and launched for 240 frames with zero errors and zero warnings, and the packed
  data is confirmed to contain the game and *no* reference to `res://tests/`. Two real
  problems surfaced only by doing this rather than by writing the presets: the project had no
  icon at all, and macOS refuses a universal or arm64 export unless ETC2 ASTC import is
  enabled — which it reports only as the word "errors".
- **Rendered frames inspected** of the shop (four stands showing `COOLING FAN 12`,
  `RICOCHET DRIVER 12`, `REPAIR 6`, `REROLL 4`, amber because affordable), the boss arena
  mid-phase-two (two versions, four corner terminals, sealed door, health bar at ~62%), and
  the run summary. Looking at those frames is how the placement bug below was found.

### Four shops, one purse

The balance suite's economy checks were written when the game was one floor long, and they were
still one floor long four floors later. `COMBAT_ROOMS_ON_FLOOR_1` and a hand-typed 3.5 enemies a
room stood in for the campaign, `floor_1_help_desk.tres` stood in for every floor, and the phrase
"a whole run's scrap" meant the Help Desk's.

That is not merely a narrower claim than it should have been — it had become a false one, silently,
while the test went on passing. The assertion spec section 17 asks for is that a run's income does
not buy one of everything on the price table, 132 scrap. One floor earns about 41 and the check
passed with room to spare. **Four floors earn about 170, so the sentence the test exists to defend
stopped being true somewhere around floor 3**, and nothing noticed, because the test's idea of "a
run" had not moved since milestone 5. A check whose subject drifts out from under it is worse than
no check: it reports on a game that is no longer the one being shipped.

What the economy actually is, computed from the shipped resources rather than typed in:

| floor | combat rooms | enemies/room | at the shop | whole floor |
|---|---|---|---|---|
| Help Desk | 6 | 3.75 | 17.3 | 41.5 |
| Development | 6 | 3.75 | 17.3 | 41.5 |
| Data Center | 6 | 4.00 | 18.0 | 43.0 |
| Cloud Operations | 6 | 4.14 | 18.4 | 43.9 |

Three claims replace the single-floor one, and each is a question only four shops can ask:

- **Every shelf is worth walking into**, modelled against the player who empties their purse at
  every shop — so what they bring to one is exactly what the game paid them since the last. That
  is 17.3 scrap at the first shop and about 42 at each of the three after it, against 12 for the
  cheapest item and 10 for the reroll-and-repair a dead shelf is escaped with. **The first shop is
  the tightest in the campaign by a factor of two and a half**, which is the opposite of the
  intuition that late shops are where a long run gets poor.
- **A whole run does not clear every shelf it passes.** Eight stands, drawn from a pool averaging
  23.3 scrap an item, come to 187 against a run's 170. It holds — *by nine percent*. That margin
  is the number to watch: a fifth floor adds roughly 44 of income against 47 of stock, so the
  claim survives lengthening the campaign, but almost anything that raises drop rates breaks it.
- **A rare stays a decision at every depth.** 32 scrap against a floor's 41.5 to 43.9, so one
  floor buys 1.3 rares. Both failure directions are quiet: below 1x the dearest rarity is
  decoration nobody can afford, above 3x the shelf is a vending machine.

The model lives in `tests/floor_economy.gd` rather than in the suite, because the shop suite was
already computing the same figure from the same fields — and moving it corrected that copy by one
scrap. `LootSpawner.spawn_treasure` drops the *top* of the clear range plus two, deterministically,
and the shop suite had been modelling it as the middle plus two. A typical Help Desk pays 39, not
the 38 that had been written down.

Two honest limits. The enemies-per-room figure is a flat average across a floor's combat templates,
which runs slightly high — 22.5 / 22.5 / 24.0 / 24.9 against the 21.9 / 21.9 / 22.8 / 23.8 measured
over four hundred generated floors, because `_capped_by_distance` draws the easy and emptier rooms
more often. That error is in the strict direction for the claim that matters. And none of it models
a player: Scrap Magnet and Compound Interest both multiply the whole table, and every figure above
is the build holding neither. **Whether four shops feel tense or flush is still unanswered**, and
still not a thing a suite can answer.

### Honest limits of that verification

**None of this is playing it.** The game has been played by hand, end to end and several times
over — see the note at the top of this document — but no part of that is what this section
reports, and no part of it is in the suite. Whether four enemy types produce interesting rooms
together, whether the Memory Leech's 0.42-second windup is enough warning, whether the boss's
phase two is a puzzle or a wall, and whether the shop's prices bite are questions a person has
now had in front of them for several runs. They remain questions no check in this repository can
answer, and what the person concluded is not recorded here — so nothing below should be read as
having been confirmed by play.

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

15. **The boss's phase change spawned bodies inside a physics callback** — the fifth time
    this project has met that trap, and the first time it reached a player rather than a
    harness. Crossing 70% health is reached from `Projectile._on_body_entered`, and adding
    the second version and its four terminals there printed twenty errors per fight. The
    suite missed it because **every boss check damaged the boss by emitting `took_damage`
    directly**, which is a faithful test of the forwarding and a blind spot for everything
    upstream of it. The phase state now changes immediately and only the *bodies* are
    deferred, so the refund cannot lapse for the frame in between; the suite now also
    fights the boss with real projectiles from a real weapon, and separately asserts the
    deferral itself so nobody can quietly make the spawn immediate again.

The pattern worth naming: **five of these were invisible to the test suite and visible the
moment something actually ran.** The suite is 692 checks and it did not catch a shop whose
stands were in another room, nor a boss that printed twenty errors every time it split.
Rendered frames, a harness that plays the game, and a person actually playing it are not
redundant with unit tests; they fail differently, and the last of those found the one the
first two missed.

---

### Bugs found during milestone 6

Four of these were found by driving the interface with synthetic input and looking at the
resulting frames, and by nothing else. The suite was green for all of them.

1. **Opening a panel left the button behind it holding keyboard focus.** Godot's focus
   navigation runs before `_unhandled_input`, so the first press of down moved the *hidden*
   menu's selection and never reached the settings panel — the second row was being adjusted
   while the first was highlighted. Found by checking the save file after a scripted run and
   noticing the wrong setting had changed. Both panels now release focus when they open.
2. **`ui_accept` and `ui_cancel` ship keyboard-only.** Godot's built-in menu actions cover
   the d-pad and left stick for the four directions but not the two buttons, so a gamepad
   player could move the selection in the pause menu and never activate anything. Every menu
   added this milestone would have been unusable on a controller. Found by the gamepad suite
   the same hour it was written.
3. **The diagnostics overlay was on by default**, covering a third of a 480x270 screen with
   developer text. Correct while the only person launching the game was the one writing it;
   wrong the moment anyone else does.
4. **The pause menu drew underneath that overlay**, because both were on the same
   CanvasLayer and the overlay came later in the scene. Menus have their own layer now.
5. **The HUD and minimap sat unreadably over the room's wall tiles.** This was known
   limitation 13 of milestone 5 — "legible today by luck rather than design" — and the luck
   ran out as soon as a frame was actually looked at. Both have opaque backings.
6. **The damage vignette's first version covered the whole screen.** A radial falloff on a
   16:9 frame reaches the corners at nearly twice the radius it reaches the top edge, so by
   the time the corners lit up the middle was already red. It is a rectangular frame now.
7. **Every music track had a bass line and drum pattern half the length of its melody**, so
   the back half of each loop played the tune over silence — which sounds like the music
   stopping rather than like a mistake. Found by making `mix()` count its own beats, which
   then immediately caught a second one: a boss bass line twice as long as its melody.
8. **`MergeConflict.get_parts` bound freed instances to a typed loop variable**, spamming
   "attempted to set an invalid object instance" on every call. Harmless, but it buried real
   errors in the test output until it was found and fixed.
9. **The gamepad suite was racing its own input.** `Input.parse_input_event` only queues;
   without an explicit flush the event arrives whenever the engine next drains its buffer,
   which is not guaranteed to be before the poll on the next physics frame. It passed for an
   afternoon and then failed four checks with no input change at all. Every synthetic event
   is flushed immediately now, and the suite was run three times over to confirm it.
10. **Quitting from a menu leaked the sound it played on the way out.** Reported from a real
    application run as "2 ObjectDB instances were leaked" and "1 resources still in use". The
    pause menu's QUIT button played `ui_back` and called `quit()` on the same frame, so the
    stream was still playing — and therefore still referenced — when the engine checked for
    leaks. The sound could never have been heard either, since the window closes at the end
    of that frame. Removed from all three quit handlers, and `AudioManager.stop_all()` is now
    the general guard. Worth noting that I had seen this warning once in my own harness output
    earlier in the milestone and not chased it.
11. **Shop rerolls could make a run unwinnable.** Reported, and the worst bug in the project
    so far. Every item a shop *displayed* was struck off the run's shared twelve-item pool for
    good, so two initial offers plus three rerolls burned eight of them; add three
    combat-clear rewards and the treasure vault and the pool was dry before the boss died. The
    boss then created zero reward stands, and victory only ever happened when a reward was
    taken — so the player was left in a cleared arena with a dead boss and no way to win.
    Rerolled items now return to the pool, and victory no longer depends on a prize existing.
12. **Settings and the controls card passed clicks straight through.** Reported. Both modal
    panels were `MOUSE_FILTER_IGNORE` on their root — copied from the HUD, where ignoring the
    mouse is correct — so a click anywhere on them landed on whatever was underneath. With
    settings open over the pause menu that meant Abandon Run and Quit were live, and hovering
    handed keyboard focus back to a button the player could not see. The keyboard half of this
    had already been reported and fixed a week earlier; the mouse half was the same mistake in
    the other input device.
13. **Every gamepad binding worked on joypad 0 and no other.** Reported. A freshly constructed
    InputEvent has `device = 0`, and `InputMap` matches a binding to an incoming event only when
    the devices agree or the binding says `-1` — so the whole generated map was pinned to one
    controller index. That is worse than "player two does not work": Godot hands out indices in
    connection order, so a pad paired after another device, or reconnected mid-session, lands on
    index 1 and does nothing at all. The editor's Input Map panel writes `-1` and calls it "All
    Devices"; a hand-built map does not get that for free. Confirmed by reintroducing the bug —
    28 checks fail, and the behavioural ones name indices 1, 2 and 7 exactly as reported.
14. **Knockback was broken in both directions at once.** Reported. The player's was authored
    three times — contact damage and Firewall Node beams at 130, the boss charge at 200 — and
    thrown away: `Player._on_damaged` only re-emitted the event, and `_physics_process`
    overwrites `velocity` every frame anyway, so an impulse parked there could never have
    survived. Enemy knockback had the opposite fault: `velocity += _knockback` every frame,
    and because `velocity` persists the same impulse was re-applied for every frame it took to
    decay, so a 55 px/s rivet peaked at 90 px/s three frames later — growing before it fell
    away, with the enemy's own steering left fighting the remains. Both now move the body as a
    separate decaying motion, so `velocity` stays purely what the actor is doing under its own
    power.
15. **Repair cells dropped on the wrong clears.** Reported: clears 1 and 4 instead of 3 and 6,
    because `FloorController` read `RunManager.rooms_cleared` while deciding, and RoomCombat
    emits its local `cleared` signal — the one that runs that handler — before the EventBus
    signal RunManager counts. So the value was always one behind, clear 1 read 0, and the very
    first room paid out a repair cell to a player still on full integrity who could not use it.
    The line immediately below it already used the controller's own `_clears`; two counters for
    one idea sat next to each other, one of them wrong.
16. **Return Protocol did nothing in a locked room.** Reported. It reversed the shot at the end
    of its lifetime, which for a rivet is 588 pixels of travel — and a room's interior is 416 by
    192, so a missed shot always died on a wall long before it was due to turn around. The item
    was a rare that did nothing in the only place the game has rooms. It now reverses when the
    shot has definitively *missed*: on a wall, once its bounces are spent. A first attempt
    capped how far it flew before turning, which its own test rejected — a shot that turns at
    140 pixels can never reach an enemy at 300, making the item a range downgrade.
17. **One failed save stopped the game saving for the rest of the session.** Reported.
    `save_game` cleared the "needs saving" flag on its first line, before it had even opened the
    file, and that flag is the only thing that makes anything try again — `_process` retries
    while dirty, and so does the flush on quit. So a transient failure (a full disk, a file held
    open, a rename losing a race) silently discarded every setting, record and unlock from that
    point on, with nothing but a warning nobody reads. The flag is now cleared only once a write
    has landed, with a five-second backoff — because the naive repair is worse than the bug:
    leaving the flag up with the countdown already expired retries every single frame.
18. **The boss's central mechanic was very nearly a trap.** Destroying all four
   synchronisation terminals saved two seconds out of thirteen — an eighteen percent return
   for crossing the arena four times under fire. Found by the balance suite computing what
   the numbers mean rather than asserting they are unchanged; the refund is now 0.75 and
   ignoring the terminals costs roughly twice as long.

### Bugs found while building the Floor 2 boss

1. **The HUD crowned the wrong boss.** Reported. `boss_phase_changed` is emitted by every
   boss, and `CombatHUD` answered it with two lines written for The Scrap King — so Runtime
   Error reached its second phase and the player was told "LONG LIVE THE KING // TWO
   CLAIMANTS" over a boss with no claim to the title, followed by "THE KING REASSEMBLES" over
   one that does not reassemble. Nothing failed and nothing errored; the HUD simply said the
   wrong thing, which is the whole difficulty of the class. A boss's own words are now
   `FloorConfig.boss_phase_banners`, bound the same way its name and epitaph already were, and
   a boss with nothing to say gets silence — which is the right amount for a fight whose phases
   announce themselves by changing what is on the floor.

   The real fault underneath it was that **`CombatHUD` had no test suite at all.** One line in
   `tests/test_boss.gd` compared two of its constants and that was the entire coverage of the
   thing the player spends the whole run reading. `tests/test_hud.gd` now drives both floors'
   shipped data through a live HUD and reads the label; putting the old hardcoded lines back
   fails it in exactly the two places the bug appeared.

2. **The greybox boss was invisible as a placeholder.** Not a crash, and not caught by
   anything — the stand-in wore The Scrap King's own 32x32 sprite under a blue tint and used
   his 14-pixel hitbox, so the second floor's boss read as the first one recoloured. It has its
   own art and its own body now. Worth recording because the placeholder was *documented* as
   temporary in its own header and still looked finished enough not to prompt the question.

### Bugs found while building Development's second wave of enemies

1. **Nothing in the game has ever flashed when hit.** `HurtFlash` declared
   `@export var target: CanvasItem`, and all eleven scenes that use it assign
   `target = NodePath("../Sprite")` — which is how the editor serialises a node reference, and
   which a hand-authored scene does not carry the extra state to resolve. `target` was
   therefore null on every enemy, both bosses' parts, and the boss terminal. `flash()` returns
   early on a null target, so the failure was total, silent, and old: shooting anything
   produced no hit feedback at all, and the 1246 checks in the suite were all satisfied by a
   component doing nothing.

   The sharpest part is that **this project already knew the rule.** Known limitation 14 has
   said "hand-authored `NodePath` literals do not resolve into exported `Node` properties, so
   text-authored scenes pass node references explicitly" for milestones. `HurtFlash` was the
   one component that did not, and writing the rule down did not catch it. The fix is a
   `NodePath` the component resolves itself, which cannot half-succeed the same way.

   The lesson is the same one the HUD taught: **every check that touched this component
   asserted behaviour it was allowed to skip.** There is now a check that the wiring itself
   resolved, separate from the one that the colour changes and comes back — because a test of
   the second kind alone is satisfied by a dead component twice over.

   Worth noting that this bug was *load-bearing* for the second one below: the tint bug could
   not have been observed by playing, because the code path that would have exposed it never
   ran.

2. **A tinted enemy would have bleached itself the first time it was shot.** Both `HurtFlash`
   and `Enemy.tint_toward` restored `modulate` to pure white rather than to the sprite's own
   colour. That was correct for as long as every enemy that could be shot had an untinted
   sprite, and stopped being correct when Floor 2 started telling Code Runner and Compiler
   apart by tint. Both now interpolate from a resting colour captured at ready, and both leave
   alpha alone so a Pop Up Drone shot mid-fade keeps fading instead of snapping to opaque.

3. **Three tinted borrows of two silhouettes.** Not a bug, but the point at which the existing
   convention broke down. Code Runner and Compiler could each borrow an existing sprite because
   the enemy they borrowed from is not on their floor; three more could not, and Development
   would have shipped a roster where two pairs of enemies differed only in colour. Null
   Pointer, Deadlock, and Recursion have their own sprites in
   [`tools/generate_art.py`](tools/generate_art.py). Recursion's is the one worth looking at:
   it is squares nested inside squares with a visibly different smaller thing at the centre, so
   a player who has never seen one split can still see there is something inside it.


## Known limitations

1. **What playing it taught is not written down.** This entry used to read "nobody has played
   this by hand", and that part is closed: the whole game to date has been played through, end
   to end, several times. The limitation that replaced it is narrower and more annoying.
   Difficulty, pacing, the enemy mix, the bosses, and the economy have now all been *felt*, and
   this document still describes essentially all of them as *reasoned* — every floor's "what
   playing it had to answer" list is a set of questions that has since been asked and whose
   answers live in somebody's head rather than in this file. Nothing in `data/` has been moved
   in response to a run, either, so the tuning is still the tuning that was argued for rather
   than the tuning that was played. The balance suite computes what the numbers mean and
   refuses to let them drift somewhere absurd; it cannot tell you whether the game is fun, and
   it is no substitute for writing down what the person holding the controller thought.
2. **Gamepad support is verified but not played.** A synthesized controller drives every
   binding and every code path from a nonzero device index, which has now caught two real
   blockers. What it cannot tell you is whether a particular controller reports the axes
   Godot's abstraction claims, or whether the deadzones feel right in the hand. Nothing has
   been tried with two pads connected at once, either — the bindings answer any index, but no
   code anywhere distinguishes one controller from another, so a second pad would drive the
   same player rather than a second one.
3. **The builds are unsigned, and two of the four have never been run.** All four targets
   build and the macOS app runs here, but nothing is code-signed or notarised, so macOS and
   Windows will both warn on first launch. The Web build is now the *best* covered of the
   four rather than the worst: Web CI exports it, serves it, and boots it in a real headless
   Chromium on every push, failing on an uncaught exception or a missing pack, and keeps a
   screenshot. What that proves is that it reaches the menu — not that a run plays through
   it, and the audio driver and file system there are still the ones no other check uses.
   **Windows and Linux have not been executed at all.** The one hand-run Windows debug build
   there has been is also the only source of the open audio bug in limitation 17.
4. **The art is generated, not drawn.** Every sprite is an ASCII grid or a few lines of
   Python, which makes it reviewable in a diff and rebuildable from text, and caps how good
   it can get. The environment, the boss, and the upgrade attachments were the three things
   worth the effort this milestone; the enemy and player silhouettes are milestone 5's and
   hold up.
5. **The music is thirteen short loops** — between 10.9 and 30 seconds each. A boss fight still
   outlasts its track several times over. Cloud Operations moved to 48 beats, and both closing
   floors use 64; the seven tracks before Cloud Operations are still only 10.9–20 seconds.
6. **Only three items visibly change the robot.** Spec section 20 asks for sprite changes
   from major items and an eleven-pixel robot has room for about that many before it stops
   being a robot. The other nine still get only a tinted cannon.
7. **The six-floor campaign is authored but not fully qualified by hand.** Help Desk,
   Development, the Data Center, Cloud Operations, Executive Systems and Core Intelligence chain
   to a real finale. `target_floor_count = 6` and `require_complete = true`, so missing content is
   now fatal rather than provisional. The last two floors still need human pacing/readability runs.
   [Floor 4's gate](#floor-4-cloud-operations--built) has been met, with the narrower claim
   written out there: no gameplay path anywhere branches on floor number, and a floor is data —
   but a new *mechanic* is still four files, so "a floor is only a new `.tres`" is true only of
   floors that reuse an idea. Executive Systems and Core Intelligence deliberately synthesize the
   existing room mechanics and boss attack primitives.
8. **Five of spec section 23's twelve game states exist** — main menu, run, paused, game
   over, victory. Settings and the shop are deliberately *not* states: one is a panel over
   whichever screen opened it, the other is a room the player walks into.
9. **No elite modifiers and no risk-and-reward rooms.** Spec sections 15 and 19 both mark
   these optional for the prototype. The generator's `_attach_dead_end` is the hook the rooms
   would use.
10. **Nothing removes an item**, so Corrupted Firmware choices are permanent — and that now
    matters far more than it did when this entry was written. Development ships three items
    with no upside at all, in the full pool, and the player is warned only by an icon and a
    rarity: the pickup banner carries a name and no description, and an item is collected by
    walking over it. Still arguably right for a roguelite, still undecided rather than
    designed, and now the sharpest edge in the game.
11. **All rooms are the same size**, including the boss arena — deliberate, see the
    architecture note, but it does mean the boss fight is a single screen.
12. **Rooms are built from `WallBlock` bodies, not a TileMap.** The 64x64 tile sheets hide
    the repetition far better than a single 16x16 tile did, but there is still no autotiling
    and no variation between rooms.
13. **Physics changes made during physics callbacks must be deferred**, and this project has
    been bitten by it five times. Every site is deferred and commented. Any new code that
    adds a body should assume it is inside a callback until it has checked.
14. **Hand-authored `NodePath` literals do not resolve into exported `Node` properties**, so
    text-authored scenes pass node references explicitly. Writing this down was not enough:
    `HurtFlash` broke the rule for its entire existence and nothing flashed when hit until
    Development's second wave of enemies found it. Components that need a sibling now take a
    `NodePath` and resolve it themselves, and a test asserts the wiring resolved rather than
    only that the behaviour looked right.
15. **The settings list cannot be operated with a mouse.** It is a keyboard and gamepad list —
    up and down choose, left and right adjust — and now that it correctly blocks clicks rather
    than passing them through, a mouse user can open it and click nothing. Escape closes it and
    the hint line along the bottom says so, but a player who reaches for the mouse gets no
    response at all.
16. **Quitting within a second of a sound starting can still print leak warnings at exit**,
    roughly one run in four when quitting during the 1.1-second victory fanfare. The specific
    reported case — a menu button that played a sound and quit on the same frame — is fixed,
    and `AudioManager.stop_all()` is confirmed to run and to find nothing playing. Adding
    prints to that function makes the warning disappear entirely, which places what is left in
    the engine's own teardown ordering rather than in this code. It is noise on stderr after
    the window has closed, and nothing the player can see.
17. **All audio went silent once on Windows, and the cause is unknown.** One report, never
    reproduced, nothing in the console. Every path above the AudioServer's output was measured
    and cleared, which is what leaves the driver as the remaining suspect rather than what
    proves it. What shipped is instrumentation, not a fix: the debug overlay now reports
    playback state and time-since-last-mix, and a watchdog logs once and re-selects the output
    device when no audio has been produced for a second. Listed here so a mitigation is not
    later mistaken for a solution — see
    [The audio went silent once](#the-audio-went-silent-once-and-it-is-not-solved).

---

## Floor 2: Development plan

Spec section 8 calls the next system layer **Development**. It should be a continuous second
floor, not a separate level selected from a menu: taking The Scrap King's reward descends
into Development with the same robot, build, integrity, scrap, shot counter, and run
statistics. The first boss is then a floor boundary; only the second boss can end the run in
victory.

This work begins after the playtest gate below. The Help Desk still has to prove that its
movement, economy, and boss are enjoyable before a second floor compounds them.

### Development's job

The Help Desk teaches the player to react to four readable movement problems. Development
asks them to **predict**. Its shared visual language is the **compile lane**: a row or column
flashes amber, waits long enough to read, then executes in red. The same warning must mean the
same thing when it comes from an enemy or the boss, and every pattern must leave a visible safe
answer.

Start with the Help Desk's ten-room shape — a start, six combat rooms, a treasure room, a
shop, and a boss — because it keeps the generator and economy comparable while the new floor
is proved. If human-paced two-floor runs drag, reduce Development to nine rooms before adding
or removing whole systems.

The presentation should read as an unfinished development lab rather than another Help Desk:
cyan and violet machinery, amber warnings, red execution errors, broken IDE windows, temporary
build scaffolds, and a distinct exploration and boss loop. Rooms stay the existing 26-by-12
tile single-screen arenas. **Built** — see
[Development's look and sound](#developments-look-and-sound), including the one place this
brief and the floor's warning language turned out to contradict each other.

### Encounter curve

Two enemies return and five are new:

| Enemy | Job |
| --- | --- |
| Ticket Bot | Familiar ranged pressure and a stable reference point for the harder floor |
| Pop Up Drone | Re-aiming pressure while the player is also reading floor warnings |
| Code Runner | Strafes across sight lines and fires while moving, forcing sustained tracking |
| Compiler | Paints one row or column, telegraphs it, then sends a fast pulse through the lane |
| Null Pointer | Marks a small patch of floor centred on where the player is standing, then executes it |
| Deadlock | Tethers the player and drains until the line is cut by cover or by distance |
| Recursion | Chases, and returns two smaller, faster copies of itself when killed |

The two combat rooms nearest the start introduce the Code Runner beside Ticket Bots. The
middle distance tier teaches the Compiler in layouts with obvious cover. The deepest combat
rooms may combine both new enemies with Pop Up Drones. Do not add Firewall Nodes to that mix
until playtesting proves that two kinds of area denial remain readable together.

The three later additions each answer a question the original four do not ask, and each is
placed where its answer is legible on first contact:

- **Null Pointer** is the counterpart to the Compiler, not a second copy of it. A Compiler
  lane picks a stripe of the room and asks "is that where you are?", and the answer is
  somewhere else in a large room. This picks the *player* and asks "are you still there?",
  and the answer is one step in any direction. Both are `CompileLane`s, so they compose
  without teaching a second warning language, and neither ever removes the player's escape —
  which is the property that lets two area-denial enemies share a room where the README's
  warning about Firewall Nodes says two others could not. It commits at the moment of marking
  and never re-aims, for the Memory Leech's reason. Its signature room is `dev_cable_trench`,
  whose safe channel between the cable runs is the one place on the floor where standing
  still is genuinely tempting.
- **Deadlock** is the only enemy in the game whose answer is a *place* rather than a
  direction: it converts the obstacles Development's rooms are already full of from scenery
  into the thing you are running towards. It has two answers on purpose — break line of
  sight, or outrange it — because cover alone would make it unfair in the rooms with the
  thinnest pillars and trivial in the ones built around a server ring, and the generator
  cannot promise which room it lands in. Distance is the answer that always exists; cover is
  the answer that is quicker when the room offers it. Its signature room is
  `dev_server_ring`, the only cover on the floor thick enough to break a sight line from any
  direction.
- **Recursion** is the one kill in the game that costs something. Popping it converts one
  slow body at a distance into two quick ones where you were aiming, so *when* to kill it is
  a real decision — which is a question no other enemy on the floor asks. It is one scene and
  one config for the whole family, with `generation` raised on the fragments, so a Recursion
  and its children cannot drift into being two unrelated things and `max_generation` is an
  honest bound rather than a promise about a second file.

Recursion is also the only enemy that touches room-clear counting. `RoomCombat` decrements on
`HealthComponent.died`, so a body that split *after* announcing its own death would drop the
alive count to zero for a frame, unlock the doors, and hand the player a cleared room with two
fragments still chasing them. It splits first and registers the fragments with `RoomCombat`
immediately — before they are added to the tree, which is deferred for `LootSpawner`'s reason —
so the count goes one to three to two and never touches zero.

Nothing here has been played by a person; see [Known limitations](#known-limitations). Two
numbers are worth revisiting first when it is: a Recursion family costs 7.5 integrity to clear
against a Compiler's 6.5, which is defensible as "harder enemy" and is also three kill events
and up to three scrap drops from one spawn point; and the Compiler's telegraph is now shorter
than the boss's, for the reason recorded in `compiler_config.gd`.

The current floor chooses every spawn independently, so weights alone cannot promise that a
teaching room contains the enemy it teaches. Development templates need one or more fixed
signature spawns, or a small encounter-pack equivalent, while their remaining points continue
to draw from the weighted roster.

`RoomTemplate.difficulty` already exists, but templates are currently chosen without regard
to distance from the start. Development should make the first rooms draw from its gentler
templates and reserve the hardest templates and roster combinations for rooms nearer the boss.

### Floor boss: Runtime Error — **built**

Runtime Error is a pattern fight, not a second terminal puzzle. It remains damageable through
all three phases:

1. One compile lane at a time, alternating with aimed spreads.
2. Two staggered lanes, alternating with projectile rings that have visible gaps.
3. Alternating checkerboard execution zones and projectile walls with a traversable opening.

The boss must use the same amber-then-red warning language as the Compiler. Randomly combining
attacks is allowed only after authored combinations prove they cannot erase every safe route.

This now exists, in [`scenes/bosses/runtime_error.gd`](scenes/bosses/runtime_error.gd), and has
replaced the greybox placeholder that stood in for it. Every hazard it paints is a `CompileLane`
— the same class the Compiler enemy uses — so the warning language is shared by construction
rather than by two implementations agreeing on a colour, and its body borrows those same two
colours for its own windup. Its six patterns are authored and strictly alternating within each
phase, which is the conservative half of the rule above; nothing has been played yet that could
license the random combinations.

Where The Scrap King asks the player to notice something, this one asks them to predict, so it
is built as that boss's opposite in the two places the player can feel it:

- **It is honest.** No refund, no damage scaling, no terminals, and no feigned death — a trick
  that works exactly once per player, and a second boss doing it would be a boss they were
  already waiting for. Its bar reports the real pool, falls once, and reaching zero means the
  fight is over. `MergeConflict.get_phase_health_ratio` deliberately lies; `RuntimeError.get_health_ratio`
  deliberately does not.
- **Its phases are derived, not stepped.** A hit large enough to cross two thresholds lands in
  the phase it earned. The Scrap King floors damage at each boundary to protect the feigned
  death; this fight has no trick to protect.

The floor's "always telegraph a reachable safe answer" criterion is what most of
[`tests/test_runtime_error.gd`](tests/test_runtime_error.gd) is for. It is not a property of any
one method — it falls out of the geometry of six patterns — so it is checked the way the player
meets it: run the fight, catch every lane at the moment it executes, and assert there was
somewhere to stand. Both halves of that were confirmed to fail when the boss was deliberately
broken, which is the only evidence that a test measuring fairness is measuring anything.

The checkerboard is the one pattern that is fair by construction rather than by tuning: in a
checkerboard every cell that lights up shares all four of its edges with cells that do not, so
the answer to any board is one step across the nearest boundary, wherever the player happens to
be standing. The parity flips afterwards, so standing still is never the answer twice.

#### A small, moving target

The body is the other half of the fight, and it is built to be hard to hit rather than hard to
survive. Its hitbox is a 7-pixel radius against The Scrap King's 14 — a quarter of the area —
and it never stops sliding from side to side above the player, so a small target is hard to hit
more than once. Those two work together: either alone is answered by settling your aim.

It moves by **sway**, not orbit. An orbit was tried first and does not fit: the arena is 416x192,
a circle wide enough to matter needs more than 192 pixels of height, and clamping one to the room
collapses it onto the player — the opposite of a boss that keeps its distance. A sine along the
horizontal, held at a fixed height above the player, gives constant lateral motion that the
player can learn to lead and has to keep leading, inside a room that shape.

The sprite in [`art/bosses/runtime_error.png`](art/bosses/runtime_error.png) is 20x20 against the
King's 32x32 and is a different *kind* of shape, not a smaller version of the same one: a banded
diamond with two rows slipped sideways and four shards thrown off its faces, hovering, with no
feet and no top. The King is a machine built out of salvage; this is a process that got loose. It
is drawn in neutral greys for the King's reason — the fight tints the body violet and flashes it
amber and red through `modulate`, which multiplies, so any colour baked into the sprite would
fight the warning language the whole fight runs on. The shards are the one honest way for a
silhouette to be bigger than its hitbox: they are visibly detached, so nothing the player reads
as the body is outside what they can hit.

**It has been played, and none of its numbers moved afterwards** — see [Known
limitations](#known-limitations). The numbers in
[`data/bosses/runtime_error.tres`](data/bosses/runtime_error.tres) are still the reasoned ones
rather than observed ones, so what follows is the argument for them and not a report on how they
played. The pool is 110, which is 27.5 seconds of *perfect* starting-weapon fire — the
least meaningful number about this boss, and the reason it is not the 150 it started at. Perfect
fire assumes a target that can be hit at will, and this one is a quarter of the King's area,
moving; the pool came down because the missing went up. `tests/test_balance.gd` still holds it
against the first boss's pool, since a second floor's boss being *shorter* than the first on
identical damage would be a difficulty curve running backwards. Whether the fight is *fun* is not
something any of this can tell you.

### Six new items

Floor 1 could reserve nine unique item ids before it ended: two shop offers, three combat
rewards, one treasure reward, and three boss choices. Only three of the current twelve remained
unseen. Both halves of that arithmetic have since moved — see
[One pool, fewer handouts](#one-pool-fewer-handouts).
Development's planned two combat rewards, two shop offers, treasure reward, and three boss
choices need eight unseen items. Five additions are the mathematical minimum; six leave one
spare rather than balancing the final reward on an exact-capacity edge.

| Item | Effect |
| --- | --- |
| Memory Spike | Adds one projectile pierce; the behaviour already exists |
| Core Dump | Makes projectile impacts explode; the behaviour already exists |
| Cold Cache | Repeated hits chill, then briefly freeze the target |
| Hot Reload | Every fifth shot applies burning |
| Breakpoint | Dashing emits a short slowing pulse |
| Stack Overflow | Corrupted: larger, harder-hitting projectiles travel more slowly |

**All six are built, plus three more.** Cold Cache and Hot Reload were the reason to implement
the small status system implied by `ProjectileConfig.status_effects`, and it now exists as
[`StatusEffectController`](scripts/components/status_effect_controller.gd).

Both of the constraints above are load-bearing and both are asserted. Statuses **compose**:
each effect is tracked independently and the movement penalty is the *product* across them, so
a chilled and burning enemy is both and neither item cancels the other. That requirement also
decided the mechanism — `projectile_add` now appends to array fields, because reaching
`status_effects` through `projectile_set` would have looked identical in a `.tres` and silently
kept only whichever item the stack reached last. Boss resistance **shortens** rather than
nullifies: boss parts carry `control_resistance = 0.65`, so an 0.8s freeze becomes 0.28s,
floored at `MIN_CONTROL_SECONDS` so even total resistance leaves a real window. Burn is
deliberately not resisted, because shortening a burn and shortening a freeze are not the same
promise.

Two things worth recording that the plan did not anticipate:

- **Cold Cache needed a freeze immunity window.** It chills on every hit and the starting
  weapon fires four times a second, so four hits is a freeze and the fourth arrives about a
  second after the first. Without a lockout the item does not make a build, it removes a
  target from the fight permanently. Chill still lands during the window, so the item keeps
  working; only the loop is broken.
- **`spawn_copy()` was sharing its status array.** `duplicate()` is shallow, and items append
  to `status_effects`, so the weapon's own resource would have grown by an entry per shot for
  the rest of the run — a Cold Cache build stacking dozens of chills within a room, with the
  source `.tres` on disk staying innocent. Only `status_effects` is re-created; deep-duplicating
  the resource would also clone the texture sixty times a second.

### Three items that are purely a cost

| Item | Effect |
| --- | --- |
| Blocking I/O | The weapon will not fire while the robot is moving |
| Tech Debt | Every room cleared permanently toughens every enemy, compounding |
| Legacy Runtime | Dash cooldown tripled, one charge gone |

These are the first items in the pool with **no upside whatsoever**. Everything else that costs
the player something buys them something: Unsafe Overclock trades integrity for damage, Stack
Overflow trades speed for size. These trade nothing, and they sit in the *full* pool — shop
stands and boss choices included. An offer the player should refuse is what makes the offers
they accept a decision.

Three consequences that follow from the delivery model and are worth knowing before playtesting:

- **Nothing warns the player.** Items are collected by walking over them, the pickup banner
  carries a name and no description, and nothing removes an item. Rarity, category, and a red
  icon with no bright core are the entire signal. This is deliberate but it is the sharpest
  edge in the game, and it is the first thing to revisit if the floor reads as unfair rather
  than as hostile.
- **A boss choice of one-of-three containing one of these is effectively one-of-two.**
- **Legacy Runtime's charge penalty is floored at one.** Base dash charges are one, so a naive
  −1 leaves a robot that can never dash — a different game, not a harder one. It therefore
  costs a Backup Battery its charge and otherwise costs nothing, and the tripled cooldown is
  where the item does its real damage.

Tech Debt accrues into `RunManager.enemy_health_scale` rather than being asked of the inventory
at spawn time, because the debt has to outlive the room it was incurred in; recomputing from
"rooms cleared so far" would silently backdate the whole bill onto a player who picked it up
late. It is not applied to bosses — a boss pool is tuned to the minute, and compounding it with
a penalty accepted eight rooms earlier would end runs at the door rather than in the fight.

Legacy Runtime also forced a fix worth noting: dash charges were the one aggregate applied
*incrementally* on pickup, which contradicted the recompute-from-the-whole-inventory rule
`Player._apply_item_stats` states in its own doc comment. An incremental applier cannot express
a negative safely, so `add_charges` became `set_bonus_charges`.

Development drops items on combat clears two and five, grants one treasure item, uses the same
learned shop prices, and ends with three boss choices. Tune its scrap income before introducing
floor-specific inflation: a common item should not silently cost more because the elevator went
down one level. The Help Desk now uses that same cadence — see
[One pool, fewer handouts](#one-pool-fewer-handouts) for why it stopped being more generous
than the floor after it.

### One pool, fewer handouts

Two things about item distribution were wrong once Development shipped its nine, and both were
found by playing rather than by any check here.

**The pool was per floor, so Development's items only ever dropped on Development.** The Help
Desk listed the original twelve and nothing else, which meant half the game's items were
invisible for the whole first floor and no run could ever find Cold Cache early enough to build
around it. There is now one [`ItemPool`](scripts/resources/item_pool.gd) at
[`data/pools/run_item_pool.tres`](data/pools/run_item_pool.tres) holding all twenty-one, and both
floors point at it — so any item can drop on any level, and adding item twenty-two is a one-file
edit rather than two lists that can drift. `RunManager.offered_item_ids` still prevents repeats
and is still run-scoped, which is the only reason sharing a pool between floors is coherent at
all: the pool is what *exists*, the offered list is what has been *spent*, and the spend list
already spanned floors.

**The player arrived on Development too strong.** The Help Desk was handing out three
combat-clear items against Development's two, which is a difficulty curve running backwards —
the first floor should not be the generous one. Floor 1's `item_clear_indices` is now `[2, 5]`,
matching Development's. In practice a Help Desk run goes from about six acquired items to about
five: two clear rewards, one treasure, one boss choice, and whatever the shop can be afforded.

If that is still too fast, `item_clear_indices` is the one line to change, and dropping floor 1
to `[3]` takes it to four.

### Either boss, either floor

Boss identity — the scene, the name, the defeat banner, the phase banners — moved off
`FloorConfig` into a [`BossEncounter`](scripts/resources/boss_encounter.gd), and each floor now
carries a *pool* of them. Both of these two floors list both of these two bosses, so a run may meet
The Scrap King in Development and Runtime Error on the Help Desk. The Data Center was held out of
this at first, so that Cascade Failure guarded its own floor only; that restriction was lifted when
the floor shipped and all three floors now draw from all three bosses — see [any floor, any
boss](#any-floor-any-boss) for what reversed it.

Bundling the four fields was not tidiness. Four parallel fields cannot be shuffled together, and
the failure mode of getting it wrong is precisely the bug this project already shipped once: the
HUD announcing "LONG LIVE THE KING" over a boss with no claim to the title. A floor now draws
*a boss*, not four values it has to keep in step.

The draw is a shuffle rather than two independent rolls. `RunManager.fought_boss_ids` is
run-scoped for the same reason `offered_item_ids` is — a floor cannot see what the previous floor
drew — so with two bosses and two floors, whichever the first floor takes, the second is left
with the other. It is drawn inside `build()` from the floor's own seed rather than when the
player reaches the arena, so one `--seed` still reproduces the whole run; drawing on arrival
would make the boss depend on how the RNG had been consumed getting there. Across 200 runs the
split is roughly 55/45 and no run ever fought the same boss twice, and the no-repeat rule was
confirmed to fail when deliberately broken.

**This is a real difficulty swing, and the pools have not moved since it was played.** Runs
since have drawn it both ways round; nothing in this document records whether the swing was
felt, which is exactly the gap [limitation 1](#known-limitations) is about. Runtime Error's pool is 110
against The Scrap King's 60, so about half of all runs now open with the longer fight against a
starting build and no items, and close with the shorter one against a full build. Worse for
readability: Runtime Error is a compile-lane fight, and the Compiler that teaches that language
is a Development enemy — on a Help Desk draw the player meets the boss's amber-then-red warnings
having never seen them before. The honest options if that reads badly are to teach the lane
earlier, to tune the two pools closer together, or to weight the draw rather than leave it even.
`tests/test_balance.gd` records the reasoning beside the assertion.

### Development's look and sound

A floor's presentation is a [`FloorTheme`](scripts/resources/floor_theme.gd) — two tile sheets
and two music ids — hung off `FloorConfig`. Split out rather than added as four more fields for
the reason `FloorConfig` exists at all: a floor's content and a floor's look are edited at
different times, and a theme is the half a later floor could reuse wholesale. Both floors carry
one explicitly; a null theme falls back to the authored textures and the shared tracks, which
is what keeps every test arena from needing a look before it needs one.

**The art.** `art/environments/dev_floor.png` and `dev_wall.png`, same 64x64 sheet
construction as the Help Desk's — sixteen different 16x16 panels, so the repeat period is four
tiles rather than one. The two floors are told apart by *shape* as much as by colour, so a
colour-blind player still knows where they are: the Help Desk's panels are closed and finished
(rivets, louvres, sealed conduit), Development's are open and unfinished (a broken IDE window
with its own title bar and one line gone red, a diagonal scaffold brace, a server rack with its
front off).

One of those panels was a real bug before it was a style question. The floor's hazard-tape
panel was drawn in **amber** first, which is correct for a work-in-progress lab and wrong for
this game: amber on this floor means "a compile lane is about to execute here", from the
Compiler, from Runtime Error, and from the Null Pointer. Permanent amber stripes painted across
the ground the lanes are drawn on would teach the player to ignore the one colour their
survival depends on reading. The tape is drawn in the floor's own dim ramp instead.

**The music.** `dev_explore` and `dev_boss`, and both are still in A minor like every other
track — the crossfade rule in `AudioManager.MUSIC_LIBRARY` is what makes descending a floor
mid-phrase sound like the game changing its mind rather than a track ending. What makes them a
different floor is everything except the key: the explore loop runs a sixteenth-note arpeggio
underneath like a progress bar, keeps landing on the flat second, and puts the bass on the
offbeat; the boss loop is built on a chromatic descent, A - G# - G - F#, because Runtime Error
does not get angrier, it degrades.

**The seam.** `FeedbackDirector` still decides *when* the music changes — boss arena gets the
boss loop, everywhere else gets the explore loop — and the theme decides only *which* two
tracks those are. That split is the point: adding a floor with its own soundtrack must not mean
adding a branch to the director, and the director naming `dev_explore` would be exactly the
content knowledge it exists not to have.

The theme is announced by `FloorController.floor_theme_changed`, emitted at the *top* of
`build()` rather than through the existing `floor_advanced`. That is not tidiness. `build()`
places the player in the start room, which emits `room_entered`, which starts the music — so a
theme applied after the build plays the previous floor's explore loop over the new floor's
opening room and only corrects itself at the next door.

Both halves were confirmed to fail when deliberately broken: walls ignoring the theme, and the
director reverting to its hardcoded track ids. A test that cannot fail is not evidence.

### The multi-floor seam

Build the transition before building Development content. A small run-level owner holds the
ordered `FloorConfig` resources; one `FloorController` builds one injected floor and emits
`floor_completed`, while the run owner decides whether to descend or win. `FloorConfig` gains
the boss scene and floor theme, and boss identity becomes data consumed by the HUD instead of
`CombatHUD.BOSS_NAME`, which is the literal string `THE SCRAP KING` kept in step with the
resource's `display_name` by a test rather than by a reference.

The same `Player` node crosses the boundary. Integrity, inventory, scrap, shared shot count,
offered item ids, and statistics survive; dash charges refill, and Development's start room
provides one guaranteed repair cell rather than a free full heal. The old floor, its pickups,
and its projectiles must be gone before the next floor becomes active, so there is never more
than one projectile container or one room graph in the tree. The minimap and
`FloorController._clears` reset; cumulative `RunManager.rooms_cleared` and run statistics do
not, so the HUD and final summary still describe the whole run.

**Each floor announces itself.** `CombatHUD.announce_floor` puts `LEVEL 1` or `LEVEL 2` up as a
banner, called from `main.gd` at startup and again on every descent — which are the only two ways
a floor ever begins. The number and not the name, deliberately: the floor's *name* is already in
the persistent strip along the bottom of the screen, and a banner repeating it would be the only
one in the game telling the player something they were already looking at. It is transient like
every other banner, because the standing answer to "where am I" is the strip, and a permanent
announcement would cover playable floor for the rest of the run.

Derive a deterministic seed for each floor from the run seed so one `--seed` reproduces the
whole run. Prove this seam first by configuring Help Desk twice. A repeated floor is ugly but
diagnostically clean: if the transition fails, no new enemy, boss, item, or texture can be the
reason.

### Delivery order

1. Play several complete Help Desk runs with a controller and record duration, damage, shop
   decisions, boss comprehension, and common builds. Tune from those observations.
2. Restore a trustworthy automated baseline: remove the doorway test's formatting errors,
   give the runner a real watchdog, and isolate save-test paths so parallel runs cannot collide.
3. Build the two-floor spine and pass Help Desk into Help Desk without losing run state or
   entering victory after the first boss.
4. Add a Development greybox: its floor resource, four combat templates, returning enemies,
   placeholder Runtime Error, and a developer-only direct-start path.
5. Add the Code Runner, Compiler, compile lanes, finished boss, six items, status effects,
   environment art, and music. **Done.** The Code Runner, the Compiler, compile lanes, and the
   finished boss, plus three more enemies (Null Pointer, Deadlock, Recursion), nine items
   rather than six, the status system those items were the reason for, and Development's own
   tile sheets and soundtrack — see [Development's look and sound](#developments-look-and-sound).
6. Play full two-floor runs with keyboard and controller, tune against the carried Help Desk
   build rather than a fresh debug character, then verify the exported builds.

### Acceptance criteria

- The first boss reward advances the run; only the *last floor's* boss reward produces victory.
  Written as Runtime Error's originally, which stopped being the same statement once either boss
  could guard either floor — what ends the run is the floor, not which boss was drawn onto it.
- The exact same player reaches Development with the same integrity, items, scrap, shot count,
  and accumulated statistics.
- One run seed reproduces both layouts, and each floor passes the structural sweep across at
  least 120 seeds.
- Combat difficulty rises with distance from the start instead of being random room to room.
- The item pool can always fill every planned offer, including the final three choices.
- The floor name, minimap, room theme, music, boss name, boss bar, and
  `FloorController._clears` change or reset at the transition; the HUD's run-wide room total
  remains cumulative.
- Compile lanes and boss patterns always telegraph a reachable safe answer.
- Restarting or dying on Development files one result and begins the next run on Help Desk.
- The complete run works in exported builds with both keyboard and controller.

Elite modifiers, challenge and secret rooms, larger arenas, a new weapon core, meta-progression,
and additional playable characters are deliberately outside this floor. They can follow once
Development proves that the run can grow without weakening the room combat already present.

---

## Floor 3: Data Center — **built**

The third floor is in the campaign. `main_campaign.tres` lists Help Desk, Development and
[Data Center](data/floors/floor_3_data_center.tres), and a run now plays all three.

### The Data Center's job

[`SIX_FLOOR_SCALING_GAMEPLAN.md`](SIX_FLOOR_SCALING_GAMEPLAN.md) calls this the
"architecture-proving vertical slice", and the emphasis is on *proving* rather than on the floor.
Two floors produce one transition, and one transition cannot show a trend — a leak, a stale room,
a run field carried the wrong way. Three floors produce two, which is the smallest number that can.
So the content below matters, and what matters as much is that adding it needed no new branch
anywhere in the generator, the controller, or the session: a floor is still a `FloorConfig`, a set
of templates, a roster, and a boss pool.

Its one taught idea is **stop camping**, and every piece of the floor says it again in a different
register.

### The signature mechanic: throughput zones

A [`ThermalZone`](scripts/combat/thermal_zone.gd) is a patch of floor that gains heat while the
player is *standing on it*, loses it the moment they step off, and vents at full heat for one point
of integrity. The zone is painted on the ground as a grille of louvre bars and its heat is
their colour, teal through indigo to a hard magenta. Nothing about it is random and nothing is
hidden.

The look is a deliberate separation from the floor above, and it was earned the embarrassing way —
by a player reporting that floor 3's boss and floor 2's boss threw the same attack. They do not, but
both ramps ended in red a beat before they bit, and the one the player meets at speed is the second.
A ramp is only worth reading if it is the only thing that looks like it. So this floor's ends in
violet, which is also what the fiction wanted: amber-to-red is fire, and nothing here is on fire — a
rack out of thermal headroom arcs. And the shape moved with the colour, because a hue difference
alone is one bad screen or one colourblind player away from not existing: `CompileLane` is a flat
filled rectangle, a thermal zone is a grille. Two hazards that mean different things now differ
twice.

What it charges for is the whole design, and it took a revision to get right. Heat used to accrue
only while the player was inside a zone *and* firing *and* holding still, which named the habit the
floor meant to tax with real precision and played badly for it: a hazard with three conditions on it
is a hazard nobody can state, so nobody learned it. Players watched a zone climb, step off, come
back, hold a firing position at a slightly different speed, and see nothing happen. Now a zone
charges for its ground and nothing else — stand on it and it heats, whatever you are doing.

What stays out of it is the weapon. Heat per shot would make a fast weapon heat a zone faster, which
quietly turns Cooling Fan and Unsafe Overclock into liabilities on one floor of six — and an item
that is a liability on a floor is an item nobody picks. Occupancy taxes a *position*, and every
build pays for a position identically. It also stops the floor quarrelling with items that ask the
player to hold still, which under the old rule were asking for exactly what the floor charged for.

The floor still teaches movement, and now teaches it to every player rather than only to the ones
who had stopped to shoot. `SECONDS_TO_VENT` is sized against walking speed instead of fire rate: a
second and a half is 240 pixels, wider than any zone on the floor, so crossing a grille is always
affordable and stopping on one never is.
[`tests/test_thermal.gd`](tests/test_thermal.gd) asserts all of it directly — that firing and moving
change the heat by nothing at all, and that walking across the widest authored zone never vents it —
so both the "simplification" to per-shot heat and a ramp shortened past the point of passability
fail named checks rather than passing review.

Zones are declared on `RoomTemplate` in tile coordinates, so a Data Center template carries its own
and a Help Desk template has none, with no `if floor_number == 3` anywhere.

### The second mechanic: cable ducts

A [`CableDuct`](scenes/rooms/cable_duct.gd) is level geometry the robot cannot drive over and shots
go straight across.

Every obstacle in the game until now was a `WallBlock`: it stops the player, it stops the enemy, and
it stops the bullet, so the answer to all of them is the same — go round, and while you are going
round nobody can hurt anybody. A room built out of walls is a room where cover and pathing are the
same object. A duct splits them, and what is left is a room the player has to *route* through while
being shot at from ground they can already see. That is this floor's question — where are you
standing — asked by the architecture rather than by a hazard.

The whole mechanic is a difference between two collision masks. Bodies mask `Teams.body_mask()`,
which is the world layer plus the duct layer; `Projectile`, `Enemy.has_line_of_sight` and Firewall
Node's beams all trace against `Teams.LAYER_WORLD` alone and were already written that way. The loot
spawner and the Pop Up Drone ask the same question the bodies do, because "is this floor a robot
could stand on" is their question too — a repair cell dropped into a duct is a repair cell nobody
can pick up.

It earns its place on this floor in particular because of what stands in these rooms. The Load
Balancer is answered by getting inside about a hundred pixels and circling it, and a duct decides
which way round is available. The Stale Replica walks the route the player walked, so a route
through ducts comes back at them along a line they picked. Neither needed a line of code for either;
both fall out of the ground having a shape.

Drawn deliberately unlike the three things it is always seen beside, and each in a different
register, because one register is not enough to carry a difference this important: lighter than the
floor where the wall is darker, one unbroken lit face where a wall panel is a grid of boxes, and
carrying dots rather than stripes because stripes are what a throughput zone is made of. It was
drawn with cable runs down it first and beside a zone the two read as the same kind of thing, which
is the one mistake here that actually matters.

`tests/test_floor.gd` asserts both halves against a wall block standing beside it in the same arena:
a duct that has quietly become a wall fails one check, a duct that has quietly become scenery fails
the other, and the wall's own two say the arena is wired up rather than the queries silently missing
everything. A second check flood-fills every template in the campaign, because a duct is the one
piece of geometry that can seal a robot into a room while looking like open floor.

### The Data Center's seven combat rooms

The floor shipped with four, and [what playing it answered](#floor-3-was-the-emptiest-floor-in-the-game)
has the measurements that said that was too few. The three new ones are all built on ducts:

- **`data_busway`** — two staggered busways run almost the room's full width, so crossing from top to
  bottom means going round the end of one and then the far end of the other, while everything in the
  room has been shooting at you the whole time. The zones sit on the two turns: running them is free,
  stopping in one to return fire is not.
- **`data_hot_containment`** — two rack rows sealing a two-tile lane with a Firewall Node standing on
  the one cold plate in the middle of it, sweeping the length. The rows are solid, so there is no
  shooting it through them; the room has exactly one answer and it is a good one — stand at a mouth
  of the aisle, where the floor is cold, and fight down it.
- **`data_tape_library`** — a lattice of shuttle rails and no cover at all. Everything can see
  everything from the moment the door shuts and almost nothing can go straight at anything. It is
  `data_grid_floor` inside out: that room removes cover so the only question is where you stand,
  this one removes cover so the only question is how you get there.

### Two new enemies

The roster is curated rather than cumulative — six entries against Development's seven, chosen
because each asks a question about *where the player is standing*. Memory Leech, Recursion and
Deadlock are all left out for the same reason: their answers are about timing, and a floor teaching
a positional idea should not spend half its rooms asking something else. Two are new.

**[Load Balancer](scenes/enemies/load_balancer.gd)** puts a plate between itself and you, and the
plate turns. Shots arriving through it are swallowed whole; shots arriving anywhere else are
ordinary hits. It is the only enemy in the game whose answer is decided by *where you are* rather
than by *when you fire* — and the fight is one comparison the player can feel without being told
it: their own angular speed, `v / r`, against the plate's fixed turn rate. That rises as they close,
so the answer is to get inside about a hundred pixels and keep going round, and the price of being
that close is that the plate is also the only part of it that hurts to touch. Its armour and its ram
are one object pointing one way, and both are read off the same arc.

It has no weapon, and that is deliberate: an enemy answerable by planting your feet and out-damaging
it would be an enemy arguing with the floor it is standing on. A player who never moves does nothing
to it at all, however good their aim.

Its one weakness from in front is not damage. `Projectile` applies status effects to the body it hit
rather than through `apply_damage`, so a chill lands on the plate even though the shot does not —
and the plate's turn is scaled by that chill. Slowing the thing you are trying to out-turn is a real
answer, it costs an item to have, and nothing had to be written for it: it falls out of two systems
already behaving as they do.

**[Stale Replica](scenes/enemies/stale_replica.gd)** chases where the player *was*, and gets there
by retracing the exact route they took. It cannot be dodged, because it is not coming at you; it can
only be outrun, and only forwards. Keep going and it never arrives. Stop, and the position it is
walking to catches up with the one you are standing in. Turn back, and you walk into it.

It needs no navigation of any kind, and that is not an optimisation — it is why the design works.
Every point on its path is a point the player has already walked, so it is clear of walls and inside
the room by construction. The Data Center's rooms are the most cluttered in the game and it needed
nothing for them. It is also the only enemy in the game fought over the shoulder: it is behind you
by definition, so shooting it means running one way and firing the other.

### Floor boss: Cascade Failure

[`scenes/bosses/cascade_failure.gd`](scenes/bosses/cascade_failure.gd). Four server nodes wired into
one rack, running too hot.

The Scrap King asks the player to **notice**; Runtime Error asks them to **predict**; this one asks
them to **keep moving**, in the floor's own words. Every hazard it puts on the ground is a
`ThermalZone` — the same class the floor's rooms are built from — so the colour ramp means here
exactly what it has meant for nine rooms. What changes is who is heating it.

**Load is the whole fight.** The rack carries a fixed amount of it split between the nodes still
standing, so `load` is `node_count / nodes_alive`: one at the start, four at the end. It drives how
fast the ring turns, how fast the packets run, and how often each node vents. One other clock
escalates — the one that aims at the player — and it counts nodes lost rather than following load.

The vent rate is the part worth stating, because it is what keeps the last phase survivable. Per
node the interval is `vent_interval / load`, so four nodes venting every three seconds and one node
venting every 0.75 put the *same* heat per second onto the floor. The boss does not out-scale the
arena as it escalates; it **concentrates**, from a ring of patches into a trail behind one body.
That is arithmetic rather than tuning, and
[`tests/test_cascade_failure.gd`](tests/test_cascade_failure.gd) measures it by counting vents in
real time at both loads rather than by re-deriving the division.

**The rack breathes.** The ring contracts to a third of its radius and opens out again on a
seven-second sine. Without it the middle of the arena is permanently safe, and a boss with a safe
centre — on the floor about not standing still — would be arguing with the room it is standing in.
The fiction does the work: this is cooling equipment, and what cooling equipment does is move air.

**Heat comes from three places.** The rack vents where its bodies are. It also **aims** — a patch
centred on wherever the robot is standing — and it **leads**, a patch centred on where the robot
will be in six tenths of a second if it does not turn.

The first of those is what makes the fight's own sentence true, and for a while it was not. "Keep
moving" was the stated job and heat only ever landed on the ring, so a player who found a patch of
floor the ellipse did not sweep could stand in it and shoot: the boss about not standing still had a
place to stand. The aimed vent takes that away everywhere in the room, and takes it away the way
this floor takes things — by painting the ground and counting down, never by landing a hit that
could not have been walked out of.

The lead vent takes away the answer the aimed one leaves open, which is the easier of the two to
find. Heat centred on the robot is always *behind* a robot that is moving, so "keep moving" was
satisfied by picking a heading and holding it — a straight line, requiring no reading at all. The
two clocks are now a pincer with one counter: the aimed patch charges for stopping, the lead patch
charges for holding a heading, and only a turn answers both.

**This replaced a scatter**, a patch at a uniformly random point in the arena, whose stated job was
closing the corners a 416x192 room has and the ellipse cannot reach. The lead vent inherits that job
and does it for a reason rather than by covering enough of the room to eventually include them: a
player walking out wide to a cold corner has a heading pointed at that corner, so the patch that
leads them is already there when they arrive. Nothing in the fight is random now, which is the
property the rest of it already had.

Neither is divided by load, and that is the point. The whole escalation here is the rack
concentrating what it already had, so two sources that quadrupled alongside it would make the last
phase a different and worse fight. Flat clocks keep the vent-rate arithmetic above true of the
*arena* rather than only of the nodes, and the suite still measures it by counting every vent from
every source at both loads.

**The aimed clock does step up, once per node.** It walks from three seconds to two by an even step
each time a node blows out — 3, 2.67, 2.33, 2 — and takes the step at the failure rather than at its
next vent. A failure is the loudest event in this fight, and it used to change nothing about the
pressure on the player's own feet: the ring came in faster and smaller, and the clock aiming at the
robot ran on exactly as it had, so every phase the player earned arrived with the same private
rhythm underneath it. The size of the step is what keeps it fair — a third off the interval is a
pace a player can feel, while the factor of four that load would have applied is a different fight —
the floor under it is the fill. The gap between the aimed clock and `vent_seconds` is how long the
ground the robot stands on is cold, so an interval at or under 1.6 seconds would leave none of it,
and *keep moving* would stop being a rhythm and become the only input.

The suite measures the ramp the way it measures everything else here: it parks the robot in a corner
the ellipse cannot reach and counts the patches that land on it, with the whole rack up and again
two failures later. It deliberately does not measure at one node left — there the last node walks
onto a stopped robot and lays its own trail across it, so the covered count quintuples whether the
ramp exists or not.

**There is not one projectile in it.** Both bosses before it are answered by dodging bullets; this
floor's mechanic is positional, so its boss is positional. Heat on the ground, load running along the
lines between the nodes, and the nodes themselves, which cost a point to stand inside like every
other body in the game. Everything that can hurt the player here is a place.

#### Why the nodes have no health of their own

They visibly can be shot and they visibly fail one at a time, so per-node pools are the obvious
build, and they are wrong. Damage would then be the player's to allocate, and allocating it
optimally means spreading it evenly — which holds the fight at load one for three quarters of its
length and then collapses phases two and three into a few seconds each. A boss whose best line skips
its own last act has been designed twice and shipped once.

So the pool is shared and a node blows out at each even fraction of it: 75%, 50%, 25%. Every player
sees all three phases at the same length. What the player *does* choose is **which** node fails — the
one that has taken the most damage since the last failure goes — so they decide the shape of the ring
they are left fighting without deciding how long they fight it. Two nodes left on opposite slots is a
line that sweeps the whole arena; two on adjacent slots is a short one near the wall. That is a real
decision, and it is about geometry rather than about pacing, which is the half worth giving away.

#### Any floor, any boss

All three floors draw from all three bosses. That reverses an earlier decision to keep Cascade
Failure to the Data Center, on the reasoning that a player meeting its vents before nine rooms of
throughput zones would be meeting an unexplained mechanic in the worst room to meet one in.

The fight does not bear that out. Every hazard it puts down is a `ThermalZone` that starts cold and
climbs visibly for 1.6 seconds before it bites — a telegraph read on its own terms at any depth. The Data Center teaches the ramp *faster*, not first. What the lock cost, and
charged every run, was a campaign whose final fight never changed.

The reverse direction was simply never listed: The Scrap King and Runtime Error are answered with
skills the game teaches in its first room, so nothing stopped them guarding floor 3. They arrive
there in a room the other floors do not have — `data_core_arena` keeps its four corner zones, so the
King's terminals stand in ground that charges the player for standing on it, and Runtime Error's
lanes sweep a cold-centred floor.

`CampaignValidator`'s boss supply is no longer exactly tight — any dealing of three bosses to three
floors works — which is what a pool is for. A fourth floor is now a fourth boss rather than a
re-plumbing of the first three.

The change moves what a seed produces, so `RunDefinition.content_version` went to 2 with it and
in-flight checkpoints from version 1 are refused rather than resumed.

#### What survives its death

The rule every fight in this game draws: **committed hazards resolve, uncommitted ones never
happen.** A vent already on the floor was put there, is visibly climbing, and goes on to fill and to
cost a point in an arena the player has apparently just won. A packet is not committed and stops
existing the moment the rack does — a packet *is* load moving between two nodes, and there are no
nodes.

Getting the first half right needed a change: a `ThermalZone` was, until this floor, a room's
furniture, built with the room and freed with it. `ThermalZone.spawn_vent` parents into the session
the way `CompileLane` always has, so a boss's heat outlives the boss and not the floor.

### The gate

[`tests/test_gate.gd`](tests/test_gate.gd) is the plan's Floor 3 acceptance list, as a suite, run
against the **shipped** campaign rather than a greybox one — which is the difference between it and
the parts of `tests/test_floor.gd` it overlaps with. Those use a synthetic campaign so malformed
destinations and lifecycle faults can be injected without touching shipped data; this asks the same
questions of the content a player will actually be handed.

Four of the five criteria were checkable as written. The third — "both transitions preserve every
declared run-wide field and reset every declared floor-local field" — was not, because nothing had
declared them. `RunManager` now carries three lists:

- `RUN_WIDE_FIELDS`, which a descent must leave exactly as it found them.
- `RUN_LEDGER_FIELDS`, which it may append to and must never lose an entry from. Opening a floor
  draws its boss and reserves the items it will offer, so both of these are longer on the other side
  of a boundary. A rule demanding they come out untouched would be a rule the game breaks on every
  descent, and a rule broken on purpose stops being checked.
- `FLOOR_LOCAL_FIELDS`, which it must replace with the floor being entered.

The suite asserts that those three between them account for every script variable on the node, so a
field added without a decision fails the gate rather than surfacing three floors later as a run that
lost its scrap. That check was confirmed to fail when a stray field was added to `RunManager`, which
is the only evidence that a completeness check is checking anything.

The floor-local half is asserted against what the campaign says the values should be, not merely
against "something changed" — a boundary that reset the floor seed to zero would satisfy the weaker
version. The fourth criterion is counted at the only place a result is actually filed,
`BestRunStats.absorb`, rather than at a state change that happens to precede it: two of its five
paths are supposed to file *nothing*, and a check watching for game-over could not tell filing
nothing from filing twice.

### What playing it had to answer

Every number here was reasoned rather than observed when it was written. The floor has been played
several times since, and no number below has moved and no question below has been answered in
writing — they are reproduced as they were asked, and answering them from the runs that have
happened is the write-up [Next recommended task](#next-recommended-task) is asking for.

- Is the plate readable as armour, or does a Load Balancer read as an enemy your weapon has stopped
  working on? The only feedback a blocked shot gives is the plate lighting for 0.14s, because
  nothing was damaged and so no hurt flash fires.
- Is out-turning it discoverable without being told? The breakeven radius is about 105 pixels and
  nothing on screen says so.
- Does the Stale Replica read as "your own path" or as a chaser with broken steering?
- Is Cascade Failure's breathing ring legible at 416x192, or is a rotating quadrilateral that also
  pulses simply too much to track?
- Is a boss with no projectiles in it tense or slack?
- Is 144 the right pool? It is 36 seconds of *perfect* starting-weapon fire, which nobody will have,
  against Runtime Error's 110 and The Scrap King's 60.

---

## Floor 4: Cloud Operations — **built**

A hyperscale hall: sealed concrete, painted aisle markings, and rows of blades that go on past the
edge of the room. Ten rooms, seven combat templates, a curated six-enemy roster, and a boss that
cannot be killed by being shot at.

### Cloud Operations' job

The gameplan calls this floor the **content-pipeline proof**, and its gate is not about content at
all:

> No `if floor_number == 4` gameplay path is required.

Floors 2 and 3 each proved a floor could be *authored*. This is the first that tests whether one can
be authored without reaching into the engine — which is the claim the remaining two floors are
budgeted against, and the claim the README had been making since `FloorConfig` existed without ever
having been made to hold.

It holds, and the honest version of that is narrower than the slogan. **A floor is data. A new
mechanic is not.** Adding migration pads took four files — the mechanic, a field on `RoomTemplate`, a
`_build_pads` in `Room`, and a resource — and then every one of the ten rooms, the roster, the theme,
the boss's eligibility, and the campaign entry was a `.tres`. What is *not* in any of it is a branch
on which floor is being played. The generator, the room, the enemies, and all four bosses read
nothing about floor number; a Data Center template leaves `pad_links` empty and gets no pads, and a
Help Desk arena that has never heard of one can still host this floor's boss.

That is the property, and it was cheaper to have from the first floor that needed it than to
retrofit. `RoomTemplate.thermal_zones` said so a floor early:

> That is the property Floor 4 of the plan exists to prove, and it was cheaper to have from the
> first floor that needed it than to retrofit later.

### The signature mechanic: migration pads

Two patches of floor that are the same place. Step onto either end of a link and the robot is
standing on the other.

Every floor before this answers *where are you standing* by changing what the ground costs — a
`CompileLane` denies a stripe of it, a `ThermalZone` charges for standing on it, a `CableDuct`
decides which way round it you may go. All three are things done **to** the floor. A pad changes what
the floor is *connected to*, which is the one thing a room could not previously say — and the player
says it, by choosing to step on one. It is the first thing in the game that moves the player.

**It charges nothing.** The lesson `ThermalZone` records at length is that a mechanic taxing the
player's damage output drowns a weak build and is invisible to a strong one. A pad is not a hazard,
never damages anybody, and no item interacts with it. What it costs is a decision about position,
which is the one currency every build has exactly as much of as every other.

**The destination is never a surprise**, and not because of anything the code does: every room in
this game is one screen with no scrolling, so both ends of a link are in view at the moment the
player decides. Pairs are told apart by **counting pips** — one bar pairs with one bar — which is
shape rather than hue, the lesson the thermal zones' louvre bars record after two floors shipped
hazards that both resolved to red.

**Bouncing is prevented by a rule, not a timer.** A pad the player *arrived* on does not fire until
they leave it. That is a fact about where the robot is rather than about how long ago something
happened, so there is no cooldown constant anywhere — and any constant would have been wrong for
somebody's frame rate.

**A used pad stays a pad.** Using a link lights both of its ends for 0.16 seconds, which is the
acknowledgement that stops a teleport reading as a glitch the first time it happens. That flash used
to paint the plate flat white and stop there — no green, no border, no pips — so for its duration a
link had no colour, no exact extent and no count, in the one moment the player is looking at the far
end to see where they have been put. It now raises the pad's own three alphas instead, and the wash
stops well short of the pips: plate and pips are the same green, so the distance between their
alphas is the only thing telling them apart, and a flash that closed it would erase the count as
thoroughly as the white did.

That was reported as the pads whiting out, and the report was more literal than it sounded. `_draw`
runs only when something asks it to, and the pad asked on every frame the flash was *running* and
not on the frame it ended — so the last picture ever painted of a used pad was a lit one, and it
stayed that way for the rest of the room, at both ends of every link the player had stepped on. The
flash was doing exactly what it was written to do and nothing was undoing it. Both halves are now
pinned in [`tests/test_migration.gd`](tests/test_migration.gd), the second through the `draw` signal
rather than through the pad's own state: `_flash_left` reaching zero was already true on the broken
build, and what was false is that anybody redrew afterwards.

#### What it changed underneath

One thing, and it is the interesting one. Floor 3 added a flood fill asserting that a template's
walkable floor is a single connected region, because a duct is invisible to everything except a
chassis and a sealed pocket reads as open floor both on screen and in the data. **A room split by
ducts and joined only by pads fails that check** — and that room is the entire point of the
mechanic.

So pads are now **edges** in that walk rather than tiles. What the suite asserts is still "the player
can reach every tile of this room", which is the claim that matters; what it has stopped requiring is
that they can *walk* there, which was only ever a proxy for it. `cloud_split_aisle` is two regions
and always will be.

`cloud_blast_radius` is the room that makes the change visible. It is a sealed vault in the middle of
the floor with the payout inside it and a pad as the only key — which is, tile for tile, the shape of
a bug this project shipped: `dev_server_ring`'s `reward_spawn` sat inside four walls, so on every
seed that room paid out, the item dropped where nobody could reach it. The layout is legal now for
exactly one reason, and the flood fill is what can tell the difference.

### Cloud Operations' seven combat rooms

The ladder is 1 / 2 / 2 / 3 / 3 / 3 / 4, and the numbers are load-bearing rather than descriptive —
`_capped_by_distance` scales a combat room's allowance by its distance from the start over the
furthest *combat* room, so a 4 is reachable only at the very end of the floor.

| room | difficulty | what it asks |
|---|---|---|
| `cloud_intake_hall` | 1 | the mechanic under mild pressure; one link, open floor, cover |
| `cloud_split_aisle` | 2 | a duct wall top to bottom — shots cross, bodies do not, and the pad is the only way over |
| `cloud_region_pair` | 2 | two crossed links, so a pad becomes a *question* about which |
| `cloud_blast_radius` | 3 | a sealed vault with the reward in it and a pad as the key |
| `cloud_failover_row` | 3 | three links across two long ducts: pads as a network, with walking still possible |
| `cloud_cold_row` | 3 | an S of ducts that is tedious on foot, and one link that skips all of it |
| `cloud_control_plane` | 4 | three regions, two links, no walking between any of them |

`cloud_failover_row` and `cloud_cold_row` are deliberately *not* pad-mandatory. A floor whose every
pad is the only route has taught the player that pads are doors; these two are where the mechanic has
to earn being used, because going round is possible and slow.

The start room is where the lesson actually lands. `cloud_ingress` is one link, no enemies, no
hazard, and no door shut behind the player — the only place in the game where a new mechanic is
taught with nothing else happening. Every floor before this taught its idea in a combat room and
hoped the player had attention spare. Floor 3's measurement is the argument against doing that again:
its teaching room was 2.4 of the six combat rooms a run saw, which is a tutorial that will not stop
repeating itself. There is exactly one start room per floor and it cannot be skipped, so a lesson
placed there is delivered once and always.

### A roster measured before anybody played it

Six entries, all of them this floor's own `EnemySpawn` resources under `data/spawns/cloud_ops/`. None
of the six is exclusive to this floor, which makes the private copies the point rather than a
formality — a shared spawn resource is one weight that has to be right on every floor listing it, and
the Data Center measured what that costs when it is not.

The roster's argument is **Pop Up Drone**. It teleports to a room's edge, and has since the first
floor, which makes it the only enemy in the game that can cross a cable duct — the only thing that
can follow the player out of a fight they left. The Data Center excluded it on the grounds that
nothing a player learns about holding ground applies to it; here that is the qualification rather
than the objection. A mobility floor whose enemies are all stationary is a floor where the mechanic
is a convenience. What it still cannot do is get into a sealed interior: it picks points on the
room's inset perimeter, so `cloud_blast_radius`'s vault stays sealed and a pad is still the only way
in.

Deliberately absent: Load Balancer and Stale Replica, which are the Data Center's and listed by no
other floor — the two enemies that floor exists to introduce should not become anybody else's
furniture. Deadlock and Recursion are both about timing rather than position.

**The floor was measured across four hundred generated floors before it was called finished**, which
is the one piece of process Floor 3 bought and the reason this table exists at all. Two of the three
columns below are corrections the measurement forced.

| | authored | after measuring | floors 1-3 |
|---|---|---|---|
| enemies per floor | 25.2 | 23.8 | 22.2 / 22.2 / 22.9 |
| Null Pointer | absent from 24.2% of floors | 3.0% | — |
| Memory Leech | absent from 16.8% | 3.8% | — |
| Code Runner | 6.34 a floor | 4.32 | — |
| `cloud_control_plane` | 0.28 rooms per floor | 0.28 | `data_grid_floor` 0.29 |

The two absences were the Data Center's exact fault, reproduced: both entries were authored at
`min_difficulty` 3, and only about 2.4 of a floor's six combat rooms reach difficulty three, so a
third-tier entry competes for a slice of the floor rather than for the floor. Twenty-four per cent is
worse than the 22% that Floor 3's Load Balancer was corrected for. Nobody would have reported it —
that is the whole reason the measurement runs.

The enemy count is the other one. Authored, this floor was 13% fuller than the fullest floor before
it, which is an escalation nobody designed; two rooms lost a spawn point each. It is still a step up,
and that is deliberate for the last floor of the campaign, but it is now a step rather than a jump.

The heading is history rather than status: the floor has been played several times since, and every
weight in `data/spawns/cloud_ops/` is still the measured one. Whether 23.8 enemies a floor is the
*right* step up from 22.9 is the question at the end of [what playing Cloud Operations had to
answer](#what-playing-cloud-operations-had-to-answer), and it is one of the ones now waiting on a
write-up rather than on a run.

### Floor boss: Orchestrator

Named for the thing that decides where a workload runs. **It is only open to damage in the moment
after it lands**, and getting caught in the open when it moves costs a point.

The fight is a four-beat cycle. It sits **sealed** on a plate and fires, and shots that hit it do
nothing at all. It **telegraphs** a migration for 1.9 seconds — naming a plate, lighting it, and
ramping the floor between the plates toward red. It **resolves**: the load moves, the floor
discharges, and anything standing off a live plate takes a point. Then it lands and is **open** for
2.2 seconds, holding fire, damageable. That window is the only time in the fight shooting it means
anything.

One turn sits on top of the four. **Stand on the plate it is migrating to and the migration is
denied** — the load has nowhere to go, so the boss stays where it is and opens for 3.6 seconds
instead. Any plate keeps you alive; *that* plate is worth running for, and it is always the live
plate furthest from wherever you were standing when the telegraph began.

The escalation is spent on the arena rather than on the boss. Its damage, its fire rate and the time
it gives you never change; what changes is how much ground answers a migration. **Six plates**, of
which the one it is standing on is never shelter, and the live set shrinks from five to three to two
across the fight. The last phase is a room with two safe squares in it, one of which is the
destination — shelter or deny, not both.

**Its health number is not comparable to the other three bosses' and must not be "corrected" toward
them.** Runtime Error's 110 and Cascade Failure's 144 are pools you can pour damage into for the
whole fight; this one is open about a third of the clock, so 68 against continuous fire is nearer
200 — more than any boss in the game. Measured rather than reasoned about: at the starting weapon's
4 damage per second the fight is 51.7 seconds and eight windows, and at the 9.4x ceiling the worst
legal build reaches it is one window and six seconds, which is what every other boss in the game
also does against that build. Winning the races shortens it honestly, because a denial buys a window
1.6 times longer with no number anywhere changing.

#### What this replaced, and why

The fight that shipped here **could not be killed by damage at all**. Damage filled a pool, a full
pool forced a failover, and only a denied failover was progress: three denials and it was done. The
reasoning was sound — a build near the damage ceiling deletes every other boss in the game, and
scoring a fight in denials makes it the one whose length is set by reading rather than by inventory.
It had two faults that between them made it unplayable.

**It was solved by standing still.** The destination was `(current + 1)` around the ring, and a
denial did not move the boss — so standing on the next plate denied every failover from a standstill,
and the race the whole design rested on never had to happen once.

**And a player who did not find that had nothing to read.** Damage moved nothing visible, nothing
happened unless they shot, and no clock ran, so the fight could stall indefinitely. Total damage to
kill was 102 against Runtime Error's 110 and Cascade Failure's 144, and none of it was progress.

The plates, the migration and the denial all survive. What they are worth has changed: the bar is an
honest pool that only falls, damage kills, and the positional demand moved from *the* plate to *a*
plate — which is a rule a player can state after one migration, and a rule that has teeth, because
missing it costs integrity.

The cost of gating damage is that shots at a sealed boss are wasted, so the fight says so in four
places at once: the body sits cold and dim and goes bright amber the instant it lands, the bar does
not move, a hit while sealed pings dim steel rather than flashing white
([`BossPart.set_shielded`](scenes/bosses/boss_part.gd)), and the opening banner states the rule in
words before the first migration.

#### The check this fight cannot ship without

Because the discharge costs a point and the live set shrinks to two plates, the fight's fairness is a
*geometry* claim: the furthest any point in the arena can sit from the nearest live plate must be
crossable inside the telegraph. [`tests/test_orchestrator.gd`](tests/test_orchestrator.gd)
brute-forces it — every plate the boss could be on, every rotation of the live set, every phase,
sampled on a two-pixel grid over the whole room — and recomputes it from `plate_count`,
`plate_radius`, `plate_size` and `live_plates_by_phase` rather than from a remembered number. The
worst case in the last phase is 225 pixels, 1.41 seconds at the robot's walking speed against a
1.9-second telegraph, and the dash is deliberately left out of that budget.

Doubling the plates from three to six is what makes the shrink possible at all. Three plates cannot
lose one without the survivors sometimes sitting on the same side of a 416x192 room, which is a
migration nobody in the far corner can answer.

It is **not called Failover**, and that is not a stylistic choice: the game already ships an item
with that id (a death save). Two things sharing one would collide in a run's records and put the same
word in the HUD for a boss banner and a pickup banner, which is the specific confusion
`BossEncounter` was created to stop.

#### Any floor, any boss — again

All four floors now list all four bosses, and the Orchestrator had to be added to the three before
this one rather than kept to its own. The reason is arithmetic that the Data Center already wrote
down: `CampaignValidator` requires a distinct boss per floor and checks every subset, so with the
Orchestrator confined to floor 4 there would be exactly **one** legal dealing — it would guard floor
4 every run and the campaign's last fight would never change. That is precisely the cost the Data
Center paid for locking Cascade Failure to itself, and paying it again one floor later would be
choosing not to have read it.

It survives being met early for the same reason Cascade Failure does. Everything it does is a lit
rectangle ramping for 1.9 seconds before anything happens, which is a telegraph read on its own terms
at any depth, and its plates are its own — the fight needs no pads in the arena, so it works in a
Help Desk room that has never heard of one. What this floor teaches first is the verb, not the fight.

`RunDefinition.content_version` goes to 3 with all of it. A run is four floors instead of three, so
victory has moved and a seed no longer reproduces the same run.

### Cloud Operations' look and sound

Deliberately the lightest and warmest environment in the game, which is a contrast decision rather
than a taste one: the Data Center is near-black cold steel and this floor follows it, so a second
dark blue hall would read as the same place with different furniture. Walls are stripes where the
Data Center's are a grid, because the two have to read apart in peripheral vision and stripe-versus-grid
does that at any size.

**Nothing in the palette is green.** A pad draws itself spring green because it is the one piece of
floor in the game that is purely an offer rather than a threat, and a floor carrying green as
decoration would spend the only colour the player has to find. Exactly the call the Data Center makes
about teal and violet, and Development about amber.

Two tracks, and they are the first in the game written from an idea rather than a mood. The floor's
mechanic is that a place can also be a different place, so `cloud_explore`'s melody is a call and an
answer: a three-note figure low, then the *same figure* an octave up, then a tail belonging to
neither. Nothing is transposed for colour — it is the identical shape in a different register, which
is what a migration is. Round the loop it stops being obvious which of the two was the original.
`cloud_boss` is the same two registers with the answer arriving *first* and the low line catching up
half a beat late, which is the fight: the boss commits to being somewhere else and the player is
trying to get there before it does.

Both run 48 beats against the 32 every track before them, which comes out at 22.9 and 17.1 seconds —
the two longest loops in the game. Short music has been a known limitation since milestone 6 and the
only cost of fixing it is writing more bars, so this floor wrote more bars. Seven tracks became nine.

### What playing Cloud Operations had to answer

The floor was written with none of this observed, and the sentence that used to stand here — that
nobody had played it at all — is no longer true: it has been played through with the rest of the
game, several times. What has not happened is any of these questions being answered on paper, and
`data/bosses/orchestrator.tres` has not been touched since, so the list stands as written.

- **Is 1.9 seconds the right telegraph?** It is the player's entire budget for crossing a 416-pixel
  arena to deny a failover. Too short and the fight is unwinnable without the arena's corner pads;
  too long and the denial is free. This is the number to move first.
- **Does a boss that cannot be damaged to death read as a puzzle or as a cheat?** The reasoning above
  is sound and the reasoning is not the experience.
- **Do the pips actually pair?** Counting bars is the colourblind-safe answer and it is also more work
  than reading a colour. `cloud_failover_row` asks a player to keep three pairs straight at once.
- **Is a room the fight cannot follow you out of a relief or an exploit?** `cloud_split_aisle` lets the
  player shoot two enemies that can never reach them. That is either the best thing on the floor or a
  turret position.
- **Is 23.8 enemies the right step up** from three floors of 22, given enemy health also grows across
  a run?

---

## What playing it answered

The first two entries below are not reasoned, which makes them the only tuning in this document
that is not. They came from beta playthroughs, and both are cases where the thing that was wrong
had been sitting in plain sight behind a rule that reads as correct.

**This section is behind the playing.** Everything in it came out of the early passes. The game
has been played through end to end several times since, across all four floors, and none of those
runs has added an entry here — not because they found nothing, but because nothing was written
down. Anything below is what playing has taught *and been recorded*; it is not the whole of what
playing has taught.

### Diminishing returns, because the player was the only curve

Floor 3 was trivial, and the cause was not floor 3. Every multiplicative aggregate in the game is a
product across everything held — the rule that makes Cooling Fan and Unsafe Overclock compound
instead of one overwriting the other, and the right rule for two items. The offer cadence is eight
per floor on *every* floor (two combat clears, one treasure, two shop, three boss choices), and
nothing about an enemy is a function of depth: `floor_number` is read in exactly three places, none
of them combat. So the player's power was geometric and the opposition was flat. A legal build
reached about 13.8x damage and 3.8x fire rate — 52x the damage per second the roster was written
for — and the last floor of the campaign stopped asking anything.

[`DiminishingReturns`](scripts/combat/diminishing_returns.gd) is the answer, and deliberately not a
cap. A hard ceiling makes every item past it worthless, which turns a reward into a message that
the run is over and makes the item that crossed the line the one the player blames. This is a soft
knee: bonus up to +100% is kept whole, and everything above it is compressed onto an asymptote at
3.5x. The two branches meet with matching slopes, so no build sits on a cliff.

| raw | 1.5 | 2.0 | 3.0 | 5.0 | 8.0 | 13.8 | → ∞ |
|---|---|---|---|---|---|---|---|
| softened | 1.5 | 2.0 | 2.6 | 3.0 | 3.2 | 3.3 | 3.5 |

Read the left of that table as the promise and the right as the point: everything a player holds by
floor 2 is untouched, and the outlier builds that trivialised floor 3 land within reach of ordinary
ones. Worst legal build is now about 9.4x damage per second rather than 52x, which
`tests/test_items.gd` asserts against the shipped pool so a new item cannot quietly undo it.

Two aggregates are on the curve and the narrowness is the design: projectile `damage`
(`ProjectileModifierStack.SOFTENED_SCALE_KEYS`) and the fire-rate multiplier
(`ItemInventory.get_fire_rate_multiplier`). Those are the two that multiply into damage per second,
which is the only quantity that can make a floor trivial. Dash cooldown, Cache Warmer's opening
shot, projectile speed, and the chain/split fractions are each left alone for a reason written down
in the class doc. Mutex Lock and Adrenal Loop fold *into* the fire-rate product before the curve
rather than multiplying on top of it — softening the held items and then applying a raw 1.5x would
let a build stand still to buy back exactly what the curve just took off.

This also does something the earlier "one boss per floor" note wanted: an asymptote is a thing the
opposition can be tuned *against*. Per-floor enemy scaling is now a sensible next lever rather than
a race.

### A moment of grace at the door

Beta reports were all one shape: walk through a door, lose a point before the room is on screen.
The cause is in `FloorController._enter_room`, which wakes the room and *then* announces the entry —
so anything already aimed at the doorway fires into a player who has not yet seen it. That is a
point of integrity spent on a decision the player was never offered, which is the definition of a
cheap shot.

`PlayerConfig.room_entry_grace` is 0.6 seconds of invulnerability granted on entering any room,
about 96 pixels at walking speed — comfortably past the doorway and into a position the player
chose. It is granted through `HealthComponent.grant_invulnerability`, which extends rather than
replaces, so walking through a door immediately after being hit cannot cut the hit's own window
short. Deliberately shorter than `damage_invulnerability` (0.8s), so entering a room is never safer
than being hit, and it cannot be farmed: the doors of an uncleared room lock behind the player, so
there is no way to spend it twice on the same room.

The robot does **not** flash for the duration, and originally it did. One predicate read the health
component and decided both whether a hit landed and whether the sprite strobed, on the reasoning
that the player should never have to work out which kind of immunity they had. What that actually
shipped was twelve hertz for six tenths of a second on entering every room in the game — forty
rooms a run, and it read as the game glitching on each transition rather than as a gift.

The two things want different rules, so they got them. `Player.should_flash` is the presentation
half: a flash is a warning with a deadline, *this is about to run out*, and it earns its place after
a hit — when the player has a window they have to spend. A doorway window is not that. It is handed
over for walking, there is nothing to do with it, and it is better felt than seen. A window carried
in from a hit still flashes after the door, which is the exception that keeps this from being a
licence to delete the flash outright, and `tests/test_floor.gd` pins both halves.

`PlayerVisuals` is handed the answer rather than the immunity, because a sprite has no business
knowing what a doorway is.

Two things fell out of building it, and both are worth naming because neither is about the feature:

- `HealthComponent.configure` did not clear a running window. It resets `_is_dead` and refills the
  pool, so a leftover timer from before it was called was already inconsistent; it simply could not
  be observed while a hit was the only thing that opened one. It clears the timer now.
- `tests/test_post_boss.gd` teleported the player into the boss arena and waited a flat two frames
  for the entry trigger. How long that actually takes is not fixed — the first arena a run opens
  took longer than two frames while every one after it took fewer — so the helper now waits for the
  entry rather than assuming it. That made exactly one test in the suite behave unlike the seven
  after it, which is the kind of thing a fixed wait hides until something else changes.

**This does not weaken the post-boss danger contract.** A committed hazard still resolves in an
arena whose boss is already dead; the grace window covers a doorway, and the boss arena's doorway is
one the player crosses before the fight rather than after it. `tests/test_post_boss.gd` still holds
both halves of that rule.

### Bosses hurt to touch

Every enemy in the game with a body the player can walk into charges them for walking into it. The
three bosses were the exception, and nobody had noticed because nothing draws attention to a rule
that is only ever *not* enforced: standing inside the thing you are shooting was free in all three
fights.

It is a bad exception everywhere and a broken one in Cascade Failure, whose nodes could be ridden
around the ring — which parks the robot on precisely the ground that node is about to vent, for
nothing. The fight that is entirely about where you are standing was paying the player to stand in
the worst place in the room.

`BossPart` now resolves contact damage the way `Enemy` always has, by distance rather than by a
second Area2D, and it lives there rather than in the three controllers for the same reason the
damage receiver does: a body that hurts to touch hurts on all of it, whichever boss it belongs to.
The numbers are per scene — a 28-pixel king and a 16-pixel rack unit are not the same thing to stand
next to — and the radius is matched to each part's collision circle, so what hurts is what the
player can see they are inside.

Two rules fall out of it, and both are checked in
[`tests/test_boss.gd`](tests/test_boss.gd) against all three part scenes:

- **It is a cooldown, not a per-frame bill.** The Scrap King's charge keeps its own separate hit,
  with its own knockback along the line it was travelling; the player's damage window is longer than
  either cooldown, so a charge that connects is never billed twice.
- **An inert body charges nothing.** The Scrap King spends a couple of seconds a phase invisible and
  off the collision layer, playing dead, and a boss the player cannot see must not be billing them
  for walking through the space it used to occupy.

### Floor 3 was the emptiest floor in the game

The report was mild — *"I often go through it without encountering many of the new enemies"* — and
measuring it found four separate faults stacked on top of each other, three of which were bugs
rather than tuning. Each was invisible while playing, which is the recurring shape of everything in
this section: the floor did not look broken, it looked *thin*, and thin is not a symptom anybody can
file a bug against.

The measurements below are all four hundred generated floors, which is the only honest way to say
anything about a system whose output is a distribution.

#### The signature mechanic had never once appeared in the rooms written for it

`ThermalZone.spawn` set `global_position` on a node it had not parented yet. That is only ever the
*local* position — there is no parent transform to measure against — and `Room._build_thermal_zones`
passes global coordinates, so every zone was placed at its room's own offset twice over. A room at
cell (2, 1) sits at (896, 224) and was building its floor patches at (1808, 464): most of a screen
away, inside whatever room happened to be standing there.

It survived because it was invisible from both ends. Every arena in the suite builds its room at the
origin, where adding zero twice is still zero, so `test_thermal.gd` passed with the placement check
it already had. And in a real run the misplaced patches were still drawn — just in the wrong rooms —
so the floor *looked* like it had zones. What it did not have was zones in the rooms authored to
teach them. The Data Center's one taught idea, the thing the whole floor is named for, had never
been in a single room it was written into.

The fix is one line moved. The check that matters is that the suite's placement test now builds its
room somewhere other than the origin, and is documented as never being allowed back: a placement
test at the origin is a placement test that cannot fail.

#### The hardest room on every floor was unreachable

`FloorGenerator._capped_by_distance` scales a combat room's difficulty allowance by how far it is
from the start, as a fraction of the floor's maximum distance. Only combat rooms are capped — but
the maximum was taken over *every* room, and the three special rooms are attached last as dead ends
hanging off combat rooms, with the boss deliberately claiming the furthest cell. So the maximum was
always at least one greater than any combat room could reach, no combat room ever scored a full one,
and the top of every floor's ladder was unreachable.

Measured: the Help Desk's `combat_ring` drew 0.23 times per floor, Development's `dev_server_ring`
0.26, and the Data Center's `data_grid_floor` — the room its whole floor is built to end on — three
times in four hundred floors. Authored, reviewed, shipped, never played.

#### A roster shared between floors is a roster tuned for none of them

An `EnemySpawn` is a scene, a weight, and an unlock difficulty, and three floors were pointing at the
same resources. One weight cannot be right for three floors: the Ticket Bot arrived on the Data
Center at the Help Desk's 2.0 and made up 7.6 of that floor's 17 enemies, while Load Balancer and
Stale Replica — the two enemies the floor exists to introduce, listed by no other floor — sat at 1.0
and 0.9 and came to about 1.4 each, missing outright from more than a fifth of floors.

The Data Center now keeps its own copies under `data/spawns/data_center/` for the four enemies it
shares, and reweights its two exclusives in place. Copying four small resources is the cost of a
floor being allowed to disagree with another floor about what it is made of.

#### Three of six combat rooms were the tutorial

`data_intake_row` is the teaching room: two spawn points, both forced Ticket Bots, so it draws
*nothing* from the roster. With only four combat templates on the floor it was 2.4 of the six combat
rooms a run sees. Three new templates at difficulties 2 and 3 — where rooms actually get drawn — put
it back to 1.1, and all three carry four or five spawn points.

#### Where that leaves it

| | before | after |
|---|---|---|
| enemies per floor | 16.9 | 22.8 |
| Load Balancer | 1.4, absent from 22% of floors | 4.5, absent from 0% |
| Stale Replica | 1.4, absent from 24% of floors | 4.2, absent from 2% |
| Ticket Bot | 7.8 | 3.9 |
| the teaching room | 2.4 rooms per floor | 1.1 |
| `data_grid_floor` | 0.00 rooms per floor | 0.25 |

Floors 1 and 2 sit at 21.9 enemies per floor, so the last floor of the campaign was the emptiest one
by a third. It is now the fullest by a hair, which is the right way round.

Two checks in `tests/test_floor.gd` are there so none of this can quietly come back. One sweeps the
shipped campaign and asserts every combat template a floor lists actually gets drawn; the other
asserts every roster entry is placed at least once per floor on average. Both would have failed on
the build this section describes.

### The audio went silent once, and it is not solved

A report from a Windows debug run: partway through, the music and every sound effect stopped at the
same moment. Nothing in the console beyond the usual startup lines, nothing about the run that
explained it, and no way to make it happen again. **This section describes an open bug**, and says
so because the worst outcome would be somebody later reading a mitigation as a fix.

What was measured and cleared, all of it on the audio manager's own terms:

- **The crossfade.** Forty-five seconds of combat-rate playback — three sounds most frames, all
  nineteen ids cycling — with a track change every ten seconds. No stall, no stuck playback
  position, no dropped player.
- **The loop.** A track watched across two wrap points in real time; position wraps where it should
  and playback continues.
- **The pool.** Sixteen voices round-robin under the same load, nothing leaked or left playing.
- **The buses.** Music and SFX both send to Master, the layout file supplies both, and
  `GameSettings.volume_to_db` floors at −80 dB rather than producing an infinity.
- **`stop_all`.** Only reachable from close-request and exit-tree, and nothing here disables
  `auto_accept_quit`, so it cannot fire while the game is still running.

That the music and the sound effects went *together* is the useful part of the report: they share
nothing in this codebase except the AudioServer's output. Above that, the two paths are independent
and both were exercised. So the remaining suspect is the output itself — a driver that has lost its
device takes both at once, needs no trigger, and on Windows can do it without raising anything the
game would see, which is the whole shape of what was reported.

Two things came out of it, and the first matters more:

**The debug overlay reports audio now.** Second row, under FPS:
`data_explore PLAYING 7.2s  fade 1.00  sfx 3/16  mix 11ms`. Silence has two causes that need
opposite fixes and look identical from the player's chair — either the game has stopped asking for
sound, or it is still asking and nothing below is listening. This splits them on sight. The `mix`
figure is milliseconds since the audio output last ran: a working driver holds it in the tens, a
dead one lets it climb without bound.

**A watchdog notices the output has stopped and asks for it back.** `get_time_since_last_mix`
climbing past a second means no audio has been produced for a second, whatever the reason — that is
a fact rather than an inference, and it is two orders of magnitude past the 3–37 ms a working driver
produces. On a trip it logs, once, with a timestamp and a device name, and re-selects the output
device, which is the documented way to make a driver re-open it.

The log line is the deliverable; the recovery is a bonus. If the failure is a lost device,
re-selecting it is the fix. If it is something else, the attempt costs a glitch nobody will hear and
the warning still lands — which is what turns "it went quiet and there was nothing in the console"
into evidence. `tests/test_audio.gd` holds the two things that have to be true of a watchdog: it
does not fire across ten seconds at each of five mix periods up to 300 ms, and it does fire after a
full second of a missing mixer, once, not once per frame.

It is skipped on the web, where the mixer runs on the game's own thread and a long frame really can
stall it — the one platform where it could produce a false positive is the one platform where the
failure it looks for cannot happen.

### Two content bugs the flood fill found

Adding `CableDuct` meant adding a check that a template's walkable floor is still one connected
piece — a duct is invisible to everything except a chassis, so a sealed pocket looks like open floor
both on screen and in the data. It failed immediately, on two rooms that had nothing to do with
ducts:

- **`dev_server_ring`** was four walls forming a closed rectangle. The twenty-four tiles inside were
  sealed — floor the player could see, walk around, shoot across, and never stand on — and
  `reward_spawn` was in the middle of them. On every seed where that room paid out an item, the item
  dropped where nobody could reach it. `LootSpawner` only nudges a drop off ground that is
  *blocked*, and a walled courtyard is not blocked, it is unreachable, which is why nothing caught
  it. The middle is filled in now, which is what the room already played like.
- **`dev_server_row`** aimed its `reward_spawn` at the centre tile, which is inside its central
  block. That one *did* get rescued, every time, by `LootSpawner._nearest_clear_position` — which is
  exactly why it went unnoticed for two floors. The fallback is there for drops that land badly, not
  for a template that aims at a wall.

Neither was reachable by the existing doorway check, which only ran against floor 1's templates. The
new one walks every template in the campaign.

---

## Next recommended task

**Write down what playing it taught.** "Play it again" held this slot from the third milestone
until now, and it is finally closed — the whole game to date has been played through by hand, end
to end, several times over, all four floors. What has not happened is the part that made the first
pass worth anything.

[What playing it answered](#what-playing-it-answered) is the argument. One hour of that pass
produced one mild sentence — *"I often go through it without encountering many of the new
enemies"* — and unpacking that sentence found three bugs, including a signature mechanic that had
never once appeared in a room written for it and the hardest room on every floor being unreachable.
None of the three was visible in the code, in a test, or on screen. **Measuring after a report is
what caught them, and the several runs since have produced no report.** A playthrough nobody writes
up is worth roughly what not playing is worth, which is the whole of why this is the top item
rather than "build floor 5".

The shape of the task is small and specific: take each floor's "what playing it had to answer"
list and replace the questions with what actually happened. The lists are unchanged since they
were written, and `data/` has not moved either, so there is no risk of contradicting a tuning pass
that already happened — there has not been one.

The questions still standing are a four-floor run's, and the newest floor has the sharpest of them
listed under [what playing Cloud Operations had to answer](#what-playing-cloud-operations-had-to-answer). The
rest, oldest first:

- **Did the Data Center fixes land where they matter?** The distribution moved a long way —
  22.9 enemies a floor from 16.9, Load Balancer from absent-on-22%-of-floors to absent on
  none — but the report was that the floor felt *thin*, and a better histogram is not the same
  as a floor that plays fuller. It has been played since the fixes landed, so this one is not
  waiting on a run; it is waiting on somebody saying whether the floor still feels thin.
- **Do the thermal zones and the cable ducts read?** The ducts have been played. The zones have
  been played *as a rule that no longer exists*, and this is the one question on the list that a
  past run cannot answer. Until the placement bug was fixed they were being built in the wrong
  rooms; since then they have been played as the three-condition version — heat only while
  standing inside a zone *and* firing *and* holding still. They now charge for occupancy alone:
  stand on one and it heats, whatever else you are doing. **Every run so far predates that
  change**, so the specific thing to watch for is new: whether a room full of grilles reads as
  ground to route around rather than as ground to avoid entirely. The ramp is sized so that
  crossing is always affordable and `tests/test_thermal.gd` holds it to that; whether it *feels*
  affordable mid-fight is what a test cannot answer.
- **Is four floors the right length?** The run has been played end to end several times, so the
  answer exists; no timing from any of those runs is recorded here, and spec section 28's "eight
  to twelve minute run" has still never been checked against a clock.
- **Does the economy still hold over four shops?** The arithmetic half of this is now done and
  the answer is *yes, by nine percent* — see [Four shops, one
  purse](#four-shops-one-purse). What is left is the half a suite cannot reach: several
  four-shop runs have happened, and whether they came out tense or obviously flush is still
  unrecorded.
- **Is 6 integrity right when the run is four times longer?**
- **Is the Orchestrator fair on floor 1, now that missing a migration costs a point?** Every
  floor can draw every boss, so a first-room player can meet a fight whose answer is positional
  and whose mechanic they have not been taught — and unlike before, failing to answer it is
  charged for. The reasoning says the telegraph carries it and the geometry check says the run
  is always makeable, but "makeable" is measured against a robot walking in a straight line and
  not against one that has never seen a plate before. Cascade Failure's inclusion rests on the
  same argument and has not been played either.
- **Is 68 the right pool for the Orchestrator?** The window arithmetic is measured — 51.7
  seconds and eight windows at the starting weapon's 4 damage per second, six seconds and one
  window at the damage ceiling — but the low end is a player with no offensive items at all,
  which is the case least likely to happen and the one most likely to feel long. This is the
  first number to move if it drags.
- **Does the lead vent read as the boss predicting you, or as heat landing at random in front
  of you?** Cascade Failure's scatter is gone and the patch that replaced it lands 96 pixels
  along the robot's own heading. The intent is a pincer with the aimed vent whose only counter
  is a turn; whether a player feels that as a rule or as noise is the thing to watch for.
- Does the CRT filter look like an arcade cabinet or like a dirty screen?

Then move the numbers in `data/`, which is one `.tres` edit each and the whole payoff for
putting tuning in resources — and update `tests/test_balance.gd` to match what playing
taught, rather than deleting it. Its economy checks are campaign-shaped now rather than
floor-1-shaped, so a shop number that moves is one edit and a re-run.

After that, in rough order of value:

1. **Get another Windows debug run, for the audio.** [Limitation
   17](#known-limitations) is open, and the instrumentation built for it only pays off the next
   time it happens: the overlay's `mix` figure and the watchdog's single log line are there to
   turn "it went quiet and there was nothing in the console" into evidence. Until then the
   report stands and nothing is diagnosed.
2. **Run the Windows and Linux builds on their target environments.** Web CI now exports,
   serves, and boots the browser build on every push, which is the execution test the other
   three still lack; the macOS app runs here, and Windows and Linux have never been started.
3. **Play and qualify the two closing floors.** Floors 5 and 6 now exist. Their density,
   coordination pressure, Executive Override and Core Intelligence need a human pacing/readability
   report before their numbers can be called balanced.
4. **Longer music, for the other seven tracks.** Cloud Operations' two run 48 beats and come out
   near twenty-three and seventeen seconds; the seven before them are 10.9 to 20.0 and a boss
   fight still laps its track. The method is proven and the only cost is bars.
5. **Elite modifiers** (spec section 15), which the spec says to add once the base enemies
   feel good — a judgement that has now been made by somebody and not written down, which is
   the top item on this page again.

---

## Floor 5: Executive Systems

Implemented as the fifth floor of the main campaign. It uses the existing compile lanes,
throughput zones, cable ducts and migration links, with Load Balancers coordinating returning
enemies. There is no floor-number branch in gameplay. It introduced campaign content version 4;
the completed six-floor campaign is now version 5 and rejects earlier checkpoints because they
describe a different ending. Floor 5 now descends into Core Intelligence.

Seven combat templates supply the usual six combat rooms. Their difficulty ladder is
1 / 2 / 2 / 3 / 3 / 3 / 4 and their populations are 4 / 5 / 5 / 6 / 6 / 6 / 7. The briefing
introduces a protected squad without a floor hazard; delegation adds ducts and migration;
quorum splits attention across two protection hubs; escalation and cost centre combine
compilers with heat and movement; board vote is the densest combination. Support enemies are
forced at authored positions, so multiple Load Balancers are a deliberate composition rather
than an unlucky roster roll. All migration landings remain clear of walls, ducts and heat.

Across 400 deterministic version-5 seeds the floor averages **31.56 enemies**, and 399/400 contain
coordination. This is a deliberate increase over Cloud Operations' roughly 24, for a mature
build; it is not yet a playtested difficulty claim. Clear rewards pay 1–2 scrap and enemy drops
remain 0–2, giving the economy model 47.93 scrap for the floor. The existing campaign-shaped
affordability and shelf-capacity tests pass with the fifth shop included.

**Executive Override** is an explicit advanced Runtime Error encounter, confined to Floor 5.
The first four bosses keep their shuffled order. Its ivory corporate seal has 156 health and
three authored rotations: twin lanes/spread/ring; checkerboard/spread/twin lanes/ring;
checkerboard/wall/twin lanes/ring. The lane warning, 3-projectile wall opening, and generous
ring gap retain the existing readable answers. Commands remain spaced beyond the complete
staggered-lane lifetime. The inherited damage and death paths preserve committed hazards
after defeat and end the floor only when a reward is claimed.

The environment has charcoal carpet, walnut panels and muted brass, reserving saturated
hazard colours for gameplay. Both new music loops are 64 beats: 30 seconds exploring and
24 seconds for the boss. Their generators and generated assets are checked in.

Mature builds exposed two UI failures. The item row now shows the newest twelve distinct
types and a count of the remaining types; holding Tab/L1 opens the complete inventory grid,
with stack counts and name tooltips. The summary no longer tries to fit a comma-separated
inventory into one label. The floor name occupies its own line above scrap/room counts.
The maximum legal inventory, long cause-of-death label, and ending buttons fit 480×270.

### Executive Systems verification

- Full regression after the finale: **33 suites, 5,472 checks**, passing on Godot 4.7.2.
- The 502 new Executive checks also pass on pinned Godot 4.7.1. They cover 400 Floor 5
  layouts, pad landings, the advanced encounter's damage/death contract, maximum inventory UI,
  and JSON checkpoint round trips at all four boundaries. Every resumed path reproduces the
  same Floor 5 content fingerprint, shop, boss ledger, scrap, scaling and item stacks.
- The structural suite sweeps 120 seeds per authored floor. The lifecycle soak now runs
  **100 shipped six-floor campaigns**, claiming the final reward and reaching victory.
- The separate combat probe drives the real Main scene through every combat room and boss on all
  six floors,
  carrying every beneficial item at its legal stack ceiling. Player immunity keeps observation
  running; remaining enemies and bosses are finished through their damage receivers after
  sampling. This is a stress test, not an estimate of human clear time or proof of fair combat.
- Two rendered six-floor campaigns on an Apple M2 Max, Godot 4.7.2 Compatibility, measured
  frame p95 **15.486 ms**, p99 **16.426 ms**, and transition p95 **14.89 ms**. Nodes returned
  to **31 after each run**, with zero orphan growth; static allocation rose from 52.64 to
  53.76 MB. Peak observed hostiles/projectiles were 7/47. This seed does not cover every
  worst-case composition, and static allocation is not process RSS.
- Native physics p95 was **12.079 ms**, over the plan's stricter 8 ms script/physics target.
  The rendered frame budget passes on this machine; the entire performance gate does not.
- A local Web export using the pinned 4.7.1 template boots successfully in Chrome, with no
  game-script or browser-page failures; the local harness does not provide the hosted
  `WavedashJS` interface. Its two-campaign stress probe returned to 31 nodes after each run with
  zero orphan growth and observed 7 hostiles/48 projectiles at peak. Web frame p95 was
  **19.2 ms**, physics p95 **21.0 ms**, and transition p95 **41.6 ms**, so this machine/browser
  does not pass the performance gate. The normal isolated Web build script is blocked on this
  Mac by Godot's ObjectDB snapshot-directory creation during import (and needs a `timeout`
  command available). The local export was made from a temporary copy with the verified custom
  template; it is not a signed, published, or release-qualified artifact.

Reproduce the focused checks and combat probe:

```bash
godot --headless --fixed-fps 60 res://tests/executive_runner.tscn
godot --headless --fixed-fps 60 res://tests/soak_runner.tscn
godot res://tests/profile_executive.tscn -- --seed=918273 --profile-cycles=2
```

The probe prints a `CAMPAIGN_PROFILE` JSON record. Use `--headless --fixed-fps 60` for a
fast lifecycle/CPU diagnostic, but do not interpret its unpaced wall times or sampled engine
monitors as rendered frame times. `--snapshots` saves a room and summary image under `/tmp`.
The diagnostic scenes stay excluded from normal exports. To play Floor 5 directly:

```bash
godot res://main.tscn -- --seed=918273 --floor=5
```

**The floor is implemented; the full gameplan gate remains open.** A human report on six-floor
length, coordination pressure and both closing bosses, the stricter CPU budget, worst-room
profiling, and performance/persistence on the actual hosted Web origin still need qualification.

---

## Floor 6: Core Intelligence

Core Intelligence completes the campaign and flips `require_complete` to true. Content version 5
moves the real victory behind the sixth boss reward, and the victory summary now says **SYSTEM
RESTORED**. Older checkpoints are refused instead of being resumed into a run with a new ending.

Seven combat templates use a 1 / 2 / 2 / 3 / 3 / 3 / 4 difficulty ladder and populations of
5 / 6 / 6 / 7 / 7 / 7 / 8. They recombine compile lanes, throughput zones, cable ducts, migration
pads, timing enemies and protection hubs without introducing a new traversal rule. Across 400
deterministic seeds the floor averages **37.62 enemies**; authored Load Balancer pressure appears
on 285/400 layouts. The floor's modeled income is 53.93 scrap before purchases.

The fixed final encounter is **Core Intelligence**, a 190-health, fully damageable pattern boss.
Its three rotations are lane/spread/thermal inference, twin lanes/gapped ring/thermal inference,
and checkerboard/gapped wall/thermal inference. Each inference paints three non-overlapping driven
throughput zones: one on the player's position and two orthogonal follow-ups toward open space.
They use the existing cold-to-violet warning, remain inside the arena, and still resolve if the
boss dies after committing them.

The floor uses black glass, indigo circuitry and cold-white traces, with two new 64-beat music
loops (28.2 seconds exploring and 22.3 seconds for the boss). Saturated hazard colours remain
reserved for gameplay.

Verification on Godot 4.7.2:

- **33 suites, 5,472 checks** pass in the complete regression run.
- The focused finale runner passes **4 suites, 1,118 checks**, including 400 finale layouts,
  boss phase/death behavior, a JSON Floor 6 boundary resume, final-victory semantics, the prior
  Executive coverage, and 100 complete six-floor campaigns.
- Two rendered maximum-build campaigns returned to 31 nodes with zero orphan growth. Frame p95
  was **15.486 ms**, p99 **16.426 ms**, and transition p95 **14.89 ms**. Physics p95 was
  **12.079 ms**, so the stricter 8 ms performance gate remains open.
- A release-template Web export completes and its package contains the Core Intelligence floor and
  boss while excluding test assets. Hosted-origin persistence and browser performance remain to be
  qualified on the release build.

Run the finale directly or reproduce its focused checks:

```bash
godot res://main.tscn -- --seed=918273 --floor=6
godot --headless --fixed-fps 60 res://tests/finale_runner.tscn
```
