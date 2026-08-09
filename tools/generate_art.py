#!/usr/bin/env python3
"""Generate Robo Rush's pixel art as RGBA PNGs.

Pure Python 3 stdlib (zlib + struct) — NOT required to build or run the game, only to
regenerate the committed PNGs.

    python3 tools/generate_art.py .

Sprites are authored as ASCII grids and every row length is asserted, so a typo fails
loudly instead of silently producing a skewed image.

Authoring art as text is not a stopgap. It means a sprite is reviewable in a diff, a
palette change is one edit rather than thirty repaints, and the whole art set can be
regenerated from a file small enough to read — which is what makes the environment
tile sheets below possible at all, since those are composed by code rather than drawn.

Spec section 20 is the brief: chunky pixel art, bold silhouettes, limited palette,
bright effects against dark environments, 1990s arcade cabinet.
"""

import os
import struct
import sys
import zlib

PALETTE = {
    ".": (0, 0, 0, 0),             # transparent
    "o": (0x12, 0x14, 0x1C, 255),  # outline
    "d": (0x3C, 0x46, 0x54, 255),  # chassis dark
    "m": (0x6D, 0x7A, 0x8C, 255),  # chassis mid
    "l": (0xA8, 0xB6, 0xC4, 255),  # chassis light
    "e": (0x2A, 0x8C, 0x7A, 255),  # screen dim
    "E": (0x58, 0xF0, 0xC8, 255),  # screen glow
    "a": (0xF2, 0xA1, 0x3C, 255),  # amber accent
    "D": (0x1B, 0x1F, 0x2B, 255),  # floor base
    "G": (0x26, 0x2C, 0x3A, 255),  # floor grid
    "S": (0x2F, 0x37, 0x47, 255),  # floor speck
    "w": (0x4A, 0x38, 0x40, 255),  # hostile chassis dark
    "W": (0x7E, 0x60, 0x68, 255),  # hostile chassis light
    "r": (0xE0, 0x4A, 0x4A, 255),  # hostile screen
    "R": (0xFF, 0x9A, 0x8A, 255),  # hostile screen hot
    "y": (0xFF, 0xD2, 0x3C, 255),  # player shot
    "Y": (0xFF, 0xF8, 0xE0, 255),  # hot white
    "p": (0xE8, 0xE4, 0xD8, 255),  # paper
    "g": (0x2E, 0xA0, 0x62, 255),  # repair cell dim
    "b": (0x4C, 0x8C, 0xF0, 255),  # item blue
    "v": (0xA8, 0x6C, 0xF0, 255),  # item violet
    "c": (0x58, 0xF0, 0xC8, 255),  # item cyan (same as screen glow, reads as "system")
    "x": (0xE0, 0x4A, 0x4A, 255),  # item red / danger
    "V": (0xC8, 0x8C, 0xFF, 255),  # leech highlight
    # --- Development's environment. The Help Desk is grey chassis and amber accents; this
    # --- floor is the same machinery built out of cyan and violet, per the floor brief. Kept
    # --- as its own ramp rather than tinting the existing one, because the two sheets sit
    # --- beside each other in a diff and a reader should be able to see which is which.
    "n": (0x2A, 0x26, 0x40, 255),  # dev chassis dark
    "u": (0x45, 0x3F, 0x63, 255),  # dev chassis mid
    "U": (0x6B, 0x62, 0x91, 255),  # dev chassis light
    "z": (0x14, 0x15, 0x22, 255),  # dev floor base
    "Z": (0x25, 0x2A, 0x3E, 255),  # dev floor grid
    "t": (0x34, 0x3B, 0x56, 255),  # dev floor speck
}


def write_png(path: str, grid: list[str]) -> None:
    height = len(grid)
    width = len(grid[0])
    for y, row in enumerate(grid):
        assert len(row) == width, f"{path}: row {y} is {len(row)} px, expected {width}"

    raw = bytearray()
    for row in grid:
        raw.append(0)  # filter type 0 (None)
        for ch in row:
            raw.extend(PALETTE[ch])

    def chunk(tag: bytes, data: bytes) -> bytes:
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")

    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as handle:
        handle.write(png)
    print(f"wrote {path} ({width}x{height})")


# --- Player: compact maintenance robot, round head display, one screen eye,
# --- tracked base with a glowing battery cell.
PLAYER = [
    "................",
    "...oooooooooo...",
    "..ollllllllllo..",
    "..olmmmmmmmmlo..",
    "..olmddddddmlo..",
    "..olmdeeeedmlo..",
    "..olmdeEEedmlo..",
    "..olmdeeeedmlo..",
    "..olmddddddmlo..",
    "..olmmmmmmmmlo..",
    "..ollllllllllo..",
    "..oooooooooooo..",
    "..odddaaddddo...",
    "..odllddddlldo..",
    "..oooooooooooo..",
    "................",
]

# --- Visible upgrades. Spec section 20: "the player sprite should visibly change for major
# --- items where practical", and names armour plating, a cooling fan, and a glowing battery
# --- among the examples. Each is an overlay drawn on top of the 16x16 body, aligned to it,
# --- so adding one is a sprite rather than a second version of the robot.

# Reinforced Chassis: bolted plating across the robot's chest.
PLAYER_ARMOUR = [
    "................",
    "................",
    "................",
    "..ollllllllllo..",
    "..olddddddddlo..",
    "..old......dlo..",
    "................",
    "................",
    "................",
    "..old......dlo..",
    "..olddddddddlo..",
    "..ollllllllllo..",
    "................",
    "................",
    "................",
    "................",
]

# Cooling Fan: a four-bladed rotor. Rotated by the game, so it is drawn square and centred
# on its own origin rather than on the robot's.
PLAYER_FAN = [
    "..oooo..",
    ".olllo..",
    "ol.ll.lo",
    "ollEEllo",
    "ollEEllo",
    "ol.ll.lo",
    "..olllo.",
    "..oooo..",
]

# Backup Battery: a cell that sits on the robot's back and glows.
PLAYER_BATTERY = [
    ".oooo.",
    "oaaaao",
    "oaEEao",
    "oaEEao",
    "oaaaao",
    ".oooo.",
]

# --- Arm cannon, points +X. Pivots near its left edge.
CANNON = [
    "........",
    "..oooooo",
    ".olllllo",
    ".ommmmao",
    "..oooooo",
    "........",
]

# --- Ticket Bot: boxy hostile silhouette with an angry red screen and a paper
# --- ticket feeding out of a slot on top. Deliberately squarer than the player.
TICKET_BOT = [
    "................",
    ".....oppppo.....",
    ".....oppppo.....",
    "..oooooooooooo..",
    "..oWWWWWWWWWWo..",
    "..owooooooooWo..",
    "..oworrrrrrowo..",
    "..oworRRRRrowo..",
    "..oworrrrrrowo..",
    "..owooooooooWo..",
    "..owWWWWWWWWwo..",
    "..owwwwwwwwwwo..",
    "..owwwwwwwwwwo..",
    "..oooooooooooo..",
    "...oo......oo...",
    "................",
]

# --- Pop Up Drone: a hovering eye. Round where the Ticket Bot is square, so the two
# --- read apart at a glance even before either of them does anything.
POP_UP_DRONE = [
    "................",
    "................",
    ".....oooooo.....",
    "...ooWWWWWWoo...",
    "..oWWwwwwwwWWo..",
    "..oWwrrrrrrwWo..",
    ".oWwrrRRRRrrwWo.",
    ".oWwrRRYYRRrwWo.",
    ".oWwrRRYYRRrwWo.",
    ".oWwrrRRRRrrwWo.",
    "..oWwrrrrrrwWo..",
    "..oWWwwwwwwWWo..",
    "...ooWWWWWWoo...",
    ".....oooooo.....",
    "......o..o......",
    "................",
]

# --- Memory Leech: a blob with a bite. Violet, because nothing else hostile is, and it
# --- is the one enemy the player must never confuse for something they can ignore.
MEMORY_LEECH = [
    "................",
    "................",
    "....o......o....",
    "...ovo....ovo...",
    "..ovvvoooovvvo..",
    "..ovvvvvvvvvvo..",
    ".ovvvVVvvVVvvvo.",
    ".ovvVVYYVVYYvvo.",
    ".ovvvVVvvVVvvvo.",
    ".ovvvvvvvvvvvvo.",
    "..ovvYvvvvYvvo..",
    "..ovvvYYYYvvvo..",
    "...ovvvvvvvvo...",
    "....oovvvvoo....",
    "......oooo......",
    "................",
]

# --- Firewall Node: a bolted-down emitter core. Deliberately the only enemy with a wide
# --- flat base, so "this one does not move" is legible before it does anything.
FIREWALL_NODE = [
    "................",
    "................",
    "....oooooooo....",
    "...oddddddddo...",
    "..oddmmmmmmddo..",
    "..odmmaaaammdo..",
    ".oddmaaYYaammdo.",
    ".odmaaYYYYaamdo.",
    ".odmaaYYYYaamdo.",
    ".oddmaaYYaammdo.",
    "..odmmaaaammdo..",
    "..oddmmmmmmddo..",
    "...oddddddddo...",
    "..oooooooooooo..",
    "..ollllllllllo..",
    "..oooooooooooo..",
]

# --- Null Pointer: a ring around nothing. The only enemy whose middle is transparent, so
# --- the floor shows through the body of the thing that dereferences empty addresses.
# --- Cyan, and deliberately the least substantial silhouette on the floor: it never
# --- touches the player and everything it does happens somewhere else.
NULL_POINTER = [
    "................",
    ".......oo.......",
    "......occo......",
    ".....oc..co.....",
    "....oc....co....",
    "...oc......co...",
    "..oc........co..",
    ".oc..........co.",
    ".oe..........eo.",
    "..oe........eo..",
    "...oe......eo...",
    "....oe....eo....",
    ".....oe..eo.....",
    "......oeeo......",
    ".......oo.......",
    "................",
]

# --- Deadlock: four corner jaws clamped around a red core. The prongs are the silhouette
# --- — nothing else on the floor has an outline that reaches outward at the corners — and
# --- they read as "this thing holds on", which is the entire fight.
DEADLOCK = [
    "................",
    "..oooo....oooo..",
    "..oddo....oddo..",
    "..odmoooooomdo..",
    "..odmmmmmmmmdo..",
    ".oodmmrrrrmmdoo.",
    ".odmmrrRRrrmmdo.",
    ".odmrrRYYRrrmdo.",
    ".odmrrRYYRrrmdo.",
    ".odmmrrRRrrmmdo.",
    ".oodmmrrrrmmdoo.",
    "..odmmmmmmmmdo..",
    "..odmoooooomdo..",
    "..oddo....oddo..",
    "..oooo....oooo..",
    "................",
]

# --- Recursion: squares nested inside squares, with a visibly different smaller thing at
# --- the centre. The silhouette is the mechanic — a player who has never seen one split
# --- can still see there is something inside it — which is the cheapest possible way to
# --- warn them that killing it is not the end of the transaction.
RECURSION = [
    "................",
    ".oooooooooooooo.",
    ".ovvvvvvvvvvvvo.",
    ".ovoooooooooovo.",
    ".ovoVVVVVVVVovo.",
    ".ovoVooooooVovo.",
    ".ovoVobbbboVovo.",
    ".ovoVobYYboVovo.",
    ".ovoVobYYboVovo.",
    ".ovoVobbbboVovo.",
    ".ovoVooooooVovo.",
    ".ovoVVVVVVVVovo.",
    ".ovoooooooooovo.",
    ".ovvvvvvvvvvvvo.",
    ".oooooooooooooo.",
    "................",
]

# --- Pop Up Drone's spread shot. Smaller and faster-reading than a ticket.
DRONE_SHOT = [
    "..oo..",
    ".oRRo.",
    "oRYYRo",
    "oRYYRo",
    ".oRRo.",
    "..oo..",
]

# --- Debug Drone: a small companion core. Reads as the player's kit, not as a threat:
# --- same chassis greys and screen green as the robot, at half the size.
PLAYER_DRONE = [
    "..oooo..",
    ".ollllo.",
    "olmEEmlo",
    "olmEEmlo",
    "olmmmmlo",
    ".ollllo.",
    "..oooo..",
    "........",
]

# --- Shop stand: a lit pedestal with a display plate. Amber like every other "you may
# --- act here" cue in the game.
SHOP_STAND = [
    "................",
    "................",
    "................",
    "....oooooooo....",
    "...oaaaaaaaao...",
    "...oaddddddao...",
    "...oaaaaaaaao...",
    "....oooooooo....",
    ".....oddddo.....",
    ".....odmmdo.....",
    ".....odmmdo.....",
    "....oddmmddo....",
    "...ollllllllo...",
    "...oooooooooo...",
    "................",
    "................",
]

def merge_conflict_sprite() -> list[str]:
    """The Merge Conflict, 32x32 — four times the area of an enemy.

    It was 24x24 and read as a slightly larger Ticket Bot, which is the wrong first
    impression for the only boss in the game. Size alone does not fix that; the silhouette
    has to be different in kind, so this is the one thing on screen that is wider than it
    is tall, stands on feet, and has something sticking out of the top.

    Built in code rather than typed as a grid because the shape that matters is the *tear*:
    a jagged seam stepping down the middle, splitting the machine into two screens that no
    longer line up. Hand-aligning a zigzag across fourteen rows of ASCII is exactly the kind
    of thing that ends up one pixel out.

    Drawn in neutral greys, which is not a style choice. The fight tints each body — red for
    one version, green for the other (see MergeConflict.RED and .GREEN) — and modulate
    multiplies, so a red tint over a baked-in green screen produces mud. The two versions
    disagreeing is expressed by the *pair* in phase two, and by the tear in phase one; the
    sprite stays a machine the tint can colour.
    """
    size = 32
    grid = [["."] * size for _ in range(size)]

    def fill(x0: int, y0: int, x1: int, y1: int, ch: str) -> None:
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                grid[y][x] = ch

    def outline(x0: int, y0: int, x1: int, y1: int) -> None:
        for x in range(x0, x1 + 1):
            grid[y0][x] = "o"
            grid[y1][x] = "o"
        for y in range(y0, y1 + 1):
            grid[y][x0] = "o"
            grid[y][x1] = "o"

    # Antennae: the only parts that break the rectangle, so the silhouette has a top.
    for x in (7, 24):
        fill(x, 1, x, 4, "m")
        grid[0][x] = "a"
        grid[1][x - 1] = "o"
        grid[1][x + 1] = "o"

    # Chassis.
    fill(2, 4, 29, 27, "d")
    outline(2, 4, 29, 27)

    # Lit top bar with rivets — reads as a rack unit rather than a box.
    fill(3, 5, 28, 7, "m")
    for x in (6, 12, 19, 25):
        grid[6][x] = "o"

    # The two screens. Left is the red version, right is the green one.
    fill(4, 9, 15, 22, "m")
    fill(16, 9, 27, 22, "m")
    outline(3, 8, 28, 23)

    # One angry eye per half, each a bright block with a hot centre.
    fill(6, 12, 12, 17, "l")
    fill(8, 14, 10, 16, "Y")
    fill(19, 12, 25, 17, "l")
    fill(21, 14, 23, 16, "Y")

    # The tear. Steps by one pixel every other row so it reads as torn rather than sawn,
    # and is drawn last so it cuts through both screens and both eyes.
    for y in range(9, 23):
        seam = 15 + (1 if (y // 2) % 2 == 0 else -1)
        grid[y][seam] = "o"
        grid[y][seam + 1] = "Y"
        grid[y][seam - 1] = "o"
        grid[y][seam + 2] = "o"

    # Exhaust vents along the bottom of the chassis.
    for y in (25, 26):
        for x in range(5, 27, 3):
            grid[y][x] = "o"
            grid[y][x + 1] = "o"

    # Feet, so it stands on the floor instead of hovering like everything else.
    for x0 in (4, 21):
        fill(x0, 28, x0 + 6, 29, "m")
        outline(x0, 28, x0 + 6, 29)

    return ["".join(row) for row in grid]


MERGE_CONFLICT = merge_conflict_sprite()


def runtime_error_sprite() -> list[str]:
    """Runtime Error, 20x20 — deliberately the smallest body in the game that is a boss.

    The Scrap King is 32x32, wider than tall, stands on feet and has antennae: a *machine*,
    built out of salvage. This one has to read as the opposite at a glance, because it is the
    opposite fight — not a thing the megacorp assembled but a process that got loose. So it is
    a diamond, which nothing else on screen is; it hovers, with no feet and no top; and it is
    small enough that hitting it is a skill rather than a formality.

    Small is also the mechanic. Its hitbox is a 7-pixel radius against the King's 14, so the
    body is a quarter of the area to hit, and the sprite has to be honest about that or the
    player is owed shots they think landed (the lesson boss_part.tscn's own comment records).
    The concentric bands are what keep it honest: the solid core is the hitbox, and everything
    outside it is either the thin diamond tip or a detached shard.

    Built in code rather than typed as a grid for the same reason the King is — the shape that
    matters is arithmetic. Here it is the displaced rows: two bands of the diamond shifted
    sideways, so the silhouette does not line up with itself. A vertical seam is what a merge
    conflict looks like; a horizontal slip is what a corrupted process looks like, and the two
    bosses must not share a tell.

    Neutral greys, and for exactly the King's reason: `RuntimeError` tints the body violet and
    flashes it amber and red through `modulate`, which multiplies. Any colour baked in here
    would fight the warning language the whole fight is built on.
    """
    size = 20
    grid = [["."] * size for _ in range(size)]
    cx = cy = 10
    radius = 7

    def diamond(limit: int, ch: str) -> None:
        for y in range(size):
            for x in range(size):
                if abs(x - cx) + abs(y - cy) <= limit:
                    grid[y][x] = ch

    # Concentric bands, drawn largest first. The outermost is the outline and each step inward
    # is brighter, so the core reads as the thing that is actually there.
    #
    # Weighted bright deliberately: `RuntimeError.BODY_TINT` is a violet whose red and green
    # channels are below one, and `modulate` multiplies — so whatever is drawn here reaches the
    # screen darker than it looks in a paint program. A body built from the dark end of the
    # palette arrived as a smudge on a dark floor.
    diamond(radius, "o")
    diamond(radius - 1, "d")
    diamond(radius - 2, "m")
    diamond(radius - 4, "l")

    # The eye: a small cross at the centre, the only part of the sprite that is not a band.
    # Everything the player aims at is this, so it is the brightest thing on the body and
    # sits exactly where the hitbox is centred.
    for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
        grid[cy + dy][cx + dx] = "Y"

    # The slip. Two bands shoved sideways in opposite directions, which breaks the diamond's
    # symmetry without breaking its silhouette — it still reads as one shape, wrongly.
    for row, shift in ((cy - 3, 2), (cy + 3, -2)):
        moved = ["."] * size
        for x in range(size):
            target = x + shift
            if 0 <= target < size:
                moved[target] = grid[row][x]
        grid[row] = moved

    # Four shards, thrown off the flat faces of the diamond and clearly detached from it.
    # Detached is the point: they enlarge the silhouette without enlarging what can be hit,
    # so the boss looks bigger than its hitbox in the one way that is honest — the parts
    # sticking out are visibly not the body.
    for dx, dy in ((-5, -5), (5, -5), (-5, 5), (5, 5)):
        x0, y0 = cx + dx, cy + dy
        grid[y0][x0] = "m"
        grid[y0 + (1 if dy > 0 else -1)][x0 + (1 if dx > 0 else -1)] = "o"

    return ["".join(row) for row in grid]


RUNTIME_ERROR = runtime_error_sprite()

# --- Synchronization terminal: a squat server box with a status light.
BOSS_TERMINAL = [
    "................",
    "................",
    "..oooooooooooo..",
    "..odddddddddo...",
    "..odmmmmmmmdo...",
    "..odmEEEEEmdo...",
    "..odmEaaaEmdo...",
    "..odmEEEEEmdo...",
    "..odmmmmmmmdo...",
    "..odddddddddo...",
    "..ollllllllllo..",
    "..odddddddddo...",
    "..ollllllllllo..",
    "..oooooooooooo..",
    "...oo......oo...",
    "................",
]

# --- Boss projectiles: the two incompatible versions.
BOSS_RED = [
    "..oooo..",
    ".orrrro.",
    "orRRRRro",
    "orRYYRro",
    "orRYYRro",
    "orRRRRro",
    ".orrrro.",
    "..oooo..",
]

BOSS_GREEN = [
    "..oooo..",
    ".oggggo.",
    "ogEEEEgo",
    "ogEYYEgo",
    "ogEYYEgo",
    "ogEEEEgo",
    ".oggggo.",
    "..oooo..",
]

# --- Player projectile: hot rivet.
RIVET = [
    ".oooo.",
    "oyYYYo",
    "oyYYYo",
    ".oooo.",
]

# --- Enemy projectile: slower, larger, unmistakably hostile.
TICKET_SHOT = [
    "..oo..",
    ".orro.",
    "orRRro",
    "orRRro",
    ".orro.",
    "..oo..",
]

# --- Muzzle flash diamond, drawn additively over the cannon.
MUZZLE_FLASH = [
    "....y...",
    "..yYYy..",
    ".yYYYYy.",
    "yYYYYYYy",
    "yYYYYYYy",
    ".yYYYYy.",
    "..yYYy..",
    "....y...",
]

# --- Particle spark. Near-white so particle colour ramps tint it cleanly.
SPARK = [
    "YY",
    "YY",
]


# --- Scrap: a hex nut. Small and bright so a floor full of them still reads.
SCRAP = [
    "..oooo..",
    ".ollllo.",
    "ollmmllo",
    "olmoomlo",
    "olmoomlo",
    "ollmmllo",
    ".ollllo.",
    "..oooo..",
]

# --- Repair cell: a green power cell. Deliberately the only green pickup, so
# --- "green means health" needs no explanation.
REPAIR_CELL = [
    "..oooo..",
    ".oooooo.",
    "oggEEggo",
    "ogEEEEgo",
    "ogEEEEgo",
    "oggEEggo",
    ".oooooo.",
    "..oooo..",
]


# --- Item icons. 8x8, one recognisable silhouette each, drawn at the size they are
# --- actually shown: the HUD item bar renders them 1:1 with no scaling, so anything that
# --- needs more than eight pixels to read would not read in the game either.
ITEM_ICONS = {
    # Ricochet Driver: a shot rebounding off a wall.
    "ricochet_driver": [
        "oo....a.",
        "om...a..",
        "om..a...",
        "oma.....",
        "oma.....",
        "om..a...",
        "om...a..",
        "oo....a.",
    ],
    # Fork Bomb: one shot becoming two.
    "fork_bomb": [
        "......aa",
        ".....a..",
        "....a...",
        "aaaa....",
        "aaaa....",
        "....a...",
        ".....a..",
        "......aa",
    ],
    # Magnetic Guidance: a horseshoe magnet, poles down.
    "magnetic_guidance": [
        "..bbbb..",
        ".b....b.",
        "b......b",
        "b......b",
        "b......b",
        "b......b",
        "x......x",
        "x......x",
    ],
    # Return Protocol: two arrows pointing opposite ways.
    "return_protocol": [
        "........",
        "..c.....",
        ".cccccc.",
        "..c.....",
        ".....c..",
        ".cccccc.",
        ".....c..",
        "........",
    ],
    # Capacitor Leak: a discharge bolt.
    "capacitor_leak": [
        "....yy..",
        "...yy...",
        "..yy....",
        ".yyyyy..",
        "...yy...",
        "..yy....",
        ".yy.....",
        "........",
    ],
    # Volatile Kernel: a fireball.
    "volatile_kernel": [
        "..x..x..",
        "x.xaax.x",
        ".xaYYax.",
        "xaYYYYax",
        "xaYYYYax",
        ".xaYYax.",
        "x.xaax.x",
        "..x..x..",
    ],
    # Cooling Fan: a bladed wheel.
    "cooling_fan": [
        "..oooo..",
        ".occcco.",
        "occ..cco",
        "oc.dd.co",
        "oc.dd.co",
        "occ..cco",
        ".occcco.",
        "..oooo..",
    ],
    # Reinforced Chassis: armour plate.
    "reinforced_chassis": [
        "oggggggo",
        "gEEEEEEg",
        "gEggggEg",
        "gEggggEg",
        ".gEggEg.",
        "..gEEg..",
        "...gg...",
        "........",
    ],
    # Backup Battery: a cell with terminals.
    "backup_battery": [
        "..o..o..",
        "oooooooo",
        "oaaaaaao",
        "oaEEEEao",
        "oaEEEEao",
        "oaaaaaao",
        "oooooooo",
        "........",
    ],
    # Scrap Magnet: the horseshoe again but in item colours, poles inward.
    "scrap_magnet": [
        "..cccc..",
        ".c....c.",
        "c......c",
        "c..oo..c",
        "c.o..o.c",
        "c......c",
        "a......a",
        "a......a",
    ],
    # Debug Drone: a small core with an orbit ring around it.
    "debug_drone": [
        "..cccc..",
        ".c.oo.c.",
        "c.oEEo.c",
        "c.oEEo.c",
        "c.oooo.c",
        ".c....c.",
        "..cccc..",
        "...cc...",
    ],
    # Unsafe Overclock: a hazard triangle. The only red icon that is not an explosion,
    # because corrupted firmware should look like a warning label.
    "unsafe_overclock": [
        "...xx...",
        "..xxxx..",
        "..xYYx..",
        ".xxYYxx.",
        ".xxYYxx.",
        "xxx..xxx",
        "xxxYYxxx",
        "xxxxxxxx",
    ],
    # --- Development's six. ---
    # Memory Spike: a nail driven through a stack of plates. Pierce, drawn as the thing
    # being pierced rather than as an arrow, so it does not read as another shot icon.
    "memory_spike": [
        "...YY...",
        "...bb...",
        "mmmbbmmm",
        "...bb...",
        "mmmbbmmm",
        "...bb...",
        "mmmbbmmm",
        "...bb...",
    ],
    # Core Dump: a shot bursting on contact. The burst is offset to the right so it reads
    # as "on impact" rather than as Volatile Kernel's symmetric fireball.
    "core_dump": [
        "......x.",
        "y....xax",
        "yy..xaYa",
        "yyy.xaYY",
        "yyy.xaYY",
        "yy..xaYa",
        "y....xax",
        "......x.",
    ],
    # Cold Cache: a snowflake over a frozen block. Cyan, and the only icon built from
    # single pixels — frost should look brittle next to Hot Reload's solid flame.
    "cold_cache": [
        "..b.b...",
        "...b....",
        "b.bbb.b.",
        ".bbbbb..",
        "b.bbb.b.",
        "...b....",
        "..b.b...",
        "cccccccc",
    ],
    # Hot Reload: a flame over a reload arrow. Reads as the fifth-shot item it is — the
    # arrow is the cycle, the flame is what arrives at the end of it.
    "hot_reload": [
        "....a...",
        "...aY...",
        "..aYYa..",
        ".aYYYYa.",
        ".aYYYYa.",
        "..aaaa..",
        ".x....x.",
        "..xxxx..",
    ],
    # Breakpoint: the debugger's dot on a line of execution, with the line stopped dead at
    # it. The one icon that is a *symbol* rather than an object, because the item is too.
    "breakpoint": [
        "........",
        "..xxxx..",
        ".xxRRxx.",
        "cxxRRxxc",
        "cxxRRxxc",
        ".xxRRxx.",
        "..xxxx..",
        "cc....cc",
    ],
    # Stack Overflow: a stack grown past its frame. Corrupted, so it wears Unsafe
    # Overclock's red — the plates are spilling out of the container that should hold them.
    "stack_overflow": [
        "vvvvvvvv",
        "v......v",
        "vvvvvvvv",
        ".vvvvvv.",
        "..vvvv..",
        "xxxxxxxx",
        ".xxxxxx.",
        "..xxxx..",
    ],
    # --- The three that are purely a cost. All red-on-red with no bright core, so the row
    # --- of them in the item bar reads as a warning label rather than as equipment. This is
    # --- the only signal the player gets: the pickup banner carries a name and no
    # --- description, so an icon that looked like a reward would be a lie.
    # Blocking I/O: a pause symbol jammed into a barrier.
    "blocking_io": [
        "xxxxxxxx",
        "x......x",
        "x.RR.R.x",
        "x.RR.R.x",
        "x.RR.R.x",
        "x.RR.R.x",
        "x......x",
        "xxxxxxxx",
    ],
    # Tech Debt: a bar chart that only goes one way, with the ground falling out under it.
    "tech_debt": [
        ".......x",
        ".....x.x",
        ".....x.x",
        "...x.x.x",
        "...x.x.x",
        ".x.x.x.x",
        ".x.x.x.x",
        "wwwwwwww",
    ],
    # Legacy Runtime: an hourglass, nearly all of it still in the top bulb.
    "legacy_runtime": [
        "xxxxxxxx",
        ".xwwwwx.",
        "..xwwx..",
        "...xx...",
        "...xx...",
        "..x..x..",
        ".xw..wx.",
        "xxxxxxxx",
    ],
}


def door_tile() -> list[str]:
    """Amber hazard barrier, banded so a 48x32 door reads as one object."""
    rows = ["o" * 16]
    for index in range(14):
        band = "a" if (index // 3) % 2 == 0 else "d"
        rows.append("o" + band * 14 + "o")
    rows.append("o" * 16)
    return rows


# --- Environment tile sheets -------------------------------------------------------
#
# Walls and floors are drawn by Godot as one sprite with texture_repeat on, so the whole
# environment is a single 16x16 image repeated across the screen. That is what made
# milestone 5's rooms read as graph paper: the eye finds a 16-pixel period instantly and
# stops seeing a room at all.
#
# The fix needs no engine change. A 64x64 sheet made of sixteen *different* 16x16 panels
# tiles exactly the same way, but the period is 64 pixels and four times as much has to
# repeat before the pattern is visible. Spec section 20 asks for industrial machinery and
# old operating system windows; that is the vocabulary the panels are drawn from.

TILE = 16
SHEET_TILES = 4
SHEET = TILE * SHEET_TILES


def _blank_panel(fill: str) -> list[list[str]]:
    return [[fill] * TILE for _ in range(TILE)]


def _wall_panel_base() -> list[list[str]]:
    """The bevel every wall panel shares: lit top edge, shaded bottom, dark outline."""
    grid = _blank_panel("m")
    for x in range(TILE):
        grid[0][x] = "o"
        grid[1][x] = "l"
        grid[TILE - 2][x] = "d"
        grid[TILE - 1][x] = "o"
    for y in range(TILE):
        grid[y][0] = "o"
        grid[y][TILE - 1] = "o"
    return grid


def wall_panel(kind: str) -> list[list[str]]:
    """One 16x16 wall panel. Four kinds, so a wall is machinery rather than graph paper."""
    grid = _wall_panel_base()

    if kind == "rivets":
        for y in (4, 11):
            for x in (4, 11):
                grid[y][x] = "l"
                grid[y + 1][x] = "d"
    elif kind == "vent":
        # Horizontal louvres. The most recognisable "this is a machine" marking there is.
        for y in range(4, 12, 2):
            for x in range(3, 13):
                grid[y][x] = "d"
                grid[y + 1][x] = "D"
    elif kind == "conduit":
        # A cable run down the panel, clipped at both ends.
        for y in range(2, TILE - 2):
            grid[y][7] = "d"
            grid[y][8] = "D"
            grid[y][9] = "d"
        for y in (4, 10):
            for x in range(6, 11):
                grid[y][x] = "l"
    elif kind == "screen":
        # A dead terminal set into the wall, with one pixel still alive in it. Spec
        # section 20's "old operating system windows", at the smallest possible scale.
        for y in range(4, 11):
            for x in range(4, 12):
                grid[y][x] = "D"
        for x in range(4, 12):
            grid[3][x] = "o"
            grid[11][x] = "o"
        for y in range(3, 12):
            grid[y][3] = "o"
            grid[y][12] = "o"
        grid[6][6] = "e"
        grid[6][7] = "e"
        grid[8][6] = "e"

    return grid


def floor_panel(kind: str) -> list[list[str]]:
    """One 16x16 floor panel. Dark, because spec section 20 wants bright effects against
    dark environments — the floor's job is to be legible and then get out of the way."""
    grid = _blank_panel("D")
    for x in range(TILE):
        grid[0][x] = "G"
    for y in range(TILE):
        grid[y][0] = "G"

    if kind == "scuffed":
        for x, y in ((5, 7), (6, 7), (11, 3), (4, 12), (12, 10)):
            grid[y][x] = "S"
    elif kind == "grate":
        for y in range(4, 12):
            for x in range(4, 12):
                grid[y][x] = "G" if (y % 2 == 0) else "S"
        for x in range(4, 12):
            grid[3][x] = "S"
            grid[12][x] = "S"
    elif kind == "seam":
        # A cable seam crossing the tile, so long runs of floor have a direction.
        for x in range(1, TILE):
            grid[9][x] = "G"
            grid[10][x] = "S"

    return grid


## Which panel goes where. Laid out by hand rather than shuffled so that no two adjacent
## cells match — including across the seam where the sheet wraps, which is the join the eye
## would otherwise find first.
WALL_LAYOUT = [
    ["rivets", "vent", "plain", "conduit"],
    ["screen", "plain", "rivets", "plain"],
    ["plain", "conduit", "plain", "vent"],
    ["rivets", "plain", "screen", "plain"],
]

FLOOR_LAYOUT = [
    ["plain", "scuffed", "plain", "plain"],
    ["plain", "plain", "grate", "plain"],
    ["seam", "plain", "plain", "scuffed"],
    ["plain", "plain", "plain", "grate"],
]


def compose_sheet(layout: list[list[str]], panel_for) -> list[str]:
    """Stitches a 4x4 arrangement of 16x16 panels into one 64x64 grid."""
    rows = [[""] * SHEET for _ in range(SHEET)]
    for cell_y, row in enumerate(layout):
        for cell_x, kind in enumerate(row):
            panel = panel_for(kind)
            for y in range(TILE):
                for x in range(TILE):
                    rows[cell_y * TILE + y][cell_x * TILE + x] = panel[y][x]
    return ["".join(row) for row in rows]


def wall_tile() -> list[str]:
    return compose_sheet(WALL_LAYOUT, wall_panel)


def floor_tile() -> list[str]:
    return compose_sheet(FLOOR_LAYOUT, floor_panel)


# --- Development's environment ------------------------------------------------------
#
# The floor brief asks for "cyan and violet machinery, amber warnings, red execution errors,
# broken IDE windows, temporary build scaffolds". Same 64x64 sheet construction as the Help
# Desk's, same four-tile repeat period, different vocabulary — this is a lab someone is still
# working in rather than a corridor someone gave up on.
#
# The two floors are told apart by *shape* as much as by colour. The Help Desk's panels are
# closed and finished: rivets, louvres, sealed conduit. Development's are open and unfinished:
# a window with its own title bar, a diagonal brace holding something up, a rack with its guts
# showing. A player who is colour-blind should still know which floor they are on.


def _dev_wall_base() -> list[list[str]]:
    """Development's bevel. Same lit-top/shaded-bottom read as the Help Desk's so walls still
    look like walls, in the violet ramp so they do not look like the same walls."""
    grid = _blank_panel("u")
    for x in range(TILE):
        grid[0][x] = "o"
        grid[1][x] = "U"
        grid[TILE - 2][x] = "n"
        grid[TILE - 1][x] = "o"
    for y in range(TILE):
        grid[y][0] = "o"
        grid[y][TILE - 1] = "o"
    return grid


def dev_wall_panel(kind: str) -> list[list[str]]:
    """One 16x16 Development wall panel."""
    grid = _dev_wall_base()

    if kind == "window":
        # A broken IDE window: title bar, close box, three lines of text, and one line that
        # has become a red error. The single most on-brief marking on the floor.
        for y in range(3, 13):
            for x in range(2, 14):
                grid[y][x] = "z"
        for x in range(2, 14):
            grid[3][x] = "n"
            grid[12][x] = "o"
        for y in range(3, 13):
            grid[y][2] = "o"
            grid[y][13] = "o"
        grid[3][12] = "x"  # close box, always red
        for x in range(4, 11):
            grid[6][x] = "c"
        for x in range(4, 9):
            grid[8][x] = "c"
        for x in range(4, 12):
            grid[10][x] = "x"  # the line that failed
    elif kind == "scaffold":
        # Temporary bracing: a diagonal strut with bolt plates at both ends. Reads as
        # "this was put up in a hurry and never taken down".
        for index in range(2, TILE - 2):
            grid[index][index] = "U"
            grid[index][TILE - 1 - index] = "n"
        for y, x in ((3, 3), (3, 12), (12, 3), (12, 12)):
            grid[y][x] = "a"
    elif kind == "rack":
        # A server rack with its front off: two columns of drive bays, some lit.
        for y in range(3, 13):
            for x in (4, 5, 6, 9, 10, 11):
                grid[y][x] = "n"
        for y in range(4, 12, 3):
            grid[y][4] = "c"
            grid[y][9] = "v"
            grid[y + 1][6] = "v"
    elif kind == "pipes":
        # Two cable runs crossing, one live. Violet on violet, so it is texture rather than a
        # focal point — most of a wall has to be quiet.
        for x in range(2, TILE - 2):
            grid[5][x] = "n"
            grid[6][x] = "U"
        for y in range(2, TILE - 2):
            grid[y][10] = "n"
            grid[y][11] = "U"

    return grid


def dev_floor_panel(kind: str) -> list[list[str]]:
    """One 16x16 Development floor panel. Darker than the Help Desk's, because this floor
    throws amber and red warning rectangles across it constantly and every one of them has to
    read instantly against whatever it lands on."""
    grid = _blank_panel("z")
    for x in range(TILE):
        grid[0][x] = "Z"
    for y in range(TILE):
        grid[y][0] = "Z"

    if kind == "cable":
        # A cable run under a floor panel, one strand lit. Development's answer to the Help
        # Desk's "seam" — same job, visibly powered.
        for x in range(1, TILE):
            grid[8][x] = "t"
            grid[9][x] = "Z"
        for x in range(3, TILE, 6):
            grid[8][x] = "e"
    elif kind == "hatch":
        # A lifted access hatch, corners bolted.
        for y in range(3, 13):
            for x in range(3, 13):
                grid[y][x] = "Z"
        for y in range(5, 11):
            for x in range(5, 11):
                grid[y][x] = "t"
        for y, x in ((4, 4), (4, 11), (11, 4), (11, 11)):
            grid[y][x] = "t"
    elif kind == "tape":
        # Hazard tape across a corner: work in progress, do not stand here.
        #
        # Drawn in the floor's own dim ramp and *not* in amber, which was the first attempt
        # and was a real bug rather than a taste call. Amber on this floor means "a compile
        # lane is about to execute here" — from the Compiler, from Runtime Error, from the
        # Null Pointer — and the whole floor is built on that warning meaning one thing.
        # Painting permanent amber stripes across the ground the lanes are drawn on would
        # teach the player to ignore the colour their survival depends on reading.
        for index in range(2, 9):
            grid[index][index] = "t"
            grid[index + 1][index] = "Z"
    elif kind == "chips":
        for x, y in ((4, 6), (10, 4), (6, 11), (12, 9), (9, 13)):
            grid[y][x] = "t"

    return grid


## Deliberately not the Help Desk's layout with different panel names. That sheet is mostly
## "plain"; this one is busier, because a lab in use should look inhabited — but the two most
## eye-catching panels, `window` and `rack`, are still kept off adjacent cells so the sheet
## does not read as a repeating pattern.
DEV_WALL_LAYOUT = [
    ["window", "plain", "pipes", "plain"],
    ["plain", "rack", "plain", "scaffold"],
    ["pipes", "plain", "window", "plain"],
    ["plain", "scaffold", "plain", "rack"],
]

DEV_FLOOR_LAYOUT = [
    ["plain", "cable", "plain", "chips"],
    ["hatch", "plain", "plain", "plain"],
    ["plain", "plain", "tape", "plain"],
    ["chips", "plain", "plain", "hatch"],
]


def dev_wall_tile() -> list[str]:
    return compose_sheet(DEV_WALL_LAYOUT, dev_wall_panel)


def dev_floor_tile() -> list[str]:
    return compose_sheet(DEV_FLOOR_LAYOUT, dev_floor_panel)



# --- Application icon -------------------------------------------------------------
#
# The project shipped without one, so the window, the dock, and every exported build used
# Godot's default. It is also what broke the macOS export: that exporter needs an icon to
# build an .icns from and reports its absence only as "configuration errors".
#
# Drawn at 32x32 and scaled up by whole numbers, because the icon of a pixel-art game should
# look like the game rather than like a smooth logo bolted onto it.

ICON_SOURCE = [
    "................................",
    "................................",
    "...oooooooooooooooooooooooooo...",
    "..ollllllllllllllllllllllllllo..",
    "..olmmmmmmmmmmmmmmmmmmmmmmmmlo..",
    "..olmddddddddddddddddddddddmlo..",
    "..olmdoooooooooooooooooooodmlo..",
    "..olmdoeeeeeeeeeeeeeeeeeeodmlo..",
    "..olmdoeeEEEEEEEEEEEEEEeeodmlo..",
    "..olmdoeeEEEEEEEEEEEEEEeeodmlo..",
    "..olmdoeeEEoooEEEEoooEEeeodmlo..",
    "..olmdoeeEEoooEEEEoooEEeeodmlo..",
    "..olmdoeeEEoooEEEEoooEEeeodmlo..",
    "..olmdoeeEEEEEEEEEEEEEEeeodmlo..",
    "..olmdoeeEEEEEEEEEEEEEEeeodmlo..",
    "..olmdoeeEEEEEEEEEEEEEEeeodmlo..",
    "..olmdoeeEEEEoooooooEEEEeodmlo..",
    "..olmdoeeEEEEoooooooEEEEeodmlo..",
    "..olmdoeeEEEEEEEEEEEEEEeeodmlo..",
    "..olmdoeeeeeeeeeeeeeeeeeeodmlo..",
    "..olmdoooooooooooooooooooodmlo..",
    "..olmddddddddddddddddddddddmlo..",
    "..olmmmmmmmmmmmmmmmmmmmmmmmmlo..",
    "..ollllllllllllllllllllllllllo..",
    "..oooooooooooooooooooooooooooo..",
    "..odddaaaaddddddddddddaaaaddo...",
    "..odllddddddddddddddddddddlldo..",
    "..odllddddddddddddddddddddlldo..",
    "..oooooooooooooooooooooooooooo..",
    "................................",
    "................................",
    "................................",
]

## Whole-number upscale, so every source pixel stays a hard square.
ICON_SCALE = 8


def scale_grid(grid: list[str], factor: int) -> list[str]:
    scaled: list[str] = []
    for row in grid:
        wide = "".join(ch * factor for ch in row)
        for _ in range(factor):
            scaled.append(wide)
    return scaled


def icon() -> list[str]:
    return scale_grid(ICON_SOURCE, ICON_SCALE)


SPRITES = {
    "art/characters/player.png": PLAYER,
    "art/characters/player_cannon.png": CANNON,
    "art/characters/player_drone.png": PLAYER_DRONE,
    "art/characters/player_armour.png": PLAYER_ARMOUR,
    "art/characters/player_fan.png": PLAYER_FAN,
    "art/characters/player_battery.png": PLAYER_BATTERY,
    "art/enemies/ticket_bot.png": TICKET_BOT,
    "art/enemies/pop_up_drone.png": POP_UP_DRONE,
    "art/enemies/memory_leech.png": MEMORY_LEECH,
    "art/enemies/firewall_node.png": FIREWALL_NODE,
    "art/enemies/null_pointer.png": NULL_POINTER,
    "art/enemies/deadlock.png": DEADLOCK,
    "art/enemies/recursion.png": RECURSION,
    "art/effects/projectile_drone.png": DRONE_SHOT,
    "art/environments/shop_stand.png": SHOP_STAND,
    "art/bosses/merge_conflict.png": MERGE_CONFLICT,
    "art/bosses/runtime_error.png": RUNTIME_ERROR,
    "art/bosses/boss_terminal.png": BOSS_TERMINAL,
    "art/effects/projectile_boss_red.png": BOSS_RED,
    "art/effects/projectile_boss_green.png": BOSS_GREEN,
    "art/effects/projectile_rivet.png": RIVET,
    "art/effects/projectile_ticket.png": TICKET_SHOT,
    "art/effects/muzzle_flash.png": MUZZLE_FLASH,
    "art/effects/spark.png": SPARK,
    "art/ui/scrap.png": SCRAP,
    "art/ui/repair_cell.png": REPAIR_CELL,
}


def main() -> int:
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    for relative, grid in SPRITES.items():
        write_png(os.path.join(root, relative), grid)
    for item_id, grid in ITEM_ICONS.items():
        write_png(os.path.join(root, f"art/items/{item_id}.png"), grid)
    write_png(os.path.join(root, "art/ui/icon.png"), icon())
    write_png(os.path.join(root, "art/environments/wall.png"), wall_tile())
    write_png(os.path.join(root, "art/environments/door.png"), door_tile())
    write_png(os.path.join(root, "art/environments/floor.png"), floor_tile())
    write_png(os.path.join(root, "art/environments/dev_wall.png"), dev_wall_tile())
    write_png(os.path.join(root, "art/environments/dev_floor.png"), dev_floor_tile())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
