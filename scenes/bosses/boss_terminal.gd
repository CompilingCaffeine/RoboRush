class_name BossTerminal
extends CharacterBody2D
## One of spec section 16's four synchronization terminals.
##
## The terminals are the fight's actual puzzle. While any of them stands, damage to one
## version of the boss partially heals the other, so shooting the boss is close to
## pointless — the answer is to stop shooting the boss and go break a terminal, which is
## the moment phase two asks the player to notice something rather than to aim.
##
## A real HealthComponent, unlike BossPart's: a terminal genuinely dies.

signal destroyed(terminal: BossTerminal)

const ACTIVE_TINT := Color(1.0, 1.0, 1.0, 1.0)
const PULSE_TINT := Color(1.6, 1.3, 0.7, 1.0)
const PULSE_HZ := 1.6

@onready var _health: HealthComponent = %Health
@onready var _sprite: Sprite2D = %Sprite
@onready var _hurt_flash: HurtFlash = %HurtFlash

var _time := 0.0


func _ready() -> void:
	add_to_group(Teams.GROUP_ENEMY)
	collision_layer = Teams.body_layer(Teams.Id.ENEMY)
	collision_mask = Teams.LAYER_WORLD
	_health.damaged.connect(_on_damaged)
	_health.died.connect(_on_died)
	HostileRegistry.register(self, Teams.Id.ENEMY, _health)


func _process(delta: float) -> void:
	# A live terminal pulses, so "these are still on" is readable from across the arena
	# without a HUD element explaining it.
	_time += delta
	if _hurt_flash.is_flashing():
		return
	var pulse := 0.5 + 0.5 * sin(_time * TAU * PULSE_HZ)
	_sprite.modulate = ACTIVE_TINT.lerp(PULSE_TINT, pulse)


func configure(health: float) -> void:
	_health.configure(health, 0.0)


func get_health_component() -> HealthComponent:
	return _health


func _on_damaged(info: DamageInfo, remaining: float) -> void:
	_hurt_flash.flash()
	EventBus.enemy_damaged.emit(self, info, remaining)


func _on_died() -> void:
	destroyed.emit(self)
	EventBus.enemy_killed.emit(self, global_position)
	queue_free()


## Registered with `HostileRegistry` so homing, blasts and chains can find this body without walking
## the whole enemy group to do it. The notification hook is what keeps the registry honest about
## sleep: a room deactivating its enemies delivers `PAUSED` to each of them.
func _notification(what: int) -> void:
	HostileRegistry.note(what, self)
