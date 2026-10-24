@tool
class_name Props
extends Node3D
## Places the Blender-made props (trees, bushes, rocks, stumps, mushrooms, dancing flowers) listed in the
## ArenaConfig, applies toon materials, turns foliage blobs into leaf-card billboards and adds
## obstacle colliders. Footprints are published to `arena.obstacles` for grass and AI.
## Props ride the ground when spells raise mounds under them (`_on_ground_changed`).
##
## Endless field: props are generated per square cell around the arena's focus (one cell per
## frame, from a hash of the cell) and dropped behind; each cell holds its props, colliders and
## leaf cards, and never puts a prop where a hole or pond is (or will be) generated.

const TREES: Array[PackedScene] = [preload("res://assets/models/tree_round.glb"), preload("res://assets/models/tree_small.glb")]
const BUSH := preload("res://assets/models/bush.glb")
const ROCKS: Array[PackedScene] = [preload("res://assets/models/rock_a.glb"), preload("res://assets/models/rock_b.glb"), preload("res://assets/models/rock_c.glb")]
const STUMP := preload("res://assets/models/stump.glb")
const MUSHROOMS := preload("res://assets/models/mushrooms.glb")

## Leaf cards per square unit of foliage blob surface.
@export var leaf_density := 11.0

# Every placed prop: { node, body (or null), xz: Vector2, y: float, leaves: Vector2i range,
# and in the endless field: cell, mmi (its cell's leaf cards), base (their transforms) }.
var _entries: Array[Dictionary] = []
var _leaves: MultiMeshInstance3D
var _leaf_base: Array[Transform3D] = []
var _arena: Arena

## Endless field: cell size and how many cells around the focus (each side).
const CELL := 10.0
const WINDOW := 2
# Live cells: Vector2i -> { node: Node3D, obstacles: Array[Vector3], decor: Array[Vector3] }.
var _cells := {}


func rebuild_from_arena(arena: Arena) -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_entries.clear()
	_cells.clear()
	_leaves = null
	_arena = arena
	if not arena.ground_changed.is_connected(_on_ground_changed):
		arena.ground_changed.connect(_on_ground_changed)
	arena.obstacles.clear()
	if arena.endless:
		for k in (2 * WINDOW + 1) * (2 * WINDOW + 1):
			_stream()
		return
	var cfg := arena.layout
	var rng := RandomNumberGenerator.new()
	rng.seed = cfg.seed * 7 + 1
	var leaves := LeafCards.new()

	for i in cfg.trees.size():
		var t := cfg.trees[i]
		var node := _place(arena, TREES[i % TREES.size()], t, rng, 0.32 * t.z, true)
		_entries[-1].leaves = leaves.add_from(node, rng, leaf_density)
		# A few mushrooms at the foot of every tree, on the side facing the island centre.
		var a := atan2(-t.y, -t.x) + rng.randf_range(-0.8, 0.8)
		_place(arena, MUSHROOMS, Vector3(t.x + cos(a) * 0.6 * t.z, t.y + sin(a) * 0.6 * t.z, 1.0), rng, 0.0, false)
	for b in cfg.bushes:
		var node := _place(arena, BUSH, b, rng, 0.5 * b.z, true)
		_entries[-1].leaves = leaves.add_from(node, rng, leaf_density)
	for i in cfg.rocks.size():
		var r := cfg.rocks[i]
		_place(arena, ROCKS[i % ROCKS.size()], r, rng, 0.42 * r.z, false)
	for s in cfg.stumps:
		_place(arena, STUMP, s, rng, 0.3 * s.z, false)
	for m in cfg.mushrooms:
		_place(arena, MUSHROOMS, m, rng, 0.0, false)
	# Petal colors: pink, blue, white, lavender, red.
	var petals: Array[int] = [30, 31, 1, 12, 4]
	for i in cfg.dancing_flowers.size():
		var f := cfg.dancing_flowers[i]
		var flower := DancingFlower.new()
		flower.petal_index = petals[rng.randi() % petals.size()]
		flower.mirrored = i % 2 == 1
		flower.position = Vector3(f.x, 0.0, f.y)
		# Faces turned roughly toward the camera.
		flower.rotation.y = rng.randf_range(-0.45, 0.45)
		flower.scale = Vector3.ONE * f.z
		add_child(flower)
		_entries.append({"node": flower, "body": null, "xz": Vector2(f.x, f.y), "y": 0.0, "leaves": Vector2i.ZERO})
		arena.decor_footprints.append(Vector3(f.x, f.y, 0.22 * f.z))

	_leaves = leaves.build()
	_leaf_base = leaves.transforms
	if _leaves:
		add_child(_leaves)


## Lifts props (and their colliders and leaf cards) onto the current ground height.
func _on_ground_changed(rect: Rect2) -> void:
	if not _arena:
		return
	var grown := rect.grow(0.2)
	for e in _entries:
		if not grown.has_point(e.xz):
			continue
		var y := _arena.height_at(e.xz)
		if is_equal_approx(y, e.y):
			continue
		e.y = y
		if is_instance_valid(e.node):
			e.node.position.y = y
		if e.body and is_instance_valid(e.body):
			e.body.position.y = y
		var r: Vector2i = e.leaves
		var mmi: MultiMeshInstance3D = e.get("mmi", _leaves)
		var base: Array = e.get("base", _leaf_base)
		if mmi and is_instance_valid(mmi) and r.y > r.x:
			var mm := mmi.multimesh
			for i in range(r.x, r.y):
				var t: Transform3D = base[i]
				t.origin.y += y
				mm.set_instance_transform(i, t)


## Places one prop. `cell` (endless field): the cell it belongs to, which then holds the node
## and its footprint instead of the arena-wide lists.
func _place(arena: Arena, scene: PackedScene, p: Vector3, rng: RandomNumberGenerator, collider_radius: float, foliage: bool, cell := {}) -> Node3D:
	var node := scene.instantiate() as Node3D
	node.position = Vector3(p.x, 0.0, p.y)
	var entry := {"node": node, "body": null, "xz": Vector2(p.x, p.y), "y": 0.0, "leaves": Vector2i.ZERO}
	_entries.append(entry)
	node.rotation.y = rng.randf() * TAU
	node.scale = Vector3.ONE * p.z
	var parent: Node = cell.node if not cell.is_empty() else self
	if not cell.is_empty():
		entry.cell = cell.key
	parent.add_child(node)
	if arena.ground_sdf(Vector2(p.x, p.y)) > -0.2:
		push_warning("Prop at %s is not on solid ground" % Vector2(p.x, p.y))
	for mi in ToonMaterials.mesh_instances(node):
		if foliage and mi.name.begins_with("Foliage"):
			mi.material_override = ToonMaterials.FOLIAGE_CORE
		else:
			mi.material_override = ToonMaterials.SOLID
	if collider_radius > 0.0:
		var body := StaticBody3D.new()
		body.collision_layer = Arena.LAYER_OBSTACLES
		body.collision_mask = 0
		var shape := CylinderShape3D.new()
		shape.radius = collider_radius
		shape.height = 2.0
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position.y = 1.0
		body.add_child(cs)
		body.position = node.position
		parent.add_child(body)
		entry.body = body
		(cell.obstacles if not cell.is_empty() else arena.obstacles).append(Vector3(p.x, p.y, collider_radius))
	else:
		# Small decorations only keep grass from growing through them.
		(cell.decor if not cell.is_empty() else arena.decor_footprints).append(Vector3(p.x, p.y, 0.25 * p.z))
	return node


# ---------------------------------------------------------------- endless field

func _process(_delta: float) -> void:
	if _arena and _arena.endless and not Engine.is_editor_hint():
		_stream()


## Drops cells out of range, then builds the nearest missing one.
func _stream() -> void:
	var f := _arena.focus
	var fc := Vector2i(floori(f.x / CELL), floori(f.y / CELL))
	var changed := false
	for c in _cells.keys():
		if absi(c.x - fc.x) > WINDOW or absi(c.y - fc.y) > WINDOW:
			_cells[c].node.queue_free()
			_cells.erase(c)
			_entries = _entries.filter(func(e: Dictionary) -> bool: return e.get("cell", null) != c)
			changed = true
	var best := Vector2i.ZERO
	var best_d := INF
	for dj in range(-WINDOW, WINDOW + 1):
		for di in range(-WINDOW, WINDOW + 1):
			var c := fc + Vector2i(di, dj)
			var d := Vector2(di, dj).length()
			if not _cells.has(c) and d < best_d:
				best_d = d
				best = c
	if best_d < INF:
		_cells[best] = _build_cell(best)
		changed = true
	if changed:
		# Obstacles and decorations of the live cells, for the AI, spells and holes.
		_arena.obstacles.clear()
		_arena.decor_footprints.clear()
		for c in _cells:
			_arena.obstacles.append_array(_cells[c].obstacles)
			_arena.decor_footprints.append_array(_cells[c].decor)


## One cell's props: a tree now and then, bushes, rocks, stumps, mushrooms and a dancing
## flower, each on clear ground (see Arena.endless_spot_clear) and apart from each other.
func _build_cell(c: Vector2i) -> Dictionary:
	var node := Node3D.new()
	node.name = "Cell_%d_%d" % [c.x, c.y]
	add_child(node)
	var obstacles: Array[Vector3] = []
	var decor: Array[Vector3] = []
	var cell := {"node": node, "obstacles": obstacles, "decor": decor, "key": c}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(c.x, c.y, _arena.layout_seed + 31337))
	var leaves := LeafCards.new()
	var leafy: Array[Dictionary] = []
	var placed: Array[Vector3] = []
	# kind, how many (chance of one, or up to n), scale range, clearance (x scale)
	var plan := [["tree", 0.3, Vector2(0.85, 1.1), 1.1], ["bush", 0.45, Vector2(0.6, 0.85), 0.8],
		["rock", 2, Vector2(0.45, 0.85), 0.7], ["stump", 0.15, Vector2(0.75, 0.95), 0.6],
		["mushrooms", 0.35, Vector2(0.9, 1.2), 0.4], ["flower", 0.35, Vector2(1.5, 1.9), 0.35]]
	for spec in plan:
		var count: int = rng.randi_range(0, spec[1]) if spec[1] is int else (1 if rng.randf() < spec[1] else 0)
		for n in count:
			for attempt in 8:
				var s := rng.randf_range(spec[2].x, spec[2].y)
				var clear: float = spec[3] * s
				var p := Vector2(c) * CELL + Vector2(rng.randf_range(0.5, CELL - 0.5), rng.randf_range(0.5, CELL - 0.5))
				if not _arena.endless_spot_clear(p, clear):
					continue
				var free := true
				for q in placed:
					if p.distance_to(Vector2(q.x, q.y)) < q.z + clear:
						free = false
				if not free:
					continue
				placed.append(Vector3(p.x, p.y, clear))
				var v := Vector3(p.x, p.y, s)
				match spec[0]:
					"tree":
						_place(_arena, TREES[rng.randi() % TREES.size()], v, rng, 0.32 * s, true, cell)
						leafy.append(_entries[-1])
						_entries[-1].leaves = leaves.add_from(_entries[-1].node, rng, leaf_density)
					"bush":
						_place(_arena, BUSH, v, rng, 0.5 * s, true, cell)
						leafy.append(_entries[-1])
						_entries[-1].leaves = leaves.add_from(_entries[-1].node, rng, leaf_density)
					"rock":
						_place(_arena, ROCKS[rng.randi() % ROCKS.size()], v, rng, 0.42 * s, false, cell)
					"stump":
						_place(_arena, STUMP, v, rng, 0.3 * s, false, cell)
					"mushrooms":
						_place(_arena, MUSHROOMS, v, rng, 0.0, false, cell)
					"flower":
						var flower := DancingFlower.new()
						flower.petal_index = [30, 31, 1, 12, 4][rng.randi() % 5]
						flower.mirrored = rng.randf() < 0.5
						flower.position = Vector3(p.x, 0.0, p.y)
						flower.rotation.y = rng.randf_range(-0.45, 0.45)
						flower.scale = Vector3.ONE * s
						node.add_child(flower)
						_entries.append({"node": flower, "body": null, "xz": p, "y": 0.0, "leaves": Vector2i.ZERO, "cell": c})
						cell.decor.append(Vector3(p.x, p.y, 0.22 * s))
				break
	var mmi := leaves.build()
	if mmi:
		node.add_child(mmi)
		for e in leafy:
			e.mmi = mmi
			e.base = leaves.transforms
	# Ground already raised here (a mound) lifts the new props.
	_on_ground_changed(Rect2(Vector2(c) * CELL, Vector2.ONE * CELL))
	return cell


## Collects leaf-card instances from foliage blobs and builds one MultiMesh for all of them.
class LeafCards:
	var transforms: Array[Transform3D] = []
	var customs: Array[Color] = []

	## Adds the cards of one prop; returns their instance range [start, end).
	func add_from(prop: Node3D, rng: RandomNumberGenerator, density: float) -> Vector2i:
		var start := transforms.size()
		for mi in ToonMaterials.mesh_instances(prop):
			if not mi.name.begins_with("Foliage"):
				continue
			var xf := mi.global_transform if mi.is_inside_tree() else mi.transform
			var center := xf.origin
			var arrays := mi.mesh.surface_get_arrays(0)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var tris: Array[PackedVector3Array] = []
			var areas := PackedFloat32Array()
			var total := 0.0
			for i in range(0, idx.size(), 3):
				var a := xf * verts[idx[i]]
				var b := xf * verts[idx[i + 1]]
				var c := xf * verts[idx[i + 2]]
				var area := (b - a).cross(c - a).length() * 0.5
				tris.append(PackedVector3Array([a, b, c]))
				total += area
				areas.append(total)
			var count := int(total * density)
			for _n in count:
				var r := rng.randf() * total
				var ti := areas.bsearch(r)
				var t := tris[mini(ti, tris.size() - 1)]
				var u := rng.randf()
				var v := rng.randf()
				if u + v > 1.0:
					u = 1.0 - u
					v = 1.0 - v
				var p := t[0] + (t[1] - t[0]) * u + (t[2] - t[0]) * v
				var face_n := (t[1] - t[0]).cross(t[2] - t[0]).normalized()
				var radial := (p - center).normalized()
				# Godot winds front faces clockwise, so the cross product points inward.
				if face_n.dot(radial) < 0.0:
					face_n = -face_n
				var n := (radial * 0.75 + face_n * 0.25).normalized()
				transforms.append(Transform3D(Basis.IDENTITY, p + n * 0.04))
				customs.append(Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5, rng.randi_range(0, 3) / 4.0))
			# The blob itself becomes a slightly shrunken dark core that fills gaps between cards.
			mi.scale *= 0.82
		return Vector2i(start, transforms.size())

	func build() -> MultiMeshInstance3D:
		if transforms.is_empty():
			return null
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = quad
		mm.instance_count = transforms.size()
		for i in transforms.size():
			mm.set_instance_transform(i, transforms[i])
			mm.set_instance_custom_data(i, customs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Leaves"
		mmi.multimesh = mm
		mmi.material_override = ToonMaterials.FOLIAGE_LEAVES
		var aabb := AABB(transforms[0].origin, Vector3.ZERO)
		for t in transforms:
			aabb = aabb.expand(t.origin)
		# Grown upward too: leaves rise with props standing on mounds.
		mmi.custom_aabb = aabb.grow(1.0).expand(aabb.end + Vector3.UP * (Arena.MOUND_LEVELS[-1].y + 1.0))
		return mmi
