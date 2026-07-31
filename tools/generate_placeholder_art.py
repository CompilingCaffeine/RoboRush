#!/usr/bin/env python3
"""Generate Robo Rush placeholder pixel art as RGBA PNGs.

Pure Python 3 stdlib (zlib + struct) — NOT required to build or run the game, only
to regenerate the committed placeholder PNGs. Placeholders are replaced with real
pixel art in milestone 6.

    python3 tools/generate_placeholder_art.py .

Sprites are authored as ASCII grids and every row length is asserted, so a typo
fails loudly instead of silently producing a skewed image.
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


def wall_tile() -> list[str]:
    rows = ["o" * 16]
    rows.append("o" + "l" * 14 + "o")
    for _ in range(12):
        rows.append("o" + "m" * 14 + "o")
    rows.append("o" + "d" * 14 + "o")
    rows.append("o" * 16)
    grid = [list(r) for r in rows]
    for y in (4, 11):          # panel rivets
        for x in (4, 11):
            grid[y][x] = "l"
    return ["".join(r) for r in grid]


def floor_tile() -> list[str]:
    grid = [list("G" * 16)]
    for _ in range(15):
        grid.append(list("G" + "D" * 15))
    grid[7][5] = "S"           # scuff marks break up the tiling
    grid[3][11] = "S"
    return ["".join(r) for r in grid]


SPRITES = {
    "art/characters/player_placeholder.png": PLAYER,
    "art/characters/player_cannon_placeholder.png": CANNON,
    "art/enemies/ticket_bot_placeholder.png": TICKET_BOT,
    "art/effects/projectile_rivet.png": RIVET,
    "art/effects/projectile_ticket.png": TICKET_SHOT,
    "art/effects/muzzle_flash.png": MUZZLE_FLASH,
    "art/effects/spark.png": SPARK,
    "art/ui/scrap_placeholder.png": SCRAP,
    "art/ui/repair_cell_placeholder.png": REPAIR_CELL,
}


def main() -> int:
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    for relative, grid in SPRITES.items():
        write_png(os.path.join(root, relative), grid)
    for item_id, grid in ITEM_ICONS.items():
        write_png(os.path.join(root, f"art/items/{item_id}.png"), grid)
    write_png(os.path.join(root, "art/environments/wall_placeholder.png"), wall_tile())
    write_png(os.path.join(root, "art/environments/door_placeholder.png"), door_tile())
    write_png(os.path.join(root, "art/environments/floor_placeholder.png"), floor_tile())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
