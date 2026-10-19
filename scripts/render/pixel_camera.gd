class_name PixelCamera
extends Camera3D
## Orthographic camera locked to the low-res pixel grid.
##
## The camera position is snapped to whole texels in its own (fixed) view plane, so static
## geometry rasterizes identically every frame (no crawling edges). The snapped-away fraction
## is exposed as `texel_error` so the display can shift the upscaled image by that sub-pixel
## amount, which keeps camera shake/drift smooth. `snap_point()` lets moving objects snap
## to the same grid so their pixels do not shimmer either.

## World units covered by one low-res pixel. Controls the overall "pixel density".
@export var texel_size := 0.031
## Pitch and yaw of the view, in degrees.
@export var pitch_deg := -40.0
@export var yaw_deg := 0.0
## Point the camera looks at.
@export var focus := Vector3(0.0, -0.75, 0.25)
@export var distance := 30.0

@export_group("Follow")
## Nodes kept in view (the fighters). Empty = fixed `focus`.
var targets: Array[Node3D] = []
## Space kept around the targets, in world units on the view plane (x, y).
@export var follow_margin := Vector2(5.5, 3.6)
## The camera zooms out (larger texels) up to this when the targets spread apart.
@export var max_texel_size := 0.05
@export var follow_speed := 2.5
@export var zoom_speed := 1.4
## The focus stays inside this XZ rectangle (set from the arena size).
var focus_bounds := Rect2(-1e4, -1e4, 2e4, 2e4)
@export_group("")

## Optional sun whose direction is forwarded to the post-process edge highlights.
@export var sun: DirectionalLight3D
@export var post_process: MeshInstance3D

var texel_error := Vector2.ZERO

var _snap_basis := Basis.IDENTITY
var _shake_strength := 0.0
var _shake_time := 0.0
var _noise := FastNoiseLite.new()
var _base_texel := 0.0
var _focus_offset := Vector3.ZERO


func _ready() -> void:
	if not sun:
		sun = get_node_or_null("../Sun") as DirectionalLight3D
	if not post_process:
		post_process = get_node_or_null("PostProcess") as MeshInstance3D
	projection = PROJECTION_ORTHOGONAL
	keep_aspect = KEEP_HEIGHT
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_noise.frequency = 1.0
	_noise.seed = 7
	_base_texel = texel_size
	_focus_offset = Vector3(0.0, focus.y, focus.z)
	_update_basis()


func _update_basis() -> void:
	_snap_basis = Basis.from_euler(Vector3(deg_to_rad(pitch_deg), deg_to_rad(yaw_deg), 0.0))


## Adds trauma-style shake; strength is in world units.
func shake(strength: float) -> void:
	_shake_strength = maxf(_shake_strength, strength)


## Recentres instantly on the targets (new round).
func snap_to_targets() -> void:
	_follow(0.0, true)


## Moves the focus toward the targets' centre and zooms out just enough to keep all of
## them (plus a margin) on screen; never zooms in past the authored pixel density.
func _follow(delta: float, instant := false) -> void:
	var pts: Array[Vector3] = []
	for t in targets:
		if is_instance_valid(t) and t.is_visible_in_tree():
			pts.append(t.global_position)
	if pts.is_empty():
		return
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	var mid := Vector3.ZERO
	var inv := _snap_basis.inverse()
	for p in pts:
		mid += p
		var v := inv * p
		lo = lo.min(v)
		hi = hi.max(v)
	mid /= pts.size()
	var vp := Vector2((get_viewport() as SubViewport).size)
	var need := maxf((hi.x - lo.x + follow_margin.x * 2.0) / vp.x, (hi.y - lo.y + follow_margin.y * 2.0) / vp.y)
	var target_texel := clampf(need, _base_texel, max_texel_size)
	var c := Vector2(clampf(mid.x, focus_bounds.position.x, focus_bounds.end.x), clampf(mid.z, focus_bounds.position.y, focus_bounds.end.y))
	var target_focus := Vector3(c.x, _focus_offset.y + mid.y * 0.5, c.y + _focus_offset.z)
	if instant:
		texel_size = target_texel
		focus = target_focus
	else:
		texel_size = lerpf(texel_size, target_texel, 1.0 - exp(-zoom_speed * delta))
		focus = focus.lerp(target_focus, 1.0 - exp(-follow_speed * delta))


func _process(delta: float) -> void:
	_update_basis()
	_follow(delta)
	var vp_height := float((get_viewport() as SubViewport).size.y)
	size = texel_size * vp_height

	_shake_time += delta * 30.0
	_shake_strength = move_toward(_shake_strength, 0.0, delta * 1.6)
	var s := _shake_strength * _shake_strength * 4.0
	var shake_offset := Vector3(_noise.get_noise_2d(_shake_time, 0.0), _noise.get_noise_2d(0.0, _shake_time), 0.0) * s

	var desired := focus + _snap_basis * (Vector3(0, 0, distance) + shake_offset)
	# Express in the camera's own plane, snap x/y to texels, keep depth.
	var local := _snap_basis.inverse() * desired
	var snapped_local := Vector3(snappedf(local.x, texel_size), snappedf(local.y, texel_size), local.z)
	global_transform = Transform3D(_snap_basis, _snap_basis * snapped_local)
	texel_error = Vector2(local.x - snapped_local.x, local.y - snapped_local.y) / texel_size

	if sun and post_process:
		var to_light := sun.global_transform.basis.z.normalized()
		var mat := post_process.mesh.surface_get_material(0) as ShaderMaterial
		mat.set_shader_parameter("light_dir_view", _snap_basis.inverse() * to_light)


## Returns `world` moved by less than one texel so it lands on the camera's pixel grid.
func snap_point(world: Vector3) -> Vector3:
	var local := _snap_basis.inverse() * world
	local.x = snappedf(local.x, texel_size)
	local.y = snappedf(local.y, texel_size)
	return _snap_basis * local


## Screen-relative movement axes on the ground plane (right, down-screen).
func ground_axes() -> Array[Vector3]:
	var right := _snap_basis.x
	right.y = 0.0
	var forward := -_snap_basis.z
	forward.y = 0.0
	return [right.normalized(), -forward.normalized()]
