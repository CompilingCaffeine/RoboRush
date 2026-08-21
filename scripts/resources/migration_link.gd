class_name MigrationLink
extends Resource
## One pair of migration pads: two patches of floor that are the same place.
##
## A *pair* rather than two entries in a flat list, and that is the whole reason this resource
## exists. The obvious authoring is `Array[Rect2i] pads`, matched two at a time — index 0 with 1,
## 2 with 3 — which is the shape `forced_enemies` already uses against `enemy_spawns` and admits to
## in its own doc. It is wrong here for a reason that does not apply there: an odd-length list is a
## pad with no partner, and a pad with no partner is a pad the player steps onto and nothing
## happens. That is not a visible failure. It is a floor tile that reads as a route and is not one,
## which is the single worst thing a mobility mechanic can ship.
##
## Bundling the two ends makes that unauthorable. There is no arrangement of this resource that
## describes half a link, so the check never has to exist and the failure it would catch cannot
## occur. Same argument `BossEncounter` makes about its four fields, reached from the other
## direction: there, parallel fields could drift apart; here, a parallel field could simply be
## missing its other half.
##
## Coordinates are in tiles, from the interior's top-left, like every other field on
## `RoomTemplate`.

## The two ends. Either one carries the player to the other — a link has no direction, and
## nothing in the game gives it one.
##
## Both are rects rather than points so a pad can be a plate the player walks onto rather than a
## tile they have to be steered at. Two by two is the authored size on this floor: wide enough to
## step on while moving, small enough that the player is never on one by accident. Nothing enforces
## that, because a room wanting a long boarding strip along a wall is a room this should not argue
## with.
@export var a := Rect2i(0, 0, 2, 2)
@export var b := Rect2i(0, 0, 2, 2)


## Whether both ends describe real ground. A link with a zero-area end is the same failure the pair
## exists to prevent, arriving by a different route — an author who typed a size of zero rather than
## one who forgot a partner.
func is_valid() -> bool:
	return a.size.x > 0 and a.size.y > 0 and b.size.x > 0 and b.size.y > 0


## Every tile either end covers. For the connectivity walk in `tests/test_floor.gd`, which needs to
## know which tiles are pads before it can treat a link as an edge, and for any check asking whether
## a pad was authored into a wall.
func tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for rect: Rect2i in [a, b]:
		for y: int in rect.size.y:
			for x: int in rect.size.x:
				out.append(rect.position + Vector2i(x, y))
	return out
