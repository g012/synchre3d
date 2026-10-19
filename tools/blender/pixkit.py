"""Shared helpers for building the game's Blender assets (run inside Blender 4.2+/5.x).

Colors: every face carries a palette index (see assets/palette/palette.json). It is written
to a second UV layer named "Palette" (u = (index + 0.5) / 32), which glTF exports as
TEXCOORD_1 and Godot reads as UV2. A "Col" color attribute + simple material mirror the
palette so assets preview correctly in Blender.
"""
import json
import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PALETTE_SIZE = 32

with open(os.path.join(ROOT, "assets", "palette", "palette.json")) as f:
    _PAL = json.load(f)["colors"]
PAL = {c["name"]: i for i, c in enumerate(_PAL)}


def _srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def pal_rgba(index):
    h = _PAL[index]["hex"].lstrip("#")
    return tuple(_srgb_to_linear(int(h[i:i + 2], 16) / 255.0) for i in (0, 2, 4)) + (1.0,)


def clear_scene():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for m in list(bpy.data.meshes):
        bpy.data.meshes.remove(m)
    for c in list(bpy.data.collections):
        if c.users == 0:
            bpy.data.collections.remove(c)


def preview_material():
    mat = bpy.data.materials.get("PalettePreview")
    if mat:
        return mat
    mat = bpy.data.materials.new("PalettePreview")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    nt.links.new(attr.outputs[0], bsdf.inputs[0])
    if "Roughness" in bsdf.inputs:
        bsdf.inputs["Roughness"].default_value = 1.0
    return mat


def bm_to_object(bm, name, face_colors, smooth=True, parent=None, origin=(0, 0, 0)):
    """Create an object from a bmesh. face_colors: list of palette indices per face (or one int)."""
    if isinstance(face_colors, int):
        face_colors = [face_colors] * len(bm.faces)
    bm.faces.ensure_lookup_table()
    uv_main = bm.loops.layers.uv.new("UVMap")
    uv_pal = bm.loops.layers.uv.new("Palette")
    col = bm.loops.layers.float_color.new("Col")
    for f, idx in zip(bm.faces, face_colors):
        f.smooth = smooth
        u = (idx + 0.5) / PALETTE_SIZE
        rgba = pal_rgba(idx)
        for l in f.loops:
            l[uv_pal].uv = (u, 0.5)
            l[uv_main].uv = (0.0, 0.0)
            l[col] = rgba
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.uv_layers.active_index = 0
    mesh.color_attributes.active_color_name = "Col"
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(preview_material())
    # Move the object origin without moving the geometry.
    o = Vector(origin)
    if o.length > 0:
        mesh.transform(Matrix.Translation(-o))
        obj.location = o
    if parent is not None:
        bpy.context.view_layer.update()
        world = obj.matrix_world.copy()
        obj.parent = parent
        obj.matrix_parent_inverse = parent.matrix_world.inverted()
        obj.matrix_world = world
    return obj


def empty(name, location=(0, 0, 0), parent=None):
    e = bpy.data.objects.new(name, None)
    e.empty_display_size = 0.2
    e.location = location
    bpy.context.scene.collection.objects.link(e)
    if parent is not None:
        e.parent = parent
    bpy.context.view_layer.update()
    return e


def ellipsoid(center, radii, segments=16, rings=10):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=1.0)
    bmesh.ops.transform(bm, matrix=Matrix.Diagonal((*radii, 1.0)), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return bm


def icosphere(center, radius, subdiv=2):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=radius)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return bm


def cone(base_center, radius1, radius2, depth, segments=10, rotation=None):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments,
                          radius1=radius1, radius2=radius2, depth=depth)
    bmesh.ops.translate(bm, vec=Vector((0, 0, depth / 2)), verts=bm.verts)
    if rotation is not None:
        bmesh.ops.transform(bm, matrix=rotation.to_4x4(), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(base_center), verts=bm.verts)
    return bm


def torus(center, major, minor, seg_major=16, seg_minor=8):
    bm = bmesh.new()
    verts = []
    for i in range(seg_major):
        a = 2 * math.pi * i / seg_major
        ring = []
        for j in range(seg_minor):
            b = 2 * math.pi * j / seg_minor
            r = major + minor * math.cos(b)
            ring.append(bm.verts.new((center[0] + r * math.cos(a), center[1] + r * math.sin(a),
                                      center[2] + minor * math.sin(b))))
        verts.append(ring)
    for i in range(seg_major):
        for j in range(seg_minor):
            a, b = verts[i][j], verts[(i + 1) % seg_major][j]
            c, d = verts[(i + 1) % seg_major][(j + 1) % seg_minor], verts[i][(j + 1) % seg_minor]
            bm.faces.new((a, b, c, d))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def tube(points, radii, segments=8, cap_top=True, jitter=0.0, seed=0):
    """Generalised cylinder through `points` with per-point `radii`."""
    rng = random.Random(seed)
    bm = bmesh.new()
    rings = []
    pts = [Vector(p) for p in points]
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        side = t.cross(Vector((0, 1, 0)))
        if side.length < 1e-4:
            side = t.cross(Vector((1, 0, 0)))
        side.normalize()
        up = side.cross(t).normalized()
        ring = []
        for s in range(segments):
            a = 2 * math.pi * s / segments
            r = radii[i] * (1.0 + rng.uniform(-jitter, jitter))
            ring.append(bm.verts.new(p + (side * math.cos(a) + up * math.sin(a)) * r))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for s in range(segments):
            s2 = (s + 1) % segments
            bm.faces.new((rings[i][s], rings[i][s2], rings[i + 1][s2], rings[i + 1][s]))
    if cap_top:
        bm.faces.new(list(reversed(rings[-1])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def displace(bm, amount, scale=1.5, seed=0):
    off = Vector((seed * 13.1, seed * 7.7, seed * 3.3))
    for v in bm.verts:
        n = noise.noise(v.co * scale + off)
        v.co += v.normal * n * amount if v.normal.length > 0 else Vector()


def face_colors_by(bm, fn):
    bm.faces.ensure_lookup_table()
    bm.normal_update()
    return [fn(f) for f in bm.faces]


def export_glb(path, objects):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
        for c in o.children_recursive:
            c.select_set(True)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_yup=True,
        export_apply=True, export_materials="NONE", export_vertex_color="NONE",
        export_texcoords=True, export_normals=True, export_animations=False)
    print("exported", path)


def model_path(name):
    return os.path.join(ROOT, "assets", "models", name + ".glb")
