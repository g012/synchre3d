#!/usr/bin/env python3
"""Generate assets/palette/palette_ramp.png from assets/palette/palette.json.

Each palette entry becomes one column of 4 texels:
    row 0 = shadow, row 1 = half-light, row 2 = lit (the base color), row 3 = highlight.
Shading ramps are hue-shifted in OKLCh (shadows drift toward cool blue/violet, highlights
toward warm yellow), the way pixel artists build ramps by hand. A palette entry may supply
its own "ramp" list of 4 hex colors to override the automatic one.

Usage: python3 tools/gen_palette.py
"""
import json
import math
import os
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "palette", "palette.json")
DST = os.path.join(ROOT, "assets", "palette", "palette_ramp.png")

SHADOW_HUE = 275.0   # cool violet-blue
HIGHLIGHT_HUE = 95.0  # warm yellow


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def linear_to_srgb(c):
    c = max(0.0, min(1.0, c))
    return c * 12.92 if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def to_oklab(rgb):
    r, g, b = (srgb_to_linear(c) for c in rgb)
    l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    l, m, s = (math.copysign(abs(v) ** (1 / 3), v) for v in (l, m, s))
    return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)


def from_oklab_unclamped(lab):
    L, a, b = lab
    l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3
    r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
    g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
    bb = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
    return (r, g, bb)


def from_oklch(L, C, H):
    """OKLCh -> sRGB, reducing chroma until the color fits the sRGB gamut (no hue-twisting clips)."""
    h = math.radians(H)
    for _ in range(40):
        lin = from_oklab_unclamped((L, C * math.cos(h), C * math.sin(h)))
        if all(-0.001 <= c <= 1.001 for c in lin):
            break
        C *= 0.92
    return tuple(linear_to_srgb(c) for c in lin)


def shift_hue(h, target, amount):
    d = (target - h + 540.0) % 360.0 - 180.0
    return h + d * amount


def ramp_color(rgb, light_mul, hue_target, hue_amount, chroma_mul):
    L, a, b = to_oklab(rgb)
    C = math.hypot(a, b)
    H = math.degrees(math.atan2(b, a)) % 360.0
    if C > 0.02:
        H = shift_hue(H, hue_target, hue_amount)
    else:  # near-greys still get a faint tint so shadows never read as dead grey
        C = 0.025
        H = hue_target
    L *= light_mul
    C *= chroma_mul
    return from_oklch(L, C, H)


def hex_to_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def build_ramp(rgb):
    return [
        ramp_color(rgb, 0.70, SHADOW_HUE, 0.16, 0.62),
        ramp_color(rgb, 0.85, SHADOW_HUE, 0.07, 0.85),
        rgb,
        ramp_color(rgb, 1.10, HIGHLIGHT_HUE, 0.12, 0.92),
    ]


def write_png(path, width, height, rows):
    raw = b"".join(b"\x00" + bytes(row) for row in rows)
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def main():
    with open(SRC) as f:
        colors = json.load(f)["colors"]
    ramps = []
    for c in colors:
        if "ramp" in c:
            ramps.append([hex_to_rgb(x) for x in c["ramp"]])
        else:
            ramps.append(build_ramp(hex_to_rgb(c["hex"])))
    rows = []
    for band in range(4):
        row = []
        for r in ramps:
            row += [round(v * 255) for v in r[band]]
        rows.append(row)
    write_png(DST, len(ramps), 4, rows)
    print(f"wrote {DST} ({len(ramps)} colors x 4 bands)")


if __name__ == "__main__":
    main()
