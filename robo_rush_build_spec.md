# Robo Rush

## Project Brief

Build a polished, replayable, 2D top down roguelite shooter inspired by the decision density, room based combat, build synergies, and run variety of *The Binding of Isaac*, while using an original retro technology themed setting.

The player controls an obsolete maintenance robot trapped inside a corrupted software megacorporation. Each floor represents a different layer of the company’s technical infrastructure. The player clears combat rooms, collects strange hardware and software upgrades, creates increasingly absurd weapon combinations, defeats bosses, and attempts to reach the central AI core.

The game should feel like a lost 1990s arcade title reimagined with modern roguelite systems.

This document is the source of truth for design and implementation decisions.

---

# 1. High Level Goals

The game must prioritize the following:

1. Responsive, satisfying movement and shooting
2. Short, replayable runs
3. Meaningful item choices
4. Unexpected upgrade combinations
5. Strong visual feedback
6. A manageable solo development scope
7. Clean, modular code
8. Easy expansion through data driven content

The first playable version should be fun before it is large.

Do not begin by creating dozens of enemies, items, rooms, or systems. Build one excellent combat loop, then expand it.

---

# 2. Recommended Technology

Use Godot 4.x with GDScript unless the environment has a strong reason to use another engine.

Recommended project characteristics:

1. 2D renderer
2. Pixel art friendly camera
3. Fixed logical resolution
4. Keyboard and mouse support
5. Gamepad support prepared but not required for the first milestone
6. Data driven item and enemy definitions
7. Scene based composition
8. Signals or an event bus for loose coupling

Suggested logical resolution:

```text
480 x 270
```

Suggested window scale:

```text
3x or 4x
```

Use nearest neighbor texture filtering for pixel art.

Do not use copyrighted assets from existing games.

Use placeholders until the gameplay is stable.

---

# 3. Core Player Fantasy

The player begins each run as a weak and outdated maintenance robot.

The robot survives by scavenging:

1. Weapons
2. Processor upgrades
3. Memory modules
4. Cooling systems
5. Drones
6. Defensive components
7. Corrupted software
8. Experimental firmware

By the end of a strong run, the player should feel like they accidentally assembled an unstable mechanical god.

The emotional arc of each run should be:

```text
Vulnerable
Capable
Specialized
Overpowered
Barely controlled
```

---

# 4. Core Gameplay Loop

The player repeats the following loop:

1. Enter a room
2. Doors lock
3. Enemies spawn
4. Dodge attacks and destroy enemies
5. Doors unlock
6. Collect scrap, health, or resources
7. Choose the next room
8. Occasionally enter a shop, upgrade room, challenge room, or boss room
9. Defeat the floor boss
10. Descend to the next system layer

A full run should eventually target:

```text
25 to 40 minutes
```

The first prototype should only contain one floor and support a run length of approximately:

```text
8 to 12 minutes
```

---

# 5. Controls

## Keyboard and Mouse

```text
WASD: Move
Mouse: Aim
Left Mouse: Fire primary weapon
Right Mouse: Use active item or secondary ability
Space: Dash
E: Interact
Tab: Open run statistics
Escape: Pause
```

## Controller

Prepare input actions for:

```text
Left Stick: Move
Right Stick: Aim
Right Trigger: Fire
Left Trigger: Active item
Face Button South: Dash
Face Button West: Interact
Start: Pause
```

Input should be implemented through named actions, not hard coded keys.

---

# 6. Player Movement

Movement must feel precise and arcade like.

Initial suggested values:

```text
Move speed: 160 pixels per second
Acceleration: 1400
Deceleration: 1800
Dash distance: 70 pixels
Dash duration: 0.14 seconds
Dash cooldown: 1.1 seconds
Invulnerability during dash: 0.10 seconds
```

Requirements:

1. Movement should normalize diagonal input
2. Acceleration should feel responsive, not slippery
3. Dash should preserve the current movement direction
4. If no movement input exists, dash toward the aim direction
5. The player should briefly flash during invulnerability
6. Collision response must not trap the player in walls
7. The player should have short post damage invulnerability

Suggested starting health:

```text
6 integrity points
```

One standard hit removes:

```text
1 integrity point
```

---

# 7. Combat Model

The game is a twin stick shooter with manually aimed weapons.

Combat should reward:

1. Positioning
2. Pattern recognition
3. Movement discipline
4. Build construction
5. Risk assessment

Avoid auto attacking as the primary design.

The player should directly aim and fire.

Initial weapon:

## Rivet Blaster

```text
Damage: 1
Fire rate: 4 shots per second
Projectile speed: 420 pixels per second
Projectile lifetime: 1.4 seconds
Spread: 0 degrees
Pierce: 0
Bounce: 0
```

Combat feedback must include:

1. Muzzle flash
2. Projectile trail
3. Hit flash
4. Impact particle
5. Damage number toggle
6. Enemy recoil or knockback
7. Screen shake for heavy effects
8. Distinct sound effects
9. Brief hit pause for major impacts

Do not overuse screen shake.

---

# 8. Run Structure

A run consists of floors.

Initial full game floor concept:

```text
Floor 1: Help Desk
Floor 2: Development
Floor 3: Data Center
Floor 4: Cloud Operations
Floor 5: Executive Systems
Floor 6: Core Intelligence
```

Each floor should have:

1. Combat rooms
2. One upgrade room
3. One shop
4. One challenge room
5. One boss room
6. Optional secret room
7. Increasingly difficult enemy combinations

For the first implementation milestone, create only:

```text
Floor 1: Help Desk
```

---

# 9. Room System

Rooms should be assembled from handcrafted templates, then selected procedurally.

Each room needs:

```text
Room ID
Room type
Door locations
Enemy spawn points
Obstacle locations
Reward spawn point
Difficulty score
Allowed floor tags
Minimum floor
Maximum floor
```

Room types:

```text
Start
Combat
Elite Combat
Treasure
Shop
Challenge
Boss
Secret
Transition
```

Use a simple connected room graph.

The first prototype can generate:

```text
Start room
4 to 6 combat rooms
1 treasure room
1 shop
1 boss room
```

Requirements:

1. The boss room must be reachable
2. The treasure room must not block progression
3. The map must not contain disconnected rooms
4. Rooms should not overlap
5. The player should see explored rooms on a minimap
6. Unexplored room types should remain hidden unless revealed by an item

---

# 10. Item Design Philosophy

Items are the heart of the game.

Items should usually change behavior, not merely increase numbers.

Weak item design:

```text
Plus 5 percent damage
```

Stronger item design:

```text
Projectiles split when they hit walls
```

A balanced item pool may include numeric upgrades, but the majority of memorable items should alter mechanics.

Each item should define:

```text
ID
Display name
Description
Rarity
Category
Tags
Stat modifiers
Behavior hooks
Visual changes
Synergy tags
Pickup sound
Icon
```

Suggested rarity tiers:

```text
Common
Uncommon
Rare
Prototype
Corrupted
```

---

# 11. Item Categories

## Weapon Cores

Change the primary firing pattern.

Examples:

```text
Laser emitter
Burst cannon
Saw launcher
Arc welder
Plasma orb
Rail spike
Drone command module
```

## Projectile Modifiers

Change projectile behavior.

Examples:

```text
Bounce
Pierce
Homing
Split
Explode
Freeze
Chain
Orbit
Return
Accelerate
Decelerate
Leave hazards
Duplicate on kill
```

## Processor Upgrades

Change timing or damage systems.

Examples:

```text
Critical hits
Faster fire rate
Charge shots
Heat based damage
Combo multiplier
Kill streak bonuses
```

## Mobility Modules

Change movement.

Examples:

```text
Extra dash
Teleport dash
Damage trail
Wall bounce
Dash explosion
Slow motion after near miss
```

## Defense Modules

Change survivability.

Examples:

```text
Orbiting shield
Armor plating
Projectile reflection
Emergency barrier
Repair on room clear
Damage reduction at low health
```

## Utility Modules

Change economy, mapping, drops, or room rules.

Examples:

```text
Reveal secret rooms
Convert excess health to scrap
Improve shop quality
Duplicate the first pickup on each floor
Reroll room rewards
```

## Corrupted Firmware

Powerful upgrades with a cost.

Examples:

```text
Double damage, half maximum health
Faster fire rate, increasing weapon spread
Enemies drop more scrap, shops become more expensive
Dash has no cooldown, dashing damages the player after repeated use
```

---

# 12. Initial Item Pool

Implement these first.

## 1. Ricochet Driver

Projectiles bounce off walls once.

```text
Tags: projectile, bounce
```

## 2. Fork Bomb

Projectiles split into two weaker projectiles on impact.

```text
Child damage: 60 percent
Tags: projectile, split
```

## 3. Magnetic Guidance

Projectiles gently curve toward nearby enemies.

```text
Tags: projectile, homing
```

## 4. Capacitor Leak

Every fifth shot creates a short chain lightning effect.

```text
Maximum jumps: 3
Damage per jump: 0.7
Tags: electric, chain
```

## 5. Cooling Fan

Increases fire rate.

```text
Fire rate increase: 20 percent
Tags: fire_rate
```

## 6. Reinforced Chassis

Adds two maximum integrity points and heals two integrity points.

```text
Tags: health, defense
```

## 7. Backup Battery

Adds one dash charge.

```text
Tags: movement, dash
```

## 8. Scrap Magnet

Pulls pickups toward the player.

```text
Tags: economy, pickup
```

## 9. Return Protocol

Missed projectiles reverse direction once at the end of their lifetime.

```text
Tags: projectile, return
```

## 10. Volatile Kernel

Explosions occur when enemies die.

```text
Tags: explosion, on_kill
```

## 11. Debug Drone

Adds one orbiting drone that fires when the player fires.

```text
Tags: drone, projectile
```

## 12. Unsafe Overclock

Increases damage and fire rate, but reduces maximum integrity.

```text
Damage increase: 35 percent
Fire rate increase: 25 percent
Maximum integrity change: minus 2
Tags: corrupted, damage, fire_rate
```

---

# 13. Synergy System

The game should support emergent combinations through reusable modifiers.

Do not hard code every possible item pairing.

Instead, create modular projectile and combat traits.

Example projectile state:

```text
damage
speed
lifetime
size
pierce_count
bounce_count
split_count
homing_strength
explosion_radius
chain_count
return_enabled
status_effects
owner
team
```

Example synergy:

```text
Ricochet Driver
plus
Fork Bomb
```

Result:

A projectile bounces once, then splits when it hits an enemy.

Another example:

```text
Magnetic Guidance
plus
Return Protocol
plus
Volatile Kernel
```

Result:

Missed projectiles reverse, home toward enemies, and trigger enemy death explosions.

Create explicit synergy rules only when a combination should have a special effect beyond normal composition.

Example explicit synergy:

```text
Debug Drone
plus
Capacitor Leak
```

Special result:

Drone shots count toward the fifth shot chain lightning trigger.

---

# 14. Weapon System Architecture

Weapons should be modular and data driven.

Suggested components:

```text
WeaponController
FirePattern
ProjectileFactory
ProjectileModifierStack
DamageResolver
StatusEffectController
```

The weapon controller should not directly contain all projectile behavior.

Projectile modifications should be applied at spawn time through a structured projectile configuration.

Avoid deeply nested item specific conditionals such as:

```text
if has_item_a and has_item_b and has_item_c
```

Prefer:

1. Trait composition
2. Event hooks
3. Modifier resources
4. Tagged effects
5. Small focused scripts

Suggested combat events:

```text
on_shot_fired
on_projectile_spawned
on_projectile_hit
on_projectile_expired
on_enemy_damaged
on_enemy_killed
on_room_cleared
on_player_damaged
on_dash_started
on_pickup_collected
```

---

# 15. Enemy Design

Enemies should create movement problems.

Each enemy should have a recognizable silhouette and one clear behavior.

The first prototype should include four standard enemies.

## Ticket Bot

Behavior:

Moves toward the player and fires slow single shots.

Purpose:

Basic pressure and tutorial enemy.

## Pop Up Drone

Behavior:

Teleports to room edges, pauses, then fires a three shot spread.

Purpose:

Forces aim changes and spatial awareness.

## Memory Leech

Behavior:

Moves quickly toward the player, stops briefly before charging, and deals contact damage.

Purpose:

Forces movement.

## Firewall Node

Behavior:

Remains stationary and projects rotating hazard beams.

Purpose:

Controls space and limits safe paths.

Optional elite modifier system:

```text
Faster
Armored
Volatile
Regenerating
Duplicating
Electrified
```

Do not add elites until the base enemies feel good.

---

# 16. Boss Design

## Floor 1 Boss: Merge Conflict

Theme:

A corrupted code integration machine that splits into incompatible versions of itself.

Arena:

Rectangular server room with four destructible terminals.

Phases:

## Phase 1

The boss fires alternating red and green projectile patterns.

## Phase 2

At 70 percent health, the boss duplicates into two versions.

One version uses red attacks.

The other uses green attacks.

Damage to one partially heals the other unless the player destroys one of the four synchronization terminals.

## Phase 3

At 35 percent health, the two versions merge incorrectly into a larger unstable form.

The boss uses:

1. Expanding ring attacks
2. Charge attacks
3. Projectile walls with gaps
4. Falling conflict markers

Defeat animation:

The boss collapses into code fragments, gears, and a giant resolved checkmark.

Boss reward:

Choose one of three rare items.

---

# 17. Economy

Primary currency:

```text
Scrap
```

Scrap drops from enemies and room rewards.

Use scrap in shops to purchase:

1. Items
2. Healing
3. Rerolls
4. Temporary floor buffs

Initial shop pricing:

```text
Common item: 12 scrap
Uncommon item: 20 scrap
Rare item: 32 scrap
Heal 1 integrity: 6 scrap
Reroll shop: 4 scrap, increasing by 2 each use
```

The player should not be able to buy everything.

Economy choices should create tension.

---

# 18. Pickups

Initial pickup types:

```text
Scrap
Repair cell
Temporary shield
Battery charge
Reroll token
Keycard
```

Repair cells restore health.

Battery charges restore active item energy if active items are implemented.

Keycards may open locked rooms or premium chests.

For the first milestone, only implement:

```text
Scrap
Repair cell
```

---

# 19. Risk and Reward Rooms

Later milestones may include:

## Challenge Room

Fight multiple waves for a high quality reward.

## Corrupted Terminal

Choose one powerful corrupted item from two options.

## Repair Bay

Trade scrap for health or maximum integrity.

## Compiler Shrine

Sacrifice one item to upgrade another.

## Debug Room

Fight a mirrored version of the player’s current build.

These are not required for the initial prototype.

---

# 20. Art Direction

Visual style:

```text
1990s arcade cabinet
Chunky pixel art
Corporate technology dystopia
CRT glow
Bold silhouettes
Limited palettes
Bright effects against dark environments
```

Influence categories:

```text
Arcade shooters
Retro computer interfaces
Industrial machinery
Old operating system windows
Cyberpunk office equipment
Saturday morning robot cartoons
```

Do not visually imitate any single existing game.

Player design:

A compact maintenance robot with:

1. Round head display
2. One expressive screen eye
3. Replaceable arm cannon
4. Small wheel or tracked base
5. Visible upgrade attachments

The player sprite should visibly change for major items where practical.

Examples:

```text
Extra drone appears
Larger cannon appears
Cooling fan spins
Armor plating attaches
Battery glows
```

---

# 21. User Interface

The UI should feel like a malfunctioning industrial operating system.

HUD elements:

```text
Integrity
Scrap
Current weapon
Active item
Dash charges
Floor name
Minimap
Boss health
Temporary effects
```

Visual motifs:

```text
Scan lines
Monospace labels
Status lights
Diagnostic warnings
Progress bars
Pixelated windows
```

Keep gameplay information readable.

CRT effects should be subtle and optional.

Include settings for:

```text
Screen shake
Flash intensity
CRT filter
Damage numbers
Master volume
Music volume
Effects volume
Fullscreen
```

---

# 22. Audio Direction

Music:

```text
Chiptune
Industrial percussion
Retro synth bass
Fast arcade loops
```

Sound effects should be short and readable.

Priority sounds:

1. Player firing
2. Enemy hit
3. Enemy death
4. Player damage
5. Item pickup
6. Room clear
7. Door opening
8. Dash
9. Boss phase transition
10. Low health warning

Avoid overly loud or fatiguing effects.

---

# 23. Game States

Implement a clear game state system.

Suggested states:

```text
Boot
Main Menu
Run Start
Room Active
Room Cleared
Paused
Item Selection
Shop
Boss Intro
Run Victory
Game Over
Settings
```

Pause gameplay cleanly.

Do not allow input to leak between UI and gameplay states.

---

# 24. Save System

Save only persistent information.

Initial save data:

```text
Settings
Unlocked items
Unlocked characters
Bosses defeated
Best run statistics
Tutorial completion
```

Do not save a run in progress for the first prototype.

Use versioned save data.

Example:

```json
{
  "save_version": 1,
  "settings": {},
  "unlocks": [],
  "statistics": {}
}
```

Handle missing or outdated fields gracefully.

---

# 25. Run Statistics

Track:

```text
Run duration
Rooms cleared
Enemies defeated
Bosses defeated
Damage dealt
Damage taken
Scrap collected
Items collected
Favorite weapon
Highest single hit
Longest no damage streak
Cause of death
```

Display a concise summary on game over.

---

# 26. Code Quality Requirements

The codebase must emphasize clarity and extension.

Requirements:

1. Use descriptive file and variable names
2. Keep scripts focused
3. Prefer composition over inheritance where practical
4. Avoid global state except for narrowly scoped autoload services
5. Avoid giant manager scripts
6. Use typed GDScript
7. Document non obvious logic
8. Store tunable values in resources or configuration files
9. Separate gameplay logic from presentation
10. Include simple test scenes for major systems
11. Do not optimize prematurely
12. Avoid magic numbers

Suggested autoloads:

```text
GameManager
RunManager
AudioManager
SaveManager
SceneRouter
EventBus
```

Keep the EventBus small and intentional.

---

# 27. Suggested Folder Structure

```text
res://
  art/
    characters/
    enemies/
    environments/
    effects/
    ui/
  audio/
    music/
    sfx/
  data/
    items/
    enemies/
    rooms/
    weapons/
  scenes/
    player/
    enemies/
    bosses/
    projectiles/
    rooms/
    floors/
    pickups/
    ui/
  scripts/
    combat/
    components/
    systems/
    resources/
    utilities/
  shaders/
  tests/
  autoload/
  main.tscn
```

---

# 28. Milestone Plan

## Milestone 1: Movement Sandbox

Deliver:

1. One test room
2. Player movement
3. Mouse aiming
4. Dash
5. Wall collision
6. Placeholder sprite
7. Camera
8. Debug overlay

Success condition:

Movement feels responsive for five minutes of continuous play.

## Milestone 2: Basic Combat

Deliver:

1. Rivet Blaster
2. Projectiles
3. One enemy
4. Enemy damage
5. Player damage
6. Death
7. Hit effects
8. Basic sound
9. Room clear detection

Success condition:

The player can enter a room, defeat enemies, and survive or die.

## Milestone 3: Room Loop

Deliver:

1. Locked doors
2. Enemy spawning
3. Room clear rewards
4. Multiple connected rooms
5. Basic minimap
6. Start room
7. Combat rooms
8. Treasure room

Success condition:

The player can complete a small multi room run.

## Milestone 4: Item System

Deliver:

1. Item resources
2. Item pickup UI
3. Item inventory
4. Six initial items
5. Projectile modifier composition
6. At least four working synergies

Success condition:

Two runs can produce noticeably different combat styles.

## Milestone 5: Floor 1

Deliver:

1. Four enemies
2. Eight to twelve rooms
3. Shop
4. Scrap economy
5. Twelve initial items
6. Floor generation
7. Merge Conflict boss
8. Game over screen
9. Run statistics

Success condition:

A complete eight to twelve minute run is playable.

## Milestone 6: Polish

Deliver:

1. Pixel art replacement
2. Sound pass
3. Music
4. Visual effects
5. UI polish
6. Settings
7. Controller support
8. Save data
9. Balance pass
10. Export build

Success condition:

A new player can understand and enjoy the game without developer explanation.

---

# 29. Minimum Viable Product

The MVP must include:

```text
One playable character
One floor
Eight to twelve rooms
Four regular enemies
One boss
One starting weapon
Twelve items
One shop
Procedural room selection
Scrap currency
Health
Dash
Game over screen
Run statistics
Basic audio
Basic settings
```

Do not add additional floors before the MVP is enjoyable.

---

# 30. Scope Guardrails

Do not include these in the first version:

```text
Online multiplayer
Local cooperative play
User accounts
Cloud saves
Procedural pixel art
Large narrative cutscenes
Complex crafting
Skill trees
Daily challenges
Live services
Leaderboards
Mod support
Multiple playable characters
More than one floor
More than one boss
```

These features may be considered only after the MVP is stable.

---

# 31. Acceptance Criteria

The project is ready for an initial public demo when:

1. The game launches without errors
2. The player can complete a full run
3. Every room is reachable
4. The boss can be defeated
5. Items stack without breaking the game
6. At least four item combinations feel meaningfully different
7. The game maintains a stable frame rate
8. Losing immediately permits a new run
9. Audio and visual settings persist
10. There are no placeholder error messages
11. Controls are explained in game
12. The game can be exported to desktop and web if supported

---

# 32. First Implementation Task

Begin by creating Milestone 1 only.

Create:

1. A Godot 4 project
2. A fixed resolution game window
3. Input actions
4. A test room
5. A player scene
6. Smooth movement
7. Mouse aiming
8. Dash with cooldown
9. Wall collisions
10. A debug HUD showing speed, dash status, and player coordinates

Do not build enemies, procedural generation, items, menus, or bosses yet.

After Milestone 1 works, provide:

1. A concise summary of the architecture
2. A list of created files
3. Instructions for running the project
4. Known limitations
5. The next recommended task

---

# 33. Model Working Instructions

When implementing this project:

1. Make small, testable changes
2. Keep the game runnable after every milestone
3. Explain major architectural decisions
4. Do not invent dependencies without documenting them
5. Prefer engine native features
6. Avoid adding plugins unless clearly justified
7. Do not replace working systems without a concrete reason
8. Preserve existing code style
9. Surface uncertainty clearly
10. Fix errors before expanding scope
11. Provide complete file contents when creating new files
12. Provide focused diffs when modifying existing files
13. Never skip setup instructions
14. Never claim code has been tested unless it was actually executed
15. Treat this document as the design authority

When tradeoffs arise, prioritize in this order:

```text
Game feel
Reliability
Clarity
Extensibility
Content quantity
Visual polish
```

The objective is not to build the largest game.

The objective is to build a small game that already feels excellent.
