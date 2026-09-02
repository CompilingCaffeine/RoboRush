class_name BossPart
extends CharacterBody2D
## One shootable body belonging to a boss.
##
## A boss with two versions of itself still has one health pool, so the two bodies cannot
## each own their health. This is the shape that falls out: a part carries a
## HealthComponent purely as a *receiver* — it is what makes a projectile register a hit at
## all, since a projectile damages whatever has one — and forwards every hit to the
## controller, which owns the real pool. Its own health is topped straight back up, so a
## part never dies on its own and the fight ends exactly once, where the controller says.
##
## The alternative was teaching projectiles about bosses, which would put a boss-specific
## branch in the one file that has never had one.
##
## ## It also hurts to touch
##
## Every ordinary enemy that has a body the player can walk into charges them for walking into it
## (`Enemy._step_contact_damage`), and until recently the bosses were the one exception: three
## fights in which standing inside the thing you are shooting was free. That is the wrong lesson
## in the room where positioning matters most, and it is worst in the fight built entirely out of
## where you are standing — Cascade Failure's nodes could be ridden around the ring, which put the
## player on the one patch of floor the boss was about to vent and charged them nothing for it.
##
## So a part is a hazard as well as a receiver, and it lives here rather than in each of the three
## controllers for the reason the receiver does: a body that hurts to touch hurts on all of it,
## whichever boss it belongs to. The numbers are per scene, because a 28-pixel king and a 16-pixel
## rack unit are not the same thing to stand next to.
##
## The Scrap King's charge keeps its own separate hit — see `MergeConflict._step_charge`. It is a
## different event with its own knockback, and the player's own damage window means the two can
## never both land.

## Emitted for every hit this part takes. The controller decides what it costs.
signal took_damage(info: DamageInfo)

## Large enough that no single hit can empty it before it is refilled, so the part never
## reaches zero and never emits `died`.
const RECEIVER_POOL := 100000.0

## The player's collision radius, from player.tscn. Duplicated for the reason `CompileLane`,
## `ThermalZone` and `CascadeFailure` all duplicate it: a body has to be able to ask who it is
## touching without depending on how the player scene is assembled.
const PLAYER_RADIUS := 5.0

@export_group("Contact")

## What touching this body costs. Zero switches contact damage off entirely, which is what a part
## that is meant to be walked through would set.
@export var contact_damage: float = 1.0

## How close the player's centre must come, before their own radius is added. Set per scene to the
## part's own collision radius, so what hurts is what the player can see they are standing in.
@export var contact_radius: float = 14.0

## Seconds before this body may charge the player again. Longer than the player's own damage window
## (`PlayerConfig.damage_invulnerability`), so a robot that has been shoved out of a boss and comes
## straight back gets a fresh moment inside it rather than being billed the instant their immunity
## lapses.
@export var contact_interval: float = 1.0

## Impulse a contact hit shoves the player with. Larger than an ordinary enemy's, because the point
## of it is to put the player back outside the body rather than to punish them twice for the same
## mistake.
@export var contact_knockback: float = 190.0

## What a hit looks like when the controller is not going to count it.
##
## Only the Orchestrator is ever shielded, and it is shielded for most of its fight: damage lands
## only in the window after it migrates, and shots fired at it the rest of the time are discarded.
## A body that flashed bright white for those would be telling the player their shots were working
## in the one fight where that is the mistake — so a shielded hit pings dim steel instead, which
## reads as a deflection rather than as damage.
##
## Pale rather than dark so the ping is still *visible*: the player has to see that they hit it and
## that it did nothing, which is a different message from having missed.
const SHIELDED_FLASH := Color(0.72, 0.86, 1.1, 1.0)

@onready var _health: HealthComponent = %Health
@onready var _sprite: Sprite2D = %Sprite
@onready var _hurt_flash: HurtFlash = %HurtFlash
@onready var _status: StatusEffectController = StatusEffectController.find_on(self)

var _contact_cooldown := 0.0

## The flash colour this scene was authored with, captured before anything overwrites it, so
## `set_shielded(false)` restores what the part actually had rather than a constant guessed at here.
## `HurtFlash` keeps the target sprite's resting colour the same way and for the same reason.
var _unshielded_flash := Color.WHITE


func _ready() -> void:
	add_to_group(Teams.GROUP_ENEMY)
	collision_layer = Teams.body_layer(Teams.Id.ENEMY)
	collision_mask = Teams.body_mask()
	_unshielded_flash = _hurt_flash.flash_color
	_health.configure(RECEIVER_POOL, 0.0)
	_health.damaged.connect(_on_damaged)
	HostileRegistry.register(self, Teams.Id.ENEMY, _health)


## Physics-timed, like every other thing in the game that decides real damage.
func _physics_process(delta: float) -> void:
	_step_contact_damage(delta)


## Charges the player for standing inside this body.
##
## Resolved by distance rather than by an extra Area2D, the way `Enemy._step_contact_damage` is and
## for its reason: both bodies are circles and the radii are known.
##
## Silent while inert, which is the one state a part can be in where it is not there at all — The
## Scrap King's feigned death hides the body and takes it off the collision layer, and a boss that
## is invisible and unshootable must not still be charging the player for walking through the space
## it used to occupy.
func _step_contact_damage(delta: float) -> void:
	_contact_cooldown = maxf(_contact_cooldown - delta, 0.0)
	if contact_damage <= 0.0 or _contact_cooldown > 0.0 or not visible:
		return

	var player := get_tree().get_first_node_in_group(Teams.GROUP_PLAYER) as Node2D
	if player == null:
		return
	var offset := player.global_position - global_position
	if offset.length() > contact_radius + PLAYER_RADIUS:
		return

	var health := HealthComponent.find_on(player)
	if health == null:
		return
	var direction := offset.normalized() if not offset.is_zero_approx() else Vector2.RIGHT
	if health.apply_damage(
		DamageInfo.new(contact_damage, self, direction, contact_knockback)
	):
		_contact_cooldown = contact_interval


## Whether hits on this body currently count, as far as the *player* can tell.
##
## Presentation only: what damage actually does is the controller's business, and this changes
## nothing about it. It exists so a controller that is discarding damage can say so on the body
## being shot rather than only on a bar at the top of the screen. See `Orchestrator._on_part_damaged`
## for the one fight that uses it.
func set_shielded(shielded: bool) -> void:
	_hurt_flash.flash_color = SHIELDED_FLASH if shielded else _unshielded_flash


func set_tint(tint: Color) -> void:
	if not _hurt_flash.is_flashing():
		_sprite.modulate = tint


## Takes this body out of the fight without ending it: invisible, and nothing a projectile can
## find. Used for the beat where the boss plays dead between phases.
##
## Hidden rather than freed and rebuilt, because the same body has to get up in the same place —
## a boss that came back somewhere else would read as a second enemy. The collision layer goes
## with the sprite deliberately: an invisible body that still stopped shots would have the player
## fighting something they cannot see, which is a worse trick than the one intended.
func set_inert(inert: bool) -> void:
	visible = not inert
	collision_layer = 0 if inert else Teams.body_layer(Teams.Id.ENEMY)


func get_sprite() -> Sprite2D:
	return _sprite


## How much of its own movement this part currently gets, from any status on it. One when
## unaffected, or when the scene was never given a controller.
##
## A part is where statuses land, because a part is what a projectile can hit — but a part
## does not move itself, so the boss controller reads this and scales the motion it applies.
## The alternative, having the controller carry the status, would mean a boss with two bodies
## could be frozen by hitting either one and slowed twice by hitting both.
func get_status_speed_scale() -> float:
	return _status.get_speed_scale() if _status != null else 1.0


func _on_damaged(info: DamageInfo, _remaining: float) -> void:
	_hurt_flash.flash()
	# Refilled immediately: this pool exists to catch hits, not to run out.
	_health.current = _health.max_health
	took_damage.emit(info)


## Registered with `HostileRegistry` so homing, blasts and chains can find this body without walking
## the whole enemy group to do it. The notification hook is what keeps the registry honest about
## sleep: a room deactivating its enemies delivers `PAUSED` to each of them.
func _notification(what: int) -> void:
	HostileRegistry.note(what, self)
