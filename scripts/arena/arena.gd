@tool
class_name Arena
extends Node3D
## Procedural floating-island arena.
##
## The walkable ground is described analytically: an organic island outline, minus runtime
## holes, raised by runtime mounds (bump -> hill -> mountain). Static geometry is built once
## per layout; everything that changes during play is cheap data:
##
##  * Grass top: a marching-squares mesh of the island outline only (chunked for culling).
##    Its vertices are lifted by the mounds in the vertex shader, and fragments over a hole
##    are discarded, both from a tiny "features" texture (one texel row per hole/mound
##    parameter set) shared by every terrain and grass shader.
##  * Holes: each hole owns a small rocky wall tube, built once when it opens and simply
##    scaled while it opens/closes. Its top follows the mound height in the shader.
##  * Collision: a grid of HeightMapShape3D chunks (heights from the mounds, NaN = real gap
##    over holes and off the island). A changing hole or mound only re-samples the few
##    hundred grid points it covers.
##  * One watertight outer shell (cliff + rocky underside), and an island SDF texture.
##
## Endless mode (`endless`, single-player survival): no island and no edge, flat ground that
## goes on forever. The grass top, collision chunks and holes are streamed around `focus`
## (the player): a fixed set of flat ground chunks is moved along, collision chunks are
## recycled as they leave the window, and holes are generated per world cell from a hash of
## the cell, so the same place always has the same holes.
##
## So opening or closing a hole costs a texel upload, a node scale and a few hundred height
## samples per tick, instead of re-meshing terrain. `ground_sdf()` / `height_at()` mirror the
## shader math exactly for gameplay, AI and spell targeting.
## @tool: editing the ArenaConfig resource updates the editor view.

signal rebuilt
## A hole finished opening (scale reached 1) or closing (removed / scale 0).
signal hole_opened(hole: Dictionary)
signal hole_closed(hole: Dictionary)
## Ground heights changed inside `rect` (world XZ): props follow the mounds.
signal ground_changed(rect: Rect2)
## A mound finished growing to its new level.
signal mound_raised(mound: Dictionary)
## The set of ponds changed (endless field streaming).
signal ponds_changed

const LAYER_FLOOR := 1
const LAYER_WALLS := 2
const LAYER_OBSTACLES := 4
const LAYER_CHARACTERS := 8
## Marching-squares cells per top-mesh chunk side.
const CHUNK_CELLS := 24
## Collision heightfield: sample spacing (world units) and cells per chunk side (17x17
## samples per HeightMapShape3D: square and 2^n + 1, and small so a change rebuilds little).
const HM_SPACING := 0.2
const HM_CHUNK := 16
## Slots in the shader features texture.
const MAX_HOLES := 64
const MAX_MOUNDS := 48
const MAX_PONDS := 8
## Height of every pond's water surface (the lawn is at 0).
const WATER_LEVEL := -0.12
## Beyond this distance from its rim a hole does not need its exact outline (see ground_sdf).
const FAR_HOLE := 1.5
## Mound levels (radius, height, sharpness): a bump you can walk over, a hill, then a steep
## rocky mountain that blocks movement and bolts.
const MOUND_LEVELS: Array[Vector3] = [Vector3(1.25, 0.5, 0.0), Vector3(2.1, 1.25, 0.05), Vector3(2.5, 2.9, 0.8)]
const MOUND_GROW_TIME := 0.45
## Mounds flatten out between these distances inside the island edge (cliff top stays flat).
const ISLAND_FADE := Vector2(0.4, 2.2)
## Collision is removed where the ground SDF exceeds this (holes / off the island). Slightly
## positive because a NaN sample removes every collision triangle touching it.
const GAP_SDF := 0.15

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

## Endless field instead of an island (see class doc). Set it, then call rebuild().
var endless := false
## Endless mode: world point (x, z) the streamed ground is centred on.
var focus := Vector2.ZERO
## Endless mode: fixed world seed (story mode: the same world every time), or -1 for random.
var endless_seed := -1
## Endless mode: circles (x, z, radius) kept free of holes, ponds and props (story shrines).
var clear_zones: Array[Vector3] = []
## The layout actually built (config scaled / randomized). Read this, not `config`.
var layout: ArenaConfig
var layout_seed := 0
var sdf_texture: ImageTexture
var sdf_rect := Rect2()
## Solid prop footprints (x, z, radius), filled by Props; used by grass placement and the AI.
var obstacles: Array[Vector3] = []
## Small decorations (x, z, radius) that only keep grass away.
var decor_footprints: Array[Vector3] = []
## Runtime holes: { id, center: Vector2, radius, scale (0..1 shown), target (0 or 1),
## duration (s for a full open/close), ph0, ph1 (outline wobble phases), dynamic: bool }.
var holes: Array[Dictionary] = []
## Runtime mounds: { id, center, radius, height, sharp, level, ph0, ph1, from, to: Vector3
## (radius, height, sharp), t (growth 0..1) }. A ridge also has `end`: its height then
## depends on the distance to the segment center-end instead of to the center.
var mounds: Array[Dictionary] = []
## Ponds: { id, center: Vector2, radius, depth, ph0, ph1 } (static per island layout,
## streamed in the endless field). A pond is a bowl dug into the ground (`pond_dip`), filled
## with water up to WATER_LEVEL.
var ponds: Array[Dictionary] = []

var _rebuild_queued := false
var _phase := PackedFloat32Array()
var _next_id := 0
var _rng := RandomNumberGenerator.new()
# Top mesh marching-squares grid.
var _cs := 0.2
var _origin := Vector2.ZERO
var _nx := 0
var _nz := 0
var _vals := PackedFloat32Array()
var _sdf_image: Image
# Shader features (holes + mounds).
var _features_image: Image
var _features_texture: ImageTexture
var _features_dirty := false
var _walls := {}
# Collision heightfield.
var _hm_origin := Vector2.ZERO
var _hm_cells := Vector2i.ZERO
var _hm_island := PackedFloat32Array()
var _hm_fade := PackedFloat32Array()
var _hm_pond := PackedFloat32Array()
var _hm_shapes := {}
var _hm_data := {}
var _collision_dirty := Rect2()
var _has_collision_dirty := false
var _mound_dirty := Rect2()
var _has_mound_dirty := false
var _mound_tick := false


func _ready() -> void:
	rebuild()


func _queue_rebuild() -> void:
	if _rebuild_queued or not is_inside_tree():
		return
	_rebuild_queued = true
	(func():
		_rebuild_queued = false
		rebuild()).call_deferred()


# ---------------------------------------------------------------- distance field / height

func island_sdf(p: Vector2) -> float:
	if endless:
		return -1000.0
	var r := layout.radius
	var a := atan2(p.y, p.x)
	var w := layout.edge_wobble * (0.55 * sin(3.0 * a + _phase[0]) + 0.3 * sin(5.0 * a + _phase[1]) + 0.15 * sin(9.0 * a + _phase[2]))
	var l := (p / r).length()
	if l < 0.0001:
		return -minf(r.x, r.y)
	# Radial distance to the ellipse along the ray from the centre.
	return p.length() * (1.0 - 1.0 / l) - w


## Signed distance to a hole's (wobbly, scaled) outline: negative inside the hole.
## Same formula as `arena_hole_dist` in toon.gdshaderinc.
func hole_sdf(p: Vector2, h: Dictionary) -> float:
	var d: Vector2 = p - h.center
	var a := atan2(d.y, d.x)
	var r: float = (h.radius + layout.hole_wobble * (0.6 * sin(3.0 * a + h.ph0) + 0.4 * sin(5.0 * a + h.ph1))) * h.scale
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
		var reach: float = (h.radius + layout.hole_wobble) * h.scale + FAR_HOLE
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


## Ground height at `p` (0 = the flat lawn): mounds (flattened near the island edge) plus
## pond bowls. Same formula as `arena_height` in the shaders.
func height_at(p: Vector2) -> float:
	var dip := pond_dip(p)
	if mounds.is_empty():
		return dip
	var best := 0.0
	for m in mounds:
		best = maxf(best, _mound_value(p, m))
	if best <= 0.0:
		return dip
	return best * smoothstep(ISLAND_FADE.x, ISLAND_FADE.y, -island_sdf(p)) + dip


## How far the ponds lower the ground at `p` (<= 0).
func pond_dip(p: Vector2) -> float:
	var dip := 0.0
	for q in ponds:
		dip = minf(dip, _pond_value(p, q))
	return dip


## Water depth at `p` (0 on dry ground).
func water_depth(p: Vector2) -> float:
	if ponds.is_empty() or pond_dip(p) >= 0.0:
		return 0.0
	return maxf(WATER_LEVEL - height_at(p), 0.0)


## Bowl profile: flat bed out to 55% of the (wobbly) radius, then a smooth shore up to the
## lawn. Same formula as in toon.gdshaderinc.
func _pond_value(p: Vector2, q: Dictionary) -> float:
	var d: Vector2 = p - q.center
	var r: float = q.radius
	var l2 := d.length_squared()
	if l2 >= r * r * 1.3:
		return 0.0
	var a := atan2(d.y, d.x)
	var x := sqrt(l2) / (r * (1.0 + 0.08 * sin(3.0 * a + q.ph0) + 0.05 * sin(5.0 * a + q.ph1)))
	if x >= 1.0:
		return 0.0
	return -q.depth * (1.0 - smoothstep(0.55, 1.0, x))


## Ground slope at `p` as (dh/dx, dh/dz).
func height_gradient(p: Vector2) -> Vector2:
	var e := 0.06
	return Vector2(height_at(p + Vector2(e, 0)) - height_at(p - Vector2(e, 0)),
		height_at(p + Vector2(0, e)) - height_at(p - Vector2(0, e))) / (2.0 * e)


## `p` relative to the nearest point of mound `m`'s spine (its center, or the segment
## center-end of a ridge).
func mound_offset(p: Vector2, m: Dictionary) -> Vector2:
	if not m.has("end"):
		return p - m.center
	var a: Vector2 = m.center
	var ab: Vector2 = m.end - a
	var l2 := ab.length_squared()
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0) if l2 > 1e-6 else 0.0
	return p - (a + ab * t)


func _mound_value(p: Vector2, m: Dictionary) -> float:
	var d: Vector2 = mound_offset(p, m)
	var r: float = m.radius
	var l2 := d.length_squared()
	if m.height <= 0.0 or l2 >= r * r * 1.3689: # (1.17 r)^2: max outline wobble
		return 0.0
	var a := atan2(d.y, d.x)
	var rr := r * (1.0 + 0.1 * sin(3.0 * a + m.ph0) + 0.06 * sin(5.0 * a + m.ph1))
	var x := sqrt(l2) / rr
	if x >= 1.0:
		return 0.0
	var smooth := (1.0 - x * x) * (1.0 - x * x)
	var peak := pow(1.0 - x, 1.5)
	return m.height * lerpf(smooth, peak, m.sharp)


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
func open_hole(center: Vector2, radius: float, duration := 0.3) -> int:
	if not can_open_hole(center, radius) or holes.size() >= MAX_HOLES:
		return -1
	var h := _add_hole(center, radius, 0.0, true, _rng.randf() * TAU, _rng.randf() * TAU)
	h.target = 1.0
	h.duration = duration
	return h.id


## Starts closing hole `id`; returns false if there is no such open hole.
func close_hole(id: int, duration := 0.4) -> bool:
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


## The hole whose current outline contains `p`; {} if none.
func hole_at(p: Vector2) -> Dictionary:
	for h in holes:
		if h.scale > 0.02 and hole_sdf(p, h) < 0.0:
			return h
	return {}


## Brings the ground back to the layout: spell holes vanish, closed ones reopen, mounds
## flatten. Instant (new round).
func reset_ground() -> void:
	for h in holes:
		if h.dynamic:
			_free_wall(h.id)
	holes = holes.filter(func(h): return not h.dynamic)
	for h in holes:
		h.scale = 1.0
		h.target = 1.0
		_update_wall(h)
	var had_mounds := not mounds.is_empty()
	mounds.clear()
	_features_dirty = true
	_upload_features()
	_refresh_collision(Rect2(_hm_origin, Vector2(_hm_cells) * HM_SPACING))
	if had_mounds:
		ground_changed.emit(sdf_rect)
	# Decorations moved by spells (a swapped flower) go back where they were.
	var props := get_node_or_null("Props")
	if props and props.has_method("restore_decor"):
		props.restore_decor()


func _add_hole(center: Vector2, radius: float, scale: float, dynamic: bool, ph0: float, ph1: float) -> Dictionary:
	var h := {"id": _next_id, "center": center, "radius": radius, "scale": scale,
		"target": scale, "duration": 0.4, "ph0": ph0, "ph1": ph1, "dynamic": dynamic}
	_next_id += 1
	holes.append(h)
	var wall := _build_hole_wall(h)
	_walls[h.id] = wall
	_add_generated(wall)
	_update_wall(h)
	_features_dirty = true
	_mark_collision(_hole_rect(h))
	return h


func _hole_rect(h: Dictionary) -> Rect2:
	var r: float = h.radius + layout.hole_wobble + 0.3
	return Rect2(h.center - Vector2(r, r), Vector2(r, r) * 2.0)


func _update_wall(h: Dictionary) -> void:
	var wall: MeshInstance3D = _walls.get(h.id)
	if wall:
		wall.visible = h.scale > 0.02
		wall.scale = Vector3(maxf(h.scale, 0.01), 1.0, maxf(h.scale, 0.01))


func _free_wall(id: int) -> void:
	var wall: Node = _walls.get(id)
	if wall:
		wall.queue_free()
	_walls.erase(id)


# ---------------------------------------------------------------- runtime mounds

## Raises the ground around `p`: a new bump, or the next level (hill, mountain) of the mound
## already there. Returns {"mound": m} or {"error": reason}.
func raise_ground(p: Vector2) -> Dictionary:
	for m in mounds:
		if m.center.distance_to(p) < maxf(m.radius * 0.8, 1.0):
			return grow_mound(m)
	if island_sdf(p) > -(MOUND_LEVELS[0].x + 0.8):
		return {"error": "too close to the edge"}
	if mounds.size() >= MAX_MOUNDS:
		return {"error": "no room"}
	var m := {"id": _next_id, "center": p, "radius": 0.0, "height": 0.0, "sharp": 0.0, "level": 0,
		"ph0": _rng.randf() * TAU, "ph1": _rng.randf() * TAU, "from": Vector3.ZERO, "to": Vector3.ZERO, "t": 1.0}
	_next_id += 1
	mounds.append(m)
	_grow(m)
	return {"mound": m}


## A short-lived mound at `p` (never merged with others): rises to `level` (1 bump, 2 hill)
## in `rise` seconds, stays `hold` seconds, then sinks back in `sink` seconds and is removed.
## The Push beam's travelling ridge is made of these. Returns the mound, or {} if full.
func raise_temporary(p: Vector2, level: int, rise: float, hold: float, sink: float) -> Dictionary:
	if mounds.size() >= MAX_MOUNDS:
		return {}
	var m := {"id": _next_id, "center": p, "radius": 0.0, "height": 0.0, "sharp": 0.0, "level": 0,
		"ph0": _rng.randf() * TAU, "ph1": _rng.randf() * TAU, "from": Vector3.ZERO, "to": Vector3.ZERO, "t": 1.0,
		"dur": rise, "hold": hold, "sink": sink}
	_next_id += 1
	mounds.append(m)
	for k in clampi(level, 1, MOUND_LEVELS.size()):
		_grow(m)
	return m


## Like raise_temporary, but a ridge: a long mound along the segment p-p (stretch it with
## set_ridge_end). The Push beam raises one along each side of its path.
func raise_ridge(p: Vector2, level: int, rise: float, hold: float, sink: float) -> Dictionary:
	var m := raise_temporary(p, level, rise, hold, sink)
	if not m.is_empty():
		m.end = p
	return m


## Moves the far end of ridge `m` (its collision and look follow).
func set_ridge_end(m: Dictionary, end: Vector2) -> void:
	var before := _mound_rect(m)
	m.end = end
	var r := before.merge(_mound_rect(m))
	_mound_dirty = r if not _has_mound_dirty else _mound_dirty.merge(r)
	_has_mound_dirty = true
	_features_dirty = true
	ground_changed.emit(r)


## Grows mound `m` to its next level. Returns {"mound": m} or {"error": reason}.
func grow_mound(m: Dictionary) -> Dictionary:
	if m.level >= MOUND_LEVELS.size():
		return {"error": "already a mountain"}
	_grow(m)
	return {"mound": m}


func _grow(m: Dictionary) -> void:
	m.from = Vector3(m.radius, m.height, m.sharp)
	m.to = MOUND_LEVELS[m.level]
	m.level += 1
	m.t = 0.0


## Sinks mound `m` one level (mountain -> hill -> bump -> flat; a flattened mound is removed
## once it has settled). Returns {"mound": m} or {"error": reason}.
func lower_mound(m: Dictionary) -> Dictionary:
	if m.level <= 0:
		return {"error": "already flat"}
	m.from = Vector3(m.radius, m.height, m.sharp)
	m.level -= 1
	m.to = MOUND_LEVELS[m.level - 1] if m.level > 0 else Vector3(m.radius, 0.0, 0.0)
	m.t = 0.0
	return {"mound": m}


func _mound_rect(m: Dictionary) -> Rect2:
	var r: float = maxf(maxf(m.radius, m.to.x), m.from.x) * 1.17 + HM_SPACING
	var rect := Rect2(m.center - Vector2(r, r), Vector2(r, r) * 2.0)
	if m.has("end"):
		rect = rect.merge(Rect2(m.end - Vector2(r, r), Vector2(r, r) * 2.0))
	return rect


# ---------------------------------------------------------------- animation

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var finished: Array[Dictionary] = []
	for h in holes:
		if is_equal_approx(h.scale, h.target):
			continue
		h.scale = move_toward(h.scale, h.target, delta / maxf(h.duration, 0.01))
		_update_wall(h)
		_mark_collision(_hole_rect(h))
		_features_dirty = true
		if is_equal_approx(h.scale, h.target):
			finished.append(h)
	for h in finished:
		if h.target <= 0.0:
			# Layout holes stay listed (hidden) so a new round can reopen them.
			if h.dynamic:
				_free_wall(h.id)
				holes.erase(h)
			hole_closed.emit(h)
		else:
			hole_opened.emit(h)
	var grown_rect := Rect2()
	var grew := false
	var flattened: Array[Dictionary] = []
	for m in mounds:
		if m.t >= 1.0:
			# A temporary mound that has risen waits, then sinks away.
			if m.has("hold") and m.level > 0:
				m.hold -= delta
				if m.hold <= 0.0:
					m.dur = m.sink
					m.level = 1
					lower_mound(m)
			continue
		m.t = minf(m.t + delta / m.get("dur", MOUND_GROW_TIME), 1.0)
		# Rising overshoots a little, like earth heaving up and settling; sinking doesn't.
		var e := 1.0 - pow(1.0 - m.t, 3.0)
		if m.to.y > m.from.y:
			e += sin(m.t * PI) * 0.12
		var v: Vector3 = m.from.lerp(m.to, e)
		m.radius = maxf(v.x, 0.0)
		m.height = maxf(v.y, 0.0)
		m.sharp = clampf(v.z, 0.0, 1.0)
		var r := _mound_rect(m)
		grown_rect = r if not grew else grown_rect.merge(r)
		grew = true
		_features_dirty = true
		if m.t >= 1.0:
			if m.level <= 0:
				flattened.append(m)
			mound_raised.emit(m)
	for m in flattened:
		mounds.erase(m)
	if grew:
		_mound_dirty = grown_rect if not _has_mound_dirty else _mound_dirty.merge(grown_rect)
		_has_mound_dirty = true
		ground_changed.emit(grown_rect)
	if _features_dirty:
		_upload_features()


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if endless:
		_stream()
	# Growing mounds update collision at half the physics rate; the last step always lands.
	_mound_tick = not _mound_tick
	if _has_mound_dirty and (_mound_tick or not _any_mound_growing()):
		_has_mound_dirty = false
		_mark_collision(_mound_dirty)
	if _has_collision_dirty:
		_has_collision_dirty = false
		_refresh_collision(_collision_dirty)


func _any_mound_growing() -> bool:
	for m in mounds:
		if m.t < 1.0:
			return true
	return false


func _mark_collision(rect: Rect2) -> void:
	_collision_dirty = rect if not _has_collision_dirty else _collision_dirty.merge(rect)
	_has_collision_dirty = true


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
	if endless:
		_rebuild_endless()
		return
	var randomized := config.randomize_layout and not Engine.is_editor_hint()
	layout_seed = randi() if randomized else config.seed
	_rng.seed = layout_seed
	layout = ArenaLayout.shape(config, _rng, randomized)
	_phase.resize(8)
	for i in _phase.size():
		_phase[i] = _rng.randf() * TAU
	ArenaLayout.populate(layout, config, _rng, randomized, island_sdf)
	if randomized:
		print("Arena layout seed: %d" % layout_seed)

	for c in get_children():
		if c.has_meta("generated"):
			remove_child(c)
			c.queue_free()
	if not has_node("Water") and not Engine.is_editor_hint():
		var water := Water.new()
		water.name = "Water"
		add_child(water)
	holes.clear()
	mounds.clear()
	_walls.clear()
	ponds.clear()
	for q in layout.ponds:
		ponds.append({"id": _next_id, "center": Vector2(q.x, q.y), "radius": q.z, "depth": layout.pond_depth,
			"ph0": _rng.randf() * TAU, "ph1": _rng.randf() * TAU})
		_next_id += 1
	_init_features()
	_bake_sdf_texture()

	# Grass top: marching squares over the island outline only (holes are cut by shaders).
	_cs = layout.cell_size
	var ext := layout.radius + Vector2(layout.edge_wobble + 0.6, layout.edge_wobble + 0.6)
	_nx = int(ceil(ext.x * 2.0 / _cs))
	_nz = int(ceil(ext.y * 2.0 / _cs))
	_origin = -Vector2(_nx, _nz) * _cs * 0.5
	_vals.resize((_nx + 1) * (_nz + 1))
	for j in _nz + 1:
		for i in _nx + 1:
			_vals[j * (_nx + 1) + i] = island_sdf(_origin + Vector2(i, j) * _cs)
	var outline_segments: Array[PackedVector2Array] = []
	for cj in ceili(float(_nz) / CHUNK_CELLS):
		for ci in ceili(float(_nx) / CHUNK_CELLS):
			_build_top_chunk(Vector2i(ci, cj), outline_segments)

	# The island outline (largest loop) becomes the outer shell.
	var loops := _chain_loops(outline_segments)
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

	for hv in layout.holes:
		_add_hole(Vector2(hv.x, hv.y), hv.z, 1.0, false, _rng.randf() * TAU, _rng.randf() * TAU)
	_upload_features()
	_build_collision()

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


## One chunk of the grass top. UV2 = (1, 1): fully lifted by mounds, top surface.
func _build_top_chunk(c: Vector2i, outline_segments: Array[PackedVector2Array]) -> void:
	var top := PackedVector3Array()
	_march_cells(c.x * CHUNK_CELLS, c.y * CHUNK_CELLS, mini((c.x + 1) * CHUNK_CELLS, _nx),
		mini((c.y + 1) * CHUNK_CELLS, _nz), top, outline_segments)
	if top.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = top
	arrays[Mesh.ARRAY_NORMAL] = _filled3(top.size(), Vector3.UP)
	var uv2 := PackedVector2Array()
	uv2.resize(top.size())
	uv2.fill(Vector2.ONE)
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, terrain_material)
	var mi := MeshInstance3D.new()
	mi.name = "Top_%d_%d" % [c.x, c.y]
	mi.mesh = mesh
	# Mounds lift vertices in the shader: make culling and shadows aware of it.
	var aabb := mesh.get_aabb()
	mi.custom_aabb = AABB(Vector3(aabb.position.x, -0.5, aabb.position.z), Vector3(aabb.size.x, MOUND_LEVELS[-1].y + 1.0, aabb.size.z))
	_add_generated(mi)


static func _filled3(count: int, v: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(count)
	out.fill(v)
	return out


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
	var t := layout.thickness
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
	var t0 := layout.thickness
	var depth := layout.underside_depth
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
	# Follow weight (UV2.x, see terrain.gdshader): the cliff's top rows dip with the ground
	# where a pond reaches the edge (mounds are flattened there anyway), fading out 0.8 down.
	for ring in rings:
		for v in ring:
			st.set_uv2(Vector2(clampf(1.0 + v.y / 0.8, 0.0, 1.0), 0.0))
			st.add_vertex(v)
	st.set_uv2(Vector2.ZERO)
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


## A hole's wall: layered earth rows hanging from its outline (at full size, in the hole's
## local space; the node is scaled on XZ while the hole opens/closes). UV2.x = how much each
## row follows the mound height (1 at the rim, 0 at the bottom), so a hole dug through a
## hill keeps a continuous wall. Faces point toward the hole's centre.
func _build_hole_wall(h: Dictionary) -> MeshInstance3D:
	var rows := _wall_rows(false)
	var t := layout.thickness
	var n := clampi(int(TAU * (h.radius + layout.hole_wobble) / 0.1), 24, 128)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c: Vector2 = h.center
	var reach := 0.0
	for r in rows.size():
		for i in n:
			var a := TAU * i / n
			var dir := Vector2(cos(a), sin(a))
			var rim: float = h.radius + layout.hole_wobble * (0.6 * sin(3.0 * a + h.ph0) + 0.4 * sin(5.0 * a + h.ph1))
			var p := _wall_point(c + dir * rim, -dir, rows[r], r, false)
			var local := Vector3(p.x - c.x, p.y, p.z - c.y)
			reach = maxf(reach, Vector2(local.x, local.z).length())
			st.set_uv2(Vector2(1.0 - rows[r].x / t, 0.0))
			st.add_vertex(local)
	# Same winding rule as the outer shell, facing inward.
	var v0 := _wall_point(c + Vector2(h.radius, 0), Vector2.LEFT, rows[0], 0, false)
	var a1 := TAU / n
	var v1 := _wall_point(c + Vector2(cos(a1), sin(a1)) * h.radius, -Vector2(cos(a1), sin(a1)), rows[0], 0, false)
	var v2 := _wall_point(c + Vector2(cos(a1), sin(a1)) * h.radius, -Vector2(cos(a1), sin(a1)), rows[1], 1, false)
	var flip := (v1 - v0).cross(v2 - v0).dot(Vector3(-1, 0, 0)) < 0.0
	for r in rows.size() - 1:
		for i in n:
			var ia := r * n + i
			var ib := r * n + (i + 1) % n
			_tri_indexed(st, ia, ib, ib + n, flip)
			_tri_indexed(st, ia, ib + n, ia + n, flip)
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, terrain_material)
	var mi := MeshInstance3D.new()
	mi.name = "HoleWall_%d" % h.id
	mi.mesh = mesh
	mi.position = Vector3(c.x, 0.0, c.y)
	mi.custom_aabb = AABB(Vector3(-reach, -t - 0.3, -reach), Vector3(reach * 2.0, t + MOUND_LEVELS[-1].y + 0.6, reach * 2.0))
	mi.set_instance_shader_parameter("self_hole_id", float(h.id))
	return mi


# ---------------------------------------------------------------- collision heightfield

func _build_collision() -> void:
	var ext := layout.radius + Vector2(layout.edge_wobble + 0.6, layout.edge_wobble + 0.6)
	var cells := (ext * 2.0 / HM_SPACING).ceil()
	_hm_cells = Vector2i(ceili(cells.x / HM_CHUNK) * HM_CHUNK, ceili(cells.y / HM_CHUNK) * HM_CHUNK)
	_hm_origin = -Vector2(_hm_cells) * HM_SPACING * 0.5
	# The island outline never changes: cache its distance (and the mound fade) per sample.
	var w := _hm_cells.x + 1
	_hm_island.resize(w * (_hm_cells.y + 1))
	_hm_fade.resize(_hm_island.size())
	_hm_pond.resize(_hm_island.size())
	for j in _hm_cells.y + 1:
		for i in w:
			var p := _hm_origin + Vector2(i, j) * HM_SPACING
			var d := island_sdf(p)
			_hm_island[j * w + i] = d
			_hm_fade[j * w + i] = smoothstep(ISLAND_FADE.x, ISLAND_FADE.y, -d)
			_hm_pond[j * w + i] = pond_dip(p)
	_hm_shapes.clear()
	_hm_data.clear()
	var half := HM_CHUNK / 2
	var empty := PackedFloat32Array()
	empty.resize((HM_CHUNK + 1) * (HM_CHUNK + 1))
	for cj in _hm_cells.y / HM_CHUNK:
		for ci in _hm_cells.x / HM_CHUNK:
			var body := StaticBody3D.new()
			body.name = "Floor_%d_%d" % [ci, cj]
			body.collision_layer = LAYER_FLOOR
			body.collision_mask = 0
			var shape := HeightMapShape3D.new()
			shape.map_width = HM_CHUNK + 1
			shape.map_depth = HM_CHUNK + 1
			var cs := CollisionShape3D.new()
			cs.shape = shape
			# Uniform scale (heights are stored pre-divided): supported by every backend.
			cs.scale = Vector3.ONE * HM_SPACING
			var o := _hm_origin + Vector2(ci * HM_CHUNK + half, cj * HM_CHUNK + half) * HM_SPACING
			cs.position = Vector3(o.x, 0.0, o.y)
			body.add_child(cs)
			_add_generated(body)
			_hm_shapes[Vector2i(ci, cj)] = shape
			_hm_data[Vector2i(ci, cj)] = empty.duplicate()
	_has_collision_dirty = false
	_refresh_collision(Rect2(_hm_origin, Vector2(_hm_cells) * HM_SPACING))


## Re-samples the heightfield inside `rect` and re-uploads the chunks it touches. Each
## sample is: NaN (a real gap) where the ground SDF exceeds GAP_SDF, else the mound height.
## Only holes and mounds that reach `rect` are evaluated; the island part is cached.
func _refresh_collision(rect: Rect2) -> void:
	if endless:
		_endless_refresh_collision(rect)
		return
	if _hm_shapes.is_empty():
		return
	var i0 := clampi(floori((rect.position.x - _hm_origin.x) / HM_SPACING), 0, _hm_cells.x)
	var j0 := clampi(floori((rect.position.y - _hm_origin.y) / HM_SPACING), 0, _hm_cells.y)
	var i1 := clampi(ceili((rect.end.x - _hm_origin.x) / HM_SPACING), 0, _hm_cells.x)
	var j1 := clampi(ceili((rect.end.y - _hm_origin.y) / HM_SPACING), 0, _hm_cells.y)
	# Only the sign of (ground SDF - GAP_SDF) matters here, so a hole is skipped for every
	# sample farther than its outer rim + GAP_SDF (no trig).
	var near_holes: Array[Dictionary] = []
	var hole_reach := PackedFloat32Array()
	for h in holes:
		var reach: float = (h.radius + layout.hole_wobble) * h.scale + GAP_SDF
		if h.scale > 0.02 and rect.grow(reach).has_point(h.center):
			near_holes.append(h)
			hole_reach.append(reach * reach)
	# Per mound: [cached distances, origin i, origin j, width, height, 1/radius, height, sharp]
	# (plain locals in the hot loop: GDScript dictionary lookups are slow).
	var near_mounds: Array[Array] = []
	# Ridges (long mounds) change shape as they stretch: no distance cache, evaluated directly.
	var near_ridges: Array[Dictionary] = []
	for m in mounds:
		if m.has("end"):
			if m.height > 0.0 and _mound_rect(m).intersects(rect):
				near_ridges.append(m)
			continue
		if m.height > 0.0 and m.radius > 0.0 and rect.grow(m.radius * 1.17).has_point(m.center):
			var cache := _mound_cache(m)
			var a0: Vector2i = cache.a0
			var size: Vector2i = cache.size
			near_mounds.append([cache.dist, a0.x, a0.y, size.x, size.y, 1.0 / m.radius, m.height, m.sharp])
	var w := _hm_cells.x + 1
	var inv := 1.0 / HM_SPACING
	var n := HM_CHUNK + 1
	var c0 := Vector2i(maxi((i0 - 1) / HM_CHUNK, 0), maxi((j0 - 1) / HM_CHUNK, 0))
	var c1 := Vector2i(mini(i1 / HM_CHUNK, _hm_cells.x / HM_CHUNK - 1), mini(j1 / HM_CHUNK, _hm_cells.y / HM_CHUNK - 1))
	for cj in range(c0.y, c1.y + 1):
		for ci in range(c0.x, c1.x + 1):
			var c := Vector2i(ci, cj)
			var data: PackedFloat32Array = _hm_data[c]
			var bi := ci * HM_CHUNK
			var bj := cj * HM_CHUNK
			# Samples on chunk borders are evaluated once per chunk sharing them (cheap).
			for j in range(maxi(j0, bj), mini(j1, bj + HM_CHUNK) + 1):
				for i in range(maxi(i0, bi), mini(i1, bi + HM_CHUNK) + 1):
					var k := j * w + i
					var d := _hm_island[k]
					if not near_holes.is_empty():
						var p := _hm_origin + Vector2(i, j) * HM_SPACING
						for hi in near_holes.size():
							if d > GAP_SDF:
								break
							if p.distance_squared_to(near_holes[hi].center) < hole_reach[hi]:
								d = maxf(d, -hole_sdf(p, near_holes[hi]))
					var v := NAN
					if d <= GAP_SDF:
						var best := 0.0
						for md in near_mounds:
							var li: int = i - md[1]
							var lj: int = j - md[2]
							if li < 0 or lj < 0 or li >= md[3] or lj >= md[4]:
								continue
							var x: float = md[0][lj * md[3] + li] * md[5]
							if x < 1.0:
								var sm := (1.0 - x * x) * (1.0 - x * x)
								best = maxf(best, md[6] * lerpf(sm, (1.0 - x) * sqrt(1.0 - x), md[7]))
						if not near_ridges.is_empty():
							var p := _hm_origin + Vector2(i, j) * HM_SPACING
							for rm in near_ridges:
								best = maxf(best, _mound_value(p, rm))
						v = (best * _hm_fade[k] + _hm_pond[k]) * inv
					data[(j - bj) * n + (i - bi)] = v
			_hm_data[c] = data
			(_hm_shapes[c] as HeightMapShape3D).map_data = data


## Per heightfield sample around mound `m`: its distance to the centre divided by the
## outline wobble at that angle. While a mound grows only its scale changes, so this is
## computed once per level and growth steps only need x = dist / radius.
func _mound_cache(m: Dictionary) -> Dictionary:
	var cache: Dictionary = m.get("cache", {})
	if cache.get("level", -1) == m.level:
		return cache
	# Covers the largest outline of this level, overshoot included.
	var reach: float = maxf(m.to.x, m.radius) * 1.17 * 1.15 + HM_SPACING
	var a0 := Vector2i(floori((m.center.x - reach - _hm_origin.x) / HM_SPACING), floori((m.center.y - reach - _hm_origin.y) / HM_SPACING))
	var size := Vector2i(ceili(reach * 2.0 / HM_SPACING) + 2, ceili(reach * 2.0 / HM_SPACING) + 2)
	var dist := PackedFloat32Array()
	dist.resize(size.x * size.y)
	for cj in size.y:
		for ci in size.x:
			var d: Vector2 = _hm_origin + Vector2(a0.x + ci, a0.y + cj) * HM_SPACING - m.center
			var a := atan2(d.y, d.x)
			dist[cj * size.x + ci] = d.length() / (1.0 + 0.1 * sin(3.0 * a + m.ph0) + 0.06 * sin(5.0 * a + m.ph1))
	cache = {"level": m.level, "a0": a0, "size": size, "dist": dist}
	m.cache = cache
	return cache


# ---------------------------------------------------------------- shader data

## Holes and mounds for the shaders (see toon.gdshaderinc): one texel per item per row.
##   row 0: hole (center.x, center.z, radius, scale)   row 1: (ph0, ph1, wobble, id)
##   row 2: mound (center.x, center.z, radius, height) row 3: (ph0, ph1, sharpness, 0)
##   row 4: pond (center.x, center.z, radius, depth)   row 5: (ph0, ph1, 0, 0)
##   row 6: mound spine end (end.x, end.z, 0, 0): a ridge's far end, else its center
func _init_features() -> void:
	_features_image = Image.create_empty(maxi(MAX_HOLES, MAX_MOUNDS), 7, false, Image.FORMAT_RGBAF)
	_features_texture = ImageTexture.create_from_image(_features_image)
	RenderingServer.global_shader_parameter_set("arena_features", _features_texture)
	_features_dirty = true


func _upload_features() -> void:
	_features_dirty = false
	if not _features_image:
		return
	var nh := mini(holes.size(), MAX_HOLES)
	for i in nh:
		var h := holes[i]
		_features_image.set_pixel(i, 0, Color(h.center.x, h.center.y, h.radius, h.scale))
		_features_image.set_pixel(i, 1, Color(h.ph0, h.ph1, layout.hole_wobble, h.id))
	var nm := mini(mounds.size(), MAX_MOUNDS)
	for i in nm:
		var m := mounds[i]
		_features_image.set_pixel(i, 2, Color(m.center.x, m.center.y, m.radius, m.height))
		_features_image.set_pixel(i, 3, Color(m.ph0, m.ph1, m.sharp, 0.0))
		var e: Vector2 = m.get("end", m.center)
		_features_image.set_pixel(i, 6, Color(e.x, e.y, 0.0, 0.0))
	var np := mini(ponds.size(), MAX_PONDS)
	for i in np:
		var q := ponds[i]
		_features_image.set_pixel(i, 4, Color(q.center.x, q.center.y, q.radius, q.depth))
		_features_image.set_pixel(i, 5, Color(q.ph0, q.ph1, 0.0, 0.0))
	_features_texture.update(_features_image)
	RenderingServer.global_shader_parameter_set("arena_pond_count", np)
	RenderingServer.global_shader_parameter_set("arena_hole_count", nh)
	RenderingServer.global_shader_parameter_set("arena_mound_count", nm)
	RenderingServer.global_shader_parameter_set("arena_island_fade", ISLAND_FADE)


## Static island outline distance (R and G), sampled by shaders.
func _bake_sdf_texture() -> void:
	if endless:
		# No outline anywhere: a constant "deep inside" texture (sampling clamps to it).
		_sdf_image = Image.create_empty(2, 2, false, Image.FORMAT_RGF)
		_sdf_image.fill(Color(-1000.0, -1000.0, 0.0))
		sdf_rect = Rect2(-ENDLESS_EXTENT, -ENDLESS_EXTENT, ENDLESS_EXTENT * 2.0, ENDLESS_EXTENT * 2.0)
		sdf_texture = ImageTexture.create_from_image(_sdf_image)
		RenderingServer.global_shader_parameter_set("arena_sdf", sdf_texture)
		RenderingServer.global_shader_parameter_set("arena_sdf_rect", Vector4(sdf_rect.position.x, sdf_rect.position.y, sdf_rect.size.x, sdf_rect.size.y))
		return
	var ext := layout.radius + Vector2(layout.edge_wobble + 1.0, layout.edge_wobble + 1.0)
	var res := 6.0 # texels per unit
	var w := int(ext.x * 2.0 * res)
	var h := int(ext.y * 2.0 * res)
	sdf_rect = Rect2(-ext, ext * 2.0)
	_sdf_image = Image.create_empty(w, h, false, Image.FORMAT_RGF)
	for j in h:
		for i in w:
			var p := sdf_rect.position + Vector2((i + 0.5) / w, (j + 0.5) / h) * sdf_rect.size
			var d := island_sdf(p)
			_sdf_image.set_pixel(i, j, Color(d, d, 0.0))
	sdf_texture = ImageTexture.create_from_image(_sdf_image)
	RenderingServer.global_shader_parameter_set("arena_sdf", sdf_texture)
	RenderingServer.global_shader_parameter_set("arena_sdf_rect", Vector4(sdf_rect.position.x, sdf_rect.position.y, sdf_rect.size.x, sdf_rect.size.y))


# ---------------------------------------------------------------- endless field

## Half-size of the (virtual) endless layout, for code that reads `layout.radius`.
const ENDLESS_EXTENT := 10000.0
## Flat ground chunks: size (world units) and how many per side around the focus.
const GROUND_CHUNK := 10.0
const GROUND_WINDOW := 5
## Collision chunks kept around the focus, per side (each HM_CHUNK * HM_SPACING = 3.2 units).
const COLLISION_WINDOW := 12
## Hole cells: size, and how many cells around the focus have their holes.
const HOLE_CELL := 7.0
const HOLE_RANGE := 2
## No holes or ponds this close to where a run starts.
const SAFE_START := 4.0
## Pond cells: size, chance that one holds a pond, and range (in cells) around the focus.
const POND_CELL := 14.0
const POND_CHANCE := 0.4
const POND_RANGE := 1
## Spell holes and mounds this far from the focus are dropped.
const FORGET_DISTANCE := 40.0

var _ground_chunks: Array[MeshInstance3D] = []
# Collision chunk (absolute chunk coords) -> { body, shape }, and recycled ones.
var _ecol := {}
var _ecol_pool: Array[Dictionary] = []
# Hole cells currently populated (Vector2i -> true), and holes waiting to be added.
var _hole_cells := {}
var _hole_queue: Array[Array] = []
var _pond_cells := {}


func _rebuild_endless() -> void:
	layout_seed = endless_seed if endless_seed >= 0 else randi()
	_rng.seed = layout_seed
	layout = config.duplicate(true) as ArenaConfig
	layout.radius = Vector2(ENDLESS_EXTENT, ENDLESS_EXTENT)
	for list in [layout.holes, layout.ponds, layout.trees, layout.bushes, layout.rocks, layout.stumps,
			layout.mushrooms, layout.dancing_flowers]:
		list.clear()
	layout.spawn_points.assign([Vector2(-1.2, 0.0), Vector2(1.2, 0.0)])
	_phase.resize(8)
	_phase.fill(0.0)
	print("Endless field seed: %d" % layout_seed)
	for c in get_children():
		if c.has_meta("generated"):
			remove_child(c)
			c.queue_free()
	if not has_node("Water"):
		var water := Water.new()
		water.name = "Water"
		add_child(water)
	holes.clear()
	mounds.clear()
	ponds.clear()
	_walls.clear()
	_ground_chunks.clear()
	_ecol.clear()
	_ecol_pool.clear()
	_hole_cells.clear()
	_hole_queue.clear()
	_pond_cells.clear()
	_init_features()
	_bake_sdf_texture()
	# One flat grid mesh, shared by every ground chunk (UV2 = (1, 1): grass top, follows mounds).
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * GROUND_CHUNK
	plane.subdivide_width = int(GROUND_CHUNK / layout.cell_size) - 1
	plane.subdivide_depth = plane.subdivide_width
	var arrays := plane.surface_get_arrays(0)
	var uv2 := PackedVector2Array()
	uv2.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	uv2.fill(Vector2.ONE)
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, terrain_material)
	# Tall enough for mountains lifted in the vertex shader.
	mesh.custom_aabb = AABB(Vector3(-GROUND_CHUNK * 0.5, -1.0, -GROUND_CHUNK * 0.5), Vector3(GROUND_CHUNK, MOUND_LEVELS[-1].y + 2.0, GROUND_CHUNK))
	for k in GROUND_WINDOW * GROUND_WINDOW:
		var mi := MeshInstance3D.new()
		mi.name = "Ground%d" % k
		mi.mesh = mesh
		_add_generated(mi)
		_ground_chunks.append(mi)
	_upload_features()
	obstacles.clear()
	decor_footprints.clear()
	_stream()
	for c in get_children():
		if c.has_method("rebuild_from_arena"):
			c.rebuild_from_arena(self)
	rebuilt.emit()


## Moves the ground chunks along, streams collision chunks and hole cells around `focus`.
func _stream() -> void:
	var gc := Vector2i(floori(focus.x / GROUND_CHUNK), floori(focus.y / GROUND_CHUNK))
	var half := GROUND_WINDOW / 2
	for k in _ground_chunks.size():
		var c := gc + Vector2i(k % GROUND_WINDOW - half, k / GROUND_WINDOW - half)
		_ground_chunks[k].position = Vector3((c.x + 0.5) * GROUND_CHUNK, 0.0, (c.y + 0.5) * GROUND_CHUNK)
	_stream_ponds()
	_stream_holes()
	_stream_collision()


func _stream_holes() -> void:
	var fc := Vector2i(floori(focus.x / HOLE_CELL), floori(focus.y / HOLE_CELL))
	var needed := {}
	for dj in range(-HOLE_RANGE, HOLE_RANGE + 1):
		for di in range(-HOLE_RANGE, HOLE_RANGE + 1):
			needed[fc + Vector2i(di, dj)] = true
	# Cells leaving the window take their holes along; far spell holes and mounds go too.
	var gone := false
	for c in _hole_cells.keys():
		if not needed.has(c):
			_hole_cells.erase(c)
	for i in range(holes.size() - 1, -1, -1):
		var h := holes[i]
		var far: bool = h.has("cell") and not needed.has(h.cell)
		far = far or (h.dynamic and (h.center as Vector2).distance_to(focus) > FORGET_DISTANCE)
		if far:
			_free_wall(h.id)
			holes.remove_at(i)
			# Its collision chunks may still be loaded: they must forget the gap.
			_mark_collision(_hole_rect(h))
			gone = true
	for i in range(mounds.size() - 1, -1, -1):
		if (mounds[i].center as Vector2).distance_to(focus) > FORGET_DISTANCE:
			_mark_collision(_mound_rect(mounds[i]))
			mounds.remove_at(i)
			gone = true
	if gone:
		_features_dirty = true
	_hole_queue = _hole_queue.filter(func(q: Array) -> bool: return needed.has(q[0]))
	for c in needed:
		if not _hole_cells.has(c):
			_hole_cells[c] = true
			for spec in _cell_holes(c):
				_hole_queue.append([c, spec])
	# A few walls per tick (each is a small mesh build).
	for n in 3:
		if _hole_queue.is_empty() or holes.size() >= MAX_HOLES - 8:
			break
		var q: Array = _hole_queue.pop_front()
		var spec: Vector3 = q[1]
		var h := _add_hole(Vector2(spec.x, spec.y), spec.z, 1.0, false, _rng.randf() * TAU, _rng.randf() * TAU)
		h.cell = q[0]


## Ponds come and go with their cells (a pond is static while it exists).
func _stream_ponds() -> void:
	var fc := Vector2i(floori(focus.x / POND_CELL), floori(focus.y / POND_CELL))
	var needed := {}
	for dj in range(-POND_RANGE, POND_RANGE + 1):
		for di in range(-POND_RANGE, POND_RANGE + 1):
			needed[fc + Vector2i(di, dj)] = true
	var changed := false
	for i in range(ponds.size() - 1, -1, -1):
		if ponds[i].has("cell") and not needed.has(ponds[i].cell):
			_mark_collision(_pond_rect(ponds[i]))
			ponds.remove_at(i)
			changed = true
	for c in _pond_cells.keys():
		if not needed.has(c):
			_pond_cells.erase(c)
	for c in needed:
		if _pond_cells.has(c):
			continue
		_pond_cells[c] = true
		var q := _cell_pond(c)
		if q.is_empty() or ponds.size() >= MAX_PONDS:
			continue
		q.id = _next_id
		q.cell = c
		_next_id += 1
		ponds.append(q)
		_mark_collision(_pond_rect(q))
		changed = true
	if changed:
		_features_dirty = true
		ponds_changed.emit()


## The pond of world cell `c` ({} if none), from a hash of the cell.
func _cell_pond(c: Vector2i) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(c.x, c.y, layout_seed + 7919))
	if rng.randf() >= POND_CHANCE:
		return {}
	var r := rng.randf_range(layout.pond_radius.x, layout.pond_radius.y)
	var m := r + 1.0
	var p := Vector2(c) * POND_CELL + Vector2(rng.randf_range(m, POND_CELL - m), rng.randf_range(m, POND_CELL - m))
	if p.length() < SAFE_START + r or _in_clear_zone(p, r * 1.15):
		return {}
	return {"center": p, "radius": r, "depth": layout.pond_depth, "ph0": rng.randf() * TAU, "ph1": rng.randf() * TAU}


func _in_clear_zone(p: Vector2, radius: float) -> bool:
	for z in clear_zones:
		if p.distance_to(Vector2(z.x, z.y)) < z.z + radius:
			return true
	return false


## Endless field: whether a prop of footprint `radius` at `p` keeps clear of every hole and
## pond that is (or will be) generated around it, and of the start. Uses the deterministic
## cell generators, so it holds before those cells have streamed in.
func endless_spot_clear(p: Vector2, radius: float) -> bool:
	if p.length() < SAFE_START + 1.5 or _in_clear_zone(p, radius):
		return false
	var hc := Vector2i(floori(p.x / HOLE_CELL), floori(p.y / HOLE_CELL))
	for dj in range(-1, 2):
		for di in range(-1, 2):
			for h in _cell_holes(hc + Vector2i(di, dj)):
				if p.distance_to(Vector2(h.x, h.y)) < h.z + layout.hole_wobble + radius + 0.5:
					return false
	var pc := Vector2i(floori(p.x / POND_CELL), floori(p.y / POND_CELL))
	for dj in range(-1, 2):
		for di in range(-1, 2):
			var q := _cell_pond(pc + Vector2i(di, dj))
			if not q.is_empty() and p.distance_to(q.center) < q.radius * 1.15 + radius + 0.3:
				return false
	return true


func _pond_rect(q: Dictionary) -> Rect2:
	var r: float = q.radius * 1.15 + HM_SPACING
	return Rect2(q.center - Vector2(r, r), Vector2(r, r) * 2.0)


## Holes of world cell `c` (x, z, radius): usually 0 or 1 (rarely 2), placed from a hash of
## the cell so they are the same every time the cell comes back into range.
func _cell_holes(c: Vector2i) -> Array[Vector3]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(c.x, c.y, layout_seed))
	var roll := rng.randf()
	var n := 0 if roll < 0.5 else (1 if roll < 0.93 else 2)
	var out: Array[Vector3] = []
	for k in n * 4:
		if out.size() >= n:
			break
		var r := rng.randf_range(0.55, 1.3)
		var m := r + 0.8
		var p := Vector2(c) * HOLE_CELL + Vector2(rng.randf_range(m, HOLE_CELL - m), rng.randf_range(m, HOLE_CELL - m))
		if p.length() < SAFE_START + r or _in_clear_zone(p, r + 0.5):
			continue
		var ok := true
		for o in out:
			if p.distance_to(Vector2(o.x, o.y)) < r + o.z + 1.2:
				ok = false
		if ok:
			out.append(Vector3(p.x, p.y, r))
	return out


func _stream_collision() -> void:
	var cw := HM_CHUNK * HM_SPACING
	var fc := Vector2i(floori(focus.x / cw), floori(focus.y / cw))
	var half := COLLISION_WINDOW / 2
	var needed := {}
	for dj in range(-half, half):
		for di in range(-half, half):
			needed[fc + Vector2i(di, dj)] = true
	for c in _ecol.keys():
		if not needed.has(c):
			_ecol_pool.append(_ecol[c])
			_ecol.erase(c)
	for c in needed:
		if _ecol.has(c):
			continue
		var e: Dictionary = _ecol_pool.pop_back() if not _ecol_pool.is_empty() else _new_collision_chunk()
		var body: StaticBody3D = e.body
		body.position = Vector3((c.x * HM_CHUNK + HM_CHUNK / 2) * HM_SPACING, 0.0, (c.y * HM_CHUNK + HM_CHUNK / 2) * HM_SPACING)
		_ecol[c] = e
		_fill_collision_chunk(c, e)


func _new_collision_chunk() -> Dictionary:
	var body := StaticBody3D.new()
	body.collision_layer = LAYER_FLOOR
	body.collision_mask = 0
	var shape := HeightMapShape3D.new()
	shape.map_width = HM_CHUNK + 1
	shape.map_depth = HM_CHUNK + 1
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3.ONE * HM_SPACING
	body.add_child(cs)
	_add_generated(body)
	var data := PackedFloat32Array()
	data.resize((HM_CHUNK + 1) * (HM_CHUNK + 1))
	return {"body": body, "shape": shape, "data": data}


## Heights of one collision chunk: NaN over holes, else the ground height (mounds and
## ponds). Only holes, mounds and ponds reaching the chunk are evaluated.
func _fill_collision_chunk(c: Vector2i, e: Dictionary) -> void:
	var o := Vector2(c * HM_CHUNK) * HM_SPACING
	var rect := Rect2(o, Vector2.ONE * HM_CHUNK * HM_SPACING)
	var near_holes: Array[Dictionary] = []
	for h in holes:
		if h.scale > 0.02 and rect.grow((h.radius + layout.hole_wobble) * h.scale + GAP_SDF).has_point(h.center):
			near_holes.append(h)
	var near_mounds: Array[Dictionary] = []
	var mound_centers := PackedVector2Array()
	var mound_reach2 := PackedFloat32Array()
	for m in mounds:
		if m.height <= 0.0:
			continue
		if m.has("end"):
			if _mound_rect(m).intersects(rect):
				near_mounds.append(m)
				mound_centers.append(m.center)
				mound_reach2.append(INF) # a ridge: no cheap center test
		elif rect.grow(m.radius * 1.17).has_point(m.center):
			near_mounds.append(m)
			mound_centers.append(m.center)
			mound_reach2.append(m.radius * m.radius * 1.3689)
	var near_ponds: Array[Dictionary] = []
	for q in ponds:
		if rect.grow(q.radius * 1.15).has_point(q.center):
			near_ponds.append(q)
	var data: PackedFloat32Array = e.data
	var inv := 1.0 / HM_SPACING
	var n := HM_CHUNK + 1
	for j in n:
		for i in n:
			var p := o + Vector2(i, j) * HM_SPACING
			var d := -1000.0
			for h in near_holes:
				d = maxf(d, -hole_sdf(p, h))
			var v := NAN
			if d <= GAP_SDF:
				var best := 0.0
				for mi in near_mounds.size():
					# Cheap reject before the full (trigonometric) profile.
					if p.distance_squared_to(mound_centers[mi]) < mound_reach2[mi]:
						best = maxf(best, _mound_value(p, near_mounds[mi]))
				var dip := 0.0
				for q in near_ponds:
					dip = minf(dip, _pond_value(p, q))
				v = (best + dip) * inv
			data[j * n + i] = v
	e.data = data
	(e.shape as HeightMapShape3D).map_data = data


func _endless_refresh_collision(rect: Rect2) -> void:
	var cw := HM_CHUNK * HM_SPACING
	var c0 := Vector2i(floori(rect.position.x / cw), floori(rect.position.y / cw))
	var c1 := Vector2i(floori(rect.end.x / cw), floori(rect.end.y / cw))
	for cj in range(c0.y, c1.y + 1):
		for ci in range(c0.x, c1.x + 1):
			var c := Vector2i(ci, cj)
			if _ecol.has(c):
				_fill_collision_chunk(c, _ecol[c])
