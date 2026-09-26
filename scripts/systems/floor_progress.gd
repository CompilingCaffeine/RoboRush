class_name FloorProgress
extends RefCounted
## How far a run has got through the floor it is standing on: what the pause menu's save writes down,
## and what a resumed floor is rebuilt from.
##
## Everything else a floor is made of comes back from its derived seed. These are the parts the seed
## cannot rebuild, because they are what the player *did*: which rooms they fought through and saw,
## how many combat clears they have counted toward the next repair cell, what the shop still has on
## its shelves, and — in the seconds between a boss falling and its prize being claimed — which three
## items are standing in the arena. See `RunCheckpoint` for how each is stored and validated, and
## `RunCheckpoint.floor_progress` for reading one back.
##
## A value and nothing more. `FloorController` fills one from its room loop, shop and arena when the
## run is saved, and hands one to the next floor it opens when the run is resumed; the floor it opens
## after that starts from a fresh one.

## Room ids the player had cleared on this floor. Combat rooms among them are rebuilt empty.
var cleared_room_ids: Array[int] = []

## Room ids the player had been inside, for the minimap.
var visited_room_ids: Array[int] = []

## Combat clears counted on this floor, which decide when the next repair cell and item drop.
var clears := 0

## What the floor's shop was holding. Null for "nothing saved here": the shop stocks itself from the
## pool, exactly as on a first visit. See `ShopStock` for why an empty stock is a different answer.
var shop: ShopStock = null

## The boss's offer, if it was standing unclaimed; empty otherwise.
var boss_reward_ids: Array[StringName] = []
