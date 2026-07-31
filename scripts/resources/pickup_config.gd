class_name PickupConfig
extends Resource
## What a pickup is and what collecting it does.
##
## The effect lives here rather than in the Pickup scene so adding spec section 18's
## remaining types (temporary shield, battery charge, reroll token, keycard) is a new .tres
## plus one match arm, not a new scene and a new script.

enum Kind {
	SCRAP,
	REPAIR_CELL,
}

@export var kind: Kind = Kind.SCRAP

## How much of whatever this grants. Scrap units, or integrity points.
@export var amount: float = 1.0

@export var texture: Texture2D

## Sound id passed to AudioManager on collection.
@export var pickup_sound: StringName = &"pickup"


## Applies the effect to whatever walked into it. Returns false if the pickup should stay on
## the floor — a repair cell on an undamaged robot is declined rather than wasted, which is
## what lets the player leave one behind and come back for it.
func apply_to(body: Node) -> bool:
	match kind:
		Kind.SCRAP:
			RunManager.add_scrap(int(amount))
			return true
		Kind.REPAIR_CELL:
			var health := HealthComponent.find_on(body)
			if health == null or health.is_approx_full() or not health.is_alive():
				return false
			health.heal(amount)
			return true
	return false
