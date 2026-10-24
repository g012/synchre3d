class_name FxSprites
extends Node3D
## Tiny CPU particle system for pixel FX: one MultiMesh, a fixed pool, deterministic motion.

const MAX := 192
const TILE_PUFF := 0
const TILE_STAR := 1
const TILE_SPARK := 2
const TILE_RING := 3

@export var material: ShaderMaterial

var _mm: MultiMesh
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _life := PackedFloat32Array()
var _max_life := PackedFloat32Array()
var _size0 := PackedFloat32Array()
var _size1 := PackedFloat32Array()
var _gravity := PackedFloat32Array()
var _drag := PackedFloat32Array()
var _tile := PackedInt32Array()
var _pal := PackedInt32Array()
var _band := PackedInt32Array()
var _next := 0


func _ready() -> void:
	# Packed arrays are values in GDScript: resize each member directly.
	_pos.resize(MAX)
	_vel.resize(MAX)
	_life.resize(MAX)
	_max_life.resize(MAX)
	_size0.resize(MAX)
	_size1.resize(MAX)
	_gravity.resize(MAX)
	_drag.resize(MAX)
	_tile.resize(MAX)
	_pal.resize(MAX)
	_band.resize(MAX)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	_mm.mesh = quad
	_mm.instance_count = MAX
	_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	add_child(mmi)


func spawn(pos: Vector3, vel: Vector3, life: float, tile: int, pal: int, band: int,
		size0: float, size1: float, gravity := 0.0, drag := 0.0) -> void:
	var i := _next
	_next = (_next + 1) % MAX
	_pos[i] = pos
	_vel[i] = vel
	_life[i] = life
	_max_life[i] = life
	_tile[i] = tile
	_pal[i] = pal
	_band[i] = band
	_size0[i] = size0
	_size1[i] = size1
	_gravity[i] = gravity
	_drag[i] = drag


## Small dust puff left behind while running.
func puff(pos: Vector3, scale := 1.0) -> void:
	spawn(pos, Vector3(randf_range(-0.3, 0.3), 0.5, randf_range(-0.3, 0.3)), 0.35, TILE_PUFF, 1, 1,
		round(6.0 * scale), 2.0, -1.0, 2.0)


## Ring of dust (landing, falling off an edge).
func dust_ring(pos: Vector3, count: int) -> void:
	for k in count:
		var a := TAU * k / count + randf() * 0.4
		var d := Vector3(cos(a), 0.0, sin(a))
		spawn(pos + d * 0.25, d * 2.2 + Vector3.UP * 0.6, 0.4, TILE_PUFF, 1, 1, 8.0, 2.0, -2.0, 5.0)


## Successful hit: star flash, sparks flying along the push direction, dust burst.
func impact(pos: Vector3, dir: Vector3) -> void:
	spawn(pos, Vector3.ZERO, 0.12, TILE_STAR, 6, 2, 16.0, 12.0)
	spawn(pos, Vector3.ZERO, 0.22, TILE_RING, 1, 2, 10.0, 22.0)
	for k in 9:
		var spread := Vector3(randf_range(-1, 1), randf_range(0.2, 1.6), randf_range(-1, 1))
		var v := (dir * randf_range(3.0, 6.5) + spread * 2.2)
		spawn(pos, v, randf_range(0.25, 0.45), TILE_SPARK, 6 if k % 2 == 0 else 1, 2, 3.0, 1.0, 12.0, 3.0)
	for k in 4:
		var a := randf() * TAU
		spawn(pos - Vector3.UP * 0.35, Vector3(cos(a), 0.4, sin(a)) * 1.6, 0.45, TILE_PUFF, 1, 1, 9.0, 2.0, -1.0, 4.0)


## Missed push: a small swipe of air.
func whoosh(pos: Vector3, dir: Vector3) -> void:
	for k in 3:
		spawn(pos + dir * 0.15 * k, dir * 2.5 + Vector3.UP * 0.2, 0.2, TILE_PUFF, 1, 2, 5.0 - k, 1.0, 0.0, 6.0)


## Elimination burst when a character disappears down a hole or off the island.
func vanish(pos: Vector3) -> void:
	for k in 10:
		var a := TAU * k / 10.0
		spawn(pos, Vector3(cos(a), randf_range(0.5, 1.5), sin(a)) * 2.0, 0.5, TILE_SPARK, 6, 2, 3.0, 1.0, -2.0, 3.0)


## Removes every live sprite (new round).
func clear() -> void:
	_life.fill(0.0)


func _process(delta: float) -> void:
	var count := 0
	for i in MAX:
		if _life[i] <= 0.0:
			continue
		_life[i] -= delta
		if _life[i] <= 0.0:
			continue
		_vel[i] = _vel[i] * exp(-_drag[i] * delta) + Vector3.DOWN * _gravity[i] * delta
		_pos[i] += _vel[i] * delta
		var t := 1.0 - _life[i] / _max_life[i]
		var size := roundf(lerpf(_size0[i], _size1[i], t))
		_mm.set_instance_transform(count, Transform3D(Basis.IDENTITY, _pos[i]))
		_mm.set_instance_custom_data(count, Color(_pal[i] / 32.0, _tile[i] / 4.0, size / 64.0, _band[i] / 4.0))
		count += 1
	_mm.visible_instance_count = count
