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

## Emitted for every hit this part takes. The controller decides what it costs.
signal took_damage(info: DamageInfo)

## Large enough that no single hit can empty it before it is refilled, so the part never
## reaches zero and never emits `died`.
const RECEIVER_POOL := 100000.0

@onready var _health: HealthComponent = %Health
@onready var _sprite: Sprite2D = %Sprite
@onready var _hurt_flash: HurtFlash = %HurtFlash
@onready var _status: StatusEffectController = StatusEffectController.find_on(self)


func _ready() -> void:
	add_to_group(Teams.GROUP_ENEMY)
	collision_layer = Teams.body_layer(Teams.Id.ENEMY)
	collision_mask = Teams.LAYER_WORLD
	_health.configure(RECEIVER_POOL, 0.0)
	_health.damaged.connect(_on_damaged)


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
