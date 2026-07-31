extends Node
## Global signal hub for events that cross system boundaries.
##
## Deliberately tiny (spec section 26: "Keep the EventBus small and
## intentional"). A signal belongs here only when two systems that should not
## know about each other need to communicate. Anything happening inside a single
## actor's own scene tree should use a local signal on that actor instead.
##
## Milestone 1 needs only dash notifications, which lets the debug overlay react
## without holding a reference into the player's component subtree. The wider
## combat event list from spec section 14 (on_projectile_hit, on_enemy_killed,
## on_room_cleared, ...) is added here as the systems that emit them are built.

## Emitted when the player commits to a dash. `direction` is normalised.
signal player_dash_started(direction: Vector2)

## Emitted when a dash's active window ends and normal movement control resumes.
signal player_dash_ended()
