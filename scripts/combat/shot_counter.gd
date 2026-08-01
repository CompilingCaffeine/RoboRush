class_name ShotCounter
extends RefCounted
## A lifetime shot tally that more than one weapon can share.
##
## Exists for one line of spec section 13. It names exactly one *explicit* synergy — the
## one combination the design says should need a rule beyond ordinary composition:
##
##     Debug Drone + Capacitor Leak → drone shots count toward the fifth-shot chain trigger
##
## The obvious implementation is a check somewhere that asks "was this shot fired by a
## drone", which is precisely the item-specific conditional spec section 14 forbids.
## Sharing the counter instead makes the synergy fall out of composition after all: the
## player hands its drones the same object its own weapon counts into, so the fifth shot is
## the fifth shot regardless of which barrel it came from, and nothing anywhere knows that
## drones and chain lightning are related.
##
## An object rather than an int because an int would be copied. The whole point is that two
## weapons see the same number.

var count: int = 0


## Records a shot and returns its one-based index in the shared sequence.
func next() -> int:
	count += 1
	return count
