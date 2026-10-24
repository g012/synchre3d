class_name Shrine
extends Node3D
## A story shrine: a glowing rune circle ringed by standing stones, a thin pillar of light
## you can spot from afar, and its sage (a big dancing flower) in the middle. Once its song
## has been learnt the shrine calms down (dimmer light, no beckoning sparkles).
## Also used for Elder Bloom's spot at the start (no pillar).

const MAGIC := preload("res://shaders/magic.gdshader")
const ROCKS: Array[PackedScene] = [preload("res://assets/models/rock_a.glb"), preload("res://assets/models/rock_b.glb"),
	preload("res://assets/models/rock_c.glb")]

var palette_index := 15
var petal_index := 30
var with_pillar := true
var fx: FxSprites
## The sage has something to say: sparkles rise above it.
var beckoning := true

var _disc_mat: ShaderMaterial
var _pillar_mat: ShaderMaterial
var _pillar: MeshInstance3D
var _sage: DancingFlower
var _t := 0.0
var _spark := 0.0


func _ready() -> void:
	_disc_mat = _magic(0.25)
	_disc_mat.set_shader_parameter("disc", true)
	var quad := QuadMesh.new()
	quad.orientation = PlaneMesh.FACE_Y
	quad.size = Vector2.ONE * 5.0
	var disc := MeshInstance3D.new()
	disc.mesh = quad
	disc.material_override = _disc_mat
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.position.y = 0.04
	add_child(disc)
	# Standing stones around the circle.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(global_position)
	for k in 6:
		var a := TAU * k / 6.0 + 0.3
		var rock := ROCKS[k % ROCKS.size()].instantiate() as Node3D
		rock.position = Vector3(cos(a) * 3.1, 0.0, sin(a) * 3.1)
		rock.rotation.y = rng.randf() * TAU
		rock.scale = Vector3(0.7, 1.6, 0.7) * rng.randf_range(0.9, 1.15)
		for mi in ToonMaterials.mesh_instances(rock):
			mi.material_override = ToonMaterials.SOLID
		add_child(rock)
	if with_pillar:
		_pillar_mat = _magic(0.6)
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.06
		cyl.bottom_radius = 0.14
		cyl.height = 9.0
		cyl.radial_segments = 8
		cyl.rings = 1
		_pillar = MeshInstance3D.new()
		_pillar.mesh = cyl
		_pillar.material_override = _pillar_mat
		_pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_pillar.position = Vector3(0.0, 4.5, -0.9)
		add_child(_pillar)
	_sage = DancingFlower.new()
	_sage.petal_index = petal_index
	_sage.scale = Vector3.ONE * 2.6
	_sage.position = Vector3(0.0, 0.0, -0.9)
	add_child(_sage)


func _magic(energy: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = MAGIC
	mat.set_shader_parameter("palette_index", palette_index)
	mat.set_shader_parameter("energy", energy)
	return mat


func sage() -> Node3D:
	return _sage


func sage_position() -> Vector3:
	return _sage.global_position if _sage else global_position


## The song has been learnt: a calm, dim shrine.
func set_done(done: bool) -> void:
	beckoning = not done
	if _pillar:
		_pillar.visible = not done


func _process(delta: float) -> void:
	_t += delta
	_disc_mat.set_shader_parameter("energy", 0.2 + 0.15 * sin(_t * 2.0) if beckoning else 0.1)
	if _pillar_mat:
		_pillar_mat.set_shader_parameter("energy", 0.5 + 0.3 * sin(_t * 3.0))
	if not beckoning or not fx:
		return
	_spark -= delta
	if _spark <= 0.0:
		_spark = 0.18
		var top := sage_position() + Vector3(randf_range(-0.4, 0.4), 2.2, randf_range(-0.2, 0.2))
		fx.spawn(top, Vector3(0.0, 0.8, 0.0), 0.7, FxSprites.TILE_STAR, palette_index, 2, 12.0, 4.0, -0.3, 1.0)
