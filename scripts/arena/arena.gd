@tool
class_name Arena
extends Node3D
## Procedural floating-island arena.
##
## The ground is described by a signed distance field (negative = solid ground):
## an organic ellipse minus a set of holes. From it we build:
##  * the grass top surface (marching squares -> holes are real gaps in the mesh),
##  * hole walls and outer cliffs with layered earth (rows jittered with smooth noise),
##  * a rocky underside so the island floats,
##  * floor + wall collision (holes are real gaps in the collision too),
##  * an SDF texture (R = ground, G = island outline) used by the terrain/grass/character
##    shaders, plus `ground_sdf()` for gameplay and AI queries.
## Mark it @tool so editing the ArenaConfig resource updates the editor view.

signal rebuilt

const LAYER_FLOOR := 1
const LAYER_WALLS := 2
const LAYER_OBSTACLES := 4
const LAYER_CHARACTERS := 8

@export var config: ArenaConfig:
	set(value):
		if config and config.changed.is_connected(_queue_rebuild):
			config.changed.disconnect(_queue_rebuild)
		config = value
		if config:
			config.changed.connect(_queue_rebuild)
		_queue_rebuild()
@export var terrain_material: Material
@export_tool_button("Rebuild") var rebuild_action := rebuild

var sdf_texture: ImageTexture
var sdf_rect := Rect2()
## Solid prop footprints (x, z, radius), filled by Props; used by grass placement and the AI.
var obstacles: Array[Vector3] = []
## Small decorations (x, z, radius) that only keep grass away.
var decor_footprints: Array[Vector3] = []

var _rebuild_queued := false
var _phase := PackedFloat32Array()


func _ready() -> void:
	rebuild()


func _queue_rebuild() -> void:
	if _rebuild_queued or not is_inside_tree():
		return
	_rebuild_queued = true
	(func():
		_rebuild_queued = false
		rebuild()).call_deferred()


# ---------------------------------------------------------------- distance field

func _wobble_phases() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = config.seed
	_phase.resize(8 + config.holes.size() * 2)
	for i in _phase.size():
		_phase[i] = rng.randf() * TAU


func island_sdf(p: Vector2) -> float:
	var r := config.radius
	var a := atan2(p.y, p.x)
	var w := config.edge_wobble * (0.55 * sin(3.0 * a + _phase[0]) + 0.3 * sin(5.0 * a + _phase[1]) + 0.15 * sin(9.0 * a + _phase[2]))
	var l := (p / r).length()
	if l < 0.0001:
		return -minf(r.x, r.y)
	# Radial distance to the ellipse along the ray from the centre.
	return p.length() * (1.0 - 1.0 / l) - w


func hole_sdf(p: Vector2, index: int) -> float:
	var h := config.holes[index]
	var d := p - Vector2(h.x, h.y)
	var a := atan2(d.y, d.x)
	var ph0 := _phase[8 + index * 2]
	var ph1 := _phase[9 + index * 2]
	var r := h.z + config.hole_wobble * (0.6 * sin(3.0 * a + ph0) + 0.4 * sin(5.0 * a + ph1))
	return d.length() - r


## Signed distance to the walkable ground edge: negative on solid ground, positive over
## holes or off the island.
func ground_sdf(p: Vector2) -> float:
	var d := island_sdf(p)
	for i in config.holes.size():
		d = maxf(d, -hole_sdf(p, i))
	return d


## Unit vector pointing away from solid ground (toward the nearest edge).
func ground_gradient(p: Vector2) -> Vector2:
	var e := 0.05
	var g := Vector2(ground_sdf(p + Vector2(e, 0)) - ground_sdf(p - Vector2(e, 0)),
		ground_sdf(p + Vector2(0, e)) - ground_sdf(p - Vector2(0, e)))
	return g.normalized() if g.length_squared() > 1e-10 else Vector2.RIGHT


func is_over_ground(p: Vector2) -> bool:
	return ground_sdf(p) < 0.0


# ---------------------------------------------------------------- noise helpers

static func _hash(p: Vector3) -> float:
	var h := sin(p.dot(Vector3(127.1, 311.7, 74.7))) * 43758.5453
	return h - floor(h)


static func _vnoise(p: Vector3) -> float:
	var i := p.floor()
	var f := p - i
	f = f * f * (Vector3.ONE * 3.0 - f * 2.0)
	var n000 := _hash(i)
	var n100 := _hash(i + Vector3(1, 0, 0))
	var n010 := _hash(i + Vector3(0, 1, 0))
	var n110 := _hash(i + Vector3(1, 1, 0))
	var n001 := _hash(i + Vector3(0, 0, 1))
	var n101 := _hash(i + Vector3(1, 0, 1))
	var n011 := _hash(i + Vector3(0, 1, 1))
	var n111 := _hash(i + Vector3(1, 1, 1))
	var x00 := lerpf(n000, n100, f.x)
	var x10 := lerpf(n010, n110, f.x)
	var x01 := lerpf(n001, n101, f.x)
	var x11 := lerpf(n011, n111, f.x)
	return lerpf(lerpf(x00, x10, f.y), lerpf(x01, x11, f.y), f.z) * 2.0 - 1.0


# ---------------------------------------------------------------- building

func rebuild() -> void:
	if not config or not is_inside_tree():
		return
	_wobble_phases()
	for c in get_children():
		if c.has_meta("generated"):
			remove_child(c)
			c.queue_free()

	var top := PackedVector3Array()
	var segments: Array[PackedVector2Array] = []
	_march(top, segments)

	# Chain the boundary into closed loops: the largest is the island outline, the rest are holes.
	var loops := _chain_loops(segments)
	var outer_i := 0
	for i in loops.size():
		if absf(_loop_area(loops[i])) > absf(_loop_area(loops[outer_i])):
			outer_i = i

	var walls := PackedVector3Array()
	var wall_normals := PackedVector3Array()
	for i in loops.size():
		if i != outer_i:
			_build_walls(loops[i], walls, wall_normals)

	var mesh := ArrayMesh.new()
	_add_surface(mesh, top, _const_normals(top.size(), Vector3.UP))
	_add_surface(mesh, walls, wall_normals)
	var cliff_collision := PackedVector3Array()
	if not loops.is_empty():
		_add_outer_shell(mesh, loops[outer_i], cliff_collision)
	for s in mesh.get_surface_count():
		mesh.surface_set_material(s, terrain_material)
	walls.append_array(cliff_collision)

	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = mesh
	_add_generated(mi)

	_add_static_body("FloorBody", top, LAYER_FLOOR)
	_add_static_body("WallBody", walls, LAYER_WALLS)
	_bake_sdf_texture()
	obstacles.clear()
	decor_footprints.clear()
	# Dependent builders (Props, then Vegetation) run in child order.
	for c in get_children():
		if c.has_method("rebuild_from_arena"):
			c.rebuild_from_arena(self)
	rebuilt.emit()


func _add_generated(n: Node) -> void:
	n.set_meta("generated", true)
	add_child(n)


func _add_static_body(body_name: String, tris: PackedVector3Array, layer: int) -> void:
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = layer
	body.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(tris)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	_add_generated(body)


func _add_surface(mesh: ArrayMesh, verts: PackedVector3Array, normals: PackedVector3Array) -> void:
	if verts.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


static func _const_normals(count: int, n: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(count)
	out.fill(n)
	return out


static func _flat_normals(tris: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(tris.size())
	for i in range(0, tris.size(), 3):
		# Godot front faces wind clockwise: normal = (c - a) x (b - a).
		var n := (tris[i + 2] - tris[i]).cross(tris[i + 1] - tris[i]).normalized()
		out[i] = n
		out[i + 1] = n
		out[i + 2] = n
	return out


## Appends triangle (a, b, c) wound so its front face points along `n`.
static func _tri(out: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	if (c - a).cross(b - a).dot(n) >= 0.0:
		out.append_array([a, b, c])
	else:
		out.append_array([a, c, b])


func _march(top: PackedVector3Array, segments: Array[PackedVector2Array]) -> void:
	var cs := config.cell_size
	var ext := config.radius + Vector2(config.edge_wobble + 0.6, config.edge_wobble + 0.6)
	var nx := int(ceil(ext.x * 2.0 / cs))
	var nz := int(ceil(ext.y * 2.0 / cs))
	var origin := -Vector2(nx, nz) * cs * 0.5
	var vals := PackedFloat32Array()
	vals.resize((nx + 1) * (nz + 1))
	for j in nz + 1:
		for i in nx + 1:
			vals[j * (nx + 1) + i] = ground_sdf(origin + Vector2(i, j) * cs)

	var p: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	var v := PackedFloat32Array([0, 0, 0, 0])
	for j in nz:
		for i in nx:
			p[0] = origin + Vector2(i, j) * cs
			p[1] = origin + Vector2(i + 1, j) * cs
			p[2] = origin + Vector2(i + 1, j + 1) * cs
			p[3] = origin + Vector2(i, j + 1) * cs
			v[0] = vals[j * (nx + 1) + i]
			v[1] = vals[j * (nx + 1) + i + 1]
			v[2] = vals[(j + 1) * (nx + 1) + i + 1]
			v[3] = vals[(j + 1) * (nx + 1) + i]
			var inside := 0
			for k in 4:
				if v[k] < 0.0:
					inside += 1
			if inside == 0:
				continue
			var poly := PackedVector2Array()
			var crossing: Array[bool] = []
			for k in 4:
				var k2 := (k + 1) % 4
				if v[k] < 0.0:
					poly.append(p[k])
					crossing.append(false)
				if (v[k] < 0.0) != (v[k2] < 0.0):
					var t := v[k] / (v[k] - v[k2])
					poly.append(p[k].lerp(p[k2], t))
					crossing.append(true)
			for k in range(1, poly.size() - 1):
				_tri(top, Vector3(poly[0].x, 0, poly[0].y), Vector3(poly[k].x, 0, poly[k].y),
					Vector3(poly[k + 1].x, 0, poly[k + 1].y), Vector3.UP)
			if inside < 4:
				for k in poly.size():
					var k2 := (k + 1) % poly.size()
					if crossing[k] and crossing[k2]:
						segments.append(PackedVector2Array([poly[k], poly[k2]]))


## Links marching-squares segments head-to-tail into closed loops of points.
func _chain_loops(segments: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	var buckets := {}
	for i in segments.size():
		var key := Vector2i((segments[i][0] * 2000.0).round())
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(i)
	var used := PackedByteArray()
	used.resize(segments.size())
	var loops: Array[PackedVector2Array] = []
	for start in segments.size():
		if used[start]:
			continue
		var loop := PackedVector2Array()
		var cur := start
		while cur >= 0 and not used[cur]:
			used[cur] = 1
			loop.append(segments[cur][0])
			cur = _find_next(segments, buckets, used, segments[cur][1])
		if loop.size() >= 3:
			loops.append(loop)
	return loops


func _find_next(segments: Array[PackedVector2Array], buckets: Dictionary, used: PackedByteArray, p: Vector2) -> int:
	var key := Vector2i((p * 2000.0).round())
	var best := -1
	var best_d := 1e-3
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for i in buckets.get(key + Vector2i(dx, dy), []):
				var d: float = segments[i][0].distance_to(p)
				if not used[i] and d < best_d:
					best_d = d
					best = i
	return best


static func _loop_area(loop: PackedVector2Array) -> float:
	var a := 0.0
	for i in loop.size():
		var p := loop[i]
		var q := loop[(i + 1) % loop.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


## Wall profile rows: (depth below the top as a fraction of thickness, inward inset).
func _wall_rows(is_outer: bool) -> Array[Vector2]:
	var t := config.thickness
	var rows: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(0.11, 0.07)]
	var n := 4
	for k in range(1, n + 1):
		var f := float(k) / n
		var y := lerpf(0.22, t, f)
		var inset := 0.1 + (0.12 * f * f if is_outer else 0.03 * f)
		rows.append(Vector2(y, inset))
	return rows


func _wall_point(q: Vector2, row: Vector2, row_index: int, is_outer: bool) -> Vector3:
	var g := ground_gradient(q)
	var jitter := 0.0
	if row_index >= 2:
		jitter = _vnoise(Vector3(q.x * 2.3, row_index * 1.7, q.y * 2.3)) * 0.09
	var y := -row.x
	if row_index >= 2 and row_index < 5:
		y += _vnoise(Vector3(q.x * 1.9 + 5.0, row_index * 3.1, q.y * 1.9)) * 0.07
	var inset := row.y + jitter
	if is_outer and row_index == 5:
		inset += _vnoise(Vector3(q.x * 1.3, 9.0, q.y * 1.3)) * 0.12
	var flat := q - g * inset
	return Vector3(flat.x, y, flat.y)


## Hole walls: layered earth rows hanging from a hole's outline loop.
func _build_walls(loop: PackedVector2Array, out: PackedVector3Array, normals: PackedVector3Array) -> void:
	var is_outer := false
	var rows := _wall_rows(is_outer)
	for i in loop.size():
		var a := loop[i]
		var b := loop[(i + 1) % loop.size()]
		var mid := (a + b) * 0.5
		var ga := ground_gradient(a)
		var gb := ground_gradient(b)
		var gm := ground_gradient(mid)
		for r in rows.size() - 1:
			var a0 := _wall_point(a, rows[r], r, is_outer)
			var b0 := _wall_point(b, rows[r], r, is_outer)
			var a1 := _wall_point(a, rows[r + 1], r + 1, is_outer)
			var b1 := _wall_point(b, rows[r + 1], r + 1, is_outer)
			var n := Vector3(gm.x, 0.0, gm.y)
			# Per-vertex normals follow the outline smoothly; the lip row tilts up a bit.
			var tilt := 0.6 if r == 0 else 0.0
			var na := Vector3(ga.x, tilt, ga.y).normalized()
			var nb := Vector3(gb.x, tilt, gb.y).normalized()
			var na1 := Vector3(ga.x, -0.1, ga.y).normalized()
			var nb1 := Vector3(gb.x, -0.1, gb.y).normalized()
			_quad(out, normals, a0, b0, b1, a1, na, nb, nb1, na1, n)


static func _quad(out: PackedVector3Array, normals: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3, facing: Vector3) -> void:
	# Two triangles (a, b, c) and (a, c, d), flipped together if needed to face `facing`.
	if (c - a).cross(b - a).dot(facing) >= 0.0:
		out.append_array([a, b, c, a, c, d])
		normals.append_array([na, nb, nc, na, nc, nd])
	else:
		out.append_array([a, c, b, a, d, c])
		normals.append_array([na, nc, nb, na, nd, nc])


## The island's outside as ONE watertight surface: it starts exactly on the grass outline
## (the same points as the top surface's boundary), drops down the layered cliff rows and
## continues, without any seam, into the rocky underside that tapers in gentle lobes to a
## single apex. Smooth normals make cliff and underside shade as a single mass.
## The cliff part is also appended to `collision` (characters falling off the edge).
func _add_outer_shell(mesh: ArrayMesh, outline: PackedVector2Array, collision: PackedVector3Array) -> void:
	var n := outline.size()
	var t0 := config.thickness
	var depth := config.underside_depth
	var centre := Vector2.ZERO
	for p in outline:
		centre += p
	centre /= n
	var apex := Vector3(centre.x + 0.3, -t0 - depth, centre.y + 0.4)

	var cliff_rows := _wall_rows(true)
	var under_rings := 12
	var rings: Array[PackedVector3Array] = []
	for r in cliff_rows.size():
		var ring := PackedVector3Array()
		for p in outline:
			ring.append(_wall_point(p, cliff_rows[r], r, true))
		rings.append(ring)
	var foot := rings[rings.size() - 1]
	for k in range(1, under_rings):
		var f := float(k) / under_rings
		var ring := PackedVector3Array()
		for i in n:
			var b := foot[i]
			var rel := Vector2(b.x - apex.x, b.z - apex.z)
			var a := atan2(rel.y, rel.x)
			# Low-frequency lobes, continuous around the ring and down the rings.
			var lobe := _vnoise(Vector3(cos(a) * 1.6, f * 1.8, sin(a) * 1.6))
			var lump := _vnoise(Vector3(cos(a) * 4.0 + 7.0, f * 5.0, sin(a) * 4.0))
			# Profile: continues the cliff almost vertically, then a rounded taper.
			var shape := pow(maxf(1.0 - pow(f, 1.6), 0.0), 0.65)
			var xz := Vector2(apex.x, apex.z) + rel * shape * (1.0 + (0.14 * lobe + 0.05 * lump) * f)
			var y := b.y - depth * f * (1.0 + 0.12 * lobe * f * (1.0 - f))
			ring.append(Vector3(xz.x, y, xz.y))
		rings.append(ring)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in rings:
		for v in ring:
			st.add_vertex(v)
	st.add_vertex(apex)
	var apex_i := rings.size() * n
	# Outline orientation decides the winding; pick it from the first quad so faces point out.
	var a0 := rings[0][0]
	var b0 := rings[0][1]
	var c0 := rings[1][1]
	var out_dir := Vector3(a0.x - apex.x, 0.0, a0.z - apex.z)
	# Triangles are emitted as (a, c, b); flip when that order would face inward.
	var flip := (b0 - a0).cross(c0 - a0).dot(out_dir) < 0.0
	for k in rings.size():
		for i in n:
			var i2 := (i + 1) % n
			var a := k * n + i
			var b := k * n + i2
			if k == rings.size() - 1:
				_tri_indexed(st, a, b, apex_i, flip)
			else:
				_tri_indexed(st, a, b, b + n, flip)
				_tri_indexed(st, a, b + n, a + n, flip)
				if k < cliff_rows.size() - 1:
					for v in [rings[k][i], rings[k][i2], rings[k + 1][i2], rings[k][i], rings[k + 1][i2], rings[k + 1][i]]:
						collision.append(v)
	st.generate_normals()
	st.commit(mesh)


## Adds triangle (a, b, c) as Godot front-facing (clockwise) unless `flip` reverses it.
static func _tri_indexed(st: SurfaceTool, a: int, b: int, c: int, flip: bool) -> void:
	st.add_index(a)
	if flip:
		st.add_index(b)
		st.add_index(c)
	else:
		st.add_index(c)
		st.add_index(b)


func _bake_sdf_texture() -> void:
	var ext := config.radius + Vector2(config.edge_wobble + 1.0, config.edge_wobble + 1.0)
	var res := 6.0 # texels per unit
	var w := int(ext.x * 2.0 * res)
	var h := int(ext.y * 2.0 * res)
	sdf_rect = Rect2(-ext, ext * 2.0)
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGF)
	for j in h:
		for i in w:
			var p := sdf_rect.position + Vector2((i + 0.5) / w, (j + 0.5) / h) * sdf_rect.size
			img.set_pixel(i, j, Color(ground_sdf(p), island_sdf(p), 0.0))
	sdf_texture = ImageTexture.create_from_image(img)
	RenderingServer.global_shader_parameter_set("arena_sdf", sdf_texture)
	RenderingServer.global_shader_parameter_set("arena_sdf_rect", Vector4(sdf_rect.position.x, sdf_rect.position.y, sdf_rect.size.x, sdf_rect.size.y))
