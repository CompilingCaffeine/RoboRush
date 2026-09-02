extends TestCase
## The balance pass, as arithmetic on the shipped data.
##
## Milestone 6 lists a balance pass. The game has since been played through end to end several
## times, and the honest position is still that no number in `data/` has moved because of it —
## what those runs taught lives in somebody's head rather than in this repository, so every value
## here remains the one spec sections 6, 15, 16 and 17 argued for. Difficulty, pacing, and whether
## the boss is fun are not things a test can judge, and guessing at numbers without the write-up
## would be worse than leaving them alone.
##
## What a test *can* do is compute what those numbers actually mean and refuse to let them
## drift somewhere absurd. Time to kill is a division. Whether the boss fight is longer than
## a trash mob is a comparison. Whether a player can afford anything at all in the shop is
## addition. None of that needs a player, and all of it is the kind of thing that quietly
## stops being true the first time somebody buffs an enemy.
##
## So the ranges below are deliberately wide. They are not claims that the game is tuned
## correctly; they are tripwires for the tuning being nonsense. When someone finally writes up
## what playing taught and moves the numbers, these should be updated to match — not deleted, and
## not treated as the design.
##
## One thing has changed shape since that was written, and it is the economy. The combat checks
## are all statements about one enemy, one boss, one dash, and a floor is the right unit for
## them. Scrap is not: a purse crosses floor boundaries, so what the player can afford at the
## fourth shop depends on the three they already walked past. Every check touching money is
## therefore asked of the whole campaign, through `FloorEconomy` — see
## `_test_every_shop_in_the_run_is_worth_walking_into` for why one floor could not stand in.

const PLAYER_CONFIG := "res://data/player/player_config.tres"
const WEAPON := "res://data/weapons/rivet_blaster.tres"
const BOSS := "res://data/bosses/merge_conflict.tres"
const SECOND_BOSS := "res://data/bosses/runtime_error.tres"
const THIRD_BOSS := "res://data/bosses/cascade_failure.tres"
const CAMPAIGN := "res://data/runs/main_campaign.tres"
const SHOP := "res://data/settings/shop_config.tres"

var _player: PlayerConfig
var _weapon: WeaponConfig
var _boss: BossConfig
var _second_boss: RuntimeErrorConfig
var _third_boss: CascadeFailureConfig
var _shop: ShopConfig

## The campaign, and every floor it lists in order.
##
## The economy checks below used to read `floor_1_help_desk.tres` and a pair of hand-typed
## constants, and every one of them was a claim about one floor and one shop standing in for a
## run. That was true of a one-floor game and quietly stopped being true three floors ago: a run
## now walks four shelves with one purse, and the interesting questions — whether spending at the
## first shop leaves anything for the fourth, whether a rare is still a decision at the bottom of
## the building — cannot be asked of a single floor at all.
var _campaign: RunDefinition
var _floors: Array[FloorConfig] = []


func run() -> void:
	_player = load(PLAYER_CONFIG)
	_weapon = load(WEAPON)
	_boss = load(BOSS)
	_second_boss = load(SECOND_BOSS)
	_third_boss = load(THIRD_BOSS)
	_shop = load(SHOP)
	_campaign = load(CAMPAIGN)

	if not require(_player, "player config loads"):
		return
	if not require(_weapon, "weapon config loads"):
		return
	if require(_campaign, "the campaign loads"):
		for index: int in _campaign.floors.size():
			var config := _campaign.load_floor(index)
			if require(config, "campaign floor %d loads" % (index + 1)):
				_floors.append(config)

	_test_starting_weapon_deals_damage()
	_test_every_enemy_dies_in_a_reasonable_window()
	_test_the_boss_is_a_fight_rather_than_a_bullet_sponge()
	_test_the_second_boss_is_a_fight_rather_than_a_bullet_sponge()
	_test_the_third_boss_is_a_fight_rather_than_a_bullet_sponge()
	_test_the_player_can_take_a_few_hits()
	_test_the_dash_is_worth_pressing()
	_test_shop_prices_match_the_spec()
	_test_every_shop_in_the_run_is_worth_walking_into()
	_test_a_whole_run_does_not_clear_every_shelf()
	_test_a_rare_stays_a_decision_at_every_depth()
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

	# Runtime Error is the longer of the two fights, which is no longer the same claim as "the
	# second floor's boss is longer". Either boss can guard either floor now, so on roughly half
	# of all runs the player meets this 110-point pool on the *first* floor, with a starting
	# build and no items — while the other half meets a 60-point Scrap King on the second floor
	# with a full one.
	#
	# The ordering assertion is kept because the two pools should still differ in this direction
	# — a random boss order is only interesting while the bosses are not interchangeable — but
	# the *spread* between them is now something a player feels as run-to-run difficulty rather
	# than as a curve. Whether 60-against-110 is too wide a swing for a coin flip is a playtest
	# question, and the first number to move if it is.
	if _boss != null:
		var first := _seconds_to_kill(_boss.max_health)
		check(
			length >= first,
			"Runtime Error is the longer of the two fights (%.1fs against %.1fs)" % [
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

	# The body has to keep up with the point it is tracking, or the sway that makes it hard to
	# hit quietly shrinks to a fraction of the amplitude the config claims — a boss that got
	# easier to hit with no number anywhere admitting it.
	var peak_lateral := _second_boss.sway_amplitude * _second_boss.sway_speed
	check(
		_second_boss.move_speed > peak_lateral,
		"the boss can keep up with its own sway (%.0f against %.0f pixels per second)" % [
			_second_boss.move_speed, peak_lateral,
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


## The Floor 3 boss, whose length is the same simple division Runtime Error's is: Cascade Failure
## refunds nothing, scales nothing, and never plays dead, so its pool over the player's damage is
## the whole answer.
##
## Measured against the *starting* weapon, like everything else in this suite, which is a deliberate
## overestimate — nobody reaches the Data Center with the rivet blaster and no items. Its value is
## the comparison against the two bosses before it, both of which are wrong by roughly the same
## factor.
func _test_the_third_boss_is_a_fight_rather_than_a_bullet_sponge() -> void:
	if not require(_third_boss, "the third boss's config loads"):
		return

	var length := _seconds_to_kill(_third_boss.max_health)
	check(length >= 10.0, "the third boss needs at least ten seconds of fire (%.1fs)" % length)
	check(length <= 60.0, "and is not a bullet sponge (%.1fs)" % length)

	# Unlike the first two, this one *is* a claim about the curve. Cascade Failure guards one floor
	# and only one — it is written in the Data Center's own visual language, so it cannot turn up
	# early the way the other two can turn up on either of their floors — which makes "the boss the
	# player meets third is the longest of the three" a sentence about difficulty rather than about
	# a coin flip.
	if _second_boss != null:
		var second := _seconds_to_kill(_second_boss.max_health)
		check(
			length > second,
			"and is the longest fight of the three, being the one that is always third (%.1fs "
				% length + "against %.1fs)" % second,
		)

	# Each node is an even share of the pool, so the fight has `node_count` acts. Every one of them
	# has to last long enough for the rack to vent several times, or a phase is over before the
	# player has seen what it does differently.
	var act := length / float(maxi(_third_boss.node_count, 1))
	var slowest_vent := _third_boss.vent_interval / float(maxi(_third_boss.node_count, 1))
	check(
		act >= slowest_vent * 3.0,
		"every act lasts several of the rack's vents (%.1fs against %.1fs)" % [act, slowest_vent],
	)

	# The player's travel while a vent climbs, against the vent itself. This is the number that
	# makes the boss's ground fair, and it belongs written down as arithmetic here as well as as a
	# rule in the fight's own suite.
	var reach := _player.move_speed * _third_boss.vent_seconds
	var deepest := float(maxi(_third_boss.vent_tiles.x, _third_boss.vent_tiles.y) * Room.TILE_SIZE)
	check(
		reach >= deepest * 1.5,
		"a vent's warning buys comfortably more travel than walking out of it costs (%.0f against "
			% reach + "%.0f pixels)" % deepest,
	)

	# And the last phase, which is a chase: the node has to be slower than the robot, or its trail
	# stops being the threat and its body starts being one.
	check(
		_third_boss.runaway_speed < _player.move_speed,
		"the last node cannot outrun the robot (%.0f against %.0f)" % [
			_third_boss.runaway_speed, _player.move_speed,
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


## Spec section 17's first half — "economy choices should create tension" — asked of every shelf
## a run walks past rather than only the first.
##
## The model is the player who empties their purse. Whatever they held on arriving at one shop,
## they leave it holding nothing, so what they bring to the next is exactly what the game paid
## them in between: the rest of the floor they were on, and the half of the next floor that comes
## before its shop. That is the only version of this question a four-shop run makes available, and
## it is the one the single-floor check could not ask — with one shelf in the game, "can the
## player afford something" has no history to be poor from.
##
## Two things have to be true at every shelf, and they are different rules. The first is that
## something on it is buyable at all. The second is that a shelf holding nothing the player wants
## is still escapable — a reroll and a repair — because a shop that can only be walked out of is
## a room that wasted the walk.
func _test_every_shop_in_the_run_is_worth_walking_into() -> void:
	if not require(not _floors.is_empty(), "the campaign's floors load"):
		return
	if not require(_shop != null and not _shop.item_prices.is_empty(), "the shop has prices"):
		return

	var cheapest := float(_shop.item_prices.min())
	var escape := float(_shop.heal_price + _shop.reroll_base_price)
	var carried := 0.0

	for index: int in _floors.size():
		var config := _floors[index]
		var earned := carried + FloorEconomy.before_the_shop(config)
		# The first shop has no previous one to have been emptied at, so it is reached on its own
		# floor's income alone — which makes it the tightest shelf in the campaign rather than the
		# most comfortable, and the message says which case it is reporting.
		var how := "on the floor's own income" if index == 0 else "having emptied the last shop"
		check(
			earned >= cheapest,
			"floor %d's shop is affordable %s (%.0f scrap against the %.0f a cheapest item costs)"
				% [index + 1, how, earned, cheapest],
		)
		check(
			earned >= escape,
			"and a dead shelf there is escapable — a reroll and a repair come to %.0f" % escape,
		)
		# Emptied, deliberately. Anything carried past a shop is a player who did not shop, and
		# the run that has to hold up is the one where they did.
		carried = FloorEconomy.after_the_shop(config)


## Spec section 17's other half — "the player should not be able to buy everything" — which is the
## claim four shops changed and the reason this check was rewritten rather than re-pointed.
##
## It used to compare one floor's income against one of every rarity in the price table, 132
## scrap, and pass with room to spare. Neither number means anything now. A run earns across four
## floors and spends across four shelves, so the honest comparison is everything the campaign pays
## against everything it puts on sale: `floors x item_stand_count` items, priced at what the pool
## they are drawn from averages. Both sides of that grow when a floor is added, which is what
## makes it a claim about the campaign rather than about its length.
##
## The known tail, recorded here for the same reason the shop suite records its own: a run that
## drew a common onto all eight stands would face 96 scrap of stock against about 170 of income
## and could clear the lot. That is the luckiest shelf in the campaign rather than the design, and
## averaging it away would be the wrong fix — it is a price-table decision if it is ever a problem.
func _test_a_whole_run_does_not_clear_every_shelf() -> void:
	if not require(not _floors.is_empty(), "the campaign's floors load"):
		return

	var income := 0.0
	for config: FloorConfig in _floors:
		income += FloorEconomy.whole_floor(config)

	var stands := _floors.size() * maxi(_shop.item_stand_count, 0)
	var average_price := _average_item_price()
	if not require(average_price > 0.0, "the run's item pool prices something"):
		return
	var stock := float(stands) * average_price

	check(
		income < stock,
		"a whole run's scrap (about %.0f) does not clear the %d shelves it walks past "
			% [income, stands] + "(about %.0f at the pool's average %.0f a stand)" % [
				stock, average_price,
			],
	)


## A rare costs 32 and a run is now four floors long, which is the pair of numbers the price table
## was never checked against. Both ways of getting this wrong are quiet.
##
## Too little income and the dearest thing in the shop is theoretical: a player who cannot clear a
## floor's worth of scrap in a floor never buys one, and the rarity is decoration. Too much and the
## shelf stops being a choice — a floor that pays for three rares is a floor whose shop the player
## empties without deciding anything, which is the vending machine spec section 17 names.
##
## Per floor rather than per run, because the income is per floor and the prices are not: a table
## that holds on the Help Desk and fails on Cloud Operations is exactly the drift a campaign-shaped
## suite exists to catch, and averaging the four together would hide it.
func _test_a_rare_stays_a_decision_at_every_depth() -> void:
	if not require(not _floors.is_empty(), "the campaign's floors load"):
		return
	if not require(_shop.item_prices.size() > int(ItemConfig.Rarity.RARE), "a rare has a price"):
		return

	var rare := float(_shop.item_prices[int(ItemConfig.Rarity.RARE)])
	for index: int in _floors.size():
		var income := FloorEconomy.whole_floor(_floors[index])
		check(
			income >= rare and income <= rare * 3.0,
			"floor %d pays %.0f scrap, between one and three rares at %.0f — dear enough to be "
				% [index + 1, income, rare]
				+ "a decision, cheap enough to be reachable (%.2fx)" % (income / rare),
		)


## What a stand costs on average, over the pool it is stocked from.
##
## Flat across the pool because that is how `ShopRoom._stock_item_stand` draws — one call to
## `RunManager.draw_item`, uniform among whatever it has not offered yet — so the expected price
## of a stand is the expected price of an item. It shifts as a run spends its uniques, which is
## a second-order effect this deliberately does not model: the direction is toward the repeatable
## chips, which are commons, and pricing the late shelves cheaper would only make the check above
## stricter.
func _average_item_price() -> float:
	var items := _floors[0].get_items()
	if items.is_empty():
		return 0.0
	var total := 0
	for item: ItemConfig in items:
		total += _shop.price_for(item)
	return float(total) / float(items.size())


## A rarity with no price silently falls back to the common price, which would put a
## prototype item on the shelf for twelve scrap.
##
## Every floor's pool rather than the first one's. All four currently name the same resource, so
## this is the same list four times over — but nothing makes them, `FloorConfig.item_pool` exists
## precisely so a later floor can name its own, and the day one does is the day a check written
## against floor 1 stops covering the campaign.
func _test_every_item_in_the_pool_has_a_price() -> void:
	if not require(not _floors.is_empty(), "the campaign's floors load"):
		return
	var priced: Dictionary[StringName, bool] = {}
	for config: FloorConfig in _floors:
		for item: ItemConfig in config.get_items():
			if item == null or priced.has(item.id):
				continue
			priced[item.id] = true
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
##
## Asked of each floor on its own, which is the limit of what this check is: `offered_item_ids` is
## run-scoped, so the floor that actually runs the pool dry is the one *after* the last one that
## fits, and no amount of per-floor arithmetic sees that. The cumulative version is simulated over
## ten thousand campaigns in `tests/test_economy.gd`, and enforced at boot by
## `CampaignValidator._validate_reward_capacity`. This one stays because it localises the failure:
## it names the floor whose own reservations are impossible, which a campaign-wide total cannot.
func _test_the_pool_cannot_run_dry_before_the_boss_reward() -> void:
	if not require(not _floors.is_empty(), "the campaign's floors load"):
		return

	for index: int in _floors.size():
		var config := _floors[index]
		var pool_size := config.get_items().size()
		var shelf := _shop.item_stand_count
		var clear_rewards := config.item_clear_indices.size()
		var treasure := 1 if config.treasure_grants_item else 0
		var reserved_before_boss := shelf + clear_rewards + treasure
		var left_for_the_boss := pool_size - reserved_before_boss

		check(
			left_for_the_boss >= FloorController.BOSS_REWARD_COUNT,
			"floor %d reserves at most %d of %d items before the boss, leaving %d for a reward "
				% [index + 1, reserved_before_boss, pool_size, left_for_the_boss]
				+ "that needs %d" % FloorController.BOSS_REWARD_COUNT,
		)
		check(
			left_for_the_boss > 0,
			"and there is always something left for its boss to offer (%d)" % left_for_the_boss,
		)
