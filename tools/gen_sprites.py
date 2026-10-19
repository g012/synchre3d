#!/usr/bin/env python3
"""Generate the small pixel-art sprite atlases used by billboards.

assets/textures/grass_atlas.png  (8 tiles of 16x16)
    tiles 0-5: grass tufts (R = height along the blade, 0 base .. 255 tip),
    tiles 6-7: flowers (R = stem height, G = petal, B = centre).
assets/textures/leaf_atlas.png   (4 tiles of 16x16) leaf clusters for tree foliage.
assets/textures/fx_atlas.png     (4 tiles of 16x16) dust puff / impact star / spark / ring.

Channels: A = coverage mask, R = accent (blade tip / petal / leaf highlight),
G = secondary accent (flower centre / leaf shade). Colors are applied in shaders from the
shared palette, so these images only carry shape information.
Deterministic (fixed seed). Usage: python3 tools/gen_sprites.py
"""
import os
import random

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "textures")
T = 16


def put(img, ox, x, y, r=0, g=0, a=255, b=0):
    if 0 <= x < T and 0 <= y < T:
        img.putpixel((ox + x, y), (r, g, b, a))


def grass_tile(img, ox, rng, blades):
    # Draw short blades first so tall ones overlap them (painter's order).
    specs = []
    for _ in range(blades):
        specs.append((rng.uniform(2.5, 13.5), rng.randint(6, 13), rng.uniform(-0.5, 0.5),
                      2 if rng.random() < 0.45 else 1))
    specs.sort(key=lambda b: b[1])
    for x, h, lean, thick in specs:
        for i in range(h):
            y = T - 1 - i
            xx = int(round(x + lean * i * (0.6 + 0.4 * i / h)))
            frac = int(255 * i / max(h - 1, 1))
            put(img, ox, xx, y, r=frac)
            if thick == 2 and i < h * 0.6:
                put(img, ox, xx + (1 if lean >= 0 else -1), y, r=frac)


def flower_tile(img, ox, rng):
    x = rng.randint(6, 9)
    h = rng.randint(6, 8)
    lean = rng.choice([-1, 0, 1])
    for i in range(h):
        put(img, ox, x + (lean if i > h // 2 else 0), T - 1 - i, r=int(160 * i / h))
    # leaves on the stem
    put(img, ox, x - 1, T - 3, r=60)
    put(img, ox, x + 1, T - 4, r=80)
    hx = x + lean
    hy = T - 1 - h
    for dx, dy in [(0, -1), (-1, 0), (1, 0), (0, 1), (-1, -1), (1, -1), (-1, 1), (1, 1)]:
        if abs(dx) + abs(dy) == 2 and rng.random() < 0.5:
            continue
        put(img, ox, hx + dx, hy + dy, g=255)
    put(img, ox, hx, hy, b=255)


def leaf_tile(img, ox, rng):
    # A roundish clump of leaves: filled blob with a ragged edge and lit upper-left pixels.
    cx, cy = 7.5 + rng.uniform(-0.5, 0.5), 7.5 + rng.uniform(-0.5, 0.5)
    for y in range(T):
        for x in range(T):
            dx, dy = x - cx, y - cy
            d = (dx * dx + dy * dy) ** 0.5
            edge = 6.2 + rng.uniform(-1.2, 0.8)
            if d < edge:
                lit = (dx + dy) < -3.5 and rng.random() < 0.8
                shade = (dx + dy) > 4.0 and rng.random() < 0.7
                put(img, ox, x, y, r=255 if lit else 0, g=255 if shade else 0)
    # a few notches so clusters read as individual leaves
    for _ in range(5):
        x, y = rng.randint(2, 13), rng.randint(2, 13)
        if ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5 > 4.0:
            img.putpixel((ox + x, y), (0, 0, 0, 0))


def fx_tiles(img):
    # 0: dust puff (soft disc with a lit top-left)
    for y in range(T):
        for x in range(T):
            d = ((x - 7.5) ** 2 + (y - 7.5) ** 2) ** 0.5
            if d < 6.5:
                put(img, 0, x, y, r=255 if (x + y) < 12 else 0)
    # 1: impact star (4 long points + 4 short)
    for i in range(-7, 8):
        put(img, T, 7 + i, 7, r=255 if abs(i) < 3 else 0)
        put(img, T, 7, 7 + i, r=255 if abs(i) < 3 else 0)
    for i in range(-3, 4):
        put(img, T, 7 + i, 7 + i, r=255)
        put(img, T, 7 + i, 7 - i, r=255)
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            put(img, T, 7 + dx, 7 + dy, r=255, g=255)
    # 2: spark (small diamond)
    for dx, dy in [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)]:
        put(img, 2 * T, 7 + dx, 7 + dy, r=255 if (dx, dy) == (0, 0) else 0)
    # 3: ring
    for y in range(T):
        for x in range(T):
            d = ((x - 7.5) ** 2 + (y - 7.5) ** 2) ** 0.5
            if 5.2 < d < 7.0:
                put(img, 3 * T, x, y)


def main():
    rng = random.Random(1234)
    grass = Image.new("RGBA", (T * 8, T), (0, 0, 0, 0))
    for i in range(6):
        grass_tile(grass, i * T, rng, blades=rng.randint(6, 9))
    flower_tile(grass, 6 * T, rng)
    flower_tile(grass, 7 * T, rng)
    grass.save(os.path.join(OUT, "grass_atlas.png"))

    leaves = Image.new("RGBA", (T * 4, T), (0, 0, 0, 0))
    for i in range(4):
        leaf_tile(leaves, i * T, rng)
    leaves.save(os.path.join(OUT, "leaf_atlas.png"))

    fx = Image.new("RGBA", (T * 4, T), (0, 0, 0, 0))
    fx_tiles(fx)
    fx.save(os.path.join(OUT, "fx_atlas.png"))

    for name in ("grass_atlas", "leaf_atlas", "fx_atlas"):
        im = Image.open(os.path.join(OUT, name + ".png"))
        preview = Image.new("RGBA", im.size, (40, 60, 40, 255))
        preview.alpha_composite(im)
        preview.resize((im.width * 8, im.height * 8), Image.NEAREST).save(
            os.path.join(os.environ.get("PREVIEW_DIR", "/tmp"), name + "_preview.png"))
    print("sprites written to", OUT)


if __name__ == "__main__":
    main()
