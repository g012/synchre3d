class_name MagicOrb
extends Node3D
## The magic a caster gathers between their hands while chanting. It grows with each correct
## syllable, sheds motes, and either flashes when the spell fires or bursts into grey puffs
## when the incantation fizzles.
##
## While the syllables so far could still become several spells (they share an opening),
## the orb is a shared, pale magic with one small satellite per possible spell circling it in
## that spell's color. Satellites drop out (shrinking into the core) as the chant rules their
## spell out, and once one spell is left the core morphs into its color.

const SHADER := preload("res://shaders/magic.gdshader")
## Color of magic not yet committed to one spell.
const SHARED_PALETTE := 18
const SATELLITE_RADIUS := 0.085

var character: ArenaCharacter
var fx: FxSprites

var _mesh: MeshInstance3D
var _mat: ShaderMaterial
var _level := 0.0
var _target := 0.0
var _palettes := PackedInt32Array()
var _morph := 0.0
var _mote_timer := 0.0
var _time := 0.0
# Satellites by palette index: { mesh, mat, size (0..1 shown), alive, angle }.
var _satellites := {}


func _ready() -> void:
	top_level = true
	_mat = _material(SHARED_PALETTE)
	_mesh = _sphere(1.0, _mat)
	add_child(_mesh)
	visible = false


func _material(palette: int) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("palette_index", palette)
	mat.set_shader_parameter("palette_index_b", palette)
	return mat


func _sphere(radius: float, mat: ShaderMaterial) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	var mi := MeshInstance3D.new()
	mi.mesh = sphere
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Progress of the incantation in progress (0 = none, 1 = complete) and the palette of
## every spell it could still become.
func set_progress(level: float, palettes: PackedInt32Array) -> void:
	var grew := level > _target
	var was_idle := _target <= 0.0
	_target = level
	_palettes = palettes
	if palettes.is_empty():
		return
	# Core: shared color while undecided, then morphing into the one spell left.
	_mat.set_shader_parameter("palette_index", SHARED_PALETTE)
	_mat.set_shader_parameter("palette_index_b", palettes[0])
	if palettes.size() == 1 and was_idle:
		_morph = 1.0
	elif palettes.size() > 1:
		_morph = 0.0
	for p in _satellites:
		_satellites[p].alive = palettes.size() > 1 and p in palettes
	if palettes.size() > 1:
		for p in palettes:
			if not _satellites.has(p):
				var mat := _material(p)
				var mi := _sphere(SATELLITE_RADIUS, mat)
				add_child(mi)
				_satellites[p] = {"mesh": mi, "mat": mat, "size": 0.0, "alive": true,
					"angle": TAU * _satellites.size() / maxf(palettes.size(), 1.0)}
	if grew and fx:
		# A little flare at the hands on every correct syllable, in each possible color.
		for k in 4:
			var a := TAU * k / 4.0 + randf() * 0.6
			fx.spawn(global_position, Vector3(cos(a), 0.6, sin(a)) * 1.6, 0.22, FxSprites.TILE_SPARK,
				palettes[k % palettes.size()], 2, 3.0, 1.0, 0.0, 6.0)


## The spell fired: brief bright flash in its color, then the orb is gone (the effect takes
## over).
func release(palette: int) -> void:
	if fx and _level > 0.01:
		fx.spawn(global_position, Vector3.ZERO, 0.12, FxSprites.TILE_STAR, palette, 2, 14.0, 6.0)
	_level = 0.0
	_target = 0.0
	_clear_satellites()


## The incantation broke (no spell can continue it): the gathered energy dissipates as grey
## puffs.
func fizzle() -> void:
	if fx and _level > 0.01:
		for k in 6:
			var a := TAU * k / 6.0
			fx.spawn(global_position, Vector3(cos(a), 0.8, sin(a)) * 1.3, 0.4, FxSprites.TILE_PUFF, 17, 1, 6.0, 2.0, -1.0, 4.0)
	_target = 0.0
	for p in _satellites:
		_satellites[p].alive = false


func _clear_satellites() -> void:
	for p in _satellites:
		_satellites[p].mesh.queue_free()
	_satellites.clear()


func _process(delta: float) -> void:
	if not character:
		return
	_time += delta
	# Grow quickly, shrink a bit slower; an idle orb fully disappears.
	_level = move_toward(_level, _target, delta * (3.0 if _target > _level else 5.0))
	visible = _level > 0.01 and character.is_alive()
	if not visible:
		if _target <= 0.0 and not _satellites.is_empty():
			_clear_satellites()
		return
	global_position = character.hand_anchor()
	var pulse := 1.0 + 0.08 * sin(_time * 18.0)
	var core := (0.07 + 0.17 * _level) * pulse
	_mesh.scale = Vector3.ONE * core
	_mat.set_shader_parameter("energy", _level)
	if _palettes.size() == 1:
		_morph = move_toward(_morph, 1.0, delta * 5.0)
	_mat.set_shader_parameter("morph", _morph)

	# Satellites orbit just outside the core; ruled-out ones sink into it and vanish.
	var gone: Array = []
	var i := 0
	for p in _satellites:
		var s: Dictionary = _satellites[p]
		s.size = move_toward(s.size, 1.0 if s.alive else 0.0, delta * (6.0 if s.alive else 4.0))
		if s.size <= 0.0 and not s.alive:
			gone.append(p)
			continue
		s.angle += delta * 5.0
		var r: float = (core + SATELLITE_RADIUS * 2.0) * (0.4 + 0.6 * s.size)
		var bob := sin(_time * 7.0 + i * 2.1) * 0.03
		s.mesh.position = Vector3(cos(s.angle) * r, bob, sin(s.angle) * r)
		s.mesh.scale = Vector3.ONE * s.size * (0.8 + 0.6 * _level)
		s.mat.set_shader_parameter("energy", _level)
		i += 1
	for p in gone:
		_satellites[p].mesh.queue_free()
		_satellites.erase(p)

	_mote_timer -= delta
	if fx and _mote_timer <= 0.0 and not _palettes.is_empty():
		_mote_timer = lerpf(0.16, 0.04, _level)
		var a := randf() * TAU
		var r := 0.15 + 0.2 * _level
		var p := global_position + Vector3(cos(a) * r, randf_range(-0.1, 0.15), sin(a) * r)
		fx.spawn(p, Vector3(-sin(a), 0.9, cos(a)) * 0.8, 0.35, FxSprites.TILE_SPARK,
			_palettes[randi() % _palettes.size()], 2, 3.0, 1.0, -0.5, 1.0)
