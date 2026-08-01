class_name PlayerDrone
extends Node2D
## Spec section 12's Debug Drone: "one orbiting drone that fires when the player fires".
##
## A child of the player, so it follows for free and there is nothing to keep in step. It
## orbits by setting its own local position, which means a second drone is the same scene
## with a different phase rather than a different scene.
##
## It fires *when told*, not on its own clock. The player calls `fire` from the same signal
## that plays its own muzzle flash, which is what makes "fires when the player fires"
## literally true rather than approximately true — a drone with an independent timer would
## drift out of step within seconds and read as a second, worse weapon.
##
## Its weapon is handed the player's modifier stack and the player's shot counter, so drone
## shots are the player's shots in every way that matters: Fork Bomb splits them, and they
## advance Capacitor Leak's fifth-shot trigger.

## Distance from the robot, far enough to read as separate and close enough to stay in the
## same glance.
@export var orbit_radius: float = 20.0

## Radians per second. Slow — a fast orbit is a distraction in a bullet-dodging game.
@export var orbit_speed: float = 1.5

## Plain child paths rather than unique names. A drone is instantiated *into* the player
## at runtime, so it has no owner of its own and its `%Weapon` would be claimed in the
## player's scene scope — taking the name away from the player's own weapon.
@onready var _weapon: WeaponController = $Weapon
@onready var _sprite: Sprite2D = $Sprite

var _angle := 0.0


func _ready() -> void:
	_weapon.setup(_weapon.config, Teams.Id.PLAYER)


func _physics_process(delta: float) -> void:
	_angle = fmod(_angle + orbit_speed * delta, TAU)
	position = Vector2.RIGHT.rotated(_angle) * orbit_radius
	_weapon.step(delta)


## Places this drone evenly around the orbit. Two drones sit opposite each other rather
## than on top of one another.
func set_orbit_phase(index: int, total: int) -> void:
	_angle = TAU * float(index) / float(maxi(total, 1))


## Everything that makes a drone shot the player's shot. Called once, when the drone is
## created, and again whenever the player's items change.
func adopt(
	modifiers: ProjectileModifierStack,
	counter: ShotCounter,
	fire_rate_multiplier: float,
	attributed_to: Node,
) -> void:
	_weapon.modifiers = modifiers
	_weapon.shots = counter
	_weapon.fire_rate_multiplier = fire_rate_multiplier
	_weapon.owner = attributed_to


## Fires in the given direction if the drone's own weapon is off cooldown. Sharing the
## player's fire-rate multiplier keeps the two in lockstep, so this is nearly always true —
## the cooldown is here so a drone cannot be made to fire twice in one frame.
func fire(direction: Vector2) -> bool:
	return _weapon.try_fire(global_position, direction)


func get_weapon_controller() -> WeaponController:
	return _weapon
