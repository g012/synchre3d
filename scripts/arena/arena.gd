@tool
class_name Arena
extends Node3D
## Procedural floating-island arena.
##
## The ground is described by a signed distance field (negative = solid ground):
## an organic ellipse minus a set of holes. From it we build:
##  * the grass top surface (marching squares -> holes are real gaps in the mesh), split into
##    chunks that each own their mesh, hole walls and floor/wall collision,
##  * one watertight outer shell: layered cliff + rocky underside (built once),
##  * an SDF texture (R = ground, G = island outline) used by the terrain/grass/character
##    shaders, plus `ground_sdf()` for gameplay and AI queries.
##
## Holes are runtime state: they start from the ArenaConfig, and spells can open new ones or
## close existing ones (`open_hole`, `close_hole`). An animated hole only rebuilds the chunks
## and SDF texels it touches, so the mesh and the collision stay exact while it grows/shrinks.
## Mark it @tool so editing the ArenaConfig resource updates the editor view.

signal rebuilt
## A hole finished opening (scale reached 1) or closing (removed / scale 0).
signal hole_opened(hole: Dictionary)
signal hole_closed(hole: Dictionary)

const LAYER_FLOOR := 1
const LAYER_WALLS := 2
const LAYER_OBSTACLES := 4
const LAYER_CHARACTERS := 8
## Marching-squares cells per chunk side.
const CHUNK_CELLS := 12
## Beyond this distance from its rim a hole does not affect geometry (see ground_sdf).
const FAR_HOLE := 1.5
## Hole animations rebuild geometry at most this often (seconds).
const HOLE_UPDATE_INTERVAL := 0.05

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
## Runtime holes: { id, center: Vector2, radius, scale (0..1 shown), target (0 or 1),
## duration (s for a full open/close), ph0, ph1 (outline wobble phases), dynamic: bool }.
var holes: Array[Dictionary] = []

var _rebuild_queued := false
var _phase := PackedFloat32Array()
var _next_hole_id := 0
# Marching-squares grid.
var _cs := 0.16
var _origin := Vector2.ZERO
var _nx := 0
var _nz := 0
var _vals := PackedFloat32Array()
var _chunks := {}
var _sdf_image: Image
var _hole_update_timer := 0.0
var _pending_dirty := Rect2()
var _has_pending := false


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


## Signed distance to a hole's (wobbly, scaled) outline: negative inside the hole.
func hole_sdf(p: Vector2, h: Dictionary) -> float:
	var d: Vector2 = p - h.center
	var a := atan2(d.y, d.x)
	var r: float = (h.radius + config.hole_wobble * (0.6 * sin(3.0 * a + h.ph0) + 0.4 * sin(5.0 * a + h.ph1))) * h.scale
	return d.length() - r


## Signed distance to the walkable ground edge: negative on solid ground, positive over
## holes or off the island.
func ground_sdf(p: Vector2) -> float:
	var d := island_sdf(p)
	for h in holes:
		if h.scale <= 0.02:
			continue
		# Far from its rim, a hole's wobble cannot change the sign of anything: use the plain
		# circle distance (no trig), which is within `hole_wobble` of the exact value.
		var reach: float = (h.radius + config.hole_wobble) * h.scale + FAR_HOLE
		var d2 := p.distance_squared_to(h.center)
		if d2 > reach * reach:
			d = maxf(d, h.radius * h.scale - sqrt(d2))
		else:
			d = maxf(d, -hole_sdf(p, h))
	return d


## Unit vector pointing away from solid ground (toward the nearest edge).
func ground_gradient(p: Vector2) -> Vector2:
	var e := 0.05
	var g := Vector2(ground_sdf(p + Vector2(e, 0)) - ground_sdf(p - Vector2(e, 0)),
		ground_sdf(p + Vector2(0, e)) - ground_sdf(p - Vector2(0, e)))
	return g.normalized() if g.length_squared() > 1e-10 else Vector2.RIGHT


func is_over_ground(p: Vector2) -> bool:
	return ground_sdf(p) < 0.0


## True when the boundary at `p` belongs to the island outline rather than to a hole.
func _is_outer_boundary(p: Vector2) -> bool:
	var d := island_sdf(p)
	for h in holes:
		if h.scale > 0.02 and -hole_sdf(p, h) > d:
			return false
	return true


# ---------------------------------------------------------------- runtime holes

## Whether a hole of `radius` can open at `center`: well inside the island (the outer shell
## never changes) and clear of props.
func can_open_hole(center: Vector2, radius: float) -> bool:
	if island_sdf(center) > -(radius * 1.2 + 0.7):
		return false
	for o in obstacles + decor_footprints:
		if center.distance_to(Vector2(o.x, o.y)) < o.z + radius + 0.15:
			return false
	return true


## Starts opening a new hole; returns its id, or -1 if it cannot open there.
func open_hole(center: Vector2, radius: float, duration := 0.45) -> int:
	if not can_open_hole(center, radius):
		return -1
	var h := {"id": _next_hole_id, "center": center, "radius": radius, "scale": 0.0,
		"target": 1.0, "duration": duration, "ph0": randf() * TAU, "ph1": randf() * TAU,
		"dynamic": true}
	_next_hole_id += 1
	holes.append(h)
	return h.id


## Starts closing hole `id`; returns false if there is no such open hole.
func close_hole(id: int, duration := 0.6) -> bool:
	for h in holes:
		if h.id == id and h.target > 0.0:
			h.target = 0.0
			h.duration = duration
			return true
	return false


## The open (or opening) hole whose rim is closest to `p`, within `max_dist`; {} if none.
func nearest_hole(p: Vector2, max_dist: float) -> Dictionary:
	var best := {}
	var best_d := max_dist
	for h in holes:
		if h.target <= 0.0:
			continue
		var d: float = maxf(p.distance_to(h.center) - h.radius, 0.0)
		if d < best_d:
			best_d = d
			best = h
	return best


## Restores the holes of the ArenaConfig (new holes vanish, closed ones reopen) instantly.
func reset_holes() -> void:
	var dirty := Rect2()
	var first := true
	for h in holes:
		if h.dynamic or h.scale < 1.0:
			var r := _hole_rect(h)
			dirty = r if first else dirty.merge(r)
			first = false
	holes = holes.filter(func(h): return not h.dynamic)
	for h in holes:
		h.scale = 1.0
		h.target = 1.0
	if not first:
		_update_region(dirty)


func _hole_rect(h: Dictionary) -> Rect2:
	var r: float = h.radius + config.hole_wobble + 0.5
	return Rect2(h.center - Vector2(r, r), Vector2(r, r) * 2.0)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or holes.is_empty():
		return
	var dirty := Rect2()
	var any := false
	var finished: Array[Dictionary] = []
	for h in holes:
		if is_equal_approx(h.scale, h.target):
			continue
		h.scale = move_toward(h.scale, h.target, delta / maxf(h.duration, 0.01))
		var r := _hole_rect(h)
		dirty = r if not any else dirty.merge(r)
		any = true
		if is_equal_approx(h.scale, h.target):
			finished.append(h)
	if not any:
		return
	for h in finished:
		if h.target <= 0.0 and h.dynamic:
			holes.erase(h)
	_pending_dirty = dirty if not _has_pending else _pending_dirty.merge(dirty)
	_has_pending = true
	_hole_update_timer -= delta
	# Throttle geometry rebuilds, but always apply the final state of a finished animation.
	if _hole_update_timer > 0.0 and finished.is_empty():
		return
	_hole_update_timer = HOLE_UPDATE_INTERVAL
	_has_pending = false
	_update_region(_pending_dirty)
	for h in finished:
		if h.target > 0.0:
			hole_opened.emit(h)
		else:
			hole_closed.emit(h)


# ---------------------------------------------------------------- noise helpers

static var _noise: FastNoiseLite


## Smooth value noise in [-1, 1] (native FastNoiseLite: this runs per wall vertex).
static func _vnoise(p: Vector3) -> float:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.noise_type = FastNoiseLite.TYPE_VALUE
		_noise.frequency = 1.0
		_noise.fractal_type = FastNoiseLite.FRACTAL_NONE
		_noise.seed = 17
	return _noise.get_noise_3dv(p)


# ---------------------------------------------------------------- building

func rebuild() -> void:
	if not config or not is_inside_tree():
		return
	_wobble_phases()
	for c in get_children():
		if c.has_meta("generated"):
			remove_child(c)
			c.queue_free()
	_chunks.clear()
	holes.clear()
	for i in config.holes.size():
		var hv := config.holes[i]
		holes.append({"id": _next_hole_id, "center": Vector2(hv.x, hv.y), "radius": hv.z,
			"scale": 1.0, "target": 1.0, "duration": 0.6, "ph0": _phase[8 + i * 2],
			"ph1": _phase[9 + i * 2], "dynamic": false})
		_next_hole_id += 1

	# Marching-squares grid over the whole island.
	_cs = config.cell_size
	var ext := config.radius + Vector2(config.edge_wobble + 0.6, config.edge_wobble + 0.6)
	_nx = int(ceil(ext.x * 2.0 / _cs))
	_nz = int(ceil(ext.y * 2.0 / _cs))
	_origin = -Vector2(_nx, _nz) * _cs * 0.5
	_vals.resize((_nx + 1) * (_nz + 1))
	_compute_vals(0, 0, _nx, _nz)

	var outer_segments: Array[PackedVector2Array] = []
	for cj in ceili(float(_nz) / CHUNK_CELLS):
		for ci in ceili(float(_nx) / CHUNK_CELLS):
			_build_chunk(Vector2i(ci, cj), outer_segments)

	# The island outline (largest loop of outer-boundary segments) becomes the outer shell.
	var loops := _chain_loops(outer_segments)
	var outer_i := 0
	for i in loops.size():
		if absf(_loop_area(loops[i])) > absf(_loop_area(loops[outer_i])):
			outer_i = i
	if not loops.is_empty():
		var mesh := ArrayMesh.new()
		var cliff_collision := PackedVector3Array()
		_add_outer_shell(mesh, loops[outer_i], cliff_collision)
		mesh.surface_set_material(0, terrain_material)
		var mi := MeshInstance3D.new()
		mi.name = "Shell"
		mi.mesh = mesh
		_add_generated(mi)
		_add_generated(_static_body("CliffBody", cliff_collision, LAYER_WALLS))

	_bake_sdf_texture()
	obstacles.clear()
	decor_footprints.clear()
	# Dependent builders (Props, then Vegetation) run in child order.
	for c in get_children():
		if c.has_method("rebuild_from_arena"):
			c.rebuild_from_arena(self)
	rebuilt.emit()


func _compute_vals(i0: int, j0: int, i1: int, j1: int) -> void:
	for j in range(maxi(j0, 0), mini(j1, _nz) + 1):
		for i in range(maxi(i0, 0), mini(i1, _nx) + 1):
			_vals[j * (_nx + 1) + i] = ground_sdf(_origin + Vector2(i, j) * _cs)


## Recomputes the distance samples covering `rect` (world XZ), then rebuilds only the chunks
## where a sample changed near the ground boundary (elsewhere the geometry is identical),
## and refreshes the SDF texels.
func _update_region(rect: Rect2) -> void:
	var i0 := maxi(floori((rect.position.x - _origin.x) / _cs) - 1, 0)
	var j0 := maxi(floori((rect.position.y - _origin.y) / _cs) - 1, 0)
	var i1 := mini(ceili((rect.end.x - _origin.x) / _cs) + 1, _nx)
	var j1 := mini(ceili((rect.end.y - _origin.y) / _cs) + 1, _nz)
	var dirty := {}
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var k := j * (_nx + 1) + i
			var old := _vals[k]
			var v := ground_sdf(_origin + Vector2(i, j) * _cs)
			_vals[k] = v
			if absf(v - old) > 1e-5 and (absf(v) < 0.6 or absf(old) < 0.6):
				# A grid point is shared by up to four chunks.
				for dj: int in [-1, 0]:
					for di: int in [-1, 0]:
						if i + di < 0 or j + dj < 0:
							continue
						var cc := Vector2i((i + di) / CHUNK_CELLS, (j + dj) / CHUNK_CELLS)
						if cc.x * CHUNK_CELLS < _nx and cc.y * CHUNK_CELLS < _nz:
							dirty[cc] = true
	for c in dirty:
		_build_chunk(c, null)
	_update_sdf_texels(rect)


## (Re)builds one chunk: its piece of grass top, the hole walls hanging from it, and their
## collision. Outer-boundary segments are skipped (the shell owns the cliff); during a full
## rebuild they are collected into `outer_segments`.
func _build_chunk(c: Vector2i, outer_segments) -> void:
	if _chunks.has(c):
		for n in _chunks[c]:
			remove_child(n)
			n.queue_free()
	var top := PackedVector3Array()
	var segments: Array[PackedVector2Array] = []
	_march_cells(c.x * CHUNK_CELLS, c.y * CHUNK_CELLS, mini((c.x + 1) * CHUNK_CELLS, _nx),
		mini((c.y + 1) * CHUNK_CELLS, _nz), top, segments)
	var walls := PackedVector3Array()
	var wall_normals := PackedVector3Array()
	var columns := {}
	for seg in segments:
		if _is_outer_boundary((seg[0] + seg[1]) * 0.5):
			if outer_segments != null:
				outer_segments.append(seg)
		else:
			_build_wall_segment(seg[0], seg[1], walls, wall_normals, columns)
	var nodes: Array[Node] = []
	if not top.is_empty() or not walls.is_empty():
		var mesh := ArrayMesh.new()
		_add_surface(mesh, top, _const_normals(top.size(), Vector3.UP))
		_add_surface(mesh, walls, wall_normals)
		for s in mesh.get_surface_count():
			mesh.surface_set_material(s, terrain_material)
		var mi := MeshInstance3D.new()
		mi.name = "Chunk_%d_%d" % [c.x, c.y]
		mi.mesh = mesh
		nodes.append(mi)
	if not top.is_empty():
		nodes.append(_static_body("Floor_%d_%d" % [c.x, c.y], top, LAYER_FLOOR))
	if not walls.is_empty():
		nodes.append(_static_body("Walls_%d_%d" % [c.x, c.y], walls, LAYER_WALLS))
	for n in nodes:
		_add_generated(n)
	_chunks[c] = nodes


func _add_generated(n: Node) -> void:
	n.set_meta("generated", true)
	add_child(n)


func _static_body(body_name: String, tris: PackedVector3Array, layer: int) -> StaticBody3D:
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
	return body


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


## Appends triangle (a, b, c) wound so its front face points along `n`.
static func _tri(out: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	if (c - a).cross(b - a).dot(n) >= 0.0:
		out.append_array([a, b, c])
	else:
		out.append_array([a, c, b])


## Marching squares over cells [i0, i1) x [j0, j1) of the shared grid.
func _march_cells(i0: int, j0: int, i1: int, j1: int, top: PackedVector3Array, segments: Array[PackedVector2Array]) -> void:
	var cs := _cs
	var origin := _origin
	var nx := _nx
	var vals := _vals
	var p: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	var v := PackedFloat32Array([0, 0, 0, 0])
	for j in range(j0, j1):
		for i in range(i0, i1):
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


## `g` = ground_gradient(q), passed in so a column of rows evaluates it once.
func _wall_point(q: Vector2, g: Vector2, row: Vector2, row_index: int, is_outer: bool) -> Vector3:
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


## Hole wall: layered earth rows hanging from one boundary segment a-b.
func _build_wall_segment(a: Vector2, b: Vector2, out: PackedVector3Array, normals: PackedVector3Array, columns: Dictionary) -> void:
	var rows := _wall_rows(false)
	var ca: Array = _wall_column(a, rows, columns)
	var cb: Array = _wall_column(b, rows, columns)
	var ga: Vector2 = ca[0]
	var gb: Vector2 = cb[0]
	var col_a: PackedVector3Array = ca[1]
	var col_b: PackedVector3Array = cb[1]
	var n := Vector3(ga.x + gb.x, 0.0, ga.y + gb.y)
	for r in rows.size() - 1:
		# Per-vertex normals follow the outline smoothly; the lip row tilts up a bit.
		var tilt := 0.6 if r == 0 else 0.0
		var na := Vector3(ga.x, tilt, ga.y).normalized()
		var nb := Vector3(gb.x, tilt, gb.y).normalized()
		var na1 := Vector3(ga.x, -0.1, ga.y).normalized()
		var nb1 := Vector3(gb.x, -0.1, gb.y).normalized()
		_quad(out, normals, col_a[r], col_b[r], col_b[r + 1], col_a[r + 1], na, nb, nb1, na1, n)


## [gradient, wall points per row] for a boundary point; neighbouring segments share their
## endpoints, so columns are cached per chunk build.
func _wall_column(q: Vector2, rows: Array[Vector2], columns: Dictionary) -> Array:
	var key := Vector2i((q * 4000.0).round())
	if columns.has(key):
		return columns[key]
	var g := ground_gradient(q)
	var col := PackedVector3Array()
	for r in rows.size():
		col.append(_wall_point(q, g, rows[r], r, false))
	var entry := [g, col]
	columns[key] = entry
	return entry


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
	var grads := PackedVector2Array()
	for p in outline:
		grads.append(ground_gradient(p))
	for r in cliff_rows.size():
		var ring := PackedVector3Array()
		for i in n:
			ring.append(_wall_point(outline[i], grads[i], cliff_rows[r], r, true))
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
	_sdf_image = Image.create_empty(w, h, false, Image.FORMAT_RGF)
	_fill_sdf_texels(0, 0, w, h)
	sdf_texture = ImageTexture.create_from_image(_sdf_image)
	RenderingServer.global_shader_parameter_set("arena_sdf", sdf_texture)
	RenderingServer.global_shader_parameter_set("arena_sdf_rect", Vector4(sdf_rect.position.x, sdf_rect.position.y, sdf_rect.size.x, sdf_rect.size.y))


func _fill_sdf_texels(x0: int, y0: int, x1: int, y1: int) -> void:
	var w := _sdf_image.get_width()
	var h := _sdf_image.get_height()
	for j in range(maxi(y0, 0), mini(y1, h)):
		for i in range(maxi(x0, 0), mini(x1, w)):
			var p := sdf_rect.position + Vector2((i + 0.5) / w, (j + 0.5) / h) * sdf_rect.size
			_sdf_image.set_pixel(i, j, Color(ground_sdf(p), island_sdf(p), 0.0))


func _update_sdf_texels(rect: Rect2) -> void:
	if not _sdf_image:
		return
	var sz := Vector2(_sdf_image.get_size())
	var a := ((rect.position - sdf_rect.position) / sdf_rect.size * sz).floor()
	var b := ((rect.end - sdf_rect.position) / sdf_rect.size * sz).ceil()
	_fill_sdf_texels(int(a.x) - 1, int(a.y) - 1, int(b.x) + 1, int(b.y) + 1)
	sdf_texture.update(_sdf_image)
