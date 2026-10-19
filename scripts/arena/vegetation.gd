@tool
class_name Vegetation
extends Node3D
## Scatters grass tufts and flowers over the arena as one MultiMesh, in dense clumps
## separated by open lawn, always keeping clear of hole edges and prop footprints.
## Regenerates whenever the parent Arena rebuilds.

@export var grass_material: ShaderMaterial
## Footprints (x, z, radius) where no grass grows (props and decorations).
var blocked: Array[Vector3] = []

var _arena: Arena
var _wind_time := 0.0


## Called by the Arena after the terrain (and Props) are built.
func rebuild_from_arena(arena: Arena) -> void:
	_arena = arena
	blocked = arena.obstacles.duplicate()
	for d in arena.decor_footprints:
		blocked.append(d)
	for o in arena.obstacles:
		blocked.append(Vector3(o.x, o.y, o.z + 0.15))
	rebuild()


func rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	var cfg := _arena.layout
	var rng := RandomNumberGenerator.new()
	rng.seed = cfg.seed * 31 + 5
	var clumps := FastNoiseLite.new()
	clumps.seed = cfg.seed
	clumps.frequency = 0.32
	clumps.fractal_octaves = 2
	var flowers_noise := FastNoiseLite.new()
	flowers_noise.seed = cfg.seed + 99
	flowers_noise.frequency = 0.9

	var transforms: Array[Transform3D] = []
	var customs: Array[Color] = []
	var step := 1.0 / sqrt(cfg.grass_density)
	var ext := cfg.radius
	var z := -ext.y
	while z < ext.y:
		var x := -ext.x
		while x < ext.x:
			var p := Vector2(x + rng.randf_range(-0.5, 0.5) * step, z + rng.randf_range(-0.5, 0.5) * step)
			x += step
			var sdf := _arena.ground_sdf(p)
			if sdf > -cfg.grass_edge_margin or _is_blocked(p):
				continue
			if rng.randf() > _density(p, clumps, sdf):
				continue
			var flower_here := flowers_noise.get_noise_2d(p.x, p.y) > 0.45 and rng.randf() < cfg.flower_density * 0.35
			var custom: Color
			if flower_here:
				var palette: Array[int] = [28, 29, 30, 31] # yellow, white, pink, blue
				var col := palette[int(abs(flowers_noise.get_noise_2d(p.x * 0.3, p.y * 0.3 + 40.0)) * 8.0) % 4]
				custom = Color(col / 32.0, rng.randi_range(6, 7) / 8.0, rng.randf(), 0.0)
			else:
				custom = Color(0.0, rng.randi_range(0, 5) / 8.0, rng.randf(), 0.0)
			transforms.append(Transform3D(Basis.IDENTITY, Vector3(p.x, 0.0, p.y)))
			customs.append(custom)
		z += step

	_bake_density_map(clumps)

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.center_offset = Vector3(0.0, 0.5, 0.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_custom_data(i, customs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Grass"
	mmi.multimesh = mm
	mmi.material_override = grass_material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Tall enough for tufts lifted by mounds (shader-side).
	mmi.custom_aabb = AABB(Vector3(-ext.x - 2.0, -1.0, -ext.y - 2.0), Vector3(ext.x * 2.0 + 4.0, Arena.MOUND_LEVELS[-1].y + 3.0, ext.y * 2.0 + 4.0))
	add_child(mmi)


## Probability of a tuft at `p`: noise clumps, thinned toward edges and props.
func _density(p: Vector2, clumps: FastNoiseLite, sdf: float) -> float:
	var cfg := _arena.layout
	var d := smoothstep(-0.05, 0.25, clumps.get_noise_2d(p.x, p.y))
	return d * smoothstep(cfg.grass_edge_margin, cfg.grass_edge_margin + 0.5, -sdf)


## The terrain shader darkens the soil under clumps, giving grass a dark base / mid blades /
## light tips structure.
func _bake_density_map(clumps: FastNoiseLite) -> void:
	var rect := _arena.sdf_rect
	var res := 8.0
	var w := int(rect.size.x * res)
	var h := int(rect.size.y * res)
	var img := Image.create_empty(w, h, false, Image.FORMAT_R8)
	for j in h:
		for i in w:
			var p := rect.position + Vector2((i + 0.5) / w, (j + 0.5) / h) * rect.size
			var sdf := _arena.ground_sdf(p)
			var d := 0.0 if sdf > 0.0 or _is_blocked(p) else _density(p, clumps, sdf)
			img.set_pixel(i, j, Color(d, 0.0, 0.0))
	RenderingServer.global_shader_parameter_set("grass_density_map", ImageTexture.create_from_image(img))


func _is_blocked(p: Vector2) -> bool:
	for b in blocked:
		if p.distance_squared_to(Vector2(b.x, b.y)) < b.z * b.z:
			return true
	return false


func _process(delta: float) -> void:
	_wind_time += delta
	RenderingServer.global_shader_parameter_set("wind_time", _wind_time)
