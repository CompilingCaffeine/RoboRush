class_name RunRng
extends RefCounted
## Where every seeded draw in a run comes from.
##
## A run has exactly one seed. Everything else — each floor's seed, and each subsystem's seed
## within that floor — is *derived* from it here, and derived by name rather than by order of
## consumption. That is the whole idea, and it replaces two habits that made a seed a much weaker
## promise than it looked.
##
## The first was chaining. A floor's seed used to be `hash()` of the floor before it, so floor 4's
## layout depended on floors 1, 2 and 3 having been generated first, in that order, from that
## content. Renaming a floor, reordering the campaign, or inserting a fifth floor moved every
## layout after it. Deriving from the run seed and the floor's *stable id* instead means floor 4 is
## floor 4: the same seed builds it whether a run fought its way there or `--floor=4` jumped
## straight to it, and it keeps building it when floor 3's content changes.
##
## The second was sharing one generator. `FloorController` drew its boss, populated its rooms,
## seeded its shop, and shuffled its boss reward from a single `RandomNumberGenerator`, so those
## four things were separated only by how many numbers had been taken before them. Adding one draw
## anywhere — a new enemy placement rule, one more shuffle — silently reshuffled everything
## downstream, which makes "the same seed reproduces the same run" true only until the next commit
## touches an unrelated system. Named streams are independent by construction: `LAYOUT` cannot
## consume `SHOP`'s numbers because they are different generators seeded from different values.
##
## What is deliberately *not* reproducible: per-frame combat. Enemies and bosses draw from the
## engine's global generator (`randf()`), which is seeded from the clock, so a fight is not replayed
## by a seed even though the floor, the roster, the boss, the shop and the loot are. Reproducing
## combat would mean routing every enemy's every decision through a stream and pinning frame
## timing, and nothing in the project promises it. A stream is added here when something starts
## depending on it, not in advance — an unused stream name is a promise nobody is keeping.
##
## The mixing below is written out rather than delegated to Godot's `hash()`, and that is a
## deliberate cost. `hash()` is an engine implementation detail: it is free to change between Godot
## versions, and if it did, every seed anybody had recorded would quietly start building a
## different run while `content_version` still claimed they matched. FNV-1a over the bytes plus an
## xor-shift finish is fixed by this file, so a seed's meaning is ours to change and only ours.

## The named streams. One per subsystem that draws from a floor's seed, and each is a promise that
## the subsystem's numbers do not move when another one's do.
##
## `BOSS` and `REWARD` are separate on purpose even though both belong to the boss fight: one picks
## which boss guards the floor, the other shuffles the three items it hands over. Adding an
## encounter to a boss pool should not change what the reward stands hold.
const LAYOUT := &"layout"
const BOSS := &"boss"
const ENCOUNTER := &"encounter"
const SHOP := &"shop"
const LOOT := &"loot"
const REWARD := &"reward"

## Every stream, for the debug manifest and for the suite that checks they stay distinct.
const STREAMS: Array[StringName] = [LAYOUT, BOSS, ENCOUNTER, SHOP, LOOT, REWARD]

## 32-bit FNV-1a, and a 32-bit result. Seeds are kept inside 32 bits so they are short enough to
## read off a debug overlay and type back in as `--seed=`, which is the only thing a seed is for.
const MASK := 0xFFFFFFFF
const PRIME := 0x01000193

## Where a digest starts. Public because the same mixer builds `RunManifest`'s content
## fingerprints: a fingerprint is a hash of content rather than a seed, but there is no reason for
## the project to own two hash functions, and one of them being subtly worse is what would happen.
const DIGEST_START := 0x811C9DC5


## The seed the floor called `floor_id` is generated from, in a run that opened on `run_seed`
## against `content_version` of the campaign.
##
## Content version is folded in rather than merely recorded alongside, so a campaign edit that
## changes what a seed means also changes the seed. The alternative is worse than it sounds: a bug
## report carrying a seed from before the edit would still generate *a* floor, just not the one
## that was reported, and nothing would say so.
static func floor_seed(run_seed: int, content_version: int, floor_id: StringName) -> int:
	var value := fold_int(DIGEST_START, run_seed)
	value = fold_int(value, content_version)
	value = fold_text(value, floor_id)
	return seal(value)


## The seed one named stream of one floor draws from.
##
## Takes the floor's seed rather than the run's, so a stream is `(this floor, this subsystem)` and
## nothing else. A caller that has a floor seed — every caller does, it is what `build()` is handed
## — can derive its own stream without knowing the campaign, the run seed, or the content version.
static func stream_seed(floor_seed_value: int, stream: StringName) -> int:
	return seal(fold_text(fold_int(DIGEST_START, floor_seed_value), stream))


## A generator on one named stream, ready to draw from.
static func stream(floor_seed_value: int, stream_name: StringName) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = stream_seed(floor_seed_value, stream_name)
	return rng


## Every stream's seed for one floor, keyed by stream name. For the debug manifest, and for
## anything comparing two routes to the same floor.
static func stream_seeds(floor_seed_value: int) -> Dictionary[StringName, int]:
	var seeds: Dictionary[StringName, int] = {}
	for stream_name: StringName in STREAMS:
		seeds[stream_name] = stream_seed(floor_seed_value, stream_name)
	return seeds


## Folds an integer into a digest, low byte first. All eight bytes, so a caller passing a full
## 64-bit value does not have most of it silently ignored.
static func fold_int(digest: int, value: int) -> int:
	var folded := digest
	for shift: int in [0, 8, 16, 24, 32, 40, 48, 56]:
		folded = ((folded ^ ((value >> shift) & 0xFF)) * PRIME) & MASK
	return folded


## Folds a name into a digest as its UTF-8 bytes, which is what makes ids and stream names usable
## as seed material at all.
static func fold_text(digest: int, text: StringName) -> int:
	var folded := digest
	for byte: int in String(text).to_utf8_buffer():
		folded = ((folded ^ byte) * PRIME) & MASK
	return folded


## Closes a digest. FNV-1a alone leaves neighbouring inputs with neighbouring high bits, and
## `layout` and `loot` differing in one late byte should not produce two seeds a few bits apart.
static func seal(digest: int) -> int:
	var mixed := digest & MASK
	mixed = ((mixed ^ (mixed >> 15)) * PRIME) & MASK
	mixed = ((mixed ^ (mixed >> 13)) * PRIME) & MASK
	return (mixed ^ (mixed >> 16)) & MASK
