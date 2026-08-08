extends TestCase
## The balance pass, as arithmetic on the shipped data.
##
## Milestone 6 lists a balance pass, and the honest position is that nobody has played this
## game. Difficulty, pacing, and whether the boss is fun are not things a test can judge, and
## guessing at numbers without playtest evidence would be worse than leaving them alone —
## every value in `data/` came from spec sections 6, 15, 16 and 17, which is a better source
## than a hunch.
##
## What a test *can* do is compute what those numbers actually mean and refuse to let them
## drift somewhere absurd. Time to kill is a division. Whether the boss fight is longer than
## a trash mob is a comparison. Whether a player can afford anything at all in the shop is
## addition. None of that needs a player, and all of it is the kind of thing that quietly
## stops being true the first time somebody buffs an enemy.
##
## So the ranges below are deliberately wide. They are not claims that the game is tuned
## correctly; they are tripwires for the tuning being nonsense. When someone finally plays
## this and moves the numbers, these should be updated to match what playing taught them —
## not deleted, and not treated as the design.

const PLAYER_CONFIG := "res://data/player/player_config.tres"
const WEAPON := "res://data/weapons/rivet_blaster.tres"
const BOSS := "res://data/bosses/merge_conflict.tres"
const SECOND_BOSS := "res://data/bosses/runtime_error.tres"
const FLOOR := "res://data/floors/floor_1_help_desk.tres"
const SHOP := "res://data/settings/shop_config.tres"

## Combat rooms on Floor 1 hold three or four enemies (see data/rooms/combat_*.tres), and a
## ten-room floor is one start, one shop, one treasure, one boss, and the rest combat.
const COMBAT_ROOMS_ON_FLOOR_1 := 6
const ENEMIES_PER_COMBAT_ROOM := 3.5

var _player: PlayerConfig
var _weapon: WeaponConfig
var _boss: BossConfig
var _second_boss: RuntimeErrorConfig
var _floor: FloorConfig
var _shop: ShopConfig


func run() -> void:
	_player = load(PLAYER_CONFIG)
	_weapon = load(WEAPON)
	_boss = load(BOSS)
	_second_boss = load(SECOND_BOSS)
	_floor = load(FLOOR)
	_shop = load(SHOP)

	if not require(_player, "player config loads"):
		return
	if not require(_weapon, "weapon config loads"):
		return

	_test_starting_weapon_deals_damage()
	_test_every_enemy_dies_in_a_reasonable_window()
	_test_the_boss_is_a_fight_rather_than_a_bullet_sponge()
	_test_the_second_boss_is_a_fight_rather_than_a_bullet_sponge()
	_test_the_player_can_take_a_few_hits()
	_test_the_dash_is_worth_pressing()
	_test_shop_prices_match_the_spec()
	_test_the_player_can_afford_something_but_not_everything()
	_test_every_item_in_the_pool_has_a_price()
	_test_the_pool_cannot_run_dry_before_the_boss_reward()


## Damage per second with the starting weapon and no items. Everything else is measured
## against this, so it is worth stating in one place.
func _player_dps() -> float:
	if _weapon.projectile == null:
		return 0.0
	return (
		_weapon.shots_per_second
		* _weapon.projectile.damage
		* maxi(_weapon.projectiles_per_shot, 1)
	)


## Seconds of continuous, perfectly accurate fire to remove `health`. Rounded up to whole
## shots, because half a rivet does not exist.
func _seconds_to_kill(health: float) -> float:
	var damage_per_shot := _weapon.projectile.damage * maxi(_weapon.projectiles_per_shot, 1)
	if damage_per_shot <= 0.0 or _weapon.shots_per_second <= 0.0:
		return INF
	return ceilf(health / damage_per_shot) / _weapon.shots_per_second


func _test_starting_weapon_deals_damage() -> void:
	check(_weapon.projectile != null, "the starting weapon has a projectile")
	check(_weapon.shots_per_second > 0.0, "the starting weapon fires")
	check(_player_dps() > 0.0, "the starting weapon can kill something (%.1f dps)" % _player_dps())


## The window every enemy on Floor 1 has to sit inside. Below the floor an enemy dies to a
## single reflex and never gets to act; above the ceiling a basic enemy is a chore.
func _test_every_enemy_dies_in_a_reasonable_window() -> void:
	var paths := [
		"res://data/enemies/ticket_bot.tres",
		"res://data/enemies/pop_up_drone.tres",
		"res://data/enemies/memory_leech.tres",
		"res://data/enemies/firewall_node.tres",
	]
	for path: String in paths:
		var config: EnemyConfig = load(path)
		if not require(config, "%s loads" % path):
			continue
		var seconds := _seconds_to_kill(config.max_health)
		check(
			seconds >= 0.4 and seconds <= 2.5,
			"%s takes %.2fs of fire to kill, inside the 0.4-2.5s window" % [
				config.display_name, seconds,
			],
		)


## The boss's real length is not its health bar. Spec section 16 refunds a fraction of damage
## while the two versions are synchronised, so phase two costs far more than its share of the
## pool until the player breaks the terminals — which is the mechanic, and is worth having
## written down as a number somewhere.
func _test_the_boss_is_a_fight_rather_than_a_bullet_sponge() -> void:
	if not require(_boss, "boss config loads"):
		return

	var pool := _boss.max_health
	var phase_one := _seconds_to_kill(pool * (1.0 - _boss.duplicate_at))

	# Phase three's share of the pool, divided by the fraction of each hit the merged form
	# actually takes. Without that division this read 5.25s for a phase that lasts 11.25s, which
	# is how the last phase of the fight was the shortest one for a milestone without anybody
	# noticing: the two numbers this test compares were never the same kind of number.
	var phase_three := _seconds_to_kill(
		pool * _boss.merge_at / maxf(_boss.merged_damage_scale, 0.01)
	)

	# Worst case for phase two: the player never breaks a terminal, so every point of damage
	# is refunded at desync_heal_fraction and costs 1/(1-fraction) times as much.
	var phase_two_health := pool * (_boss.duplicate_at - _boss.merge_at)
	var refund_multiplier := 1.0 / maxf(1.0 - _boss.desync_heal_fraction, 0.01)
	var phase_two_synced := _seconds_to_kill(phase_two_health * refund_multiplier)
	var terminals := _seconds_to_kill(_boss.terminal_health) * _boss.terminal_count
	var phase_two_desynced := terminals + _seconds_to_kill(phase_two_health)

	# Two phase ends, each spent watching the boss play dead, in which no damage can be dealt at
	# all. Counted because it is time the player spends in the fight, and the fight's length is
	# what this test is about.
	var feints := _boss.feigned_death_seconds * 2.0

	var fastest := phase_one + phase_two_desynced + phase_three + feints
	var slowest := phase_one + phase_two_synced + phase_three + feints

	check(
		fastest >= 10.0,
		"the boss needs at least ten seconds of fire even played well (%.1fs)" % fastest,
	)
	check(
		fastest <= 60.0,
		"the boss is not a bullet sponge when played well (%.1fs)" % fastest,
	)
	# Not merely "faster": *worth it*. This started as a `<` and passed at 11.25s versus
	# 13.25s — an eighteen percent return for crossing the arena four times under fire, which
	# is a mechanic the optimal player ignores. The margin is the assertion.
	check(
		phase_two_synced >= phase_two_desynced * 1.5,
		"breaking the terminals is worth the trip: %.1fs versus %.1fs ignoring them" % [
			phase_two_desynced, phase_two_synced,
		],
	)
	# The last phase should not be the shortest one. Phases two and three are handed the same
	# share of the pool, so until `merged_damage_scale` existed phase two's four terminals made it
	# twice the fight phase three was — a boss whose climax was over in five seconds. Measured
	# against the player who breaks the terminals, because that is the phase two worth matching.
	check(
		phase_three >= phase_two_desynced * 0.9,
		"the merged form lasts as long as the phase before it: %.1fs versus %.1fs" % [
			phase_three, phase_two_desynced,
		],
	)
	check(
		slowest <= 150.0,
		"even ignoring the terminals entirely, phase two ends (%.1fs total)" % slowest,
	)

	var toughest_enemy := _seconds_to_kill(6.0)
	check(
		fastest > toughest_enemy * 4.0,
		"the boss takes substantially longer than any regular enemy (%.1fs vs %.1fs)" % [
			fastest, toughest_enemy,
		],
	)


## The Floor 2 boss, whose length is far simpler arithmetic than the first one's: Runtime Error
## refunds nothing, scales nothing, and spends no time playing dead, so its pool divided by the
## player's damage is the whole answer.
##
## Measured against the *starting* weapon, like every other check in this suite, which makes it
## a deliberate overestimate — nobody reaches Development with the rivet blaster and no items.
## That is what the comparison against the first boss is for. Both numbers are wrong by roughly
## the same factor, so a second boss that lands near the first one on this scale is a second boss
## that lands near it in a real run too, and one that drifts to half or double the first is
## drifting for a reason worth knowing about.
func _test_the_second_boss_is_a_fight_rather_than_a_bullet_sponge() -> void:
	if not require(_second_boss, "the second boss's config loads"):
		return

	var length := _seconds_to_kill(_second_boss.max_health)
	check(
		length >= 10.0,
		"the second boss needs at least ten seconds of fire (%.1fs)" % length,
	)
	check(
		length <= 60.0,
		"and is not a bullet sponge (%.1fs)" % length,
	)

	# The floor the player arrives on with a whole extra floor's items. A second boss that was
	# *shorter* than the first on identical damage would be a difficulty curve running backwards.
	if _boss != null:
		var first := _seconds_to_kill(_boss.max_health)
		check(
			length >= first,
			"and the second floor's boss is at least the first one's pool (%.1fs against %.1fs)" % [
				length, first,
			],
		)

	# Each phase is a third of the pool, so each has to be long enough to show both of its
	# patterns more than once — a phase over before its second attack has come round twice is a
	# phase the player never learns to read.
	var phase_length := length / 3.0
	var slowest_interval := maxf(
		maxf(_second_boss.phase_one_interval, _second_boss.phase_two_interval),
		_second_boss.phase_three_interval,
	)
	check(
		phase_length >= slowest_interval * 4.0,
		"every phase lasts several attacks (%.1fs against a %.1fs interval)" % [
			phase_length, slowest_interval,
		],
	)

	# The lane telegraph, as the distance the player covers while it is amber, against the
	# deepest thing they ever have to walk out of. This is the number that makes the whole
	# mechanic fair, and it is worth having written down as arithmetic in the balance pass and
	# not only as a rule in the boss's own suite.
	var reach := _player.move_speed * _second_boss.lane_telegraph_seconds
	var deepest_pattern := 192.0 / float(maxi(_second_boss.checker_rows, 1))
	check(
		reach >= deepest_pattern * 1.5,
		"a lane warning buys comfortably more travel than its answer costs (%.0f against %.0f "
			% [reach, deepest_pattern] + "pixels)",
	)


func _test_the_player_can_take_a_few_hits() -> void:
	var leech: EnemyConfig = load("res://data/enemies/memory_leech.tres")
	if not require(leech, "the contact-damage enemy loads"):
		return
	check(leech.contact_damage > 0.0, "the chasing enemy actually hurts")

	var hits := floorf(_player.max_integrity / leech.contact_damage)
	check(
		hits >= 4.0 and hits <= 12.0,
		"the player survives %d contact hits, inside the 4-12 window" % int(hits),
	)
	check(
		_player.damage_invulnerability > 0.2,
		"there is enough invulnerability after a hit to escape the thing that landed it",
	)


## The dash has to be meaningfully faster than walking, or it is a button that does nothing.
func _test_the_dash_is_worth_pressing() -> void:
	var dash_speed := _player.dash_distance / maxf(_player.dash_duration, 0.001)
	check(
		dash_speed > _player.move_speed * 1.5,
		"dashing (%.0f px/s) is much faster than walking (%.0f px/s)" % [
			dash_speed, _player.move_speed,
		],
	)
	check(
		_player.dash_cooldown < 3.0,
		"the dash comes back often enough to be part of the moment-to-moment (%.1fs)"
			% _player.dash_cooldown,
	)
	# Spec section 6 wants the dash to be a defensive option, which needs the invulnerability
	# to cover a meaningful share of the travel.
	check(
		_player.dash_invulnerability >= _player.dash_duration * 0.5,
		"the dash is invulnerable for at least half its travel (%.2fs of %.2fs)" % [
			_player.dash_invulnerability, _player.dash_duration,
		],
	)


## Spec section 17 gives four of these numbers outright. They are asserted rather than trusted
## because they are the one part of the economy the spec fixes.
func _test_shop_prices_match_the_spec() -> void:
	if not require(_shop, "shop config loads"):
		return
	check(_shop.item_prices.size() >= 3, "there is a price for at least the first three rarities")
	check(_shop.item_prices[0] == 12, "spec section 17: a common item costs 12 scrap")
	check(_shop.item_prices[1] == 20, "spec section 17: an uncommon item costs 20 scrap")
	check(_shop.item_prices[2] == 32, "spec section 17: a rare item costs 32 scrap")
	check(_shop.heal_price == 6, "spec section 17: one integrity costs 6 scrap")
	check(_shop.reroll_base_price == 4, "spec section 17: the first reroll costs 4 scrap")
	check(_shop.reroll_price_step == 2, "spec section 17: each reroll costs 2 more")


## Spec section 17: "the player should not be able to buy everything" and "economy choices
## should create tension". Both halves are checkable against the floor's actual drop rates.
func _test_the_player_can_afford_something_but_not_everything() -> void:
	if not require(_floor, "floor config loads"):
		return

	var enemies := COMBAT_ROOMS_ON_FLOOR_1 * ENEMIES_PER_COMBAT_ROOM
	var per_enemy := (_floor.enemy_scrap_range.x + _floor.enemy_scrap_range.y) * 0.5
	var per_clear := (_floor.clear_scrap_range.x + _floor.clear_scrap_range.y) * 0.5
	# Every combat room plus the boss room pays a clear reward.
	var expected_run_scrap := enemies * per_enemy + (COMBAT_ROOMS_ON_FLOOR_1 + 1) * per_clear

	# The shop sits somewhere in the middle of the floor, so roughly half the run's income has
	# been collected by the time the player can spend any of it.
	var scrap_at_the_shop := expected_run_scrap * 0.5

	check(
		scrap_at_the_shop >= float(_shop.item_prices[0]),
		"by the shop the player can afford the cheapest item (about %.0f scrap vs %d)" % [
			scrap_at_the_shop, _shop.item_prices[0],
		],
	)
	check(
		scrap_at_the_shop >= float(_shop.heal_price + _shop.reroll_base_price),
		"a dead shop is escapable: a reroll and a heal are affordable (about %.0f scrap)"
			% scrap_at_the_shop,
	)

	var everything := 0
	for price: int in _shop.item_prices:
		everything += price
	check(
		expected_run_scrap < float(everything),
		"a whole run's scrap (about %.0f) does not buy one of everything (%d) — spec section 17"
			% [expected_run_scrap, everything],
	)


## A rarity with no price silently falls back to the common price, which would put a
## prototype item on the shelf for twelve scrap.
func _test_every_item_in_the_pool_has_a_price() -> void:
	if not require(_floor, "floor config loads"):
		return
	for item: ItemConfig in _floor.item_pool:
		if item == null:
			continue
		check(
			int(item.rarity) >= 0 and int(item.rarity) < _shop.item_prices.size(),
			"'%s' has a rarity the shop has a price for" % item.display_name,
		)
		check(
			_shop.price_for(item) > 0,
			"'%s' costs something (%d scrap)" % [item.display_name, _shop.price_for(item)],
		)


## The check that would have caught a reported soft-lock, and the reason this suite computes
## what the numbers mean rather than asserting they have not changed.
##
## Every item the floor reserves — the shop's shelf, each combat-clear reward, the treasure
## vault — comes out of one shared pool, and the boss's reward comes out of what is left. If
## the floor can reserve everything, the boss offers nothing, and victory (which waits on a
## reward being taken) becomes unreachable. There is now a guard in FloorController that wins
## the run anyway, but a floor that reaches it has still cheated the player out of spec
## section 16's promised choice.
##
## Rerolls are deliberately *not* counted: a reroll returns what it sweeps off the shelf, so
## the shop's cost is its shelf size no matter how many times it is rerolled. That property is
## the actual fix, and it is asserted directly in the Shop suite.
func _test_the_pool_cannot_run_dry_before_the_boss_reward() -> void:
	if not require(_floor, "floor config loads"):
		return

	var pool_size := _floor.item_pool.size()
	var shelf := _shop.item_stand_count
	var clear_rewards := _floor.item_clear_indices.size()
	var treasure := 1 if _floor.treasure_grants_item else 0
	var reserved_before_boss := shelf + clear_rewards + treasure
	var left_for_the_boss := pool_size - reserved_before_boss

	check(
		left_for_the_boss >= FloorController.BOSS_REWARD_COUNT,
		"the floor reserves at most %d of %d items before the boss, leaving %d for a reward "
			% [reserved_before_boss, pool_size, left_for_the_boss]
			+ "that needs %d" % FloorController.BOSS_REWARD_COUNT,
	)
	check(
		left_for_the_boss > 0,
		"there is always something left for the boss to offer (%d)" % left_for_the_boss,
	)
