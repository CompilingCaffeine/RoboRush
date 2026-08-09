class_name ItemPool
extends Resource
## Every item a run may offer.
##
## A resource of its own rather than an `Array[ItemConfig]` on each `FloorConfig`, because the
## pool stopped being a property of a floor the moment both floors drew from the same list.
## Two floors holding identical twenty-one-entry arrays is two places to add item twenty-two
## and one place to forget — and the symptom of forgetting is silent, since a floor with a
## short pool does not error, it just quietly stops offering things and drops repair cells
## instead.
##
## `RunManager.offered_item_ids` is still what stops an item being offered twice, and it is
## run-scoped rather than pool-scoped. That split is deliberate: the pool is what *exists*,
## the offered list is what has been *spent*, and sharing one pool between floors is only
## coherent because the spend list already spanned them.

@export var items: Array[ItemConfig] = []


func size() -> int:
	return items.size()
