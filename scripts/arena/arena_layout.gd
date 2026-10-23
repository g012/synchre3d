class_name ArenaLayout
extends RefCounted
## Builds the runtime layout (an ArenaConfig copy) the Arena is generated from.
##
## * Authored: the config's own arrays, scaled by `size_scale` (used in the editor and when
##   `randomize_layout` is off).
## * Random: a new island shape, holes, props and spawn points from `seed`, placed by
##   rejection sampling so holes keep apart, props keep clear of holes, and both fighters
##   start on safe ground. `island_sdf` must already reflect the returned radius/wobble
##   (the Arena calls `shape()` first, then `populate()`).


## Island size and outline for this layout.
static func shape(base: ArenaConfig, rng: RandomNumberGenerator, randomized: bool) -> ArenaConfig:
	var cfg := base.duplicate(true) as ArenaConfig
	var k := base.size_scale
	cfg.radius = base.radius * k
	cfg.edge_wobble = base.edge_wobble * (1.0 + (k - 1.0) * 0.6)
	cfg.underside_depth = base.underside_depth * (1.0 + (k - 1.0) * 0.5)
	if randomized:
		cfg.radius *= Vector2(rng.randf_range(0.92, 1.08), rng.randf_range(0.92, 1.08))
		cfg.edge_wobble *= rng.randf_range(0.8, 1.25)
	return cfg


## Fills holes, props and spawn points. `island_sdf(p: Vector2) -> float`.
static func populate(cfg: ArenaConfig, base: ArenaConfig, rng: RandomNumberGenerator, randomized: bool, island_sdf: Callable) -> void:
	var k := base.size_scale
	if not randomized:
		cfg.holes = _scaled(base.holes, k, false)
		cfg.ponds = _scaled(base.ponds, k, false)
		cfg.trees = _scaled(base.trees, k, true)
		cfg.bushes = _scaled(base.bushes, k, true)
		cfg.rocks = _scaled(base.rocks, k, true)
		cfg.stumps = _scaled(base.stumps, k, true)
		cfg.mushrooms = _scaled(base.mushrooms, k, true)
		cfg.dancing_flowers = _scaled(base.dancing_flowers, k, true)
		var sp: Array[Vector2] = []
		for s in base.spawn_points:
			sp.append(s * k)
		cfg.spawn_points = sp
		return

	var r := cfg.radius
	# Spawns: one on each side of the centre, a comfortable distance apart.
	var spawns: Array[Vector2] = []
	for side in [-1.0, 1.0]:
		for attempt in 200:
			var p := Vector2(side * rng.randf_range(0.2, 0.36) * r.x, rng.randf_range(-0.25, 0.25) * r.y)
			if island_sdf.call(p) < -3.0:
				spawns.append(p)
				break
		if spawns.size() < (2 if side > 0.0 else 1):
			spawns.append(Vector2(side * 0.28 * r.x, 0.0))
	cfg.spawn_points = spawns

	# Holes keep apart from each other, from the outer edge and from the spawns.
	var holes: Array[Vector3] = []
	var want := rng.randi_range(base.hole_count.x, base.hole_count.y)
	for attempt in want * 60:
		if holes.size() >= want:
			break
		var hr := rng.randf_range(base.hole_radius.x, base.hole_radius.y)
		var p := Vector2(rng.randf_range(-r.x, r.x), rng.randf_range(-r.y, r.y))
		if island_sdf.call(p) > -(hr + 1.4):
			continue
		var ok := true
		for h in holes:
			if p.distance_to(Vector2(h.x, h.y)) < hr + h.z + 1.5:
				ok = false
				break
		for s in spawns:
			if p.distance_to(s) < hr + 2.4:
				ok = false
		if ok:
			holes.append(Vector3(p.x, p.y, hr))
	cfg.holes = holes

	# Ponds: the first one straddles the front edge (the one facing the camera) so it spills
	# down the cliff; the others sit against a hole and pour into it.
	var ponds: Array[Vector3] = []
	var want_ponds := rng.randi_range(base.pond_count.x, base.pond_count.y)
	for attempt in 400:
		if ponds.size() >= want_ponds:
			break
		var pr := rng.randf_range(base.pond_radius.x, base.pond_radius.y)
		var p := Vector2.ZERO
		if ponds.is_empty():
			var a := rng.randf_range(0.25, 0.75) * PI # front half (+z)
			p = Vector2(cos(a) * r.x, sin(a) * r.y)
			# Walk inward until the rim crosses the edge by a bit.
			for step in 60:
				if island_sdf.call(p) < -pr * 0.55:
					break
				p *= 0.97
		else:
			if holes.is_empty():
				break
			var h := holes[rng.randi() % holes.size()]
			var a := rng.randf() * TAU
			p = Vector2(h.x, h.y) + Vector2(cos(a), sin(a)) * (h.z + pr * 0.55)
			if island_sdf.call(p) > -(pr + 1.0):
				continue
		var ok := true
		for s in spawns:
			if p.distance_to(s) < pr + 1.8:
				ok = false
		for q in ponds:
			if p.distance_to(Vector2(q.x, q.y)) < pr + q.z + 1.0:
				ok = false
		for h in holes:
			# Pond against a hole: overlapping its rim is the point, swallowing it is not.
			if p.distance_to(Vector2(h.x, h.y)) < h.z + pr * 0.35:
				ok = false
		if ok:
			ponds.append(Vector3(p.x, p.y, pr))
	cfg.ponds = ponds

	# Props: solid ones first (bigger clearance), then decorations.
	var placed: Array[Vector3] = [] # x, z, clearance radius
	for q in ponds:
		placed.append(Vector3(q.x, q.y, q.z * 1.05))
	# Trees ring the island edge (the camera follows the fighters, so a tree in the middle
	# would keep hiding them), denser along the back where the canopy frames the view.
	cfg.trees = _scatter(rng, base.tree_count, Vector2(0.85, 1.15), 1.1, cfg, island_sdf, holes, spawns, placed,
		func(p: Vector2): return island_sdf.call(p) > (-4.5 if p.y < 0.0 else -3.0))
	cfg.bushes = _scatter(rng, base.bush_count, Vector2(0.6, 0.85), 0.8, cfg, island_sdf, holes, spawns, placed,
		func(p: Vector2): return p.y < 0.4 * r.y)
	cfg.rocks = _scatter(rng, base.rock_count, Vector2(0.45, 0.85), 0.7, cfg, island_sdf, holes, spawns, placed, Callable())
	cfg.stumps = _scatter(rng, base.stump_count, Vector2(0.75, 0.95), 0.6, cfg, island_sdf, holes, spawns, placed, Callable())
	cfg.mushrooms = _scatter(rng, base.mushroom_count, Vector2(0.9, 1.2), 0.4, cfg, island_sdf, holes, spawns, placed, Callable())
	# Dancing flowers line the edge (a ring of dancers around the fight), a few further in.
	cfg.dancing_flowers = _scatter(rng, base.dancing_flower_count, Vector2(1.5, 1.9), 0.35, cfg, island_sdf, holes, spawns, placed,
		func(p: Vector2): return island_sdf.call(p) > -3.2 or rng.randf() < 0.25)


static func _scatter(rng: RandomNumberGenerator, count: Vector2i, scale: Vector2, clearance: float, cfg: ArenaConfig,
		island_sdf: Callable, holes: Array[Vector3], spawns: Array[Vector2], placed: Array[Vector3], accept: Callable) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var want := rng.randi_range(count.x, count.y)
	var r := cfg.radius
	for attempt in want * 80:
		if out.size() >= want:
			break
		var p := Vector2(rng.randf_range(-r.x, r.x), rng.randf_range(-r.y, r.y))
		var s := rng.randf_range(scale.x, scale.y)
		var c := clearance * s
		if island_sdf.call(p) > -(c + 0.6):
			continue
		if accept.is_valid() and not accept.call(p):
			continue
		var ok := true
		for h in holes:
			if p.distance_to(Vector2(h.x, h.y)) < h.z + c + 0.9:
				ok = false
				break
		for sp in spawns:
			if p.distance_to(sp) < c + 1.6:
				ok = false
		for q in placed:
			if p.distance_to(Vector2(q.x, q.y)) < q.z + c:
				ok = false
				break
		if ok:
			out.append(Vector3(p.x, p.y, s))
			placed.append(Vector3(p.x, p.y, c))
	return out


static func _scaled(src: Array[Vector3], k: float, keep_z: bool) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for v in src:
		out.append(Vector3(v.x * k, v.y * k, v.z if keep_z else v.z * (1.0 + (k - 1.0) * 0.3)))
	return out
