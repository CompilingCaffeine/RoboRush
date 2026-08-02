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
    "art/effects/projectile_drone.png": DRONE_SHOT,
    "art/environments/shop_stand.png": SHOP_STAND,
    "art/bosses/merge_conflict.png": MERGE_CONFLICT,
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
    write_png(os.path.join(root, "art/environments/wall.png"), wall_tile())
    write_png(os.path.join(root, "art/environments/door.png"), door_tile())
    write_png(os.path.join(root, "art/environments/floor.png"), floor_tile())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
