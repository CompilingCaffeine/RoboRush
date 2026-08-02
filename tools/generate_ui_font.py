#!/usr/bin/env python3
"""Generate the Robo Rush UI font: a 5x8 monospace bitmap face as PNG + BMFont .fnt.

Pure Python 3 stdlib (zlib + struct) — NOT required to build or run the game, only to
regenerate the committed font.

    python3 tools/generate_ui_font.py .

Why a hand-drawn font at all: the game renders into a 480x270 buffer and scales that up
whole (see project.godot), so every UI label is drawn at 8 pixels and then magnified three
times. A vector face antialiases at 8px and the magnifier turns that grey fringe into a
visible blur, which is exactly the look spec section 20's "chunky pixel art" is not. A
bitmap face has no fringe to magnify.

Monospace because spec section 21 asks for it, and because a fixed advance is what lets the
HUD lay out a number column without measuring anything.

Glyphs are ASCII 32..126 authored as 5x8 ASCII grids. Every grid is asserted to be the right
shape, so a typo fails loudly rather than shifting the whole atlas by a pixel.
"""

import os
import struct
import sys
import zlib

# Glyph box. The cell is one pixel wider and one taller than the drawn box, which is where
# inter-character and inter-line spacing comes from — the glyphs themselves stay flush left.
GLYPH_WIDTH = 5
GLYPH_HEIGHT = 8
CELL_WIDTH = 6
CELL_HEIGHT = 9

# Row 7 of the box is below the baseline and only descenders reach it.
BASELINE = 7

COLUMNS = 16

FIRST_CODE = 32
LAST_CODE = 126

# Every glyph is eight rows of five characters: '#' is ink, anything else is transparent.
GLYPHS: dict[str, str] = {
    " ": "...../...../...../...../...../...../...../.....",
    "!": "..#../..#../..#../..#../..#../...../..#../.....",
    '"': ".#.#./.#.#./...../...../...../...../...../.....",
    "#": ".#.#./.#.#./#####/.#.#./#####/.#.#./.#.#./.....",
    "$": "..#../.####/#.#../.###./..#.#/####./..#../.....",
    "%": "##..#/##..#/...#./..#../.#.../#..##/#..##/.....",
    "&": ".##../#..#./#.#../.#.../#.#.#/#..#./.##.#/.....",
    "'": "..#../..#../...../...../...../...../...../.....",
    "(": "...#./..#../.#.../.#.../.#.../..#../...#./.....",
    ")": ".#.../..#../...#./...#./...#./..#../.#.../.....",
    "*": "...../#.#.#/.###./#####/.###./#.#.#/...../.....",
    "+": "...../..#../..#../#####/..#../..#../...../.....",
    ",": "...../...../...../...../...../..##./..#../.#...",
    "-": "...../...../...../#####/...../...../...../.....",
    ".": "...../...../...../...../...../.##../.##../.....",
    "/": "....#/...#./..#../..#../.#.../#..../#..../.....",
    "0": ".###./#...#/#..##/#.#.#/##..#/#...#/.###./.....",
    "1": "..#../.##../..#../..#../..#../..#../.###./.....",
    "2": ".###./#...#/....#/..##./.#.../#..../#####/.....",
    "3": "####./....#/....#/.###./....#/....#/####./.....",
    "4": "...#./..##./.#.#./#..#./#####/...#./...#./.....",
    "5": "#####/#..../####./....#/....#/#...#/.###./.....",
    "6": "..##./.#.../#..../####./#...#/#...#/.###./.....",
    "7": "#####/....#/...#./..#../.#.../.#.../.#.../.....",
    "8": ".###./#...#/#...#/.###./#...#/#...#/.###./.....",
    "9": ".###./#...#/#...#/.####/....#/...#./.##../.....",
    ":": "...../.##../.##../...../.##../.##../...../.....",
    ";": "...../.##../.##../...../.##../..#../.#.../.....",
    "<": "...#./..#../.#.../#..../.#.../..#../...#./.....",
    "=": "...../...../#####/...../#####/...../...../.....",
    ">": ".#.../..#../...#./....#/...#./..#../.#.../.....",
    "?": ".###./#...#/....#/..##./..#../...../..#../.....",
    "@": ".###./#...#/#.###/#.#.#/#.###/#..../.###./.....",
    "A": ".###./#...#/#...#/#####/#...#/#...#/#...#/.....",
    "B": "####./#...#/#...#/####./#...#/#...#/####./.....",
    "C": ".###./#...#/#..../#..../#..../#...#/.###./.....",
    "D": "###../#..#./#...#/#...#/#...#/#..#./###../.....",
    "E": "#####/#..../#..../####./#..../#..../#####/.....",
    "F": "#####/#..../#..../####./#..../#..../#..../.....",
    "G": ".###./#...#/#..../#.###/#...#/#...#/.####/.....",
    "H": "#...#/#...#/#...#/#####/#...#/#...#/#...#/.....",
    "I": ".###./..#../..#../..#../..#../..#../.###./.....",
    "J": "..###/...#./...#./...#./...#./#..#./.##../.....",
    "K": "#...#/#..#./#.#../##.../#.#../#..#./#...#/.....",
    "L": "#..../#..../#..../#..../#..../#..../#####/.....",
    "M": "#...#/##.##/#.#.#/#.#.#/#...#/#...#/#...#/.....",
    "N": "#...#/##..#/#.#.#/#.#.#/#..##/#...#/#...#/.....",
    "O": ".###./#...#/#...#/#...#/#...#/#...#/.###./.....",
    "P": "####./#...#/#...#/####./#..../#..../#..../.....",
    "Q": ".###./#...#/#...#/#...#/#.#.#/#..#./.##.#/.....",
    "R": "####./#...#/#...#/####./#.#../#..#./#...#/.....",
    "S": ".####/#..../#..../.###./....#/....#/####./.....",
    "T": "#####/..#../..#../..#../..#../..#../..#../.....",
    "U": "#...#/#...#/#...#/#...#/#...#/#...#/.###./.....",
    "V": "#...#/#...#/#...#/#...#/#...#/.#.#./..#../.....",
    "W": "#...#/#...#/#...#/#.#.#/#.#.#/##.##/#...#/.....",
    "X": "#...#/#...#/.#.#./..#../.#.#./#...#/#...#/.....",
    "Y": "#...#/#...#/.#.#./..#../..#../..#../..#../.....",
    "Z": "#####/....#/...#./..#../.#.../#..../#####/.....",
    "[": ".###./.#.../.#.../.#.../.#.../.#.../.###./.....",
    "\\": "#..../#..../.#.../..#../..#../...#./....#/.....",
    "]": ".###./...#./...#./...#./...#./...#./.###./.....",
    "^": "..#../.#.#./#...#/...../...../...../...../.....",
    "_": "...../...../...../...../...../...../...../#####",
    "`": ".#.../..#../...../...../...../...../...../.....",
    "a": "...../...../.###./....#/.####/#...#/.####/.....",
    "b": "#..../#..../####./#...#/#...#/#...#/####./.....",
    "c": "...../...../.###./#..../#..../#..../.###./.....",
    "d": "....#/....#/.####/#...#/#...#/#...#/.####/.....",
    "e": "...../...../.###./#...#/#####/#..../.###./.....",
    "f": "..##./.#.../.#.../####./.#.../.#.../.#.../.....",
    "g": "...../...../.####/#...#/#...#/.####/....#/.###.",
    "h": "#..../#..../####./#...#/#...#/#...#/#...#/.....",
    "i": "..#../...../.##../..#../..#../..#../.###./.....",
    "j": "...#./...../..##./...#./...#./...#./#..#./.##..",
    "k": "#..../#..../#..#./#.#../##.../#.#../#..#./.....",
    "l": ".##../..#../..#../..#../..#../..#../.###./.....",
    "m": "...../...../##.#./#.#.#/#.#.#/#.#.#/#...#/.....",
    "n": "...../...../####./#...#/#...#/#...#/#...#/.....",
    "o": "...../...../.###./#...#/#...#/#...#/.###./.....",
    "p": "...../...../####./#...#/#...#/####./#..../#....",
    "q": "...../...../.####/#...#/#...#/.####/....#/....#",
    "r": "...../...../#.##./##.../#..../#..../#..../.....",
    "s": "...../...../.####/#..../.###./....#/####./.....",
    "t": ".#.../.#.../####./.#.../.#.../.#..#/..##./.....",
    "u": "...../...../#...#/#...#/#...#/#...#/.####/.....",
    "v": "...../...../#...#/#...#/#...#/.#.#./..#../.....",
    "w": "...../...../#...#/#.#.#/#.#.#/#.#.#/.#.#./.....",
    "x": "...../...../#...#/.#.#./..#../.#.#./#...#/.....",
    "y": "...../...../#...#/#...#/#...#/.####/....#/.###.",
    "z": "...../...../#####/...#./..#../.#.../#####/.....",
    "{": "...##/..#../..#../.##../..#../..#../...##/.....",
    "|": "..#../..#../..#../..#../..#../..#../..#../.....",
    "}": "##.../..#../..#../..##./..#../..#../##.../.....",
    "~": "...../...../.#..#/#.#.#/#..#./...../...../.....",
}


def parse_glyph(character: str) -> list[str]:
    rows = GLYPHS[character].split("/")
    assert len(rows) == GLYPH_HEIGHT, f"'{character}': {len(rows)} rows, expected {GLYPH_HEIGHT}"
    for index, row in enumerate(rows):
        assert len(row) == GLYPH_WIDTH, (
            f"'{character}' row {index}: {len(row)} px, expected {GLYPH_WIDTH}"
        )
    return rows


def write_png(path: str, width: int, height: int, pixels: bytearray) -> None:
    raw = bytearray()
    for y in range(height):
        raw.append(0)  # filter type 0 (None)
        raw.extend(pixels[y * width * 4 : (y + 1) * width * 4])

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


def main(root: str) -> None:
    codes = list(range(FIRST_CODE, LAST_CODE + 1))
    missing = [chr(code) for code in codes if chr(code) not in GLYPHS]
    assert not missing, f"no glyph for: {missing}"

    rows = (len(codes) + COLUMNS - 1) // COLUMNS
    atlas_width = COLUMNS * CELL_WIDTH
    atlas_height = rows * CELL_HEIGHT

    # White ink with a per-pixel alpha, so Godot's font colour modulation is the only thing
    # that decides what colour a label is.
    pixels = bytearray(atlas_width * atlas_height * 4)
    records: list[str] = []

    for index, code in enumerate(codes):
        cell_x = (index % COLUMNS) * CELL_WIDTH
        cell_y = (index // COLUMNS) * CELL_HEIGHT

        for y, row in enumerate(parse_glyph(chr(code))):
            for x, ink in enumerate(row):
                if ink != "#":
                    continue
                offset = ((cell_y + y) * atlas_width + (cell_x + x)) * 4
                pixels[offset : offset + 4] = b"\xff\xff\xff\xff"

        records.append(
            f"char id={code} x={cell_x} y={cell_y} width={GLYPH_WIDTH} height={GLYPH_HEIGHT} "
            f"xoffset=0 yoffset=0 xadvance={CELL_WIDTH} page=0 chnl=15"
        )

    png_name = "font_6x8.png"
    write_png(os.path.join(root, "art", "ui", png_name), atlas_width, atlas_height, pixels)

    # BMFont's text format, which Godot imports directly as a FontFile. smooth=0 and aa=1 are
    # what tell it this is a bitmap face and must not be filtered.
    lines = [
        'info face="Robo Rush 6x8" size=8 bold=0 italic=0 charset="" unicode=1 stretchH=100 '
        "smooth=0 aa=1 padding=0,0,0,0 spacing=1,1",
        f"common lineHeight={CELL_HEIGHT} base={BASELINE} scaleW={atlas_width} "
        f"scaleH={atlas_height} pages=1 packed=0",
        f'page id=0 file="{png_name}"',
        f"chars count={len(records)}",
    ]
    lines.extend(records)

    fnt_path = os.path.join(root, "art", "ui", "font_6x8.fnt")
    with open(fnt_path, "w", encoding="ascii") as handle:
        handle.write("\n".join(lines) + "\n")
    print(f"wrote {fnt_path} ({len(records)} glyphs)")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
