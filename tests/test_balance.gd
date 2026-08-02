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
const FLOOR := "res://data/floors/floor_1_help_desk.tres"
const SHOP := "res://data/settings/shop_config.tres"

## Combat rooms on Floor 1 hold three or four enemies (see data/rooms/combat_*.tres), and a
## ten-room floor is one start, one shop, one treasure, one boss, and the rest combat.
const COMBAT_ROOMS_ON_FLOOR_1 := 6
const ENEMIES_PER_COMBAT_ROOM := 3.5

var _player: PlayerConfig
var _weapon: WeaponConfig
var _boss: BossConfig
var _floor: FloorConfig
var _shop: ShopConfig


func run() -> void:
	_player = load(PLAYER_CONFIG)
	_weapon = load(WEAPON)
	_boss = load(BOSS)
	_floor = load(FLOOR)
	_shop = load(SHOP)

	if not require(_player, "player config loads"):
		return
	if not require(_weapon, "weapon config loads"):
		return

	_test_starting_weapon_deals_damage()
	_test_every_enemy_dies_in_a_reasonable_window()
	_test_the_boss_is_a_fight_rather_than_a_bullet_sponge()
	_test_the_player_can_take_a_few_hits()
	_test_the_dash_is_worth_pressing()
	_test_shop_prices_match_the_spec()
	_test_the_player_can_afford_something_but_not_everything()
	_test_every_item_in_the_pool_has_a_price()


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
	var phase_three := _seconds_to_kill(pool * _boss.merge_at)

	# Worst case for phase two: the player never breaks a terminal, so every point of damage
	# is refunded at desync_heal_fraction and costs 1/(1-fraction) times as much.
	var phase_two_health := pool * (_boss.duplicate_at - _boss.merge_at)
	var refund_multiplier := 1.0 / maxf(1.0 - _boss.desync_heal_fraction, 0.01)
	var phase_two_synced := _seconds_to_kill(phase_two_health * refund_multiplier)
	var terminals := _seconds_to_kill(_boss.terminal_health) * _boss.terminal_count
	var phase_two_desynced := terminals + _seconds_to_kill(phase_two_health)

	var fastest := phase_one + phase_two_desynced + phase_three
	var slowest := phase_one + phase_two_synced + phase_three

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
