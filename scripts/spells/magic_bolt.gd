class_name MagicBolt
extends Node3D
## The Push spell's projectile: a glowing orb that flies straight from the caster's hands and
## shoves the first opponent it touches with the same knockback as the old melee push.

const SHADER := preload("res://shaders/magic.gdshader")

var caster: ArenaCharacter
var targets: Array[ArenaCharacter] = []
var arena: Arena
var fx: FxSprites
var camera: PixelCamera
var direction := Vector3.FORWARD
var speed := 12.0
var max_range := 7.5
## Horizontal hit radius around the target's centre.
var hit_radius := 0.6
var strength := 11.5
var palette_index := 15

var _travelled := 0.0
var _trail := 0.0
var _mesh: MeshInstance3D


func _ready() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("palette_index", palette_index)
	mat.set_shader_parameter("energy", 0.55)
	var sphere := SphereMesh.new()
	sphere.radius = 0.24
	sphere.height = 0.48
	sphere.radial_segments = 12
	sphere.rings = 6
	_mesh = MeshInstance3D.new()
	_mesh.mesh = sphere
	_mesh.material_override = mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_mesh)


func _physics_process(delta: float) -> void:
	var step := direction * speed * delta
	global_position += step
	_travelled += step.length()
	_mesh.scale = Vector3.ONE * (1.0 + 0.12 * sin(_travelled * 9.0))

	_trail -= delta
	if fx and _trail <= 0.0:
		_trail = 0.025
		fx.spawn(global_position - direction * 0.2, -direction * 1.5 + Vector3.UP * 0.3, 0.25,
			FxSprites.TILE_SPARK, palette_index, 2, 4.0, 1.0, 0.0, 4.0)

	for t in targets:
		if t == caster or not t.is_alive() or t.state == ArenaCharacter.State.SPAWNING:
			continue
		var d := t.global_position - global_position
		var dy := global_position.y - (t.global_position.y + 0.45)
		d.y = 0.0
		if d.length() < hit_radius and absf(dy) < 0.8:
			_hit(t)
			return
	if arena:
		var p := Vector2(global_position.x, global_position.z)
		for o in arena.obstacles:
			if global_position.y < 2.5 and p.distance_to(Vector2(o.x, o.y)) < o.z + 0.15:
				_pop()
				return
	if _travelled >= max_range:
		_pop()


func _hit(target: ArenaCharacter) -> void:
	var to := target.global_position - global_position
	to.y = 0.0
	var dir := (direction * 0.8 + to.normalized() * 0.2).normalized()
	target.receive_push(dir, strength, caster)
	if fx:
		fx.impact(global_position, dir)
		fx.spawn(global_position, Vector3.ZERO, 0.18, FxSprites.TILE_RING, palette_index, 2, 10.0, 26.0)
	if camera:
		camera.shake(0.26)
	queue_free()


func _pop() -> void:
	if fx:
		for k in 6:
			var a := TAU * k / 6.0
			fx.spawn(global_position, Vector3(cos(a), 0.5, sin(a)) * 1.8, 0.3, FxSprites.TILE_SPARK, palette_index, 2, 3.0, 1.0, 0.0, 4.0)
	queue_free()
