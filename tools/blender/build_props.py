"""Build arena props (trees, bush, rocks, stump, mushrooms, dancing flower) and export them to
assets/models/.

Run inside Blender:
    p = "<project>/tools/blender/build_props.py"; exec(open(p).read(), {"__file__": p})
To export only some props, pass their names: exec(..., {"__file__": p, "ONLY": ["dancing_flower"]})

Foliage is exported as rough "blob" meshes named Foliage*. In Godot the blobs are rendered
as a dark inner core and their surface is covered with pixel-art leaf billboards whose
normals come from the blob (see scripts/arena/props.gd and shaders/foliage.gdshader).
All props have their origin on the ground at the base.
"""
import math
import os
import random
import sys

import bmesh
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import importlib
import pixkit
importlib.reload(pixkit)
from pixkit import (PAL, bm_to_object, clear_scene, cone, displace, ellipsoid, empty, export_glb,
                    face_colors_by, icosphere, model_path, tube)


def curve(p0, p1, bend, n=6):
    """Points from p0 to p1 bowed sideways by `bend` (a vector)."""
    pts = []
    for i in range(n):
        t = i / (n - 1)
        pts.append(Vector(p0).lerp(Vector(p1), t) + Vector(bend) * math.sin(t * math.pi))
    return pts


def build_tree(name, height=1.0, blobs=None, seed=1, x_offset=0.0):
    rng = random.Random(seed)
    root = empty(name, (x_offset, 0, 0))
    o = Vector((x_offset, 0, 0))
    h = height
    trunk_pts = curve(o + Vector((0, 0, -0.15)), o + Vector((0.08, 0.02, 1.45 * h)), (0.06, 0.03, 0), 7)
    radii = [0.26, 0.2, 0.16, 0.14, 0.12, 0.11, 0.09]
    trunk = tube(trunk_pts, radii, segments=8, jitter=0.08, seed=seed)
    bm_to_object(trunk, "Trunk", PAL["brown"], smooth=False, origin=o, parent=root)
    # Root flares.
    for i in range(4):
        a = i * math.pi / 2 + rng.uniform(-0.3, 0.3)
        d = Vector((math.cos(a), math.sin(a), 0))
        pts = curve(o + Vector((0, 0, 0.25)), o + d * 0.5 + Vector((0, 0, -0.08)), (0, 0, 0.06), 4)
        r = tube(pts, [0.1, 0.08, 0.055, 0.03], segments=6, seed=seed + i)
        bm_to_object(r, "Root%d" % i, PAL["brown"], smooth=False, origin=o, parent=root)
    # Branches.
    for i, (dx, dz) in enumerate([(-0.55, 0.45), (0.5, 0.35)]):
        start = o + Vector((0.03, 0.0, 1.05 * h))
        end = o + Vector((dx, rng.uniform(-0.15, 0.15), 1.05 * h + dz))
        b = tube(curve(start, end, (0, 0, 0.12), 4), [0.08, 0.065, 0.05, 0.04], segments=6, seed=seed + 10 + i)
        bm_to_object(b, "Branch%d" % i, PAL["brown"], smooth=False, origin=o, parent=root)
    for i, (c, r) in enumerate(blobs):
        bm = icosphere(o + Vector(c), r, 2)
        bmesh.ops.scale(bm, vec=Vector((1.0, 1.0, 0.85)), verts=bm.verts, space=Matrix.Translation(-(o + Vector(c))))
        bm.normal_update()
        displace(bm, r * 0.12, scale=2.5, seed=seed + i)
        bm_to_object(bm, "Foliage%d" % i, PAL["leaf"], origin=o + Vector(c), parent=root)
    return root


def build_bush(x_offset=0.0, seed=3):
    root = empty("Bush", (x_offset, 0, 0))
    o = Vector((x_offset, 0, 0))
    for i, (c, r) in enumerate([((0, 0, 0.32), 0.42), ((-0.33, 0.08, 0.22), 0.3), ((0.32, -0.05, 0.24), 0.32)]):
        bm = icosphere(o + Vector(c), r, 2)
        displace(bm, r * 0.12, scale=3.0, seed=seed + i)
        bm_to_object(bm, "Foliage%d" % i, PAL["leaf"], origin=o + Vector(c), parent=root)
    return root


def build_rock(name, seed, size=(0.55, 0.45, 0.36), x_offset=0.0):
    rng = random.Random(seed)
    root = empty(name, (x_offset, 0, 0))
    o = Vector((x_offset, 0, 0))
    bm = icosphere(Vector(), 1.0, 1)
    for v in bm.verts:
        v.co *= 1.0 + rng.uniform(-0.18, 0.18)
    bmesh.ops.transform(bm, matrix=Matrix.Diagonal((*size, 1.0)), verts=bm.verts)
    for v in bm.verts:
        if v.co.z < -size[2] * 0.35:
            v.co.z = -size[2] * 0.35
    bmesh.ops.translate(bm, vec=o + Vector((0, 0, size[2] * 0.3)), verts=bm.verts)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    def color(f):
        if f.normal.z > 0.72 and rng.random() < 0.85:
            return PAL["moss"]
        return PAL["stone"]
    bm_to_object(bm, "Rock", face_colors_by(bm, color), smooth=False, origin=o, parent=root)
    return root


def build_stump(x_offset=0.0, seed=5):
    root = empty("Stump", (x_offset, 0, 0))
    o = Vector((x_offset, 0, 0))
    bm = tube([o + Vector((0, 0, -0.1)), o + Vector((0, 0, 0.18)), o + Vector((0, 0, 0.3))], [0.3, 0.25, 0.24],
              segments=9, jitter=0.06, seed=seed)
    bm_to_object(bm, "Stump", face_colors_by(bm, lambda f: PAL["tan"] if f.normal.z > 0.9 else PAL["brown"]),
                 smooth=False, origin=o, parent=root)
    return root


def build_mushrooms(x_offset=0.0, seed=9):
    rng = random.Random(seed)
    root = empty("Mushrooms", (x_offset, 0, 0))
    o = Vector((x_offset, 0, 0))
    for i, (dx, dy, s) in enumerate([(0, 0, 1.0), (0.13, 0.07, 0.75), (-0.1, 0.1, 0.6)]):
        base = o + Vector((dx, dy, 0))
        stem = tube([base, base + Vector((0, 0, 0.14 * s))], [0.035 * s, 0.03 * s], segments=6, seed=seed + i)
        bm_to_object(stem, "Stem%d" % i, PAL["white"], smooth=False, origin=base, parent=root)
        cap_c = base + Vector((0, 0, 0.13 * s))
        cap = ellipsoid(cap_c, (0.1 * s, 0.1 * s, 0.07 * s), 10, 6)
        cut = [v for v in cap.verts if v.co.z < cap_c.z - 0.005]
        bmesh.ops.delete(cap, geom=cut, context="VERTS")
        bmesh.ops.holes_fill(cap, edges=[e for e in cap.edges if e.is_boundary], sides=0)
        bmesh.ops.recalc_face_normals(cap, faces=cap.faces)
        bm_to_object(cap, "Cap%d" % i,
                     face_colors_by(cap, lambda f: PAL["white"] if (f.normal.z > 0.6 and rng.random() < 0.25) else PAL["mush_red"]),
                     origin=cap_c, parent=root)
    return root


def build_dancing_flower(x_offset=0.0, seed=13):
    """A little flower with a face that dances to the beat (animated in Godot by
    scripts/arena/dancing_flower.gd). Separate parts: Stem, LeafL/R (pivots at the stem), and a
    Head empty (pivot where it sits on the stem) holding Center, Petal0-7, eyes, mouth, blush.
    The face looks along -Y (the game's camera side)."""
    root = empty("DancingFlower", (x_offset, 0, 0))
    o = Vector((x_offset, 0, 0))
    stem = tube(curve(o + Vector((0, 0, -0.05)), o + Vector((0, 0, 0.47)), (0.025, 0, 0), 6),
                [0.042, 0.038, 0.034, 0.031, 0.029, 0.027], segments=7, seed=seed)
    bm_to_object(stem, "Stem", PAL["leaf"], origin=o, parent=root)
    for side, name in [(-1, "LeafL"), (1, "LeafR")]:
        pivot = o + Vector((side * 0.025, 0, 0.13))
        bm = ellipsoid(pivot + Vector((side * 0.12, 0, 0.0)), (0.12, 0.03, 0.05), 10, 6)
        bmesh.ops.rotate(bm, verts=bm.verts, cent=pivot, matrix=Matrix.Rotation(-side * 0.55, 3, "Y"))
        bm_to_object(bm, name, PAL["leaf_light"], origin=pivot, parent=root)
    hc = o + Vector((0, 0, 0.52))
    head = empty("Head", hc, parent=root)
    center = ellipsoid(hc, (0.12, 0.07, 0.12), 14, 8)
    bm_to_object(center, "Center", PAL["flower_yellow"], origin=hc, parent=head)
    for i in range(8):
        a = i * 2 * math.pi / 8 + math.pi / 8
        petal = ellipsoid(Vector(), (0.085, 0.032, 0.062), 10, 6)
        bmesh.ops.rotate(petal, verts=petal.verts, cent=Vector(), matrix=Matrix.Rotation(-a, 3, "Y"))
        bmesh.ops.translate(petal, vec=hc + Vector((math.cos(a), 0, math.sin(a))) * 0.17 + Vector((0, 0.03, 0)), verts=petal.verts)
        bm_to_object(petal, "Petal%d" % i, PAL["flower_pink"], origin=hc, parent=head)
    for side, name in [(-1, "EyeL"), (1, "EyeR")]:
        c = hc + Vector((side * 0.043, -0.064, 0.028))
        bm_to_object(ellipsoid(c, (0.018, 0.012, 0.03), 8, 6), name, PAL["ink"], origin=c, parent=head)
        b = hc + Vector((side * 0.078, -0.055, -0.018))
        bm_to_object(ellipsoid(b, (0.022, 0.01, 0.013), 8, 6), "Blush" + name[-1], PAL["blush"], origin=b, parent=head)
    m = hc + Vector((0, -0.068, -0.03))
    bm_to_object(ellipsoid(m, (0.026, 0.01, 0.012), 8, 6), "Mouth", PAL["ink"], origin=m, parent=head)
    return root


BUILDERS = [
    ("tree_round", lambda x: build_tree("TreeRound", 1.0, [((0.05, 0.0, 2.15), 0.78), ((-0.62, 0.08, 1.75), 0.52),
                                                           ((0.62, -0.05, 1.78), 0.55), ((0.0, 0.32, 1.7), 0.5)], 1, x)),
    ("tree_small", lambda x: build_tree("TreeSmall", 0.75, [((0.06, 0.0, 1.6), 0.62), ((-0.42, 0.05, 1.32), 0.42),
                                                           ((0.4, 0.1, 1.38), 0.4)], 4, x)),
    ("bush", lambda x: build_bush(x)),
    ("rock_a", lambda x: build_rock("RockA", 11, (0.55, 0.45, 0.38), x)),
    ("rock_b", lambda x: build_rock("RockB", 23, (0.38, 0.32, 0.42), x)),
    ("rock_c", lambda x: build_rock("RockC", 37, (0.7, 0.4, 0.26), x)),
    ("stump", lambda x: build_stump(x)),
    ("mushrooms", lambda x: build_mushrooms(x)),
    ("dancing_flower", lambda x: build_dancing_flower(x)),
]


def main():
    only = globals().get("ONLY")
    for name, build in BUILDERS:
        if only and name not in only:
            continue
        clear_scene()
        export_glb(model_path(name), [build(0.0)])
    clear_scene()
    for i, (name, build) in enumerate(BUILDERS):
        build((i - len(BUILDERS) / 2) * 1.9)


main()
