class_name FeedbackDirector
extends Node2D
## Turns gameplay events into everything the player sees and hears.
##
## One node subscribes to the EventBus and owns the entire mapping from "what
## happened" to "what it looks and sounds like". Two things fall out of that:
## gameplay scripts contain no presentation calls at all (spec section 26.9), and
## milestone 6's polish pass is a change to this one file rather than an audit of
## every combat script.
##
## Screen shake and hit pause are applied here rather than at their sources, which is
## how the "do not overuse screen shake" rule (spec section 7) stays enforceable —
## every shake in the game is one of the numbers below.

const IMPACT_BURST := preload("res://scenes/effects/impact_burst.tscn")
const DEATH_BURST := preload("res://scenes/effects/death_burst.tscn")
const EXPLOSION_BURST := preload("res://scenes/effects/explosion_burst.tscn")
const CHAIN_ZAP := preload("res://scenes/effects/chain_zap.tscn")
const DAMAGE_NUMBER := preload("res://scenes/effects/damage_number.tscn")

## Trauma per event. Ordinary projectile impacts get none at all — at 4 shots per
## second, shaking on every hit is indistinguishable from a rendering fault.
const SHAKE_ENEMY_KILLED := 0.34
const SHAKE_PLAYER_DAMAGED := 0.55
const SHAKE_PLAYER_DIED := 0.85

## Explosions shake less than a kill even though they look bigger, because Volatile Kernel
## fires one on *every* death — the kill's own shake is already playing, and adding a second
## one would make the item feel like a screen fault rather than a payoff.
const SHAKE_EXPLOSION := 0.16

## The boss changing shape. Larger than a kill, smaller than the player dying: it is the most
## significant thing that happens in the fight that is not somebody's death.
const SHAKE_BOSS_PHASE := 0.5

## The explosion particle scene is built around a 36px blast (Volatile Kernel's radius), so
## this converts a requested radius into a scale for anything else.
const EXPLOSION_REFERENCE_RADIUS := 36.0

## Fire is pitch-varied because it repeats constantly; a perfectly identical sound
## four times a second is what makes an arcade shooter tiring.
const FIRE_PITCH_VARIATION := 0.12
const HIT_PITCH_VARIATION := 0.18
const PICKUP_PITCH_VARIATION := 0.22

## Scrap drops in handfuls, so several blips overlap; this keeps the sum bearable.
const PICKUP_VOLUME_DB := -6.0

var _shake: ShakeCamera


func _ready() -> void:
	EventBus.shot_fired.connect(_on_shot_fired)
	EventBus.projectile_hit.connect(_on_projectile_hit)
	EventBus.enemy_damaged.connect(_on_enemy_damaged)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.player_damaged.connect(_on_player_damaged)
	EventBus.player_died.connect(_on_player_died)
	EventBus.player_dash_started.connect(_on_player_dash_started)
	EventBus.room_cleared.connect(_on_room_cleared)
	EventBus.pickup_collected.connect(_on_pickup_collected)
	EventBus.item_collected.connect(_on_item_collected)
	EventBus.doors_changed.connect(_on_doors_changed)
	EventBus.projectile_bounced.connect(_on_projectile_bounced)
	EventBus.explosion_triggered.connect(_on_explosion_triggered)
	EventBus.chain_jumped.connect(_on_chain_jumped)
	EventBus.room_entered.connect(_on_room_entered)
	EventBus.purchase_made.connect(_on_purchase_made)
	EventBus.boss_phase_changed.connect(_on_boss_phase_changed)
	EventBus.boss_feigned_defeat.connect(_on_boss_feigned_defeat)
	EventBus.boss_defeated.connect(_on_boss_defeated)


## Wired by main.gd, which owns scene composition.
func setup(camera: ShakeCamera) -> void:
	_shake = camera


func _on_shot_fired(team: int, muzzle: Vector2, _direction: Vector2) -> void:
	# Enemy shots are announced by their telegraph and their projectile, and one
	# firing sound per enemy per second would bury the player's own weapon.
	if team != Teams.Id.PLAYER:
		return
	AudioManager.play_sfx(&"fire", FIRE_PITCH_VARIATION)


func _on_projectile_hit(projectile: Node, target: Node, point: Vector2, normal: Vector2) -> void:
	var tint := Color.WHITE
	var config: ProjectileConfig = projectile.get("config")
	if config != null:
		tint = config.trail_color

	var burst: OneShotBurst = IMPACT_BURST.instantiate()
	burst.position = point
	burst.set_tint(tint)
	burst.aim_along(normal)
	add_child(burst)

	# Only hits on something destructible get a sound; wall pings would be constant.
	if target != null:
		AudioManager.play_sfx(&"enemy_hit", HIT_PITCH_VARIATION)


func _on_enemy_damaged(enemy: Node, info: DamageInfo, _remaining: float) -> void:
	if not GameManager.feedback.damage_numbers_enabled:
		return
	var number: DamageNumber = DAMAGE_NUMBER.instantiate()
	number.position = (enemy as Node2D).global_position + Vector2.UP * 8.0
	add_child(number)
	# After add_child: the label is only available once the scene is ready.
	number.show_damage(info.amount, info.is_critical)


func _on_enemy_killed(_enemy: Node, position: Vector2) -> void:
	var burst: OneShotBurst = DEATH_BURST.instantiate()
	burst.position = position
	add_child(burst)

	AudioManager.play_sfx(&"enemy_death")
	_add_trauma(SHAKE_ENEMY_KILLED)
	GameManager.hit_pause()


func _on_player_damaged(_info: DamageInfo, remaining: float) -> void:
	AudioManager.play_sfx(&"player_hurt")
	_add_trauma(SHAKE_PLAYER_DAMAGED)
	GameManager.hit_pause()
	if remaining <= 1.0 and remaining > 0.0:
		AudioManager.play_sfx(&"low_integrity")


func _on_player_died() -> void:
	_add_trauma(SHAKE_PLAYER_DIED)
	GameManager.hit_pause()
	# The power-down sound and the summary screen need the room to themselves.
	AudioManager.stop_music()


## Which music plays is decided here rather than by the floor, for the same reason every other
## sound is: the room should not know what a soundtrack is. Two tracks and one rule — the boss
## arena gets the boss loop, everywhere else gets the explore loop — and `play_music` ignores a
## request for the track already playing, so walking through a door does not restart it.
func _on_room_entered(type: int, _room_id: int) -> void:
	var wants_boss := type == RoomTemplate.Type.BOSS
	AudioManager.play_music(&"boss" if wants_boss else &"explore")


## Distinct from the item fanfare, because buying something and finding it are different
## events even when the item is the same. Zero-cost stands are the boss reward, which is a
## gift rather than a transaction and keeps the fanfare it already had.
func _on_purchase_made(cost: int) -> void:
	if cost > 0:
		AudioManager.play_sfx(&"purchase")


## Spec section 22 lists the boss phase transition among its priority sounds. Phase one is the
## fight starting, which the boss music already announced.
##
## Every phase after the first begins on the far side of a feigned death, so this is also where the
## music comes back. Restarting it *here* rather than on a timer is what makes the boss theme
## returning read as the boss standing up, and it is the one thing the player has left to go on
## after the bar refilled.
func _on_boss_phase_changed(phase: int) -> void:
	if phase > 1:
		AudioManager.play_sfx(&"boss_phase")
		_add_trauma(SHAKE_BOSS_PHASE)
		AudioManager.play_music(&"boss")


## The boss playing dead gets exactly what dying gets: the death burst, the death sound, a kill's
## worth of shake, and the music going out. Deliberately not a softer version of it — a fake death
## the player can tell apart from the real one is only a pause in the fight, and this fight is
## built to be believed. The lie is corrected by `_on_boss_phase_changed` two seconds later.
func _on_boss_feigned_defeat(_boss: Node, at: Vector2) -> void:
	var burst: OneShotBurst = DEATH_BURST.instantiate()
	burst.position = at
	add_child(burst)

	AudioManager.play_sfx(&"enemy_death")
	AudioManager.stop_music()
	_add_trauma(SHAKE_ENEMY_KILLED)
	GameManager.hit_pause()


func _on_boss_defeated(_boss: Node) -> void:
	AudioManager.stop_music()


func _on_player_dash_started(_direction: Vector2) -> void:
	AudioManager.play_sfx(&"dash")


func _on_room_cleared() -> void:
	AudioManager.play_sfx(&"room_clear")


## Scrap is picked up constantly, so its blip is pitch-varied and quieter than the rest —
## spec section 22 warns against fatiguing effects, and this is the one most likely to become
## one.
func _on_pickup_collected(_kind: int, _amount: float, _position: Vector2) -> void:
	AudioManager.play_sfx(&"pickup", PICKUP_PITCH_VARIATION, PICKUP_VOLUME_DB)


## The one pickup worth interrupting for. Louder and longer than the scrap blip, with no
## pitch variation — a fanfare that came out slightly different each time would sound
## broken rather than varied.
func _on_item_collected(_item: ItemConfig) -> void:
	AudioManager.play_sfx(&"item_pickup")


func _on_doors_changed(_are_locked: bool) -> void:
	AudioManager.play_sfx(&"door")


## A spark where a shot changed direction, so a bouncing or returning projectile is
## visibly doing something rather than appearing to glitch through the wall. Silent: at a
## bounce per shot, a ping four times a second is the fatigue spec section 22 warns about.
func _on_projectile_bounced(point: Vector2, normal: Vector2) -> void:
	var burst: OneShotBurst = IMPACT_BURST.instantiate()
	burst.position = point
	burst.aim_along(normal)
	add_child(burst)


func _on_explosion_triggered(position: Vector2, radius: float) -> void:
	var burst: OneShotBurst = EXPLOSION_BURST.instantiate()
	burst.position = position
	# Scaled rather than re-authored per radius, so a bigger blast looks bigger without a
	# second particle scene to keep in sync with the first.
	burst.scale = Vector2.ONE * maxf(radius / EXPLOSION_REFERENCE_RADIUS, 0.35)
	add_child(burst)

	AudioManager.play_sfx(&"explosion", HIT_PITCH_VARIATION)
	_add_trauma(SHAKE_EXPLOSION)


func _on_chain_jumped(from: Vector2, to: Vector2) -> void:
	var zap: ChainZap = CHAIN_ZAP.instantiate()
	add_child(zap)
	# After add_child: strike() sets top_level, which needs a parent to be meaningful.
	zap.strike(from, to)

	AudioManager.play_sfx(&"zap", HIT_PITCH_VARIATION)


func _add_trauma(amount: float) -> void:
	if _shake != null:
		_shake.add_trauma(amount)
