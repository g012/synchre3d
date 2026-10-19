"""Build arena props (trees, bush, rocks, stump, mushrooms) and export them to assets/models/.

Run inside Blender:
    p = "<project>/tools/blender/build_props.py"; exec(open(p).read(), {"__file__": p})

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
]


def main():
    for name, build in BUILDERS:
        clear_scene()
        export_glb(model_path(name), [build(0.0)])
    clear_scene()
    for i, (name, build) in enumerate(BUILDERS):
        build((i - len(BUILDERS) / 2) * 1.9)


main()
