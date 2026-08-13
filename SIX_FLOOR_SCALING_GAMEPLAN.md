# RoboRush Six-Floor Scaling Gameplan

Status: implementation handoff  
Audit baseline: `7a877dc2af9a0f1f2d60791534184fe15cc405a9`  
Scope: scale the working Floor 1 -> Floor 2 run into a stable, performant, release-ready six-floor campaign  
Floor sequence: Help Desk, Development, Data Center, Cloud Operations, Executive Systems, Core Intelligence

This is a planning artifact. It does not authorize unrelated redesigns or release publication, and it does not represent the work below as already implemented.

## Product decision: post-boss hazards are intentional

Hostile attacks that were fired or visibly telegraphed before a boss died are allowed to resolve after boss defeat. They may damage or kill the player while the reward is present. This is a feature, not a defect.

Implementation and review guardrails:

- Do not clear, neutralize, pause, or make the player immune to already-active hazards when `boss_defeated` fires.
- Do not add a generic "safe reward" state.
- A dead boss must not begin new attacks, but attacks already committed remain authoritative.
- Normal damage and death handling remains active until the player actually claims the reward.
- If a lingering hazard kills the player before the reward is claimed, the loss wins the state race: do not descend, grant the reward, or file a victory.
- Hazards must remain finite, correctly telegraphed, and owned by their current floor.
- Transition cleanup is still required. A hazard may survive boss death, but it must not survive descent into the next floor or leak into a later run.
- Tests must preserve this behavior rather than treating post-boss damage as a failure.

The important boundary is:

```text
Boss dies                 Reward claimed                  Next floor begins
    |                           |                                |
    | active hazards resolve   | transition begins              |
    | damage/death is allowed  | old floor is invalidated       | no old hazard exists
    +---------------------------+--------------------------------+
```

## Executive direction

The successful two-floor seam is a strong prototype. Floors are resource-driven, generation is deterministic for a floor seed, the same Player node crosses the boundary, and run-wide state naturally survives. Six floors should build on that foundation rather than replace it.

Do not begin by attaching four finished `FloorConfig` resources to the existing linked list. First make the campaign spine transactional, validate all six floor definitions, fix cross-floor object ownership, settle the longer-run economy, and establish measurable performance and persistence contracts. Then produce Floors 3-6 in vertical slices.

## Verified current baseline

- Floor 1 advances to Floor 2, while Floor 2 is terminal.
- The same Player node carries integrity, inventory, weapon state, scrap, offered-item history, boss history, enemy scaling, and cumulative statistics.
- `FloorConfig` holds floor content and `FloorGenerator` builds deterministic connected layouts.
- The minimap, floor announcement, theme, music, and boss HUD rebind after descent.
- With writable Godot user data, the current suite passes 16 suites and 1,500 checks.
- The suite still reports 125 `ObjectDB` instances at shutdown. Until those are identified or eliminated, exit-leak output cannot serve as a reliable lifecycle gate.
- Sequential ten-room rebuilds measured roughly 2.6-3.6 ms in native headless debug. The number of floors does not inherently multiply live room cost if old floor objects are correctly released.
- These measurements are diagnostic native/headless results, not evidence of hosted-Web or rendered gameplay performance.

## Blocking constraints before Floor 3

### 1. Cross-floor lifecycle ownership

Current evidence:

- `scenes/floors/floor.tscn` places `LootSpawner` and `Projectiles` beside `Rooms` and `Doors`.
- `FloorController._teardown()` frees rooms and doors but not loot, pickups, projectiles, compile lanes, or other persistent hazards.
- A five-transition probe accumulated exactly one injected pickup and projectile per transition while room count stayed stable.
- Some loot and projectile insertion is deferred, so deleting current children alone cannot prevent a queued old-floor spawn from landing after cleanup.

Required result:

- One disposable floor-generation root owns every floor-local room, door, pickup, projectile, lane, hazard, encounter, and deferred spawn.
- Every generation has an identity/token. Deferred work from an invalid generation must be rejected.
- Descent invalidates old spawning, preflights the destination, swaps ownership, and removes the old generation.
- Boss defeat does not perform this cleanup; reward claim/descent does.

### 2. Reward economy capacity

The shared pool contains 21 unique items. The current cadence reserves eight offers per floor:

- Two combat-clear offers
- Two shop offers
- One treasure offer
- Three boss choices

Six floors therefore request 48 offers. Current simulation fills all offers on Floors 1 and 2, five of eight on Floor 3, and none on Floors 4-6.

Do not solve this only by authoring 27 additional permanent items. Define the six-floor reward model first. Recommended model:

- Unique, build-defining items remain one-time offers.
- A second repeatable reward class provides upgrades, repair, scrap, rerolls, or explicitly stackable stat chips.
- Each floor has a declared offer budget and fallback policy.
- Boss rewards always present exactly three valid choices with at least one beneficial/non-hindrance option.
- Corrupted or hindrance choices remain opt-in pressure, not an accidental three-choice lockout.

Inventory currently rejects duplicate items, so repeatable rewards require an explicit stacking or upgrade contract rather than bypassing duplicate protection.

### 3. Floor 3 content eligibility

The current shared start, treasure, and boss templates, plus every current combat template, stop at `max_floor = 2`. Only the shared shop reaches Floor 6. The generator correctly rejects a floor that has no eligible template.

Before a six-floor skeleton can build, Floors 3-6 need either:

- Deliberately shared templates whose eligibility and visuals are valid through Floor 6, or
- Floor-specific eligible start, combat, treasure, shop, and boss templates.

A campaign validator must catch missing eligible content before a run starts.

### 4. Transaction failure behavior

The current transition tears down the working floor before attempting to build the destination. An invalid Floor 3 can therefore leave GameManager in `RUN` with no playable floor.

Required result:

- Validate the campaign resource at boot or campaign selection.
- Preflight the next config and layout before relinquishing the current floor.
- If an unexpected runtime failure remains, preserve the current floor or exit through a recoverable menu/error path.
- File the run result no more than once.

### 5. Boss progression

Only two boss encounters currently serve both floors. After both have been fought, selection intentionally falls back to the full pool, so Floor 3 onward repeats bosses.

Choose one policy before content production:

- Six distinct bosses,
- Floor- or act-specific boss pools,
- Authored rematches with new phases and explicit tier IDs, or
- A mixed policy with a fixed Core Intelligence finale.

Recommended direction: curated floor/act pools and a fixed final boss. Any repeat must be intentional and mechanically advanced, not a pool-exhaustion fallback.

### 6. Longer-run duration and persistence

Six ten-room floors create a 60-room run. Measure complete two-floor runs before locking that structure across the campaign. Set a full-run duration target, then tune room count and special-room cadence to it; later floors may need fewer, denser rooms rather than ten each.

Active runs are intentionally not saved today. Before Floor 3, explicitly choose between:

- No resume, clearly communicated, or
- A versioned floor-boundary checkpoint.

Recommended direction: checkpoint only after a completed floor. Store stable campaign/floor IDs, content/schema version, immutable run seed, player integrity and inventory, weapon/run counters, scrap, offers, boss history, scaling state, and run statistics. Clear it on win, loss, abandon, and restart.

Before introducing save version 2, prevent an older build from reading a future-version save and rewriting it without unknown fields. Refuse the write, preserve unknown data, or back up and migrate explicitly.

## Target architecture

```text
RunDefinition
  ordered stable floor IDs/paths
  campaign/content version
  validation rules
          |
          v
RunDirector
  current floor index
  immutable run seed and named RNG streams
  transition transaction
  checkpoint and terminal outcome ownership
          |
          v
FloorSession (exactly one active)
  FloorController
  Rooms and Doors
  Loot and Pickups
  Projectiles, Compile Lanes, and Hazards
  Encounters and deferred-spawn generation token
```

Responsibilities:

- `RunDefinition` describes the ordered campaign. It replaces an unchecked transitive resource chain as the source of truth.
- `RunDirector` decides descend versus victory, derives stable seeds, owns transaction/checkpoint behavior, and supports direct start.
- `FloorSession` owns everything that is allowed to die at a floor boundary.
- `FloorController` builds and runs one injected floor. It should not determine the whole campaign by following `next_floor` links.
- The Player, long-lived UI, run-wide item effects, feedback director, and run state remain outside the disposable session.

Use a lightweight catalog of stable IDs/resource paths. Load the current floor and asynchronously preload the next; do not strongly reference the entire six-floor resource graph from Floor 1.

## Dependency-ordered implementation work

### Work package 1: Campaign resource and validator

Primary files:

- New `scripts/resources/run_definition.gd`
- New campaign resource under `data/runs/`
- `scripts/resources/floor_config.gd`
- `main.gd`
- `tests/test_floor.gd` or a focused campaign-validation suite

Tasks:

1. Define stable campaign and floor IDs, ordered floor paths, and content version.
2. Validate exactly Floors 1-6, unique IDs/numbers, correct order, and Core Intelligence as the sole terminal floor.
3. Validate every floor's eligible templates, boss policy, theme/music IDs, shop, enemy roster, reward rules, and numeric ranges.
4. Detect missing paths, null content, duplicate floors, accidental cycles, and insufficient reward capacity.
5. Generalize developer direct start to `--floor=N` for 1-6.
6. Keep a compatibility migration path while `FloorConfig.next_floor` is removed or demoted; do not leave two independent campaign authorities.

Acceptance criteria:

- Every valid floor can be located by stable ID and index.
- Invalid campaign content fails before gameplay begins with actionable diagnostics.
- Only Floor 6 is terminal.
- Direct start uses the same derived floor seed and content selection as reaching that floor normally.

### Work package 2: Transactional floor-session ownership

Primary files:

- `scenes/floors/floor.tscn`
- `scenes/floors/floor_controller.gd`
- `scripts/systems/loot_spawner.gd`
- `scripts/combat/projectile_factory.gd`
- `scripts/combat/compile_lane.gd`
- New RunDirector/FloorSession files
- `tests/test_floor.gd`

Tasks:

1. Place all floor-local objects under one session root.
2. Add a generation token checked by every deferred floor-local spawn.
3. Preflight the destination before invalidating the current session.
4. On reward claim, disable old generation spawning, commit the transition, then release the old session.
5. Preserve the same Player and declared run-wide state.
6. Reset minimap, visited rooms, current room, local clear count, theme, and other floor-local state.

Acceptance criteria:

- Five consecutive boundaries leave exactly one floor graph and one active floor-local projectile/hazard owner.
- No pickup, projectile, lane, enemy, door, signal callback, or queued spawn from floor N appears on floor N+1.
- The declared run-wide fields survive every boundary exactly.
- An invalid destination cannot strand the player in an empty `RUN`.
- This package performs no boss-defeat hazard neutralization.

### Work package 3: Preserve and specify the post-boss danger feature

Primary files:

- `scenes/floors/floor_controller.gd`
- `scenes/bosses/runtime_error.gd`
- Other boss scripts
- `scripts/combat/compile_lane.gd`
- Focused boss/floor integration tests

Tasks:

1. Document the committed-attack rule in the relevant boss and floor code.
2. Verify a dead boss cannot schedule a new attack.
3. Preserve already-fired projectiles and already-painted lanes until they resolve naturally or the player claims the reward.
4. Define outcome ordering when a lingering hazard kills the player before reward collection.
5. Ensure victory/descent cannot be granted after that loss.
6. Ensure reward claim invalidates the old generation so unresolved objects cannot enter the next floor.

Acceptance criteria:

- A projectile fired before boss death can still hit and damage the player afterward.
- A compile lane painted before death can still resolve afterward.
- A boss begins no new telegraph or attack after death.
- A post-boss lethal hit produces exactly one loss and no reward, descent, or victory.
- Surviving and claiming the reward progresses normally.
- No active hazard crosses the floor boundary.

### Work package 4: Six-floor reward and boss policy

Primary files:

- `data/pools/run_item_pool.tres`
- `scripts/resources/item_pool.gd`
- `scripts/components/item_inventory.gd`
- `autoload/run_manager.gd`
- `scenes/floors/floor_controller.gd`
- Shop and reward resources
- `tests/test_items.gd`
- `tests/test_balance.gd`

Tasks:

1. Implement the approved unique/repeatable reward contract.
2. Make offer cadence explicit per floor or act.
3. Make boss selection intentional after the first two bosses.
4. Shuffle reward selection deterministically.
5. Guarantee three valid boss options and at least one beneficial/non-hindrance option.
6. Simulate complete campaigns, not floors in isolation.
7. Revisit unbounded long-run effects such as Tech Debt before a 30-plus-combat-room campaign.

Acceptance criteria:

- At least 10,000 deterministic campaign simulations produce no empty required offer.
- Duplicate/stack behavior always follows the declared policy.
- Every boss reward contains exactly three choices and at least one beneficial choice.
- Boss repeats occur only when explicitly authored.
- Worst legal builds remain inside declared integrity, fire-rate, projectile, drone, status, and enemy-health limits.

### Work package 5: Determinism and reproducibility

Primary files:

- `autoload/run_manager.gd`
- RunDirector
- `scenes/floors/floor_controller.gd`
- Enemy, boss, shop, loot, and weapon RNG call sites
- Debug HUD and run statistics

Tasks:

1. Keep one immutable run seed.
2. Derive stable floor seeds from run seed plus stable floor ID/index, not from the previous mutable floor seed.
3. Derive named streams for layout, boss, encounter, shop, loot, and any promised combat reproduction.
4. Record run seed, content version, deepest floor, and per-floor timing/outcome data.
5. Expose a compact six-floor content manifest for debugging.

Acceptance criteria:

- The same run seed and content version reproduce the same layouts, boss choices, encounters, shops, and rewards.
- Adding an unrelated random draw to one subsystem does not perturb another named stream.
- Direct start and full-run arrival agree on the target floor's derived seed and content manifest.

### Work package 6: Performance scaling

Primary files:

- `scripts/combat/targeting.gd`
- `scenes/projectiles/projectile.gd`
- `scripts/combat/explosion.gd`
- Chain-lightning logic
- `scripts/systems/item_effects.gd`
- Floor catalog/preload code

Tasks:

1. Maintain an active-room hostile registry instead of scanning all instantiated enemies.
2. Implement nearest-target selection as a one-pass minimum without sorting.
3. Return unsorted radius/blast results unless callers explicitly require order.
4. Remove prior-floor pickups so global pickup effects cannot accumulate work.
5. Load the current floor and preload only the next heavy graph.
6. Instrument active enemies, projectiles, transient VFX, target-query time, frame time, nodes, and memory.
7. Profile exported native and hosted-Web builds before adding projectile pooling.

Current evidence does not justify mandatory projectile pooling: 100 non-homing projectiles measured about 0.43 ms/frame in the isolated probe. Homing cost is the urgent issue because target selection raised 100 homing projectiles to about 3.95 ms/frame.

Acceptance criteria:

- Total frame time: p95 at or below 16.7 ms and p99 at or below 25 ms on the supported 60 Hz matrix.
- Script/physics CPU: p95 at or below 8 ms native and 10 ms hosted Web.
- Targeting: at or below 1 ms p95 in the worst legal room/build.
- Adding 100 dormant enemies changes active targeting cost by less than 10 percent.
- Preloaded transition: p95 at or below 33 ms, maximum 50 ms or covered by an intentional transition presentation.
- After warm-up, repeated six-floor runs show less than 5 percent monotonic RSS/node growth.

### Work package 7: Boundary checkpoint and save hardening

Primary files:

- `autoload/save_manager.gd`
- `autoload/run_manager.gd`
- RunDirector
- Save and run integration tests

Tasks:

1. Implement the approved no-resume or floor-boundary checkpoint decision.
2. If checkpoints are enabled, write atomically and retain one known-good backup.
3. Validate file size, collection counts, string lengths, known IDs, duplicates, and numeric ranges.
4. Handle corrupt primary, valid backup, orphaned temporary file, failed overwrite, and quit during save.
5. Prevent older builds from destructively rewriting future-version saves.
6. Exercise persistence on the actual hosted Web origin, not only native `user://`.

Acceptance criteria:

- A boundary restore reproduces the declared player/run state and the next floor's seed.
- Win, loss, abandon, and restart remove the active checkpoint.
- Restore cannot duplicate rewards, scrap, boss credit, or run results.
- Corrupt or incompatible data fails closed while preserving recoverable originals.
- A future-version save cannot be silently downgraded by an older build.

### Work package 8: Test-harness and release trust

Primary files:

- `tests/test_runner.gd`
- Floor, item, boss, save, performance, and integration suites
- `export_presets.cfg`
- Release documentation or automation

Tasks:

1. Identify and eliminate test-owned `ObjectDB` leaks, or establish a precise zero-growth baseline that exposes new ones.
2. Run structural generation over at least 120 seeds per floor.
3. Run at least 100 complete six-floor transition sequences.
4. Build releases from a clean tag into an empty, versioned directory.
5. Pin and verify the Godot engine/export-template version and hashes.
6. Replace the placeholder bundle identity and tag-drive application versions.
7. Sign/notarize macOS and sign Windows artifacts before public release.
8. Publish artifact manifests containing commit, engine version, target, size, and SHA-256.
9. Qualify the exact hosted Web build for save/reopen, refresh, audio, fullscreen, browsers, controllers, and version updates.

Acceptance criteria:

- All suites pass with writable user data and no unexpected log errors.
- Exit-leak output is zero or consists only of explicitly identified, non-growing harness objects.
- Fresh Web, macOS, Windows, and Linux exports exclude tests/tools and pass target-platform smoke tests.
- Distributed artifacts are reproducible, versioned, signed where applicable, and hashed.

## Content production roadmap

Before finished Floor 3 content, create a six-floor greybox campaign using deliberately minimal or duplicated eligible resources. Its purpose is to prove five transitions, terminal-floor logic, state carryover, cleanup, determinism, and economy simulation without allowing new art or enemy behavior to hide architecture failures.

The creative directions below are proposals, not locked requirements. Each floor should add one readable combat idea, teach it alone, vary it, then combine it with mastered mechanics.

### Floor 3: Data Center - architecture-proving vertical slice

Role:

- Prove the new campaign/run/session architecture with real new content.
- Introduce one signature mechanic, such as predictable data-routing or thermal/throughput zones.
- Add one or two new enemies and a curated returning roster.
- Use an intentional boss assignment or boss tier tied to the taught mechanic.
- Add eligible start, combat, treasure, shop, and boss content, plus theme and music.

Gate:

- Floors 1 -> 2 -> 3 complete with no stale object from either prior floor.
- All three floors pass at least 120 generation seeds.
- Both transitions preserve every declared run-wide field and reset every declared floor-local field.
- Death, abandon, restart, reward claim, and checkpoint restore each file the run at most once.
- Post-boss committed hazards retain their intended behavior.

### Floor 4: Cloud Operations - content-pipeline proof

Role:

- Demonstrate that a floor is added through resources and registries rather than floor-number conditionals.
- Promote encounter packs and explicit teaching/mastery checkpoints into data.
- If upgrade, challenge, elite, transition, or secret rooms remain in scope, add them through an explicit floor room manifest. The current generator schedules only boss, treasure, and shop special rooms.
- Suggested mechanic direction: mobility, remote spawns, or elastic/teleport relationships with strong entrance telegraphs.

Gate:

- No `if floor_number == 4` gameplay path is required.
- Direct-start Floor 4 reproduces the full-run floor manifest.
- The four-floor reward and boss simulation has no unintended repeats or empty offers.
- Teaching encounters always precede mixed/mastery encounters.

### Floor 5: Executive Systems - endurance and mature-build validation

Role:

- Stress mature builds, compounding items, dense compositions, UI capacity, checkpoint recovery, and hosted-Web performance.
- Favor recombination over another foundational subsystem.
- Suggested mechanic direction: enemy coordination, commands/buffs, and resource pressure without unfair off-screen punishment.

Gate:

- Worst legal builds remain within the declared combat caps.
- Item HUD and summary remain readable at maximum supported build size and 480x270.
- Object counts return to a bounded baseline after rooms, bosses, and transitions.
- A complete Floor 1 -> 5 soak meets native and hosted-Web frame-time budgets.
- Boundary resume after Floors 1-4 restores the same Floor 5 seed and state.

### Floor 6: Core Intelligence - authored finale

Role:

- Synthesize mechanics the player has already learned.
- Avoid introducing an entirely new base combat language in the final floor.
- Use a fixed final boss or an explicit final boss tier.
- Define final reward behavior, victory presentation, deepest-floor and per-floor statistics, and terminal checkpoint cleanup.

Gate:

- Floors 1-5 always advance; only Floor 6 can produce victory.
- Missing finale content fails campaign validation before play.
- All five transitions are clean.
- Post-boss danger remains active until the final reward is claimed; a lethal lingering hazard still produces a loss rather than victory.
- Win, loss, and abandon each file exactly one result.
- The active checkpoint is removed on every terminal outcome.
- Complete native and hosted-Web runs pass with keyboard and controller.

## Campaign-wide definition of done

### Functional and deterministic

- Exactly six validated floors exist in the declared order.
- One run seed plus content version reproduces a six-floor content manifest.
- At least 720 generated layouts are covered: 120 seeds per floor.
- At least 100 complete six-floor transition sequences pass.
- The same Player and declared run-wide state survive every boundary.
- Only Floor 6 completion produces victory.

### Lifecycle and post-boss feature

- Exactly one floor session is active after every transition.
- No prior-floor pickup, projectile, compile lane, hazard, room, door, enemy, callback, or deferred spawn survives descent.
- Already-committed hazards remain live after boss defeat and can damage or kill the player.
- Dead bosses initiate no new attacks.
- Loss caused by a lingering hazard cannot race into reward, descent, or victory.

### Economy and balance

- Every required offer is filled for the complete campaign.
- Every boss reward has exactly three choices and at least one beneficial option.
- Repeats, stacking, upgrades, and fallbacks follow explicit policies.
- Boss repetition is authored rather than accidental.
- The full-run duration and room counts are based on playtest evidence.

### Performance and stability

- Exported native and hosted-Web builds meet the declared frame-time budgets.
- Targeting stays inside its budget under the worst legal build.
- Transition, node, and memory measurements show no monotonic floor-over-floor growth.
- Logs contain no unexpected errors and shutdown leak reporting is trustworthy.

### Persistence and release

- The run-resume decision is explicit and tested.
- Future, corrupt, oversized, and interrupted saves fail safely.
- Actual hosted-Web persistence is qualified.
- Release artifacts come from clean versioned builds, exclude development material, and are signed/hashed as appropriate.

## Recommended execution order

1. Lock run duration, reward, boss, determinism, and checkpoint contracts. The post-boss hazard contract is already locked by this document.
2. Build `RunDefinition`, RunDirector, and campaign validation.
3. Make floor-session ownership transactional and generation-token-aware.
4. Add regression coverage for the intentional post-boss danger behavior.
5. Implement and simulate the six-floor economy and boss policies.
6. Split deterministic RNG streams and add reproducibility telemetry.
7. Optimize active targeting and move to current-plus-next floor loading.
8. Prove a complete six-floor greybox chain.
9. Produce and tune Data Center.
10. Prove the content pipeline with Cloud Operations.
11. Perform mature-build/endurance qualification with Executive Systems.
12. Author Core Intelligence and run full release qualification.

Do not declare a floor complete because its resource loads or its isolated tests pass. Each floor is complete only when it works as part of the cumulative carried-build campaign and passes the boundary, economy, performance, persistence, and post-boss-danger contracts above.
