class_name MagicOrb
extends Node3D
## The magic a caster gathers between their hands while chanting. It grows with each correct
## syllable, sheds motes of the spell's color, and either flashes when the spell fires or
## bursts into grey puffs when the incantation fizzles.

const SHADER := preload("res://shaders/magic.gdshader")

var character: ArenaCharacter
var fx: FxSprites

var _mesh: MeshInstance3D
var _mat: ShaderMaterial
var _level := 0.0
var _target := 0.0
var _palette := 15
var _mote_timer := 0.0
var _time := 0.0


func _ready() -> void:
	top_level = true
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	_mesh = MeshInstance3D.new()
	_mesh.mesh = sphere
	_mesh.material_override = _mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	visible = false


## Progress of the incantation in progress (0 = none, 1 = complete) and its color.
func set_progress(level: float, palette_index: int) -> void:
	_target = level
	_palette = palette_index
	_mat.set_shader_parameter("palette_index", palette_index)
	if level > 0.0 and fx:
		# A little flare at the hands on every correct syllable.
		for k in 4:
			var a := TAU * k / 4.0 + randf() * 0.6
			fx.spawn(global_position, Vector3(cos(a), 0.6, sin(a)) * 1.6, 0.22, FxSprites.TILE_SPARK, palette_index, 2, 3.0, 1.0, 0.0, 6.0)


## The spell fired: brief bright flash, then the orb is gone (the effect takes over).
func release() -> void:
	if fx and _level > 0.01:
		fx.spawn(global_position, Vector3.ZERO, 0.12, FxSprites.TILE_STAR, _palette, 2, 14.0, 6.0)
	_level = 0.0
	_target = 0.0


## The incantation broke: the gathered energy dissipates as grey puffs.
func fizzle() -> void:
	if fx and _level > 0.01:
		for k in 6:
			var a := TAU * k / 6.0
			fx.spawn(global_position, Vector3(cos(a), 0.8, sin(a)) * 1.3, 0.4, FxSprites.TILE_PUFF, 17, 1, 6.0, 2.0, -1.0, 4.0)
	_target = 0.0


func _process(delta: float) -> void:
	if not character:
		return
	_time += delta
	# Grow quickly, shrink a bit slower; an idle orb fully disappears.
	_level = move_toward(_level, _target, delta * (3.0 if _target > _level else 5.0))
	visible = _level > 0.01 and character.is_alive()
	if not visible:
		return
	global_position = character.hand_anchor()
	var pulse := 1.0 + 0.08 * sin(_time * 18.0)
	_mesh.scale = Vector3.ONE * (0.07 + 0.17 * _level) * pulse
	_mat.set_shader_parameter("energy", _level)
	_mote_timer -= delta
	if fx and _mote_timer <= 0.0:
		_mote_timer = lerpf(0.16, 0.04, _level)
		var a := randf() * TAU
		var r := 0.15 + 0.2 * _level
		var p := global_position + Vector3(cos(a) * r, randf_range(-0.1, 0.15), sin(a) * r)
		fx.spawn(p, Vector3(-sin(a), 0.9, cos(a)) * 0.8, 0.35, FxSprites.TILE_SPARK, _palette, 2, 3.0, 1.0, -0.5, 1.0)
