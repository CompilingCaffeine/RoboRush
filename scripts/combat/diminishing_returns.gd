class_name DiminishingReturns
extends RefCounted
## The curve that stops stacked multipliers from compounding a floor out of existence.
##
## Every multiplicative aggregate in this game is a product across everything held — that is what
## makes Cooling Fan and Unsafe Overclock compound instead of one overwriting the other, and it is
## the right rule for two items. It is the wrong rule for twelve. The offer cadence is eight per
## floor on every floor, nothing about an enemy is a function of depth, and a product of a dozen
## scalars is geometric against a roster that is flat. By the Data Center a legal build reached
## roughly 13.8x damage and 3.8x fire rate — 52x the damage per second the enemy health numbers
## were written against — and the floor stopped being a floor.
##
## The fix is deliberately *not* a cap. A hard ceiling makes every item past it worthless, which
## turns a reward into a message that the run is over, and it makes the item that crossed the line
## the one the player blames. This is a soft knee instead: bonus below `KNEE` is kept whole, and
## everything above it is compressed onto an asymptote. More is always more; it is just never
## proportionally more.
##
## **The shape.** With `bonus = multiplier - 1`:
##
##     bonus <= KNEE          ->  kept exactly
##     bonus  > KNEE          ->  KNEE + RANGE * excess / (excess + RANGE)
##
## The second branch approaches `RANGE` and never reaches it, so the whole function approaches
## `1 + KNEE + RANGE` — 3.5x at the shipped constants. Its derivative at the knee is exactly 1, so
## the two branches meet without a corner: there is no build sitting on a cliff, and no item whose
## value collapses because the item before it happened to land first.
##
## **Why a knee at all, rather than compressing from 1.0.** A player who has doubled their damage
## has spent most of a run doing it and should feel every point of it. Softening from the first
## item would make the first item weaker than it reads, which is the version of this change a
## player would actually notice and resent. The knee is where "a strong build" turns into "a build
## that has stopped needing to play the game", and putting it at +100% is a judgement about this
## game's enemy health, not a universal constant — see the table in `soften`.
##
## **What this is applied to, and what it is not.** Two aggregates: projectile `damage` and the
## fire-rate multiplier. Those are the two that multiply directly into damage per second, which is
## the only quantity that can make a floor trivial. Everything else multiplicative is left alone
## and each for its own reason:
##
##   - `dash_cooldown_scale` — the benefit is a value *below* one, so the same curve would have to
##     be written twice with the sign flipped. It is also not a damage stat; a build with a very
##     short dash cooldown is mobile, not unopposed.
##   - `first_shot_damage_scale` — Cache Warmer, one shot per room. A burst is not a curve.
##   - `speed`, `radius`, `split_spread_degrees` — one authored item each, and none of them is
##     damage. Chip Speed stacks five times to 1.76x projectile speed, which is a feel change.
##   - `chain_damage_scale`, `split_damage_scale` — fractions *of* a damage number this curve has
##     already softened. Softening them again would be applying the knee twice to one hit.
##
## The list is short on purpose. A softened aggregate is one the player cannot fully reason about,
## so every one of them is a cost, and the two here are the two worth paying for.


## Bonus kept at full value, as a fraction. 1.0 means a build up to +100% is untouched.
##
## The number comes from what the enemies are worth. Floor 1's roster is 2 to 6 integrity and the
## rivet blaster removes about 6.6 per second, so doubled damage already kills the whole roster
## inside one reaction. Past that the fight is not getting shorter in a way the player can feel —
## it is getting shorter in a way the *floor* feels, which is the thing being fixed.
const KNEE := 1.0

## How much further the bonus may climb above the knee, asymptotically. The total ceiling is
## therefore `1 + KNEE + RANGE`.
##
## 1.5 puts that ceiling at 3.5x. Chosen so that the strongest legal build is roughly two and a
## half times an ordinary one rather than eight times it: a build is still won or lost, but the
## difference between winning it and winning it twice over stops mattering. It is also chosen with
## room left over — a six-floor campaign wants per-floor enemy scaling as well, and an asymptote
## the opposition can be tuned against is more useful than one it has to be tuned around.
const RANGE := 1.5


## `multiplier` softened. Values at or below 1.0 are returned untouched.
##
## Penalties pass through whole, and that asymmetry is the point rather than an oversight. Burst
## Buffer's 0.8x damage and Deprecated API's 0.6x fire rate are what those items charge for what
## they give; running them through a curve built to compress *benefits* would quietly refund part
## of the price and make the trade-off items the safest picks in the pool.
##
## What the shipped constants do to a build, as damage multipliers:
##
##     raw    1.5   2.0   3.0   5.0   8.0   13.8   ->  infinity
##     soft   1.5   2.0   2.6   3.0   3.2   3.3    ->  3.5
##
## Read the first two columns as the promise and the last as the point: everything a player is
## likely to hold by floor 2 is untouched, and the outlier builds that used to trivialise floor 3
## land within reach of the ordinary ones.
static func soften(multiplier: float) -> float:
	var bonus := multiplier - 1.0
	if bonus <= KNEE:
		return multiplier

	var excess := bonus - KNEE
	return 1.0 + KNEE + RANGE * excess / (excess + RANGE)
