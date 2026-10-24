class_name MagicBeam
extends Node3D
## The Push spell: a beam of light that shoots out from the caster's hands almost at once
## (no travel time), shoves and hurts every enemy along it, then thins out. Props block it.
## From level 2 SpellEffects also runs a ridge of rising ground along its path (see
## SpellEffects._update_wakes) that throws enemies out to the sides.

const SHADER := preload("res://shaders/magic.gdshader")
## Seconds to reach full length, to stay, and to thin out.
const GROW := 0.05
const HOLD := 0.12
const FADE := 0.22
## Height band (relative to the beam) in which a character is hit.
const HIT_HEIGHT := Vector2(-1.0, 0.6)

var caster: ArenaCharacter
var arena: Arena
var fx: FxSprites
var camera: PixelCamera
var direction := Vector3.FORWARD
var length := 8.0
var width := 0.5
var strength := 15.0
var damage := 0.0
var palette_index := 15

var _t := 0.0
var _pivot: Node3D
var _mat: ShaderMaterial
var _sparks := 0.0


func _ready() -> void:
	top_level = true
	direction.y = 0.0
	direction = direction.normalized()
	length = _clipped_length()
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("palette_index", palette_index)
	_mat.set_shader_parameter("energy", 1.0)
	var cyl := CylinderMesh.new()
	cyl.top_radius = width * 0.5
	cyl.bottom_radius = width * 0.5
	cyl.height = 1.0
	cyl.radial_segments = 10
	cyl.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0.0, 0.5, 0.0)
	# The pivot's +Y runs along the beam, so scaling Y grows it out of the hands.
	_pivot = Node3D.new()
	_pivot.basis = Basis(Quaternion(Vector3.UP, direction))
	_pivot.scale = Vector3(1.0, 0.001, 1.0)
	add_child(_pivot)
	_pivot.add_child(mi)
	_hit_all()
	if camera:
		camera.shake(0.22)
	if fx:
		fx.spawn(global_position, Vector3.ZERO, 0.12, FxSprites.TILE_STAR, palette_index, 2, 16.0, 6.0)


## Stops at the first prop in the way.
func _clipped_length() -> float:
	if not arena:
		return length
	var o := Vector2(global_position.x, global_position.z)
	var d := Vector2(direction.x, direction.z)
	var best := length
	for ob in arena.obstacles:
		var to := Vector2(ob.x, ob.y) - o
		var along := to.dot(d)
		if along > 0.0 and along < best and absf(to.cross(d)) < ob.z + width * 0.5:
			best = along
	return best


func _hit_all() -> void:
	var o := Vector2(global_position.x, global_position.z)
	var d := Vector2(direction.x, direction.z)
	for e in caster.enemies():
		var to := Vector2(e.global_position.x, e.global_position.z) - o
		var along := to.dot(d)
		var lateral := to.cross(d)
		var dy := e.global_position.y - global_position.y
		if along < -0.2 or along > length + ArenaCharacter.RADIUS or absf(lateral) > width * 0.5 + ArenaCharacter.RADIUS:
			continue
		if dy < HIT_HEIGHT.x or dy > HIT_HEIGHT.y:
			continue
		# Mostly along the beam, a little away from its axis.
		var side := Vector3(-d.y, 0.0, d.x) * signf(-lateral) * 0.25
		var dir := (direction + side).normalized()
		e.receive_push(dir, strength, caster)
		e.take_damage(damage, caster)
		if fx:
			fx.impact(e.global_position + Vector3.UP * 0.45, dir)


func _process(delta: float) -> void:
	_t += delta
	if _t < GROW:
		_pivot.scale = Vector3(1.0, maxf(_t / GROW, 0.001) * length, 1.0)
	elif _t < GROW + HOLD:
		_pivot.scale = Vector3(1.0 + 0.15 * sin(_t * 60.0), length, 1.0 + 0.15 * sin(_t * 60.0))
	elif _t < GROW + HOLD + FADE:
		var k := 1.0 - (_t - GROW - HOLD) / FADE
		_pivot.scale = Vector3(k, length, k)
		_mat.set_shader_parameter("energy", k)
	else:
		queue_free()
		return
	_sparks -= delta
	if fx and _sparks <= 0.0 and _t < GROW + HOLD:
		_sparks = 0.02
		var p := global_position + direction * randf() * length * minf(_t / GROW, 1.0)
		fx.spawn(p, Vector3(randf_range(-1, 1), randf_range(0.5, 1.5), randf_range(-1, 1)) * 1.2, 0.3,
			FxSprites.TILE_SPARK, palette_index, 2, 3.0, 1.0, 1.0, 3.0)
