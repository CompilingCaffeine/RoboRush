@tool
class_name CableDuct
extends WallBlock
## A knee-high cable run. The robot cannot drive over it; shots go straight across.

## Level geometry that hampers *movement* without touching the fight, which is the one thing the
## room could not previously say. Every obstacle in the game until now was a `WallBlock`: it stops
## the player, it stops the enemy, and it stops the bullet, so the answer to every one of them is
## the same — go round, and while you are going round nobody can hurt anybody. A room built out of
## walls is a room where cover and pathing are the same object.
##
## A duct splits them. The player and every enemy on the floor collide with it, so the ground they
## can stand on has a shape; `Projectile`, `Enemy.has_line_of_sight` and `FirewallNode`'s beams all
## trace against `Teams.LAYER_WORLD` alone, so nothing about the shot changes at all. What the
## player gets is a room they have to *route* through while being shot at from ground they can
## already see, which is the Data Center's question — where are you standing — asked by the
## architecture instead of by a hazard.
##
## It earns its place on this floor in particular because of what is standing in these rooms. The
## Load Balancer's plate is answered by getting inside a hundred pixels and circling it, and a duct
## is the thing that decides which way round you can go. The Stale Replica walks the route the
## player walked, so a route with a duct in it is a route that comes back at them along a line they
## chose. Neither enemy needed a line of code for either of those; both fall out of the ground
## having a shape.
##
## **It is a `WallBlock` with a different layer and a different texture, and nothing else.** The
## sizing machinery — one exported `size` driving both the collision rectangle and the tiled sprite,
## so the two cannot drift — is exactly what a duct needs and already correct. What is not inherited
## is the theme: `Room._build_obstacles` hands a wall block the floor's wall sheet, and a duct is
## deliberately never given one. A duct that looked like the wall beside it would be a wall bullets
## pass through, and there is no worse thing for a piece of level geometry to look like.
##
## The collision layer is set in `cable_duct.tscn` rather than here, the same place `wall_block.tscn`
## sets its own — a body's layer is part of what the scene *is*, and a script that overwrote it in
## `_ready` would make the value in the scene file a lie.
