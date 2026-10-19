"""Build the two arena characters and export them to assets/models/.

Run inside Blender (see tools/blender/README.md):
    p = "<project>/tools/blender/build_characters.py"; exec(open(p).read(), {"__file__": p})

Each character is a hierarchy of separate rigid parts so Godot can animate them
procedurally (squash/stretch, walk cycle, push, flail):
    <Root>                 empty at the feet, character faces -Y (Godot +Z)
      Body                 torso (+ scarf / belt)
        Head               origin at the neck; ears / cap merged in
          EyeL, EyeR       origin at the eye centre (scaled on Y to blink)
        HandL, HandR
      FootL, FootR
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
from pixkit import PAL, bm_to_object, clear_scene, cone, ellipsoid, empty, export_glb, face_colors_by, model_path, torus


def build_pip(x_offset=0.0):
    root = empty("Pip", (x_offset, 0, 0))
    ox = Vector((x_offset, 0, 0))

    body_bm = ellipsoid(ox + Vector((0, 0, 0.29)), (0.21, 0.19, 0.2))
    body = bm_to_object(body_bm, "Body", PAL["red"], origin=ox + Vector((0, 0, 0.1)), parent=root)
    # Belt band (merged visually by sitting just outside the body).
    scarf = torus(ox + Vector((0, 0, 0.44)), 0.14, 0.055, 18, 8)
    bm_to_object(scarf, "Scarf", PAL["yellow"], origin=ox + Vector((0, 0, 0.44)), parent=body)
    tail = cone(ox + Vector((0.06, 0.13, 0.43)), 0.05, 0.03, 0.2, 6,
                Matrix.Rotation(math.radians(155), 3, "X") @ Matrix.Rotation(math.radians(-15), 3, "Y"))
    bm_to_object(tail, "ScarfTail", PAL["yellow"], smooth=False, origin=ox + Vector((0.06, 0.13, 0.43)), parent=body)

    head_c = ox + Vector((0, 0, 0.67))
    head_bm = ellipsoid(head_c, (0.265, 0.25, 0.25), 20, 12)

    def head_color(f):
        n = f.normal
        # Face opening: front-facing band, everything else is the hood.
        if n.y < -0.42 and -0.62 < n.z < 0.55 and abs(n.x) < 0.78:
            return PAL["skin"]
        return PAL["red"]
    head = bm_to_object(head_bm, "Head", face_colors_by(head_bm, head_color), origin=ox + Vector((0, 0, 0.46)), parent=body)
    for side in (-1, 1):
        ear = cone(ox + Vector((0.13 * side, 0.03, 0.83)), 0.085, 0.0, 0.2, 8,
                   Matrix.Rotation(math.radians(-24 * side), 3, "Y") @ Matrix.Rotation(math.radians(8), 3, "X"))
        bm_to_object(ear, "Ear" + ("L" if side > 0 else "R"),
                     face_colors_by(ear, lambda f: PAL["red_dark"] if f.calc_center_median().z > 0.95 else PAL["red"]),
                     smooth=False, origin=ox + Vector((0.13 * side, 0.03, 0.83)), parent=head)
        eye_c = ox + Vector((0.088 * side, -0.236, 0.675))
        eye = ellipsoid(eye_c, (0.03, 0.022, 0.05), 10, 8)
        bm_to_object(eye, "Eye" + ("L" if side > 0 else "R"), PAL["ink"], origin=eye_c, parent=head)
        blush_c = ox + Vector((0.155 * side, -0.205, 0.6))
        blush = ellipsoid(blush_c, (0.035, 0.014, 0.02), 8, 6)
        bm_to_object(blush, "Blush" + ("L" if side > 0 else "R"), PAL["blush"], origin=blush_c, parent=head)
        hand_c = ox + Vector((0.25 * side, -0.02, 0.29))
        hand = ellipsoid(hand_c, (0.075, 0.075, 0.075), 10, 8)
        bm_to_object(hand, "Hand" + ("L" if side > 0 else "R"), PAL["skin"], origin=hand_c, parent=body)
        foot_c = ox + Vector((0.1 * side, -0.03, 0.055))
        foot = ellipsoid(foot_c, (0.085, 0.115, 0.06), 10, 8)
        bm_to_object(foot, "Foot" + ("L" if side > 0 else "R"), PAL["brown_dark"], origin=foot_c, parent=root)
    return root


def build_mog(x_offset=0.0):
    root = empty("Mog", (x_offset, 0, 0))
    ox = Vector((x_offset, 0, 0))
    rng = random.Random(7)

    body_bm = ellipsoid(ox + Vector((0, 0, 0.28)), (0.235, 0.21, 0.2))
    body = bm_to_object(body_bm, "Body",
                        face_colors_by(body_bm, lambda f: PAL["navy"] if f.calc_center_median().z < ox.z + 0.16 else PAL["teal"]),
                        origin=ox + Vector((0, 0, 0.1)), parent=root)

    head_c = ox + Vector((0, 0, 0.6))
    head_bm = ellipsoid(head_c, (0.235, 0.22, 0.2), 20, 12)
    head = bm_to_object(head_bm, "Head", PAL["lavender"], origin=ox + Vector((0, 0, 0.44)), parent=body)

    # Mushroom cap: a wide squashed dome with a flat gill underside and white spots.
    # Tilted back and raised so the face stays visible from the elevated game camera.
    cap_c = ox + Vector((0, 0.07, 0.74))
    cap_bm = ellipsoid(cap_c, (0.41, 0.38, 0.24), 24, 14)
    cut = [v for v in cap_bm.verts if v.co.z < cap_c.z - 0.03]
    bmesh.ops.delete(cap_bm, geom=cut, context="VERTS")
    edges = [e for e in cap_bm.edges if e.is_boundary]
    bmesh.ops.holes_fill(cap_bm, edges=edges, sides=0)
    bmesh.ops.recalc_face_normals(cap_bm, faces=cap_bm.faces)
    spot_centres = [Vector((math.cos(a) * r, math.sin(a) * r, 0)) for a, r in
                    [(0.3, 0.22), (2.1, 0.25), (3.6, 0.2), (5.0, 0.27), (1.2, 0.05)]]

    def cap_color(f):
        c = f.calc_center_median() - cap_c
        if f.normal.z < -0.5:
            return PAL["tan"]
        flat = Vector((c.x, c.y, 0))
        for s in spot_centres:
            if (flat - s).length < 0.075:
                return PAL["white"]
        return PAL["purple"]
    cap_colors = face_colors_by(cap_bm, cap_color)
    bmesh.ops.rotate(cap_bm, verts=cap_bm.verts, cent=cap_c, matrix=Matrix.Rotation(math.radians(-16), 3, "X"))
    bm_to_object(cap_bm, "Cap", cap_colors, origin=cap_c, parent=head)

    for side in (-1, 1):
        eye_c = ox + Vector((0.088 * side, -0.208, 0.575))
        eye = ellipsoid(eye_c, (0.034, 0.022, 0.056), 10, 8)
        bm_to_object(eye, "Eye" + ("L" if side > 0 else "R"), PAL["ink"], origin=eye_c, parent=head)
        brow_c = ox + Vector((0.092 * side, -0.198, 0.648))
        brow = ellipsoid(brow_c, (0.055, 0.02, 0.016), 8, 6)
        bmesh.ops.rotate(brow, verts=brow.verts, cent=brow_c, matrix=Matrix.Rotation(math.radians(-22 * side), 3, "Y"))
        bm_to_object(brow, "Brow" + ("L" if side > 0 else "R"), PAL["ink"], origin=brow_c, parent=head)
        hand_c = ox + Vector((0.265 * side, -0.02, 0.28))
        hand = ellipsoid(hand_c, (0.075, 0.075, 0.075), 10, 8)
        bm_to_object(hand, "Hand" + ("L" if side > 0 else "R"), PAL["lavender"], origin=hand_c, parent=body)
        foot_c = ox + Vector((0.105 * side, -0.03, 0.055))
        foot = ellipsoid(foot_c, (0.09, 0.115, 0.06), 10, 8)
        bm_to_object(foot, "Foot" + ("L" if side > 0 else "R"), PAL["navy"], origin=foot_c, parent=root)
    return root


def main():
    # Export each character alone so node names stay clean (no ".001" suffixes),
    # then rebuild both side by side for previewing in Blender.
    for build, name in ((build_pip, "pip"), (build_mog, "mog")):
        clear_scene()
        export_glb(model_path(name), [build(0.0)])
    clear_scene()
    build_pip(-0.7)
    build_mog(0.7)


main()
