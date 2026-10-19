class_name Clouds
extends Node3D
## Puffy toon-shaded clouds drifting around and below the floating island.
## Each cloud is a cluster of low-poly spheres lit with the shared palette material, so it
## gets the same bands, outlines and island shadow as everything else.

@export var count := 9
@export var drift_speed := 0.35
## Clouds wrap around when they leave this half-width on X.
@export var wrap_x := 26.0
@export var seed := 5

var _clouds: Array[Node3D] = []
var _speeds: Array[float] = []


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var mat := ToonMaterials.SOLID.duplicate() as ShaderMaterial
	mat.set_shader_parameter("palette_index", 29) # cloud_white: cool blue-grey shadows
	mat.set_shader_parameter("dither", 0.15)
	mat.set_shader_parameter("receive_shadows", false)
	mat.set_shader_parameter("use_pit_darkness", false)
	# Layers: (y, z min, z max). Mid clouds drift past the island's flanks (hidden while
	# behind/below it), low ones pass under its front, far ones float behind the trees.
	var layers := [Vector3(-3.0, -3.0, 4.0), Vector3(-6.5, 3.0, 6.0), Vector3(1.0, -16.0, -11.0)]
	for i in count:
		var layer: Vector3 = layers[i % layers.size()]
		var cloud := _make_cloud(rng, mat, rng.randf_range(0.8, 1.5))
		cloud.position = Vector3(rng.randf_range(-wrap_x, wrap_x), layer.x + rng.randf_range(-1.0, 1.0),
			rng.randf_range(layer.y, layer.z))
		add_child(cloud)
		_clouds.append(cloud)
		_speeds.append(drift_speed * rng.randf_range(0.7, 1.3))


func _make_cloud(rng: RandomNumberGenerator, mat: Material, size: float) -> Node3D:
	var root := Node3D.new()
	var puffs := rng.randi_range(4, 7)
	for k in puffs:
		var r := size * rng.randf_range(0.6, 1.1) * (1.25 if k == 0 else 1.0)
		var sphere := SphereMesh.new()
		sphere.radius = r
		sphere.height = r * 2.0
		sphere.radial_segments = 14
		sphere.rings = 7
		var mi := MeshInstance3D.new()
		mi.mesh = sphere
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var along := (float(k) / maxf(puffs - 1, 1) - 0.5) * size * 3.4
		mi.position = Vector3(along, rng.randf_range(0.0, 0.4) * size, rng.randf_range(-0.5, 0.5) * size)
		mi.scale = Vector3(1.0, 0.72, 1.0)
		root.add_child(mi)
	return root


func _process(delta: float) -> void:
	for i in _clouds.size():
		var c := _clouds[i]
		c.position.x += _speeds[i] * delta
		if c.position.x > wrap_x:
			c.position.x -= wrap_x * 2.0
