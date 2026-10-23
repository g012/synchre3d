class_name MagicBolt
extends Node3D
## A spell projectile flying straight from the caster's hands, hitting the first enemy it
## touches: Push (a big ball of light that shoves hard), Swap (a small fast ball: caster and
## target trade places), Knockout (a spinning star that stuns) or Snare (a slow, heavy blob
## that slows the target down).
## It glides over gentle slopes but bursts against steep ones (a mountain is a shield).

enum Kind { PUSH, SWAP, KNOCKOUT, SNARE }

const SHADER := preload("res://shaders/magic.gdshader")

var kind := Kind.PUSH
var caster: ArenaCharacter
var arena: Arena
var fx: FxSprites
var camera: PixelCamera
var direction := Vector3.FORWARD
var speed := 16.0
var max_range := 9.0
## Visual radius of the ball.
var radius := 0.36
## Horizontal hit radius around the target's centre.
var hit_radius := 0.8
var strength := 15.0
## Health taken from the target (survival).
var damage := 0.0
## Knockout duration (s).
var stun_time := 2.0
## Snare: speed multiplier and duration (s).
var slow_mult := 0.5
var slow_time := 3.0
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
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	_mesh = MeshInstance3D.new()
	_mesh.mesh = sphere
	_mesh.material_override = mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_mesh)


## Height kept above the ground while gliding.
const GLIDE := 0.5


func _physics_process(delta: float) -> void:
	var step := direction * speed * delta
	global_position += step
	if arena:
		# Climbs anything walkable at once (<= ~50 deg), bursts against steeper ground,
		# and sinks back gently after a crest.
		# Skims over pond water rather than diving to the bed.
		var ground := maxf(arena.height_at(Vector2(global_position.x, global_position.z)), Arena.WATER_LEVEL) + GLIDE
		var climb := ground - global_position.y
		if climb > step.length() * 1.2 + 0.05:
			_pop()
			return
		if climb > 0.0:
			global_position.y = ground
		else:
			global_position.y = move_toward(global_position.y, ground, 2.5 * delta)
	_travelled += step.length()
	_mesh.scale = Vector3.ONE * (1.0 + 0.12 * sin(_travelled * 9.0))
	if kind == Kind.SNARE:
		# A wobbling, heavy blob.
		_mesh.scale = Vector3(1.0 + 0.15 * sin(_travelled * 5.0), 1.0 - 0.15 * sin(_travelled * 5.0), 1.0)
	if kind == Kind.KNOCKOUT:
		_mesh.scale = Vector3(1.0, 0.45, 1.0) * (1.0 + 0.15 * sin(_travelled * 6.0))
		_mesh.rotation = Vector3(0.0, _travelled * 4.0, 0.5)

	_trail -= delta
	if fx and _trail <= 0.0:
		_trail = 0.025
		var tile := FxSprites.TILE_STAR if kind == Kind.KNOCKOUT else FxSprites.TILE_SPARK
		fx.spawn(global_position - direction * radius, -direction * 1.5 + Vector3.UP * 0.3, 0.25,
			tile, palette_index, 2, 4.0 + radius * 6.0, 1.0, 0.0, 4.0)

	for t in caster.enemies():
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
	target.take_damage(damage, caster)
	match kind:
		Kind.PUSH:
			target.receive_push(dir, strength, caster)
			if fx:
				fx.impact(global_position, dir)
				fx.spawn(global_position, Vector3.ZERO, 0.22, FxSprites.TILE_RING, palette_index, 2, 14.0, 34.0)
			if camera:
				camera.shake(0.32)
		Kind.SWAP:
			if caster.is_alive():
				_swap(target)
		Kind.SNARE:
			target.slow_down(slow_mult, slow_time)
			if fx:
				for k in 10:
					var a := TAU * k / 10.0
					fx.spawn(global_position, Vector3(cos(a), 0.4, sin(a)) * 1.6, 0.5, FxSprites.TILE_PUFF, palette_index, 2, 7.0, 3.0, 4.0, 2.0)
			if camera:
				camera.shake(0.12)
		Kind.KNOCKOUT:
			target.knock_out(stun_time)
			if fx:
				fx.spawn(global_position, Vector3.ZERO, 0.2, FxSprites.TILE_STAR, palette_index, 2, 16.0, 8.0)
				fx.spawn(global_position, Vector3.ZERO, 0.2, FxSprites.TILE_RING, palette_index, 2, 8.0, 20.0)
			if camera:
				camera.shake(0.18)
	queue_free()


## Caster and target trade places (and lose their momentum).
func _swap(target: ArenaCharacter) -> void:
	var a := caster.global_position
	var b := target.global_position
	for pair in [[caster, b], [target, a]]:
		var c: ArenaCharacter = pair[0]
		var to: Vector3 = pair[1]
		if fx:
			_sparkle(c.global_position)
		c.global_position = to
		c.velocity = Vector3.ZERO
		c.reset_physics_interpolation()
		if fx:
			_sparkle(to)
	if camera:
		camera.shake(0.15)


func _sparkle(p: Vector3) -> void:
	for k in 8:
		var a := TAU * k / 8.0
		fx.spawn(p + Vector3.UP * 0.4, Vector3(cos(a), randf_range(-0.3, 0.8), sin(a)) * 1.6, 0.35,
			FxSprites.TILE_SPARK, palette_index, 2, 3.0, 1.0, 0.0, 3.0)
	fx.spawn(p + Vector3.UP * 0.4, Vector3.ZERO, 0.2, FxSprites.TILE_RING, palette_index, 2, 6.0, 18.0)


func _pop() -> void:
	if fx:
		for k in 6:
			var a := TAU * k / 6.0
			fx.spawn(global_position, Vector3(cos(a), 0.5, sin(a)) * 1.8, 0.3, FxSprites.TILE_SPARK, palette_index, 2, 3.0, 1.0, 0.0, 4.0)
	queue_free()
