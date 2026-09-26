# Changelog

What changed in Robo Rush, written for playtesters. The newest build is at the top. Developer-facing detail is in the commit history and in [ROADMAP.md](ROADMAP.md).

## Next build

**Saved runs from earlier builds cannot be resumed.** This build changes which rooms and items a seed produces, so a run saved in an earlier build no longer matches it. Choosing Continue on such a run discards it and returns you to the title screen. Your settings and records are kept. The run statistics show the content version after the seed; this build is `v6`.

### New

- **Mouse aim.** The robot aims at the mouse pointer when you move it, and holding the left mouse button fires towards it. The arrow keys and the right stick still work; whichever you used last sets the aim. Turn it off in Settings under **Mouse aim** if a trackpad keeps firing by accident. The controls card shows the mouse while the setting is on.
- **Eight new combat rooms** on the first two floors, four each. The Help Desk gains a queue, a call centre, a waiting room, and a break room. Development gains a sprint board, a code freeze, a merge window, and a stand-up. You will see far fewer repeated rooms on the floors every run starts with.

### Changed

- **Rarity now affects how often items appear.** Common and uncommon items are the usual finds from clearing a room. Rare items are more likely in treasure rooms and shops, and the boss still offers the best it has. Previously every item was equally likely, so rare items were the ones you saw most, especially on the first floor.
- **The minimap marks the shop and the boss room** once you have been inside them: the shop in blue, the boss room in red with a dark mark in the middle.

### Removed

- **The "Active item" control** (right mouse button / left trigger) is gone from the controls list. It never did anything. It will come back when active items do.

## Build of 2026-09-25

### Fixed

- **Scrap Magnet no longer pulls items into you.** It pulls scrap and repair cells only, so an item you did not want, like Tech Debt, can no longer be dragged into the robot and picked up by accident.
- **A repair cell you stand on at full integrity is now picked up** as soon as you take damage, instead of staying under the robot until you step off it and back on.
