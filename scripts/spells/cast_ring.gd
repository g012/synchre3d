class_name CastRing
extends MeshInstance3D
## Ring on the ground around a fighter (see shaders/cast_ring.gdshader): pulses on every beat
## and shows the syllables of the incantation in progress, lit as they are validated.

const SHADER := preload("res://shaders/cast_ring.gdshader")

var caster: SpellCaster
var arena: Arena
var _mat: ShaderMaterial
var _shown := PackedInt32Array()
var _slots := -1


func _ready() -> void:
	top_level = true
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("palette_index", caster.character.color_index)
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	quad.orientation = PlaneMesh.FACE_Y
	mesh = quad
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(_delta: float) -> void:
	var c := caster.character
	visible = caster.listening and c.is_alive() and c.state != ArenaCharacter.State.SPAWNING
	if not visible:
		return
	var p := c.get_global_transform_interpolated().origin
	global_position = Vector3(p.x, arena.height_at(Vector2(p.x, p.z)) + 0.06, p.z)
	var chanted := caster.chanted()
	var slots := caster.chant_length()
	if chanted != _shown or slots != _slots:
		_shown = chanted
		_slots = slots
		var pips := PackedInt32Array(chanted)
		pips.resize(12)
		_mat.set_shader_parameter("pips", pips)
		_mat.set_shader_parameter("pip_count", mini(chanted.size(), 12))
		_mat.set_shader_parameter("slot_count", mini(slots, 12))
