class_name Water
extends Node3D
## Ponds: a water surface over each pond bowl (shaders/water.gdshader) and waterfalls
## (shaders/waterfall.gdshader) wherever pond water meets a gap: the island's edge, or a hole
## (spell-made ones too). Waterfalls are rebuilt whenever a hole finishes opening or closing.
##
## The water surface is one flat quad per pond at Arena.WATER_LEVEL; the shader works out
## everything else analytically from the shared ground functions (depth, shore, gaps).

const WATER_SHADER := preload("res://shaders/water.gdshader")
const FALL_SHADER := preload("res://shaders/waterfall.gdshader")
## Lip tracing grid (world units).
const STEP := 0.08
## How far a waterfall drops: off the island's edge (into the sky) and into a hole.
const FALL_EDGE := 6.0
const FALL_HOLE := 2.2
const RINGS := 14

var arena: Arena
var _surface_mat: ShaderMaterial
var _fall_mat: ShaderMaterial
var _falls: MeshInstance3D
# Lip points for spray: [position, outward direction].
var _lips: Array = []
var _spray := 0.0


func rebuild_from_arena(a: Arena) -> void:
	arena = a
	for c in get_children():
		c.queue_free()
	_falls = null
	_lips.clear()
	if arena.ponds.is_empty():
		return
	_surface_mat = ShaderMaterial.new()
	_surface_mat.shader = WATER_SHADER
	_fall_mat = ShaderMaterial.new()
	_fall_mat.shader = FALL_SHADER
	for q in arena.ponds:
		var quad := QuadMesh.new()
		quad.orientation = PlaneMesh.FACE_Y
		quad.size = Vector2.ONE * q.radius * 2.4
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = _surface_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.position = Vector3(q.center.x, Arena.WATER_LEVEL, q.center.y)
	if not arena.hole_opened.is_connected(_on_hole_changed):
		arena.hole_opened.connect(_on_hole_changed)
		arena.hole_closed.connect(_on_hole_changed)
	_rebuild_falls()


## Only holes reaching a pond change its waterfalls.
func _on_hole_changed(h: Dictionary) -> void:
	for q in arena.ponds:
		if (h.center as Vector2).distance_to(q.center) < q.radius * 1.2 + h.radius + arena.layout.hole_wobble + 0.2:
			_rebuild_falls()
			return


## Traces the zero line of the ground SDF (marching squares) where it runs through pond
## water, and hangs a falling ribbon from it.
func _rebuild_falls() -> void:
	if not arena or arena.ponds.is_empty():
		return
	if _falls:
		_falls.queue_free()
		_falls = null
	_lips.clear()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 0
	for q in arena.ponds:
		var r: float = q.radius * 1.2
		var o: Vector2 = q.center - Vector2(r, r)
		var n := int(ceil(r * 2.0 / STEP))
		# Ground SDF over the pond's box, with only the holes that reach it.
		var near: Array[Dictionary] = []
		for h in arena.holes:
			if h.scale > 0.02 and (h.center as Vector2).distance_to(q.center) < r + (h.radius + arena.layout.hole_wobble) * h.scale + 0.2:
				near.append(h)
		var sdf := PackedFloat32Array()
		sdf.resize((n + 1) * (n + 1))
		for j in n + 1:
			for i in n + 1:
				var p := o + Vector2(i, j) * STEP
				var d := arena.island_sdf(p)
				for h in near:
					d = maxf(d, -arena.hole_sdf(p, h))
				sdf[j * (n + 1) + i] = d
		for j in n:
			for i in n:
				var pts := _cell_crossings(sdf, n + 1, i, j, o)
				for k in range(0, pts.size() - 1, 2):
					var a: Vector2 = pts[k]
					var b: Vector2 = pts[k + 1]
					# Only where there is water on the solid side of the lip.
					var mid := (a + b) * 0.5
					var inward := -arena.ground_gradient(mid)
					if arena.water_depth(mid + inward * 0.12) <= 0.0:
						continue
					_ribbon(st, a, b)
					count += 1
					if count % 3 == 0:
						_lips.append([Vector3(mid.x, Arena.WATER_LEVEL, mid.y), Vector3(-inward.x, 0.0, -inward.y)])
	if count == 0:
		return
	_falls = MeshInstance3D.new()
	_falls.name = "Waterfalls"
	_falls.mesh = st.commit()
	_falls.material_override = _fall_mat
	_falls.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_falls)


## Zero crossings of the SDF on the edges of cell (i, j), paired into segments.
func _cell_crossings(sdf: PackedFloat32Array, w: int, i: int, j: int, o: Vector2) -> Array:
	var corners := [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i + 1, j + 1), Vector2i(i, j + 1)]
	var out := []
	for e in 4:
		var c0: Vector2i = corners[e]
		var c1: Vector2i = corners[(e + 1) % 4]
		var v0 := sdf[c0.y * w + c0.x]
		var v1 := sdf[c1.y * w + c1.x]
		if (v0 < 0.0) != (v1 < 0.0):
			var t := v0 / (v0 - v1)
			out.append(o + (Vector2(c0).lerp(Vector2(c1), t)) * STEP)
	return out


## A sheet of water from the lip segment a-b: starts just past the lip at the water level and
## falls with a slight outward arc (wider off the cliff, hugging the wall in a hole).
func _ribbon(st: SurfaceTool, a: Vector2, b: Vector2) -> void:
	var ends := [a, b]
	var verts := []
	for e in 2:
		var p: Vector2 = ends[e]
		var out := arena.ground_gradient(p)
		var edge := arena.island_sdf(p) > -0.3
		var length := FALL_EDGE if edge else FALL_HOLE
		var arc := 0.7 if edge else 0.12
		var col := []
		for k in RINGS + 1:
			var f := float(k) / RINGS
			var xz := p + out * (0.03 + arc * f * f)
			col.append([Vector3(xz.x, Arena.WATER_LEVEL - f * length, xz.y), Vector2(0.0, f * length), 1.0 if edge else 0.0])
		verts.append(col)
	for k in RINGS:
		var quad := [verts[0][k], verts[1][k], verts[1][k + 1], verts[0][k], verts[1][k + 1], verts[0][k + 1]]
		for v in quad:
			st.set_uv(v[1])
			st.set_uv2(Vector2(v[2], 0.0))
			st.add_vertex(v[0])


func _process(delta: float) -> void:
	var fx := get_node_or_null("../../Fx") as FxSprites
	if _lips.is_empty() or not fx:
		return
	_spray -= delta
	if _spray > 0.0:
		return
	_spray = 0.08
	var lip: Array = _lips[randi() % _lips.size()]
	var p: Vector3 = lip[0]
	var out: Vector3 = lip[1]
	fx.spawn(p + out * 0.05, out * randf_range(0.4, 1.0) + Vector3.UP * randf_range(0.3, 0.9), 0.35,
		FxSprites.TILE_SPARK, 1, 3, 2.0, 1.0, 4.0, 1.0)
