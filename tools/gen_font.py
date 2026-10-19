#!/usr/bin/env python3
"""Generate a 5x7 pixel font as a BMFont (assets/fonts/pixel_font.fnt + .png).

Glyphs are drawn white with a baked 1px dark outline, so a Label's font_color tints the
fill while the outline stays dark and readable over the busy game image.
Lowercase letters reuse the uppercase glyphs. Usage: python3 tools/gen_font.py
"""
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "fonts")

GLYPHS = {
    "A": ".###.|#...#|#...#|#####|#...#|#...#|#...#",
    "B": "####.|#...#|#...#|####.|#...#|#...#|####.",
    "C": ".###.|#...#|#....|#....|#....|#...#|.###.",
    "D": "####.|#...#|#...#|#...#|#...#|#...#|####.",
    "E": "#####|#....|#....|####.|#....|#....|#####",
    "F": "#####|#....|#....|####.|#....|#....|#....",
    "G": ".###.|#...#|#....|#.###|#...#|#...#|.####",
    "H": "#...#|#...#|#...#|#####|#...#|#...#|#...#",
    "I": ".###.|..#..|..#..|..#..|..#..|..#..|.###.",
    "J": "..###|...#.|...#.|...#.|...#.|#..#.|.##..",
    "K": "#...#|#..#.|#.#..|##...|#.#..|#..#.|#...#",
    "L": "#....|#....|#....|#....|#....|#....|#####",
    "M": "#...#|##.##|#.#.#|#.#.#|#...#|#...#|#...#",
    "N": "#...#|#...#|##..#|#.#.#|#..##|#...#|#...#",
    "O": ".###.|#...#|#...#|#...#|#...#|#...#|.###.",
    "P": "####.|#...#|#...#|####.|#....|#....|#....",
    "Q": ".###.|#...#|#...#|#...#|#.#.#|#..#.|.##.#",
    "R": "####.|#...#|#...#|####.|#.#..|#..#.|#...#",
    "S": ".####|#....|#....|.###.|....#|....#|####.",
    "T": "#####|..#..|..#..|..#..|..#..|..#..|..#..",
    "U": "#...#|#...#|#...#|#...#|#...#|#...#|.###.",
    "V": "#...#|#...#|#...#|#...#|#...#|.#.#.|..#..",
    "W": "#...#|#...#|#...#|#.#.#|#.#.#|#.#.#|.#.#.",
    "X": "#...#|#...#|.#.#.|..#..|.#.#.|#...#|#...#",
    "Y": "#...#|#...#|.#.#.|..#..|..#..|..#..|..#..",
    "Z": "#####|....#|...#.|..#..|.#...|#....|#####",
    "0": ".###.|#...#|#..##|#.#.#|##..#|#...#|.###.",
    "1": "..#..|.##..|..#..|..#..|..#..|..#..|.###.",
    "2": ".###.|#...#|....#|...#.|..#..|.#...|#####",
    "3": "####.|....#|....#|.###.|....#|....#|####.",
    "4": "...#.|..##.|.#.#.|#..#.|#####|...#.|...#.",
    "5": "#####|#....|####.|....#|....#|#...#|.###.",
    "6": "..##.|.#...|#....|####.|#...#|#...#|.###.",
    "7": "#####|....#|...#.|..#..|.#...|.#...|.#...",
    "8": ".###.|#...#|#...#|.###.|#...#|#...#|.###.",
    "9": ".###.|#...#|#...#|.####|....#|...#.|.##..",
    "!": "#|#|#|#|#|.|#",
    "?": ".###.|#...#|....#|...#.|..#..|.....|..#..",
    ".": ".|.|.|.|.|.|#",
    ",": "..|..|..|..|..|.#|#.",
    ":": ".|.|#|.|.|#|.",
    "-": "....|....|....|####|....|....|....",
    "+": ".....|..#..|..#..|#####|..#..|..#..|.....",
    "/": "....#|...#.|...#.|..#..|.#...|.#...|#....",
    "'": "#|#|.|.|.|.|.",
    "(": "..#|.#.|#..|#..|#..|.#.|..#",
    ")": "#..|.#.|..#|..#|..#|.#.|#..",
    "<": "...#|..#.|.#..|#...|.#..|..#.|...#",
    ">": "#...|.#..|..#.|...#|..#.|.#..|#...",
    "=": "....|....|####|....|####|....|....",
}

CELL_W, CELL_H = 8, 10  # glyph (<=5x7) + 1px outline each side, + spacing
COLS = 16
INK = (43, 33, 53, 255)
WHITE = (255, 255, 255, 255)


def main():
    os.makedirs(OUT, exist_ok=True)
    chars = []
    for ch, rows in GLYPHS.items():
        chars.append((ch, rows.split("|")))
        if ch.isalpha():
            chars.append((ch.lower(), rows.split("|")))
    rows_needed = (len(chars) + COLS - 1) // COLS
    img = Image.new("RGBA", (COLS * CELL_W, max(64, rows_needed * CELL_H)), (0, 0, 0, 0))
    lines = []
    for n, (ch, rows) in enumerate(chars):
        w = len(rows[0])
        cx = (n % COLS) * CELL_W
        cy = (n // COLS) * CELL_H
        on = {(x, y) for y, r in enumerate(rows) for x, c in enumerate(r) if c == "#"}
        # Outline: every empty neighbour (8-connected) of a lit pixel.
        for (x, y) in on:
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    p = (x + dx, y + dy)
                    if p not in on:
                        img.putpixel((cx + 1 + p[0], cy + 1 + p[1]), INK)
        for (x, y) in on:
            img.putpixel((cx + 1 + x, cy + 1 + y), WHITE)
        lines.append(f"char id={ord(ch)} x={cx} y={cy} width={w + 2} height=9 xoffset=-1 yoffset=-1 "
                     f"xadvance={w + 1} page=0 chnl=15")
    lines.append("char id=32 x=0 y=0 width=0 height=0 xoffset=0 yoffset=0 xadvance=4 page=0 chnl=15")
    img.save(os.path.join(OUT, "pixel_font.png"))
    header = [
        'info face="Pixel5x7" size=8 bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=0 aa=1 '
        'padding=0,0,0,0 spacing=0,0 outline=0',
        f"common lineHeight=10 base=8 scaleW={img.width} scaleH={img.height} pages=1 packed=0",
        'page id=0 file="pixel_font.png"',
        f"chars count={len(lines)}",
    ]
    with open(os.path.join(OUT, "pixel_font.fnt"), "w") as f:
        f.write("\n".join(header + lines) + "\n")
    print("font written:", len(lines), "glyphs")


if __name__ == "__main__":
    main()
