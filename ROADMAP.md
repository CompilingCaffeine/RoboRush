# Robo Rush Roadmap: Improvements, Feature Upgrades, and New Content

- **Status:** Planning proposal. Nothing below is implemented yet.
- **Baseline:** `1c450d8` on `main` (2026-09-19). Six floors, six bosses, 16 enemies, 54 items, 52 room templates, and 35 test files.
- **Authority:** [robo_rush_build_spec.md](robo_rush_build_spec.md) is still the design authority. Where this plan departs from it, the entry says so. The post-boss hazard contract in [SIX_FLOOR_SCALING_GAMEPLAN.md](SIX_FLOOR_SCALING_GAMEPLAN.md) still holds.

This plan comes from reading the code and data, not from playing the game. Every finding cites the file that shows it. Every proposal is sized, lists its dependencies, and states the evidence that should count as "done". The six-floor campaign already works, so the plan builds on it without restructuring it.

## Contents

1. [Where the game stands](#1-where-the-game-stands)
2. [Ground rules for all new work](#2-ground-rules-for-all-new-work)
3. [Track A: fix first](#3-track-a-fix-first)
4. [Track B: codebase health](#4-track-b-codebase-health)
5. [Track C: improving existing features](#5-track-c-improving-existing-features)
6. [Track D: new systems that content depends on](#6-track-d-new-systems-that-content-depends-on)
7. [Track E: new content](#7-track-e-new-content): items, active items, elites, rooms, enemies, bosses, and levels
8. [Track F: modes and meta-progression](#8-track-f-modes-and-meta-progression)
9. [Sequenced milestones](#9-sequenced-milestones)
10. [Decisions needed from the owner](#10-decisions-needed-from-the-owner)
11. [Risks](#11-risks)
12. [Appendix: design cards and file map](#12-appendix-design-cards-and-file-map)

**Effort key** (rough, for one developer who knows the codebase): **S** ≤ 1 day · **M** 2–5 days · **L** 1–3 weeks · **XL** more than 3 weeks.
**Implementation tags for content:** **DATA** can be written today as a `.tres` using existing fields. **HOOK** needs a new field on an existing resource plus a small hook in an existing system. **SYSTEM** needs a new subsystem from Track D.

---

## 1. Where the game stands

| Area | Shipped | Notes |
| --- | --- | --- |
| Floors | 6 | Help Desk, Development, Data Center, Cloud Operations, Executive Systems, Core Intelligence. Ten rooms each. |
| Room templates | 52 | Floors 1–2 have **4 combat templates each**. Floors 3–6 have 7–8 each. |
| Room types generated | 5 of 9 | START, COMBAT, TREASURE, SHOP, and BOSS. `RoomTemplate.Type` also declares ELITE_COMBAT, CHALLENGE, SECRET, and TRANSITION, but `FloorGenerator.SPECIAL_TYPES` never schedules them. |
| Enemies | 16 | 11 base designs and 5 "one rung up" variants (Hot Path Runner, Optimizing Compiler, Redundant Firewall, Elder Recursion, Lagging Replica). Floor 4 introduces **no enemy of its own**. |
| Bosses | 6 | The Scrap King, Runtime Error, Cascade Failure, and Orchestrator are shuffled across Floors 1–4. Executive Override (a Runtime Error rematch) always guards Floor 5. Core Intelligence always guards Floor 6 and wears five **hard-coded** masks. |
| Items | 54 | 48 unique items and 6 repeatable chips. By rarity: 15 common, 12 uncommon, 18 rare, **1 prototype**, and 8 corrupted. |
| Item categories | 7 | Weapon core 3, projectile 19, processor 9, **mobility 3**, defence 8, **utility 4**, corrupted 8. |
| Pickups | 3 kinds | Scrap, repair cell, and item. Spec §18 lists six. |
| Status effects | 4 | Chill, freeze, burn, and shock. |
| Player weapons | 1 | The Rivet Blaster. The three "weapon core" items modify it rather than replace it. |
| Active items | 0 | `use_active_item` is bound to the right mouse button and left trigger, and the README lists it, but no code reads it. |
| Modes | 1 | The campaign. Seeds are available only from the command line. The Web build has a fastest-victory leaderboard. |
| Meta-progression | Records only | `SaveManager.unlocked_items` records every item ever picked up, but nothing reads it. |

**What must survive every change below.** These are the project's real strengths:

- **Composition over pairing.** `ItemConfig` names `ProjectileConfig` fields in three dictionaries, so synergies emerge without code that handles specific item pairs.
- **Named RNG streams** (`RunRng`). Adding a draw in one system cannot reshuffle another system.
- **`CampaignValidator`, checkpoint validation, and the declared field lists in `RunManager`.** `test_gate` makes it impossible to add a run-wide field without classifying it.
- **Clear design rules.** Each enemy has one sentence, each boss asks for one verb (notice, predict, keep moving, be somewhere first), and each floor teaches one idea.
- **The post-boss hazard contract.**
- **A large test suite** with determinism, soak, performance, and economy simulations.

---

## 2. Ground rules for all new work

These rules turn the codebase's unwritten conventions into a checklist. Every entry in Tracks C–F assumes them.

1. **Priority order is unchanged:** game feel, reliability, clarity, extensibility, content quantity, then visual polish.
2. **Content is data.** A new behaviour becomes a field on `ItemConfig`, `ProjectileConfig`, or `EnemyConfig` plus one hook. It never becomes `if has_item_a and has_item_b`.
3. **Every new `ItemConfig` field must be classified** in `has_upside()` and `is_stat_only()`, and aggregated in `ItemInventory`. `tests/test_items.gd` holds the hindrance tag against `has_upside`, so an unclassified field is a silent misclassification.
4. **Enums are append-only.** `RoomTemplate.Type`, `ItemConfig.Rarity`, and `ItemConfig.Category` are stored as integers in `.tres` files (for example, `rarity = 4`). Inserting a value in the middle silently changes every resource after it.
5. **Stable ids never change** (items, bosses, floors, and campaigns). A new name goes in `display_name`.
6. **Every new seeded draw gets its own named stream** in `RunRng`. It must never consume numbers from an existing stream.
7. **`content_version` is precious.** `RunCheckpoint._validate_identity` refuses a checkpoint whose content version differs from the campaign's. A bump therefore drops every saved run in progress, including hosted Wavedash saves. Batch content changes into releases, and show the player a clear message when a saved run is dropped (see ENG-9).
8. **Every new run-wide field goes into one of `RunManager`'s declared lists**, into `RunCheckpoint` serialisation and `validate()`, and into `test_checkpoint`'s round trip.
9. **The post-boss hazard contract stands.** An active item or defensive item that clears hostile projectiles is a *player-spent* effect, not an automatic safe state. Section 10, decision Q6, asks the owner to confirm this.
10. **Every enemy gets one sentence, every boss one verb, and every floor one idea.** The design cards in the [appendix](#12-appendix-design-cards-and-file-map) make this a template.
11. **Nothing ships without tests** in the matching suite, plus a validator rule wherever content can be malformed.

---

## 3. Track A: fix first

Review found these problems. Most are small, and several block content in later tracks.

| ID | Finding | Severity | Effort |
| --- | --- | --- | --- |
| FIX-1 | Scrap Magnet drags **item** pickups, including pure-cost hindrances, into the robot. | High | S |
| FIX-2 | Free floor drops can be pure-cost hindrances, and items are collected on contact without any explanation. | High | S–M |
| FIX-3 | Rarity sets price and boss-reward priority but **does not affect how often an item appears**. "Rare" is the largest tier. | Medium | M |
| FIX-4 | The Scrap King's red and green attacks differ **only by hue**, which colour-vision deficiency makes hard to read. | Medium | S–M |
| FIX-5 | Design rationale lives in `;` comments inside `.tres` files, which are lost when the Godot editor re-saves the resource. | Medium | M |
| FIX-6 | An advertised control (active item) does nothing. | Low | S |
| FIX-7 | Keyboard players cannot aim with the mouse, although spec §5 expects it and Web players reach for it first. | Medium | M |
| FIX-8 | Floors 1–2, which every run plays, have the thinnest room variety in the game. | Medium | M |
| FIX-9 | On the minimap, a visited shop or boss room looks the same as a combat room. | Low | S |

### FIX-1: Scrap Magnet pulls items

- **Evidence:** `ItemEffects._physics_process` (`scripts/systems/item_effects.gd:39`) moves every node in `Pickup.GROUP` toward the robot with no filter by kind. `Pickup._on_body_entered` (`scenes/pickups/pickup.gd:46`) collects items on contact. A combat-clear drop of Tech Debt or Off-By-One inside 72 px is therefore dragged into the player. The existing test (`test_items.gd:1112`) covers scrap only.
- **Fix:** Skip `PickupConfig.Kind.ITEM` in the magnet loop, and add a regression test.
- **Also verify:** a declined repair cell that the magnet drags under a robot at full integrity may never fire `body_entered` again while the two overlap. Add a test that damages the robot while the cell rides along.

### FIX-2: Hindrances as free drops

- **Evidence:** `RunManager.draw_item` (`autoload/run_manager.gd:532`) does not exclude hindrances. `LootSpawner.spawn_item` and `spawn_treasure` place the result on the floor as a contact pickup. `ItemConfig.description` is deliberately never shown, so a player can walk into Blocking I/O in a treasure vault without knowing what it does.
- **Fix, minimal:** Give `draw_item` a context argument. Floor drops (combat clears and treasure) exclude `is_hindrance()` items. Shops and the new Corrupted Terminal room (RM-5) may still offer them, because there the offer is a visible choice with a price or a trade-off.
- **Fix, fuller:** Adopt the drop tables in IMP-3 and the readability decision in IMP-2.
- **Acceptance:** Across 10,000 simulated campaigns, no floor drop is a hindrance, and every hindrance is still offered somewhere.

### FIX-3: Rarity does not weight draws

- **Evidence:** `draw_item` picks uniformly (`candidates[rng.randi_range(...)]`). Rarity only indexes `ShopConfig.item_prices` and orders `_draw_boss_reward`. With 18 rare items against 15 common, "rare" is the most common tier. Adrenal Loop is the only prototype.
- **Fix:** Add weights per context (see IMP-3), draw deterministically from the existing reward and shop streams, and re-run `test_economy` and `test_balance`. This changes floor manifests, so it needs a `content_version` bump (ground rule 7).

### FIX-4: Red/green-only boss read

- **Evidence:** `art/effects/projectile_boss_red.png` and `projectile_boss_green.png` are the same circle in two colours (`MergeConflict.RED` and `.GREEN`, `scenes/bosses/merge_conflict.gd:33`). Phase 2 depends on telling the two versions apart, because damage to one partially heals the other.
- **Fix:** Give each version a different silhouette, for example red as a diamond or cross and green as a hollow ring, and give each body a matching tell. Then add a colour-vision setting (IMP-10). Update `tools/generate_art.py`, not the PNGs.

### FIX-5: Rationale stored in `.tres` comments

- **Evidence:** `floor_3_data_center.tres` has 51 comment lines, `floor_4_cloud_ops.tres` has 47, and many room templates have 10–22. Godot's text-resource saver regenerates the whole file, so one save in the inspector deletes all of it. Confirm this once in the editor.
- **Fix:** Add `@export_multiline var design_notes: String` to `FloorConfig`, `RoomTemplate`, `EnemySpawn`, and `BossEncounter`, and move the text there. It then survives editor saves and appears in the inspector. Add a CI check that fails on `^;` lines in `data/**/*.tres`.

### FIX-6: Dead active-item control

- **Evidence:** `use_active_item` appears only in `project.godot` and `tools/generate_input_map.gd`, yet the README's controls table lists it.
- **Fix:** Implement active items (SYS-3). Until then, remove the row from the README so the game does not advertise a button that does nothing.

### FIX-7: No mouse aim

- **Evidence:** `PlayerInput` reads only the arrow keys and the right stick, so keyboard aim is limited to 8 directions. Spec §5 lists "Mouse: Aim / Left Mouse: Fire".
- **Fix:** Add an optional aim mode (arrows, or mouse plus left-click fire) inside `PlayerInput`, which is already the only file that reads input. Convert the pointer position through the viewport's canvas transform. The stretch mode is `viewport`, so account for the 3× scale. Add a setting and a controls-card variant. The existing input tests can drive it.

### FIX-8: Thin early floors

- **Evidence:** `floor_1_help_desk.tres` and `floor_2_development.tres` each list four combat templates. The notes in Floors 3 and 4 already recorded that four templates made the teaching room about 2.4 of every 6 combat rooms and left floors under-populated.
- **Fix:** Add 3–4 templates per floor, at difficulty 2–3, where most draws land (see RM-9). Floors 1 and 2 are played on every run, so repetition hurts most there.

### FIX-9: Minimap forgets the shop

- **Evidence:** `Minimap._colour_for` (`scenes/ui/minimap.gd:160`) colours only START and TREASURE. A player who comes back with more scrap has to remember where the shop was.
- **Fix:** Add a colour or a 3×3 glyph for SHOP and BOSS rooms once visited (IMP-5 extends this).

---

## 4. Track B: codebase health

| ID | Item | Effort | Depends on |
| --- | --- | --- | --- |
| ENG-1 | Split `FloorController` (1,159 lines) | L | — |
| ENG-2 | Boss attack-primitive library and data-driven finale masks | L | — |
| ENG-3 | Move design notes out of `.tres` comments | M | — |
| ENG-4 | Static analysis in CI | S–M | — |
| ENG-5 | Split CI into fast tests, export, and nightly soak | M | — |
| ENG-6 | Autopilot: a headless playtesting bot | L | — |
| ENG-7 | Opt-in run telemetry and balance reports | M | ENG-6 helps |
| ENG-8 | Room authoring from ASCII layouts, plus a room validator | M | — |
| ENG-9 | Save schema v4 and the policy for content-version bumps | M | — |
| ENG-10 | Combat caps and a VFX budget | M | — |
| ENG-11 | Prepare for localisation | M | — |
| ENG-12 | Comment hygiene and a player-facing changelog | S | — |

### ENG-1: Decompose FloorController

It currently owns generation, session lifecycle, room entry, shop stocking, boss draw, boss reward, trophy, transitions, and resume state. Spec §26 says to avoid giant manager scripts. Extract these pieces, keeping `FloorController` as the coordinator:

- `BossRewardDealer`: `_draw_boss_reward`, `_take_reward`, `_restore_boss_reward`, and `get_pending_boss_reward_ids`.
- `FloorTransition`: `_finish_floor`, `_advance_to_next_floor`, and `_release_session`.
- `RoomEntryDirector`: `_enter_room`, `_needs_clearing`, `_award_first_visit`, and door locking.
- `ShopStocker`: `_stock_shop` and restoring `ShopStock`.

This is a pure refactor. The acceptance test is that every existing suite passes unchanged and the determinism fingerprints are byte-identical. Do this **before** Track D adds more special rooms, because each new room type would otherwise grow this file.

### ENG-2: Boss attack primitives and data-driven masks

Boss scripts run 584–1,009 lines. Core Intelligence extends Runtime Error's attack vocabulary with integer offsets (`ATTACK_VENTS := 6`, and so on, "numbered on from its enum"). That works, but it is fragile.

Extract a small library of primitives, each with a telegraph phase and an execute phase:

- a ring with gaps
- an aimed volley
- a projectile wall with gaps
- a lane (reusing `CompileLane`)
- a vent (reusing `ThermalZone`)
- a marker drop
- a migration

Existing bosses keep their authored sequencing and call these primitives. The same primitives then serve the new enemies (Hold Music, EN-1) and the mini-bosses (Track E).

**Masks as data.** `CoreIntelligence.Mask` is a fixed enum of Scrap King, Runtime Error, Cascade Failure, Orchestrator, and Core. When BOSS-2 and later bosses join the pool for Floors 1–4, a run could fight a boss the finale never wears, which breaks the finale's premise that it wears the bosses the player fought. Define a `BossMask` resource (footprint, attack rotation, damage rule, banner) that ships with each boss. Core Intelligence then picks its masks from `RunManager.fought_boss_ids`, in the order the run fought them, with the Core mask last. Any boss added to the Floors 1–4 pool must ship a mask, and `CampaignValidator` enforces this.

### ENG-3: Design notes

See FIX-5. After the move, add a validator warning for any floor or room without notes, since the notes are the project's design record.

### ENG-4: Static analysis

- Add `gdtoolkit` (`gdlint` and `gdformat --check`) to CI, with a config tuned to the current style so the first run is not 5,000 warnings.
- In `project.godot`, raise `debug/gdscript/warnings/untyped_declaration`, `unused_variable`, and `unsafe_*` to warnings or errors. Spec §26 requires typed GDScript, so enforce it.
- Run `ruff` on `tools/*.py` and `tools/ci/*.py`, and `shellcheck` on `tools/**/*.sh`.

### ENG-5: CI shape

Today a single job runs `tools/ci/build_web.sh`, which imports, tests, exports, and smoke-tests. Split it into:

1. **tests:** import plus `test_runner`. This is the fastest signal and should be a required check.
2. **web-export:** runs after tests. Export, verify, smoke-test, and upload the artifact exactly as now.
3. **nightly:** `executive_runner`, `finale_runner`, `soak_runner`, `profile_executive`, and ENG-6's Autopilot campaigns. Publish timings so any regression is visible.

Cache the pinned Godot binary by `tools/engine.lock` hash. Print a table of per-suite durations so slow suites are visible.

### ENG-6: Autopilot, a headless playtesting bot

`PlayerInput` is already test-drivable, and `HostileRegistry` knows every threat. Write a scripted pilot with a simple policy:

- aim at the nearest target, leading moving ones
- strafe at the preferred range
- dash across incoming projectiles inside a danger cone
- walk to rewards, buy the cheapest shop item, and take the first boss reward

Run N seeded campaigns at `--fixed-fps 60` and emit JSON with time per room, damage taken per enemy type and per boss attack, deaths by floor, and scrap curves. This is not a balance oracle. It is a **regression detector**: if a change doubles the Autopilot's damage taken in Data Center rooms, a human should look. It builds on the existing `tests/greybox_campaign.gd` and `tests/floor_economy.gd`.

### ENG-7: Telemetry and balance reports

`RunStats` already records cause of death, damage, rooms, and per-floor records. Add a local-only, opt-in run log (`user://runs/*.json`, capped at 50 files) with per-room entries: template id, time, damage taken and its sources, and items held. Add `tools/balance_report.py` to aggregate Autopilot or human logs into item pick-and-win rates, the deadliest rooms and enemies, and run-duration distributions against spec §4's 25–40 minute target. There is no network telemetry unless the owner asks for it.

### ENG-8: Room authoring

Rooms are `Rect2i` arrays edited by hand in `.tres` files, which is slow and error-prone. Add `tools/rooms/*.txt` ASCII layouts:

```text
# data_new_room  difficulty=2  floors=3-4  tags=data_center
##########################
#........................#
#..XX........E.......XX..#
#..XX................XX..#
#.....E....~~~~....E.....#
#..........~~~~..........#
#..XX................XX..#
#..XX.......R........XX..#
#........................#
##########################
```

Here `X` is an obstacle, `E` an enemy spawn, `R` the reward spawn, `~` a thermal zone, `=` a duct, `a`/`A` a linked pad pair, and `$` a shop stand. `tools/compile_rooms.py` turns each layout into `.tres`, and the reverse direction lets existing rooms be converted.

Pair it with a room validator in `CampaignValidator` or a new `RoomValidator`:

- every door reaches every other door and every spawn (flood fill)
- no spawn is inside an obstacle or within N tiles of a door
- the reward spawn is clear
- pad links are paired
- thermal zones leave a safe path

### ENG-9: Save v4 and content-version policy

Plan all new persistent fields in **one** migration (v3 to v4), not one per feature:

- `discovered_items`, a rename of today's `unlocked_items` meaning "ever picked up"
- a true `unlocked_items` list (META-3)
- `achievements`
- `characters_unlocked`
- per-mode and per-difficulty records
- key bindings, aim mode, and accessibility settings
- `archive_seen` flags

The current forward-version guard stays. **Content-version policy:** a bump drops saved runs. Tell the player on the main menu ("Your saved run was from an older build and could not continue."), and give release notes a checklist item: "Does this release bump `content_version`?"

### ENG-10: Combat caps

Before adding split depth, orbiting shots, echoes, and swarm bosses, add a `CombatCaps` resource enforced in `ProjectileFactory` and `ItemEffects`:

- maximum live player projectiles (drop the oldest non-piercing shots first)
- maximum split depth and children per impact
- maximum drones and turrets
- maximum status stacks
- maximum explosions per frame (queue the excess to the next frame)

`test_balance`'s "worst legal build" gains these as assertions. Profile the hosted Web build as `SIX_FLOOR_SCALING_GAMEPLAN.md` work package 6 describes.

### ENG-11: Localisation readiness

UI strings are hard-coded constants such as `"START RUN"`. Wrap them in `tr()`, move them to a CSV translation table, and make sure `tools/generate_ui_font.py` can emit glyph coverage for at least Latin-1. This is low priority but cheap if done before the menu count grows.

### ENG-12: Comment hygiene and changelog

Keep the explanatory "why" comments; they are an asset. Move historical narration ("used to…", "was renamed…") into commit messages once the code no longer depends on that history. The recent commit "Say what the code does now" already follows this direction. Add a short player-facing `CHANGELOG.md` for Wavedash playtesters.

---

## 5. Track C: improving existing features

| ID | Item | Effort | Depends on |
| --- | --- | --- | --- |
| IMP-1 | Controls: mouse aim, fire toggle, rebinding, device glyphs | M–L | FIX-7 |
| IMP-2 | Item readability (**owner decision**) | M | — |
| IMP-3 | Reward model v2: drop tables, rarity weights, enabler-aware offers | M | FIX-2, FIX-3 |
| IMP-4 | Shop v2 | M | IMP-3 |
| IMP-5 | Minimap and navigation | S–M | FIX-9 |
| IMP-6 | Combat feel pass | M | — |
| IMP-7 | Waves in `RoomCombat` | M | — |
| IMP-8 | Boss presentation: intro card, spec §16 defeat moment | M | — |
| IMP-9 | Run summary, sharing, and death recap | M | — |
| IMP-10 | Accessibility pack | M | FIX-4 |
| IMP-11 | Adaptive music and audio polish | M | — |
| IMP-12 | Difficulty tiers | M | ENG-9 |

### IMP-1: Controls

- **Mouse aim** (FIX-7), with a small reticle drawn at logical resolution.
- **Fire mode:** hold (today's behaviour) or toggle, for mouse and right stick. Spec §5's right-trigger fire is also missing: add `fire` bound to the right trigger and left mouse button, used when aiming by stick or mouse.
- **Rebinding screen** in Settings, persisted in the v4 save (ENG-9) and regenerated through `tools/generate_input_map.gd`'s action list.
- **Device glyphs:** the controls card and prompts ("E BUY") switch between keyboard, Xbox, and PlayStation labels according to the last device used.
- **Optional light aim assist** for the stick: a snap within 8°, off by default, and recorded on leaderboard entries.

### IMP-2: Item readability (owner decision)

The code deliberately never shows `description`; see the `ItemConfig.description` and `CombatHUD` docs. The trade-off is real. With 54 items, and 100+ after Track E, discovery becomes guesswork, and FIX-2 shows the cost. Here are three options, from least to most change:

- **(a) Keep it hidden in runs, add the Archive** (META-4). Descriptions appear in a menu screen for items already discovered. The in-run experience does not change.
- **(b) Add a pickup tagline.** Add `tagline` (at most 28 characters, for example "BOUNCES OFF WALLS") to `ItemConfig`, shown under the name in the pickup banner. This is the Isaac compromise: the tagline hints without explaining numbers.
- **(c) Show the build while paused.** Holding Tab (run stats) or pausing shows item icons with their taglines. Combat never shows them.

**Recommendation:** (a) + (b) + (c). Taglines keep the "items explain themselves by being used" spirit while ending "I don't know what just happened to my gun". The validator should require a tagline for every item.

### IMP-3: Reward model v2

- **`DropTable` resource per context:** `COMBAT_CLEAR`, `TREASURE`, `SHOP`, `BOSS`, `SECRET`, `CHALLENGE`, `ELITE`, and `TERMINAL`. Each holds rarity weights, category weights, and exclusions (hindrance or corrupted allowed?).
  - Suggested defaults: combat clears 50/35/15/0/0 across common/uncommon/rare/prototype/corrupted. Treasure 30/40/28/2/0. Shop 35/35/25/0/5. Boss uses rare and prototype first, with today's beneficial-slot guarantee kept. Secret uses 0/20/50/30/0.
- **Enabler-aware offers.** Wide Bus and Fragmentation say in their descriptions that they do nothing alone ("Does nothing without something that splits"). Add `requires_any_tags: Array[StringName]` and `boost_if_any_tags`. An item whose requirement is unmet is not offered as a free drop and is down-weighted in shops. When an enabler is held, the dependent item's weight rises. This steers toward synergy without scripting it.
- **Diversity guard:** avoid offering a third item whose only tag is `knockback` while two unchosen knockback items are already on offer.
- **Determinism:** reuse `SHOP` and `REWARD` streams and add `SECRET` and `CHALLENGE` streams. Bump `content_version`.
- **Acceptance:** extend `test_economy` to 10,000 campaigns and assert the observed rarity frequencies per context fall within ±2% of the weights, no empty required offer, and no free hindrance.

### IMP-4: Shop v2

- **Price curve by floor.** Clear scrap drops from 1–3 on Floors 1–4 to 1–2 on Floors 5–6, while `ShopConfig` prices stay flat. Make the curve explicit by adding a `price_scale_by_floor` array. Whatever the tuning, write the intended purchasing power per floor into the economy test.
- **Third item stand from Floor 3** (`item_stand_count` per floor).
- **Floor-buff stand** (spec §17, "temporary floor buffs", not yet implemented). A one-floor effect for about 10 scrap: +1 Faraday charge per room, reveal the map (Traceroute for one floor), or +20% scrap drops.
- **Shop-exclusive stock:** a small pool (Open Source, Monetization, Recycle Bin) that appears only on shelves.
- **"Hotfix" reroll token** (PU-3) as a free reroll.
- **Keep:** the reroll price step, and `release_item` on reroll (its doc describes a real soft-lock, so preserve that behaviour).

### IMP-5: Minimap and navigation

- FIX-9 glyphs for shop, boss, treasure, and later the elite, challenge, and closet rooms.
- **`reveal_all` finally gets its item.** `Minimap.reveal_all` is documented as "an item that reveals room types later only has to flip `reveal_all`". Traceroute (ITM-37) and Ping (ACT-9) should use it.
- **Cleared marker:** a dot in rooms that are cleared but still hold an uncollected pickup, so leftover repair cells are not forgotten.
- A **larger map on Tab**, drawn with the run statistics.

### IMP-6: Combat feel pass

Audit against spec §7's feedback list.

- **Crits** (ITM-19) need their own damage-number style.
- **Spawn-in:** enemies are present on room entry, protected only by the robot's 0.6 s `room_entry_grace`. Add a 0.4 s "materialise" shimmer during which enemies cannot fire. This makes the grace period readable instead of invisible.
- **Enemy projectile readability:** a dark 1 px outline on hostile shots (a setting in IMP-10) so they stay visible over bright thermal zones and lanes.
- **Hit-stop tuning:** today `GameManager.hit_pause` refuses nested pauses. Give heavier hits longer pauses (crits, boss phase changes), capped.
- **Muzzle variety per weapon core** once the SYS-1 weapon cores exist.

### IMP-7: Waves in `RoomCombat`

`RoomCombat` says wave scheduling "was never built and nothing in the game asks for it". The Challenge rooms (RM-2), the Autoscaler (EN-4), and later floors do. Add `RoomTemplate.waves: Array[WaveSpec]`, where each spec lists spawn points or enemy entries plus a trigger ("previous wave at ≤ N alive" or "after T seconds"). `RoomCombat` reports `cleared` only after the last wave. Spawns use the SHIMMER from IMP-6 and come from the encounter stream. Test that a wave room never clears early, and that restart, death, and descent mid-wave leak nothing (per the floor-session ownership rules).

### IMP-8: Boss presentation

- **Boss intro card** (spec §23 "Boss Intro" state): name, a one-line title from `BossEncounter` (for example, "THE SCRAP KING // everything the company threw away"), and 1.2 s with no input lockout beyond the existing room-entry grace. Skippable with any action. Shown once per boss per save, then shortened.
- **Audit the spec §16 defeat moment** ("collapses into code fragments, gears, and a giant resolved checkmark") against what ships. Give each boss a signature defeat burst.
- **Phase stingers:** `boss_phase.wav` exists. Add a per-boss variant through `BossEncounter`.

### IMP-9: Run summary and sharing

- **Build card:** seed, character, difficulty, time, deepest floor, and item icons in pickup order, as a screenshot-friendly panel with a "copy seed" button. On Web, copy through `JavaScriptBridge`.
- **Per-floor splits** from the `FloorRecord`s that already exist.
- **Damage by source:** the top three things that hurt the robot this run.
- **Death recap:** the killing blow's source, plus the last 3 hits (a ring buffer in `RunStats`).

### IMP-10: Accessibility pack

- **Colour-vision modes** (deuteranopia, protanopia, tritanopia): palette swaps through `UIPalette` and projectile configs. This depends on FIX-4 making shapes carry the meaning first.
- **High-contrast hostile projectiles** (IMP-6 outline).
- **Game speed** (assist) of 70–100%. Runs below 100% are flagged, not ranked.
- **Hold versus toggle fire** (IMP-1).
- **Reduce motion:** one switch that sets shake to 0, flash to 0.3, and turns off CRT.
- **Text scale** is limited at 480×270. Offer a bolder font variant from `generate_ui_font.py` instead.

### IMP-11: Adaptive music

`tools/generate_music.py` writes per-floor explore and boss tracks. Generate each explore track as **two stems** (a calm bed and a combat layer) and cross-fade the combat layer in when doors lock and out on clear. Add a low-integrity filter (a low-pass on the music bus while at 1 integrity). `low_integrity.wav` already exists as the one-shot cue.

### IMP-12: Difficulty tiers

Named in-fiction:

- **Staging** (assist): +2 integrity, 85% hostile projectile speed, a repair every 2 clears, no elites.
- **Production** (today's game, unchanged).
- **Incident** (hard): `enemy_health_scale` starts at 1.25, the elite chance doubles, repairs every 4 clears, and the boss reward is 2 of 3. The Incident tier unlocks after the first victory.

`REPAIR_EVERY_CLEARS` is a `const` in `FloorController` (`floor_controller.gd:78`), so move it to `FloorConfig` or a `DifficultyConfig` first. Keep separate leaderboards per tier. The difficulty is recorded in the checkpoint and in `RunStats`.

---

## 6. Track D: new systems that content depends on

| ID | System | Effort | Unlocks |
| --- | --- | --- | --- |
| SYS-1 | Weapon modifiers on items (`weapon_set/add/scale`) | M | True weapon cores |
| SYS-2 | Projectile behaviour extensions | L | About 15 new items |
| SYS-3 | Active item slot | L | Active items; `use_active_item` finally does something |
| SYS-4 | Elite modifiers | M | Elite rooms, the YOLO Deploy item, the Incident tier |
| SYS-5 | Special-room manifest and hidden placement | L | Elite, challenge, secret, closet, terminal, repair, refactor, and transition rooms |
| SYS-6 | New pickup kinds | M | Shield, battery, Hotfix token, Access Badge |
| SYS-7 | Certifications (set bonuses) | M | Build identity and a meta-goal |
| SYS-8 | Item upgrades (v2 items) | M | The Refactor Station |
| SYS-9 | Branching campaigns | L | Floor variants and the alternate path |

### SYS-1: Weapon modifiers on items

`WeaponConfig` has `shots_per_second`, `projectiles_per_shot`, `spread_degrees`, and `muzzle_offset`, but items can reach only `fire_rate_scale`. Mirror the projectile dictionaries with `weapon_set`, `weapon_add`, and `weapon_scale`, validated against `WeaponConfig`'s property list the same way `ProjectileModifierStack` refuses unknown keys. Add fields where missing:

- `lateral_offset`, for parallel shots
- `alternate_rear`, which fires backwards every other shot
- `fire_mode` (`AUTO` or `CHARGE`)
- `charge_seconds` and `charge_max_scale`

### SYS-2: Projectile behaviour extensions

Add each as a `ProjectileConfig` field so items stay pure data:

| Field(s) | Behaviour | Spec §11 name |
| --- | --- | --- |
| `speed_over_life`, `damage_over_life` (curve or end multiplier) | Accelerate or decelerate | Accelerate / Decelerate |
| `orbit_seconds`, `orbit_radius` | Orbits the owner, then releases | Orbit |
| `trail_hazard_interval`, `trail_hazard_effect` | Drops small player-owned hazard patches | Leave hazards |
| `split_on_kill_count` | A killing shot continues as N copies | Duplicate on kill |
| `split_depth` | Split children may split again (capped by ENG-10) | — |
| `pause_and_retarget_seconds` | Stops mid-flight, re-aims at the nearest enemy | — |
| `radius_over_distance` | Grows as it travels | — |
| `expire_retarget_shot` | On expiry, fires one shot at the nearest enemy | — |
| `crit_chance`, `crit_scale` | Critical hits | Critical hits (processor) |
| `echo_delay`, `echo_damage_scale` | Fires a delayed copy (reuses `echo_rivet`) | — |
| `bonus_vs_status` | Extra damage against a target with any status | — |
| `aura_tick_damage`, `aura_radius` | Damages everything it passes near | Plasma orb |

Use the existing `EventBus.projectile_expired` for expiry hooks. Every new field needs a composition test alongside the existing ricochet-plus-fork cases in `test_combat` and `test_items`.

### SYS-3: Active item slot

- **Resource:** an `ActiveItemConfig` extending `ItemConfig`, or an "Active" group on it, with:
  - `charge_kind`: `ROOMS_CLEARED`, `SECONDS`, or `DAMAGE_DEALT`
  - `max_charge`
  - `effect_scene` or an `effect_id`
  - `starts_charged`
- **Component:** `ActiveItemSlot` on the Player, with one slot. Picking up a new active item drops the old one on the floor, as in Isaac.
- **Input:** `use_active_item` (already bound).
- **HUD:** a slot icon with a segmented charge bar, flashing when ready.
- **Run state:** the held active id and its charge are run-wide. Add them to `RunManager`'s lists and the checkpoint (ground rule 8).
- **Battery pickup** (SYS-6) restores charge.
- **Draw policy:** actives come from their own pool slice (drop-table category `ACTIVE`), roughly one active offer per floor.

### SYS-4: Elite modifiers (spec §15)

- An `EliteModifier` resource (id, prefix, tint and outline, stat multipliers, optional behaviour script) applied by `Enemy._ready` when the spawner marks the enemy elite. The spec's six modifiers become the entries in Track E's ELT table.
- **Spawn rules:** a new `EnemySpawn.elite_chance` (0 on Floor 1, rising by floor), guaranteed elites in ELITE_COMBAT rooms, never on bosses. `is_eligible` rules exclude incompatible bodies, such as Duplicating on Recursion.
- **Draws** use a new `ELITE` stream.
- **Reward:** +2 scrap, and a 10% chance of a chip.

### SYS-5: Special-room manifest and hidden placement

`FloorGenerator.SPECIAL_TYPES` is hard-coded to boss, treasure, and shop. Replace it with `FloorConfig.special_rooms: Array[SpecialRoomRule]`. Each rule has:

- `type`, `count`, `chance` (from a `SPECIAL` stream)
- `placement`: `DEAD_END`, `FARTHEST`, or `HIDDEN`
- `min_distance_from_start`
- `door_rule`: `OPEN`, `KEYCARD`, `FULL_INTEGRITY`, or `EXPLOSION`

Rules for the manifest:

- **`HIDDEN` placement** chooses an empty cell adjacent to at least two existing rooms, the classic secret-room heuristic. It creates **no visible door**, only a cracked-wall segment (see RM-3). The generator's existing guarantees still hold: every special room is a dead end, so it can never cut the path to anything else.
- **New enum values are appended** after `TRANSITION` (ground rule 4). Add any new types, such as `CLOSET`, `TERMINAL`, `REPAIR_BAY`, or `REFACTOR`, at the end.
- **`CampaignValidator`** checks that every scheduled type has eligible templates on its floor, as it already does for the five current types.
- `room_count` stays the budget. Special rooms beyond the core three take cells from combat rooms, so pacing does not quietly grow. Revisit per floor with ENG-7 data.

### SYS-6: New pickup kinds (spec §18)

Append to `PickupConfig.Kind`:

| Kind | In-fiction name | Effect |
| --- | --- | --- |
| `SHIELD` | Firewall Rule | One Faraday-style absorb charge until the next room |
| `BATTERY` | Battery Cell | Restores active item charge (SYS-3) |
| `REROLL` | Hotfix Token | Rerolls a shop or one pedestal for free (IMP-4) |
| `KEYCARD` | Access Badge | Opens Server Closets and Challenge doors (RM-2, RM-4) |

Keycards and Hotfix tokens are run-wide counters: add them to `RunManager` and the checkpoint. Scrap Magnet should pull these small pickups but, per FIX-1, never items.

### SYS-7: Certifications (set bonuses)

Isaac's "transformations", in this game's fiction: holding **three items from one family** (identified by a family tag) earns an IT certification. It gives a visible robot change (a `PlayerVisuals` attachment), a banner, and a modest bonus.

| Certification | Family tag | Bonus |
| --- | --- | --- |
| Certified Drone Operator | `drone` | +1 drone, and drones inherit the chain trigger |
| Cryogenics Specialist | `chill` | Freezes shatter for 1 damage in a 24 px area |
| Thermal Engineer | `burn` | Burning enemies spread burn on death |
| Network Engineer | `chain` | Chain jumps +1, chain radius +15% |
| Site Reliability Engineer | `defense` | +1 max integrity, +0.2 s invulnerability after a hit |
| Growth Hacker | `scrap` / `economy` | 10% cheaper shops, +1 scrap per clear |
| Malware Analyst | `corrupted` | Each held corrupted item grants +8% damage |

Data model: a `Certification` resource (tag, threshold, bonus given as an `ItemConfig`-shaped modifier set). `ItemInventory` checks on `item_added`. Counts are recomputed from the inventory, never stored, so checkpoints need nothing new. Earned certifications count toward META-2 achievements.

### SYS-8: Item upgrades (v2 items)

Add `ItemConfig.upgrade_to: ItemConfig`, a stronger "v2" of the same item: Ricochet Driver v2 bounces twice, Fork Bomb v2 splits into three, Cooling Fan v2 gives +35%. The Refactor Station (RM-7) consumes one unique item to upgrade another. The v2 resources are not in any pool. The validator checks that each upgrade has the same category, stronger `has_upside`, and no cycles.

### SYS-9: Branching campaigns

`RunDefinition.floors` is an ordered list. Floor variants (LVL-1) and the alternate path (LVL-2) need a campaign graph:

- `FloorEntry.alternatives: Array[FloorEntry]` for variant slots, chosen per run by a `CAMPAIGN` stream.
- `FloorEntry.exits: Array[FloorExit]` for conditional branches (for example, "via the Service Elevator in a secret room").
- The checkpoint records the **path taken** (a list of floor ids), not only the index.
- `CampaignValidator` checks the graph is acyclic, that every path ends in a terminal floor, and that every floor on every path passes today's per-floor checks.
- `--floor=` accepts a floor id, and the manifest prints the path.
- The leaderboard groups by ending (see META-1).

---

## 7. Track E: new content

### 7.1 Passive items

These are grouped by category, targeting the thin ones (mobility 3, utility 4, prototype 1). Names avoid collisions with existing items, enemies, and bosses. The **Needs** column refers to the tags defined at the top and the systems in Track D.

**Weapon cores** (true fire patterns; spec §11 examples in brackets)

| ID | Name | Rarity | Effect | Needs |
| --- | --- | --- | --- | --- |
| ITM-1 | Shotgun Surgery | Rare | Three rivets in a 22° fan, each at 55% damage. Fire rate ×0.8. [burst cannon] | SYS-1 |
| ITM-2 | Hard Link | Rare | A rail spike: speed ×2.5, +2 pierce, lifetime ×0.5, damage ×1.8, fire rate ×0.6. [rail spike] | DATA |
| ITM-3 | Circular Dependency | Rare | Shots orbit the robot once before flying out. [saw launcher] | SYS-2 orbit |
| ITM-4 | Blob Storage | Uncommon | A slow, large orb that damages everything it passes every 0.25 s. [plasma orb] | SYS-2 aura |
| ITM-5 | Batch Job | Rare | Hold fire to charge for up to 1 s; release to fire one shot at up to 4× damage and 2× size. [charge shots] | SYS-1 charge |
| ITM-6 | Soldering Iron | Prototype | A short continuous beam that arcs to one extra target. [arc welder / laser emitter] | SYSTEM (beam) |
| ITM-7 | Round Robin | Uncommon | Every other shot fires backwards. | SYS-1 |
| ITM-8 | Parallel Port | Common | Two parallel rivets, side by side, each at 65% damage. | SYS-1 |

**Projectile modifiers**

| ID | Name | Rarity | Effect | Needs |
| --- | --- | --- | --- | --- |
| ITM-9 | Exponential Backoff | Uncommon | Shots accelerate in flight and hit up to 60% harder at the end of their range. [accelerate] | SYS-2 |
| ITM-10 | Throttle | Uncommon | Shots slow to a halt and hang as mines. Lifetime +1.5 s. [decelerate] | SYS-2 |
| ITM-11 | Copy-on-Write | Rare | A shot that kills continues as two copies. [duplicate on kill] | SYS-2 |
| ITM-12 | Recursive Descent | Prototype | Split children split once more. With Fork Bomb, this is the "barely controlled" moment spec §3 promises. | SYS-2 split depth + ENG-10 |
| ITM-13 | Log Rotation | Uncommon | Shots leave short burning patches behind them. [leave hazards] | SYS-2 trail |
| ITM-14 | Two-Phase Commit | Rare | Shots pause for 0.15 s mid-flight, then re-aim at the nearest enemy. | SYS-2 |
| ITM-15 | Big O | Uncommon | Shots grow as they travel, up to 2.5× radius. | SYS-2 |
| ITM-16 | Tail Call | Uncommon | A shot that expires without hitting fires one new shot at the nearest enemy. Pairs with Return Protocol. | SYS-2 + `projectile_expired` |
| ITM-17 | Checksum | Common | +25% damage against any target with a status effect. | SYS-2 |
| ITM-18 | Heap Spray | Common | +1 projectile per shot, 12° spread, each at 70% damage. | SYS-1 |

**Processor**

| ID | Name | Rarity | Effect | Needs |
| --- | --- | --- | --- | --- |
| ITM-19 | Critical Section | Uncommon | 12% chance to crit for 2.5×, shown in the crit damage-number style. [critical hits] | SYS-2 |
| ITM-20 | Uptime | Uncommon | Each consecutive hit adds +5% damage, up to +50%. A shot that expires without hitting resets it. [combo multiplier] | HOOK |
| ITM-21 | Nine Nines | Rare | Kills within 1.5 s of each other stack +10% fire rate (5 stacks), decaying. [kill streak] | HOOK |
| ITM-22 | Thermal Throttling | Rare | Firing builds heat, and damage scales up to +80% with it. At 100% heat the weapon locks for 1 s. A HUD heat bar shows it. [heat-based damage] | SYSTEM (heat) |
| ITM-23 | Hyperthreading | Rare | Every shot echoes 0.12 s later at 50% damage. | SYS-2 echo |
| ITM-24 | Branch Predictor | Common | Shots lead moving targets within 10°. | HOOK |

**Mobility** (currently only 3 items)

| ID | Name | Rarity | Effect | Needs |
| --- | --- | --- | --- | --- |
| ITM-25 | Symlink | Rare | The dash becomes an instant blink and leaves an afterimage that enemies target for 1 s. [teleport dash] | HOOK dash mode |
| ITM-26 | Segfault | Uncommon | Each dash ends in a small explosion. [dash explosion] | HOOK: generalise `dash_pulse_*` to damage |
| ITM-27 | Continuous Deployment | Uncommon | Moving without stopping for 1.5 s gives +15% move speed and +25% fire rate. The mirror of Mutex Lock. | HOOK |
| ITM-28 | Race Condition | Rare | Dashing through a hostile shot slows time to 50% for 0.6 s. [slow motion after near miss] | HOOK |
| ITM-29 | Hot Swap | Common | +1 dash charge, but charges refill 20% slower. | DATA |
| ITM-30 | Burst Transfer | Uncommon | Dashing through an enemy deals 2 damage and shoves it. [damage trail, contact variant] | HOOK |

**Defence**

| ID | Name | Rarity | Effect | Needs |
| --- | --- | --- | --- | --- |
| ITM-31 | Air Gap | Rare | An orbiting blocker destroys hostile shots it touches. It recharges for 1 s after each block. [orbiting shield] | HOOK |
| ITM-32 | Loopback | Rare | Hostile shots the robot dashes through are reflected at their shooter. [projectile reflection] | HOOK |
| ITM-33 | Graceful Degradation | Uncommon | At 2 integrity or less, post-hit immunity lasts 60% longer and any hit costs at most 1. [damage reduction at low health] | HOOK |
| ITM-34 | Health Check | Uncommon | Three rooms cleared in a row without damage repair 1 integrity. [repair on room clear] | HOOK |
| ITM-35 | Circuit Breaker | Rare | Once per floor, dropping to 1 integrity releases a pulse that destroys hostile shots within 80 px. [emergency barrier] Needs owner decision Q6. | HOOK |
| ITM-36 | RAID Array | Common | +1 max integrity, and each descent repairs 1. | HOOK (on floor begin) |

**Utility** (currently only 4 items)

| ID | Name | Rarity | Effect | Needs |
| --- | --- | --- | --- | --- |
| ITM-37 | Traceroute | Uncommon | Reveals the floor, including special and secret rooms, through `Minimap.reveal_all`. [reveal secret rooms] | HOOK |
| ITM-38 | Open Source | Uncommon | Shop items cost 25% less. [improve shop quality] | HOOK |
| ITM-39 | Recycle Bin | Common | Repair cells collected at full integrity become 3 scrap. [convert excess health to scrap] | HOOK |
| ITM-40 | Backup Tape | Rare | The first item picked up on each floor also drops a chip. [duplicate the first pickup each floor] | HOOK |
| ITM-41 | Package Manager | Uncommon | Treasure rooms show two items; taking one removes the other. [reroll room rewards] | HOOK |
| ITM-42 | Service Level Agreement | Rare | Clearing a room within 20 s of entering pays 3 scrap. This rewards pace and suits the fastest-victory leaderboard. | HOOK |

**Corrupted bargains** (spec §11's four examples, plus one; each trades something for something, so none is a hindrance)

| ID | Name | Effect | Needs |
| --- | --- | --- | --- |
| ITM-43 | Root Access | Damage ×2; max integrity halved, rounding up. | HOOK `max_integrity_scale` |
| ITM-44 | Memory Fragmentation | Fire rate +40%; spread widens 3° per consecutive shot, up to 30°, and resets when firing stops. | HOOK |
| ITM-45 | Monetization | Enemies drop double scrap; shop prices +50%. | HOOK |
| ITM-46 | Busy Wait | The dash has no cooldown, but a fourth dash within 3 s costs 1 integrity. | HOOK |
| ITM-47 | YOLO Deploy | Each combat room spawns one extra elite; each clear has a 25% chance to drop a chip. | SYS-4 |

**Prototype** (fills out the one-item tier; secret rooms and bosses only)

| ID | Name | Effect | Needs |
| --- | --- | --- | --- |
| ITM-48 | Quantum Bit | Every shot has a mirrored twin reflected across the aim line. When one hits, the other collapses into a small explosion. | HOOK |
| ITM-49 | Singularity | Shots pull enemies within 40 px toward them, and shots that touch merge into one larger shot. | HOOK + ENG-10 |
| ITM-50 | Self-Modifying Code | On each descent, one held unique item becomes a different unique item of the same category, drawn from a named stream. | HOOK + checkpoint |
| ITM-51 | Neural Net | Each Debug Drone copies one of the robot's projectile modifiers, re-rolled each room. | HOOK (drone weapon stack) |

**Chips** (repeatable; extends the six existing chips)

| ID | Name | Effect |
| --- | --- | --- |
| ITM-52 | Range Chip | +0.15 s lifetime. Stacks. DATA. |
| ITM-53 | Dash Chip | Dash cooldown ×0.92. Stacks. DATA. |
| ITM-54 | Scrap Chip | +1 scrap per room cleared. Stacks. HOOK. |

For each item, test composition with at least two existing items. The item suite's key checks stay in force.

### 7.2 Active items (SYS-3)

Charge is counted in rooms cleared unless noted.

| ID | Name | Charge | Effect | Notes |
| --- | --- | --- | --- | --- |
| ACT-1 | Ctrl+Z | 3 | Rewinds the robot's position and integrity to where they were 2 s ago. | Ring buffer on the Player. The signature active. |
| ACT-2 | Blue Screen | 4 | Freezes every non-boss enemy for 2 s and chills bosses. The screen tints blue, respecting the flash setting. | Uses `StatusEffectController`, which already respects `control_resistance`. |
| ACT-3 | Kill -9 | 2 | Destroys the nearest non-boss enemy outright. Bosses take a fixed 8 damage instead. | |
| ACT-4 | Fork() | 3 | Spawns a decoy robot for 4 s that hostile targeting prefers. | Registers with `HostileRegistry` as `Teams.Id.PLAYER`. |
| ACT-5 | Cron Job | 3 | Deploys a turret that fires the robot's current projectile config every 0.5 s for 8 s. | Reuses `WeaponController`. |
| ACT-6 | Hotfix Deploy | 6 | Rerolls every item pickup and shop stand in the room. | Uses `release_item` then `draw_item`, with the IMP-3 context. |
| ACT-7 | Overclock | 2 | Doubles fire rate for 5 s, then locks the weapon for 2 s. | |
| ACT-8 | Flush Queue | 4 | Destroys all hostile **projectiles** on screen. Never touches lanes or zones. | Owner decision Q6. |
| ACT-9 | Ping | 1 | Reveals the map and makes secret-room cracks pulse for 5 s. | Cheap; a good first active to teach the slot. |
| ACT-10 | Stack Trace | 30 s | Fires a piercing beam along the aim whose damage equals twice the damage the robot took in this room. | Time-charged. A comeback tool. |

### 7.3 Elite modifiers (SYS-4)

| ID | In-fiction prefix | Spec §15 name | Effect | Tell |
| --- | --- | --- | --- | --- |
| ELT-1 | Overclocked | Faster | Move and attack speed +40% | Afterimages |
| ELT-2 | Enterprise Edition | Armored | Health ×2, knockback resistance +0.5 | Plated outline |
| ELT-3 | Unstable | Volatile | Explodes 0.8 s after death, with a telegraph ring | Pulsing red core |
| ELT-4 | Hotfixed | Regenerating | Regains 10% health per second after 2 s without being hit | Green ticks |
| ELT-5 | Forked | Duplicating | On first death, splits into two copies with 40% health | Doubled outline |
| ELT-6 | Surge-Protected | Electrified | Hits on it zap the robot if it is within 40 px | Sparks |

Keep the tells distinct by **shape**, not only colour (IMP-10). Elites never appear on Floor 1 outside ELITE rooms. Unstable's explosion is a committed hazard, so it follows the post-boss contract's ownership rules.

### 7.4 Rooms (SYS-5)

| ID | Room | Enum | Floors | Door rule | Contents |
| --- | --- | --- | --- | --- | --- |
| RM-1 | Escalation | ELITE_COMBAT | 2–6 | Open | 2–3 elites. Reward from the `ELITE` drop table and scrap. |
| RM-2 | Load Test | CHALLENGE | 2–6 | Full integrity **or** an Access Badge | Three waves (IMP-7). Reward from the `CHALLENGE` table (rare-weighted). |
| RM-3 | Shadow IT | SECRET | 1–6 | Explosion on a cracked wall, or revealed by Traceroute or Ping | One of three: a secret-table item (prototype-weighted), the Code Review fight (BOSS-4), or a lore terminal with a Source Fragment (LVL-2). |
| RM-4 | Server Closet | CLOSET (new) | 1–6 | Access Badge | One item and scrap. A locked treasure room. |
| RM-5 | Corrupted Terminal | TERMINAL (new) | 3–6 | Open | Choose one of two corrupted *bargains*, never a hindrance. Spec §19. |
| RM-6 | Repair Bay | REPAIR_BAY (new) | 2–6 | Open | +1 max integrity for 15 scrap, once; repairs for 5 scrap each. Spec §19. |
| RM-7 | Refactor Station | REFACTOR (new) | 3–6 | Open | Sacrifice one unique item to upgrade another to its v2 (SYS-8). Spec §19's Compiler Shrine. |
| RM-8 | Service Elevator | TRANSITION | Between floors | — | A calm room that stages the descent: lore terminal, vending machine (one random pickup for 3 scrap), and the in-world checkpoint point. It also presents SYS-9 branches. |
| RM-9 | Combat templates | COMBAT | 1–2 | — | FIX-8: 3–4 new templates each. Help Desk ideas: "Queue" (a long room with pillars in a line), "Call Centre" (cubicle maze), "Break Room" (a central obstacle with four approaches). Development ideas: "Sprint Board" (lanes), "Code Freeze" (thermal-free cold room with narrow gaps), "Merge Window" (two halves joined by one gap). |

Explosion-opened walls give Core Dump, Volatile Kernel, Interrupt Handler, and Segfault a use outside combat, as bombs do in Isaac, without adding a bomb resource.

### 7.5 Enemies

Each has one sentence, following the convention in `scenes/enemies/*.gd`.

| ID | Name | Floors | Sentence | Behaviour | Needs |
| --- | --- | --- | --- | --- | --- |
| EN-1 | Hold Music | 1–2 | "It fills the room with rings, and the gaps are the song." | A stationary speaker emitting slow expanding rings, each with one rotating gap. It teaches ring-gap reading **before** the Scrap King's phase 3 uses it. | ENG-2 ring primitive |
| EN-2 | Auto-Responder | 2–3 | "It answers every shot." | When hit, it returns one slow shot back along the incoming line after 0.4 s. It punishes spraying and rewards burst timing (Interrupt Vector, Cache Warmer). | — |
| EN-3 | Spot Instance | 4 | "It uses the pads too." | A turret that migrates between the room's migration pads, telegraphed at the destination. Standing on that pad blocks the arrival and stuns it. Floor 4's first enemy of its own. | `MigrationPad` API for non-player bodies |
| EN-4 | Autoscaler | 4–5 | "It keeps the room full." | Spawns a fragile Container minion whenever the room drops below its target count, capped at 3 live and 6 total. Creates a kill order. | `RoomCombat.register_enemy` (exists) |
| EN-5 | Cold Start | 4 | "It only exists when invoked." | A dormant pillar until the robot comes within 60 px, then a 0.5 s boot and a burst. Teaches approach paths. | — |
| EN-6 | Middle Manager | 5 | "It makes everything else worse." | Never attacks. Every 4 s it delegates a visible, tethered buff (a shield charge or +fire rate) to the nearest ally. The buffs end when it dies. Fits Floor 5's coordination theme. | — |
| EN-7 | KPI Tracker | 5–6 | "It charges by the hour." | Its speed and damage rise every 5 s the room stays uncleared, shown as a climbing bar. Pressures slow builds without taxing strong ones. | — |
| EN-8 | Gradient | 6 | "It chases where you're going." | A predictive chaser that leads the robot's velocity, the future-facing mirror of Stale Replica, which chases the past. Reversing direction baits it. | — |
| EN-9 | Prompt Injector | 6 (late) | "It borrows your shots." | Player shots that pass through its field turn hostile. High risk: prototype it behind playtests. | Team-swap in `Projectile` |

**Variants ("one rung up"), for Floors 4–6:**

- **Priority Ticket:** a Ticket Bot that fires three-shot bursts.
- **Pop-Up Ad:** a Pop Up Drone that leaves a hovering "ad" hazard until it is shot.
- **Flaky Test:** phases in and out on a visible schedule. Kept for the QA Lab variant in LVL-1.

**Mini-bosses** (Escalation and Load Test rooms; they share a pool and use `BossPart`-style bodies with a small health bar):

- **PC LOAD LETTER** (a printer, Floors 1–2): alternates a jam (vulnerable) with sprays of paper-sheet walls that have gaps.
- **Rack Mount** (Floors 3–4): four stacked units, each firing a different enemy's attack. Kill order decides the fight.
- **Chief of Staff** (Floor 5): escorts two enemies and issues orders to the room, such as "FOCUS FIRE" (aimed volleys) or "SPREAD OUT" (flanking).

### 7.6 Bosses

The current verbs are **notice** (Scrap King), **predict** (Runtime Error), **keep moving** (Cascade Failure), and **be somewhere first** (Orchestrator), and Core Intelligence says them all. New bosses should each claim an unused verb. Every boss added to the Floors 1–4 pool needs a `BossMask` for the finale (ENG-2).

**BOSS-1: The Board of Directors** (Floor 5; original). Verb: **lobby**.

- **Arena:** a long boardroom table with five seated directors, reusing Floor 5's board-vote and quorum rooms as its teaching rooms.
- **Phase 1:** each cycle the Board votes on a motion shown as a banner ("MOTION: RIGHTSIZE" becomes projectile walls, "MOTION: SYNERGY" becomes linked beams between directors, "MOTION: OFFSITE" teleports the arena's hazards). Each director votes yes or no, visible as a lamp. A director brought under 50% health before the vote closes **abstains**. The player chooses which motions pass by choosing whom to hurt.
- **Phase 2:** two directors are voted off (removed). The rest vote faster, and motions combine two at a time.
- **Phase 3:** the Chair stands alone and enacts every motion that passed, in order. It is a rhythm fight built from the player's own earlier choices.
- **Existing boss:** Executive Override becomes either a Floor 5 alternate (50/50 through the `BOSS` stream) or a Floor 1–4 pool member for mature runs. This is owner decision Q8.

**BOSS-2: Legacy Mainframe** (Floors 1–4 pool). Verb: **aim**.

- **Arena:** a tall mainframe cabinet across the top wall, with tape reels.
- **Phase 1:** armoured, taking damage only through ports that open one at a time in a punch-card rhythm. The next port is telegraphed.
- **Phase 2:** the tape reels spin projectile spirals while two ports open at once.
- **Phase 3:** it "boots peripherals": printer adds (PC LOAD LETTER–lite) and a card-reader beam that sweeps the floor.
- **Why:** it asks for precision, which no boss asks for today. A good first-floor boss for a player still learning aim.

**BOSS-3: Cron Daemon** (Floors 2–4 pool). Verb: **keep time**.

- **Arena:** a clock face on the floor, with a visible hand and tick marks.
- **Fight:** every attack fires on the beat shown by the hand, and the tempo rises each phase (synced to the boss music's BPM). Phase 3 introduces syncopation, with off-beat attacks that are telegraphed one beat early.
- **Why:** the most readable kind of pattern boss, and a showcase for IMP-11's adaptive audio.

**BOSS-4: Code Review** (secret; spec §19's "Debug Room"). Verb: **know yourself**.

- **Fight:** a mirror robot using the player's own `WeaponController` config and projectile modifier stack, at 60% damage. Enemies already share `WeaponController` with the player, so this is mostly composition.
- **Phases:** 1 mirrors the player's movement with a delay; 2 uses their dash; 3 adds the player's drones.
- **Reward:** a prototype item.
- **Risk:** degenerate builds, such as 400 split shots, become a boss attack. Apply ENG-10's caps to the mirror.

**BOSS-5: Botnet** (Floors 3–4 pool). Verb: **thin the swarm**.

- **Fight:** one shared health pool spread over up to 40 small nodes that re-form into shapes: an arrow charge, a ring, and a wall with a gap. Damage anywhere counts. The formation *is* the attack. Losing nodes changes which formations are available, from full to sparse.
- **Risk:** Web performance. Budget it under ENG-10 and profile hosted Web before committing.

**BOSS-6: Factory Reset** (the alternate path's final boss, LVL-2). Verb: **protect**.

- **Fight:** the robot's own original firmware, trying to wipe the build. Each phase an "uninstaller" node latches onto one held item, visibly greying its icon, and the item is **suspended** until the node is destroyed. Items are never deleted.
- **Why:** the only fight about protecting the build instead of using it. A fitting end to a game whose fantasy is "an accidentally assembled mechanical god".
- **Implementation:** needs `ItemInventory` suspension, meaning items that stay held but are excluded from aggregates, with a test that the aggregates recompute.

**Pool policy:** the Floors 1–4 pool grows from 4 to 6–7 bosses, drawn without repeats, so each run leaves 2–3 unseen. Floor 5 alternates between Board and Override. Floor 6 stays Core Intelligence, with data-driven masks.

### 7.7 Levels

**LVL-1: Floor variants** (needs SYS-9). Each depth gets a B-side that shares its difficulty band. Pilot with **one**:

- **Depth 5-B, Legal & Compliance** (recommended pilot).
  - **Idea:** each room posts a **policy** on entry, such as "NO DASHING IN RED TAPE", "ALL SHOTS AUDITED" (the first three shots each room cost scrap), or "QUIET HOURS" (no firing while inside the zone). The policy is enforced by visible zones, and breaking it summons an Auditor enemy.
  - **Teaches:** reading room rules.
  - **Boss:** The Board of Directors.
  - **Enemies:** Auditor ("It shows up when you break the rules"), Middle Manager, and Priority Ticket.
- **Depth 2-B, QA Lab:**
  - **Idea:** assertion tripwires, lasers that fire turrets when crossed.
  - **Enemies:** Flaky Test, Auto-Responder.
  - **Boss pool:** as Floor 2.
- **Depth 3-B, Network Operations Centre:**
  - **Idea:** packet conveyors that push the robot *and* projectiles along cables.
  - **Enemies:** Load Balancer, Spot Instance.
- **Depth 4-B, Edge Network:**
  - **Idea:** latency. Hostile shots are fired from delayed "edge copies" of enemies.
  - **Enemies:** Lagging Replica, which is currently forced into only one Floor 6 room, so it would get a proper home.

Every variant needs a theme, two music tracks, 8+ templates, and a curated roster, the same bar Floors 3–6 met.

**LVL-2: The alternate path, Legacy Archives** (needs SYS-9, RM-3, and RM-8).

- **Unlock:** collect **Source Fragments**, one per secret room, from lore terminals. With three fragments, Floor 3's Service Elevator offers "B1" instead of Floor 4.
- **Floors:** B1 "Tape Archive" and B2 "Mainframe Hall". The oldest layer of the company, where the robot was built.
- **Visuals:** a green-phosphor palette.
- **Enemies:** legacy versions of earlier enemies (COBOL-era variants).
- **Final boss:** Factory Reset (BOSS-6). Beating it is a **true ending** with its own victory card and trophy variant.
- **Leaderboards:** a separate board, "fastest true ending".

**LVL-3: On-Call (endless).** After a victory, offer "Stay on call": loop Floors 4–6 with `enemy_health_scale` rising by 0.15 per loop (the `MAX_ENEMY_HEALTH_SCALE` cap of 2.5 becomes per-mode), elite chance +10% per loop, and bosses drawn from the full pool. There is a leaderboard by depth reached. The checkpoint schema needs the loop index.

---

## 8. Track F: modes and meta-progression

The spec's §30 guardrails deferred daily challenges, leaderboards, and multiple characters until the MVP was stable. The MVP is well past that point, and a leaderboard already ships.

| ID | Feature | Effort | Notes |
| --- | --- | --- | --- |
| META-1 | Daily Build | M | UTC-date seed through `RunRng`, pinned to the day's `content_version`. One ranked attempt per day, with unlimited practice. A Wavedash leaderboard per day, or per week if daily boards are unsupported. Combat is not seed-deterministic (see the `RunRng` doc), and it does not need to be: layouts, bosses, shops, and loot match, which is what makes a daily fair. |
| META-2 | Achievements ("Tickets Closed") | M | 30–40 local achievements, such as "Beat Cascade Failure without being hit", "Hold 3 certifications", and "Win with Tech Debt". They feed META-3. Mirror them to Wavedash if its SDK exposes achievements; check this before building. |
| META-3 | Item unlocks | M | Start with about 36 items unlocked and unlock the rest through achievements. New players meet fewer, simpler items first, and veterans get goals. The pool filter reads `SaveManager.unlocked_items` (ENG-9 renames today's list to `discovered_items`). `CampaignValidator` must reason about the **starter** pool's offer capacity. |
| META-4 | Archive (compendium) | M | Three tabs. **Items:** discovered items with descriptions (resolving IMP-2 without touching the run). **Incident reports:** each enemy's one-sentence design line, which is already written in the scripts' headers. **Bosses:** defeated bosses and best times. Undiscovered entries show as silhouettes. |
| META-5 | Seed entry and display | S | A menu field to type a seed. The seed is shown on the summary and in the pause menu. Seeded runs are unranked. |
| META-6 | Characters | L | A `CharacterConfig` combining `PlayerConfig`, `WeaponConfig`, starting items, and sprite set. The Player scene is already config-driven. See the four proposals below. |
| META-7 | Challenge runs ("Incidents") | M | Fixed constraints unlocked by achievements: "Legacy Only" (start with Legacy Runtime), "Drones Only" (the rivet does 0 damage and you start with Debug Drone), and "No Shop". Separate records. |
| META-8 | Lore | S–M | Short megacorp emails at Service Elevator terminals, one per floor per run from a pool. They build the world without cutscenes, respecting spec §30. |

**Character proposals** (META-6):

- **Unit 404:** the default maintenance robot.
- **Intern Bot:** 4 integrity, starts with Debug Drone and Scrap Magnet, and a weaker rivet. Unlocked by finishing Floor 3.
- **Tower PC:** 9 integrity, slow, no dash (a slow shove instead), and starts with Stack Overflow. Unlocked by beating the Scrap King without dashing.
- **The Glitch:** every item offer is corrupted or a chip, and it starts with Failover. Unlocked by winning while holding two hindrances.

---

## 9. Sequenced milestones

Each milestone ends with a playable, releasable build, per spec §33.

### M0: Fix first (about 1–2 weeks)

- **Scope:** FIX-1, FIX-2 (minimal), FIX-4 (silhouettes), FIX-6, FIX-9, ENG-3/FIX-5, ENG-4, and ENG-12.
- **Exit:**
  - All suites green, with new regression tests for FIX-1 and FIX-2.
  - A CI lint check exists.
  - No `;` comments remain in `data/**/*.tres`.
  - The README matches the controls that actually work.

### M1: Foundations (about 4–6 weeks)

- **Scope:** ENG-1, ENG-2 (primitives and `BossMask`), ENG-5, ENG-8, ENG-9 (schema only), ENG-10, FIX-3 and IMP-3, FIX-7 and IMP-1 (mouse aim and fire toggle), IMP-7 (waves), SYS-1, SYS-2 (first half: speed and damage over life, crit, expiry retarget, echo), SYS-5, and SYS-6.
- **Exit:**
  - Determinism fingerprints are unchanged by the refactors.
  - One `content_version` bump, for the reward model.
  - The generator schedules a test SECRET room on a greybox floor.
  - Save v3 migrates to v4 losslessly.
  - A mouse-aim test passes.

### M2: Content wave "Depth" (about 4–6 weeks)

- **Scope:** FIX-8/RM-9 (8 templates); ITM-1, 2, 8, 9, 16, 17, 19, 20, 24, 26, 27, 29, 34, 37, 38, 39, 52, 53, and 54; SYS-3 with ACT-1, 2, 7, and 9; SYS-4 with all six elite modifiers; RM-1 and RM-2; EN-1, EN-2, and EN-3; IMP-5, IMP-6, and IMP-8.
- **Exit:**
  - Economy simulations pass.
  - Autopilot damage per floor stays within ±20% of the M1 baseline on Production.
  - Hosted Web keeps p95 frame time at or below 16.7 ms in the worst elite room.

### M3: Discovery (about 3–5 weeks)

- **Scope:** RM-3, RM-4, RM-5, and RM-6; the remaining SYS-6 pickups; ITM-40, 41, 42, and 43–47; SYS-7 (certifications); META-2, META-3, and META-4; IMP-2 (b) and (c); IMP-9.
- **Exit:**
  - A secret room exists on every floor in about 70% of seeds, validated over 120 seeds per floor.
  - The starter pool fills every required offer in 10,000 simulated campaigns.
  - Achievements persist through the cloud-save round trip.

### M4: Bosses (about 5–8 weeks)

- **Scope:** BOSS-1 (Board), BOSS-2 (Legacy Mainframe), BOSS-4 (Code Review), data-driven Core Intelligence masks, mini-bosses, EN-4 through EN-8, and SYS-2 (second half).
- **Exit:**
  - Every pool boss has a mask.
  - The finale wears exactly the bosses the run fought.
  - The post-boss hazard contract is covered for each new boss.
  - The Code Review mirror respects the combat caps under the worst legal build.

### M5: Replayability (about 4–6 weeks)

- **Scope:** META-1 (Daily), META-5, IMP-12 (difficulty tiers), META-6 (Intern Bot and Tower PC), META-7, IMP-10, IMP-11, and ENG-6 and ENG-7 in nightly CI.
- **Exit:**
  - Daily seeds reproduce the same manifest on desktop and Web.
  - Separate leaderboards exist per tier and mode.
  - The accessibility settings persist.

### M6: The alternate path (about 8–12 weeks)

- **Scope:** SYS-8 and RM-7; SYS-9; RM-8; the LVL-1 pilot (Legal & Compliance); LVL-2 (Legacy Archives with BOSS-6); BOSS-3 and BOSS-5 if the budget allows; LVL-3 (On-Call); META-8.
- **Exit:**
  - Every path in the campaign graph validates.
  - 100 complete runs on each path pass in the soak test.
  - The true-ending leaderboard exists.

**Parallel throughout:** playtests on Floors 5–6 (the README's current limitation), Windows and Linux hands-on coverage, gamepad hardware testing, and release signing.

---

## 10. Decisions needed from the owner

| # | Question | Recommendation |
| --- | --- | --- |
| Q1 | Should items say what they do (IMP-2)? | Taglines in the pickup banner, plus full descriptions in the Archive and the pause screen. |
| Q2 | Should hindrances be offered as free floor drops? | No. Offer them only where the choice is visible (shop, terminal, boss third slot). |
| Q3 | Should rarity weight draws? | Yes, per context (IMP-3), accepting one `content_version` bump. |
| Q4 | Active items? | Yes. The button is already bound and advertised. |
| Q5 | Mouse aim? | Yes, as an option. The browser build makes it close to mandatory. |
| Q6 | May player-spent effects destroy hostile projectiles (ACT-8, ITM-31, ITM-35)? | Yes, for **projectiles only**, never lanes or zones, and never automatically on boss death. This is consistent with the contract's intent. |
| Q7 | Unlock-gated items (META-3)? | Yes, with a generous starter pool of about 36 items and a "unlock all" option in settings for returning players. |
| Q8 | What happens to Executive Override when the Board arrives? | Make it a Floor 5 alternate rather than cutting it. |
| Q9 | Daily Build cadence if Wavedash cannot create boards dynamically? | Weekly seed boards, or a single rolling "today" board that resets. |
| Q10 | Should the run length target (spec §4: 25–40 minutes) be enforced by tuning `room_count` per floor? | Measure first with ENG-7, then consider eight denser rooms on Floors 5–6. |
| Q11 | Branching campaigns (SYS-9) at all? | Yes, but only after M3. It is the most invasive change here. |

---

## 11. Risks

- **Scope creep against the spec's core rule** ("a small game that already feels excellent"). *Mitigation:* each milestone is shippable on its own, and M0–M2 improve what exists before M4–M6 add breadth.
- **Determinism erosion.** *Mitigation:* ground rule 6, the existing determinism suite, and a fingerprint diff printed in CI whenever `content_version` changes.
- **Saved runs dropped by content bumps.** *Mitigation:* ground rule 7, one bump per milestone at most, and a clear player message (ENG-9).
- **Web performance with swarm, split-depth, and echo content.** *Mitigation:* ENG-10 caps, profiling hosted Web before each milestone exits, and keeping Botnet (BOSS-5) optional.
- **Readability overload.** Elites, certifications, actives, and 100+ items could crowd a 480×270 screen. *Mitigation:* shape-coded tells, taglines, the Archive, and playtests at native resolution with the Floor 5–6 build caps.
- **Leaderboard fairness.** *Mitigation:* separate boards per mode and tier, assists flagged, and seeded or practice runs unranked.
- **Test-suite runtime.** *Mitigation:* ENG-5 splits fast and nightly suites, and per-suite timings are published.
- **Save growth.** Achievements and archive flags grow the save. *Mitigation:* keep it under `MAX_SAVE_BYTES` (256 KiB) with bitsets for flags. Cloud-save sync costs are unchanged.

---

## 12. Appendix: design cards and file map

### Enemy design card

```text
Name:            Floors:            Difficulty unlock (EnemySpawn.min_difficulty):
One sentence:    "It ..."
The question it asks the player:
The answer a good player learns:
What habit of the previous floor's roster it charges for:
Telegraph (what, how long, readable at 480x270 in all colour-vision modes?):
Counters in the item pool:
Interacts badly with (items/rooms/hazards):
Tests: behaviour, telegraph timing, room-clear accounting, post-boss ownership if it leaves hazards
```

### Boss design card

```text
Name:            Floor(s)/pool:      Verb:
Arena:           Phases (health thresholds):
Phase n: attacks, telegraph lengths, safe space, what escalates
Committed hazards at death (per post-boss contract):
BossMask for Core Intelligence:
Reward table:    Music/stinger:     Intro title line:
Tests: phase transitions, no new attacks after death, reward/loss race, checkpoint of reward stands
```

### Item design card

```text
Id (never changes):   Display name:   Tagline (<= 28 chars):
Category / rarity / tags / family (certification):
Effect as a sentence:  Fields used (set/add/scale/hooks):
has_upside / is_stat_only classification:
Enablers required (requires_any_tags):  Drop contexts:
Synergy tests (at least two existing items):
Cap interactions (ENG-10):
```

### File map for the new systems

| System | New files | Touched files |
| --- | --- | --- |
| Drop tables (IMP-3) | `scripts/resources/drop_table.gd`, `data/drops/*.tres` | `run_manager.gd`, `loot_spawner.gd`, `floor_controller.gd` (or `BossRewardDealer`), `shop_room.gd`, `campaign_validator.gd` |
| Weapon modifiers (SYS-1) | — | `item_config.gd`, `weapon_config.gd`, `weapon_controller.gd`, `item_inventory.gd` |
| Projectile extensions (SYS-2) | — | `projectile_config.gd`, `projectile.gd`, `projectile_modifier_stack.gd`, `projectile_factory.gd` |
| Active items (SYS-3) | `scripts/resources/active_item_config.gd`, `scripts/components/active_item_slot.gd`, `scripts/combat/active_effects/*.gd` | `player.gd`, `combat_hud.gd`, `run_manager.gd`, `run_checkpoint.gd` |
| Elites (SYS-4) | `scripts/resources/elite_modifier.gd`, `data/elites/*.tres` | `enemy.gd`, `enemy_spawn.gd`, `room.gd` |
| Special rooms (SYS-5) | `scripts/resources/special_room_rule.gd` | `floor_generator.gd`, `floor_config.gd`, `room_template.gd` (append enum), `minimap.gd`, `campaign_validator.gd` |
| Pickups (SYS-6) | `data/pickups/*.tres` | `pickup_config.gd` (append enum), `item_effects.gd` (magnet filter), `run_manager.gd` |
| Certifications (SYS-7) | `scripts/resources/certification.gd`, `data/certifications/*.tres` | `item_inventory.gd`, `player_visuals.gd`, `combat_hud.gd` |
| Item upgrades (SYS-8) | `scenes/rooms/refactor_station.gd` | `item_config.gd`, `item_inventory.gd` |
| Branching (SYS-9) | `scripts/resources/floor_exit.gd` | `run_definition.gd`, `floor_entry.gd`, `run_checkpoint.gd`, `campaign_validator.gd`, `main.gd` |
| Room authoring (ENG-8) | `tools/compile_rooms.py`, `tools/rooms/*.txt`, `scripts/systems/room_validator.gd` | `campaign_validator.gd` |
| Autopilot (ENG-6) | `tests/autopilot/autopilot.gd`, `tests/autopilot_runner.tscn`, `tools/balance_report.py` | `.github/workflows/` (nightly) |
| Finale masks (ENG-2) | `scripts/resources/boss_mask.gd`, `data/bosses/masks/*.tres`, `scripts/combat/patterns/*.gd` | `core_intelligence.gd`, boss scripts, `boss_encounter.gd` |
