class_name ArenaCharacter
extends CharacterBody3D
## A pushable arena fighter: screen-relative movement with inertia, a short-range push,
## knockback with friction, and falling when the ground under it disappears. Also used,
## scaled down, for summoned minions (see SpellEffects).
##
## Support follows the arena's exact ground outline (the same function the shaders cut
## holes with): as soon as a grounded character's centre is over a hole or off the island
## it stops colliding with the floor and drops, kept inside the hole it fell into. Animation is fully procedural on the separate
## rigid parts of the Blender model (body, head, eyes, hands, feet).

signal pushed(attacker: ArenaCharacter, target: ArenaCharacter, hit: bool)
signal fell(character: ArenaCharacter)
signal eliminated(character: ArenaCharacter)
signal landed(character: ArenaCharacter)
signal jumped(character: ArenaCharacter)
signal dashed(character: ArenaCharacter)

enum State { SPAWNING, ACTIVE, PUSHING, HITSTUN, FALLING, OUT, VICTORY, FROZEN }

@export var display_name := "Pip"
@export var model_scene: PackedScene
## Palette index used for this character's HUD color.
@export var color_index := 4
## Uniform scale applied to the model (collision is set in character.tscn).
@export var model_scale := 1.15
## Characters only shove / get hit by characters of another team (a fighter and their
## minions share one).
@export var team := 0
## Height above the spawn point a character drops from.
@export var spawn_height := 3.5
## Starts fighting as soon as it lands (minions) instead of waiting for the round to start.
@export var auto_activate := false
## Permanent dithered darkening (0..1): summoned undead minions.
@export var shade := 0.0

@export_group("Movement")
@export var move_speed := 5.0
@export var acceleration := 38.0
@export var deceleration := 30.0
@export var turn_speed := 18.0
@export var gravity := 30.0
## Initial upward speed of a jump (with gravity 30: ~0.9 high, ~0.5 s in the air).
@export var jump_velocity := 7.4
## Fraction of ground acceleration available in the air.
@export var air_control := 0.7

@export_group("Dash")
## Horizontal speed of a dash (move_speed is 5), held for `dash_time`, then braked normally.
@export var dash_speed := 13.0
@export var dash_time := 0.16
## Seconds before the next dash. One dash per jump while airborne.
@export var dash_cooldown := 0.65

@export_group("Push")
## Reach measured from this character's centre to the target's centre.
@export var push_range := 1.2
## Half-angle of the push cone in degrees.
@export var push_half_angle := 55.0
## Kept below the Push spell's bolt so the spell is worth chanting.
@export var push_strength := 7.5
@export var push_cooldown := 0.45
@export var push_windup := 0.07
@export var push_active := 0.07
@export var push_recovery := 0.17
## Forward lunge speed at the start of a push.
@export var lunge_speed := 4.0
@export var recoil_speed := 2.2

@export_group("Knockback")
@export var hitstun_time := 0.36
## Exponential friction applied to knockback velocity (1/s).
@export var knockback_friction := 3.4
@export var hitstop_time := 0.07

var brain: CharacterBrain
var opponent: ArenaCharacter
var arena: Arena
var camera: PixelCamera
var fx: FxSprites

var state := State.FROZEN
var facing := Vector3.FORWARD
var _facing_angle := 0.0
var _state_time := 0.0
var _cooldown := 0.0
var _push_resolved := false
var _hitstop := 0.0
var _fall_time := 0.0
## The hole being fallen into ({} when falling off the outer edge).
var _fall_hole := {}

# Visual / animation
var _visual: Node3D
var _pivot: Node3D
var _parts := {}
var _rest := {}
var _meshes: Array[MeshInstance3D] = []
var _walk_phase := 0.0
var _squash := 0.0
var _squash_vel := 0.0
var _flash := 0.0
var _blink_timer := 2.0
var _anim_time := 0.0
var _lean := 0.0
var _hit_lean := 0.0
var _dust_timer := 0.0
var _spin := 0.0
var _jump_buffer := 0.0
var _was_airborne := false
var _dash_t := 0.0
var _dash_cd := 0.0
var _dash_fx := 0.0
var _air_dash_used := false
## Seconds left knocked out: no control, still pushable.
var _ko := 0.0
var _ko_fx := 0.0
## Incantation visuals, driven by the SpellCaster: 0 = idle, 1 = last syllable reached.
var cast_level := 0.0
var _cast_pose := 0.0
var _cast_bob := 0.0

const GROUND_MASK := Arena.LAYER_FLOOR | Arena.LAYER_OBSTACLES
const FALL_MASK := Arena.LAYER_WALLS
const RADIUS := 0.36
const GROUP := &"arena_characters"
## Squash spring sub-step: explicit integration of this stiff spring diverges past ~70 ms
## per step (e.g. a frame hitch when the window regains focus), so long frames are split.
const SPRING_STEP := 1.0 / 120.0


func _ready() -> void:
	collision_layer = Arena.LAYER_CHARACTERS
	collision_mask = GROUND_MASK
	floor_snap_length = 0.2
	# Hills (up to ~43 deg) are walkable; mountain flanks are not.
	floor_max_angle = deg_to_rad(47.0)
	add_to_group(GROUP)
	_build_visual()


func _build_visual() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	_visual.top_level = true
	_visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_visual)
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	_visual.add_child(_pivot)
	var model := model_scene.instantiate() as Node3D
	model.scale = Vector3.ONE * model_scale
	_pivot.add_child(model)
	for part in ["Body", "Head", "EyeL", "EyeR", "HandL", "HandR", "FootL", "FootR"]:
		var n := model.find_child(part, true, false) as Node3D
		if n:
			_parts[part] = n
			_rest[part] = n.transform
	_meshes = ToonMaterials.mesh_instances(model)
	for mi in _meshes:
		mi.material_override = ToonMaterials.CHARACTER


# ------------------------------------------------------------------ round control

func spawn(at: Vector3, face: Vector3) -> void:
	global_position = at + Vector3.UP * spawn_height
	velocity = Vector3.ZERO
	facing = face.normalized()
	_facing_angle = atan2(facing.x, facing.z)
	collision_mask = GROUND_MASK
	_cooldown = 0.0
	_hitstop = 0.0
	_squash = 0.0
	_squash_vel = 0.0
	_flash = 0.0
	_spin = 0.0
	_hit_lean = 0.0
	_jump_buffer = 0.0
	_dash_t = 0.0
	_dash_cd = 0.0
	_air_dash_used = false
	_ko = 0.0
	cast_level = 0.0
	_set_state(State.SPAWNING)
	_visual.visible = true
	reset_physics_interpolation()


func set_frozen(frozen: bool) -> void:
	if frozen and state in [State.ACTIVE, State.PUSHING, State.HITSTUN]:
		_set_state(State.FROZEN)
	elif not frozen and state == State.FROZEN:
		_set_state(State.ACTIVE)


func celebrate() -> void:
	if state in [State.ACTIVE, State.PUSHING, State.HITSTUN, State.FROZEN]:
		_set_state(State.VICTORY)


func is_alive() -> bool:
	return state != State.FALLING and state != State.OUT


func is_controllable() -> bool:
	return state == State.ACTIVE and _ko <= 0.0


func is_knocked_out() -> bool:
	return _ko > 0.0


## Can't move, push, jump or dash for `seconds`; still pushed around (and still chants).
func knock_out(seconds: float) -> void:
	if not is_alive():
		return
	_ko = maxf(_ko, seconds)
	_dash_t = 0.0
	_squash_vel += 8.0


## Alive characters of other teams (fighters and minions).
func enemies() -> Array[ArenaCharacter]:
	var out: Array[ArenaCharacter] = []
	for n in get_tree().get_nodes_in_group(GROUP):
		var c := n as ArenaCharacter
		if c and c.team != team and c.is_alive() and c.state != State.SPAWNING:
			out.append(c)
	return out


func _set_state(s: State) -> void:
	state = s
	_state_time = 0.0


# ------------------------------------------------------------------ simulation

func _physics_process(delta: float) -> void:
	if _hitstop > 0.0:
		_hitstop -= delta
		return
	_state_time += delta
	_cooldown = maxf(_cooldown - delta, 0.0)
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	_dash_cd = maxf(_dash_cd - delta, 0.0)
	_ko = maxf(_ko - delta, 0.0)
	if brain:
		brain.update(self, delta)
		if brain.wants_jump(self) and _ko <= 0.0:
			_jump_buffer = 0.12

	match state:
		State.SPAWNING:
			velocity.y -= gravity * delta
			move_and_slide()
			if is_on_floor():
				velocity = Vector3.ZERO
				_squash_vel += 7.0
				if fx:
					fx.dust_ring(global_position, 6)
				landed.emit(self)
				_set_state(State.ACTIVE if auto_activate else State.FROZEN)
		State.ACTIVE:
			if _ko > 0.0:
				var h := Vector2(velocity.x, velocity.z).move_toward(Vector2.ZERO, deceleration * delta)
				velocity.x = h.x
				velocity.z = h.y
				_ko_stars(delta)
				_apply_gravity_and_move(delta)
				return
			if _dash_t > 0.0:
				# Committed burst: no steering until it ends, then normal braking takes over.
				_dash_t -= delta
				_dash_trail(delta)
			else:
				_update_move(delta, 1.0 if is_on_floor() else air_control)
			if brain and brain.wants_push(self) and _cooldown <= 0.0 and is_on_floor():
				_start_push()
			_try_dash()
			_try_jump()
			_apply_gravity_and_move(delta)
		State.PUSHING:
			_update_push(delta)
			_try_jump()
			_apply_gravity_and_move(delta)
		State.HITSTUN:
			var h := Vector2(velocity.x, velocity.z) * exp(-knockback_friction * delta)
			velocity.x = h.x
			velocity.z = h.y
			if _state_time > hitstun_time:
				_set_state(State.ACTIVE)
			if _ko > 0.0:
				_ko_stars(delta)
			_apply_gravity_and_move(delta)
		State.FALLING:
			_fall_time += delta
			velocity.y -= gravity * delta
			velocity.x *= exp(-1.2 * delta)
			velocity.z *= exp(-1.2 * delta)
			move_and_slide()
			_keep_inside_hole()
			if global_position.y < arena.height_at(_xz()) - arena.layout.thickness - 1.6 or _fall_time > 2.5:
				_set_state(State.OUT)
				_visual.visible = false
				eliminated.emit(self)
		State.VICTORY, State.FROZEN:
			var h := Vector2(velocity.x, velocity.z).move_toward(Vector2.ZERO, deceleration * delta)
			velocity.x = h.x
			velocity.z = h.y
			_apply_gravity_and_move(delta)
		State.OUT:
			pass


## `control` scales acceleration/braking (lower in the air), never the top speed, so a
## running jump keeps its momentum.
func _update_move(delta: float, control: float) -> void:
	var wish: Vector3 = brain.get_move(self) if brain else Vector3.ZERO
	wish.y = 0.0
	if wish.length() > 1.0:
		wish = wish.normalized()
	var target := Vector2(wish.x, wish.z) * move_speed
	var cur := Vector2(velocity.x, velocity.z)
	var rate := (acceleration if target.length_squared() > 0.0001 else deceleration) * control
	# Faster response when reversing direction keeps the controls snappy.
	if target.length_squared() > 0.0001 and cur.dot(target) < 0.0:
		rate *= 1.6
	cur = cur.move_toward(target, rate * delta)
	velocity.x = cur.x
	velocity.z = cur.y
	if wish.length_squared() > 0.01:
		_turn_towards(wish, delta)


func _turn_towards(dir: Vector3, delta: float) -> void:
	var target := atan2(dir.x, dir.z)
	_facing_angle = rotate_toward(_facing_angle, target, turn_speed * delta)
	facing = Vector3(sin(_facing_angle), 0.0, cos(_facing_angle))


func _apply_gravity_and_move(delta: float) -> void:
	# Support is only checked at ground level: a jumping character flies over holes and
	# only drops into one if it comes down over it.
	var p := _xz()
	var grounded := velocity.y <= 0.0 and (is_on_floor() or global_position.y <= arena.height_at(p) + 0.05)
	# Safety net: a body that ever ends up well under the ground counts as fallen.
	if (grounded and not arena.is_over_ground(p)) or global_position.y < arena.height_at(p) - 0.8:
		_start_fall()
		return
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0
	move_and_slide()
	var airborne := not is_on_floor()
	if not airborne:
		_air_dash_used = false
	if _was_airborne and not airborne:
		_squash_vel += 6.0
		if fx:
			fx.dust_ring(global_position + Vector3.UP * 0.05, 4)
	_was_airborne = airborne


## Dashes along the stick (or the facing direction without input) if the cooldown allows.
func _try_dash() -> void:
	if _dash_cd > 0.0 or (_air_dash_used and not is_on_floor()) or not brain or not brain.wants_dash(self):
		return
	var dir: Vector3 = brain.get_move(self)
	dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 0.04 else facing
	_dash_t = dash_time
	_dash_cd = dash_cooldown + dash_time
	if not is_on_floor():
		_air_dash_used = true
		velocity.y = maxf(velocity.y, 1.5)
	velocity.x = dir.x * dash_speed
	velocity.z = dir.z * dash_speed
	_facing_angle = atan2(dir.x, dir.z)
	facing = dir
	_squash_vel -= 6.0
	_dash_fx = 0.0
	if fx:
		fx.whoosh(global_position + Vector3.UP * 0.3, dir)
	dashed.emit(self)


## Dust puffs left behind while dashing.
func _dash_trail(delta: float) -> void:
	_dash_fx -= delta
	if fx and _dash_fx <= 0.0:
		_dash_fx = 0.035
		fx.puff(global_position + Vector3.UP * 0.12 - facing * 0.25, 0.6)


## Little stars circling the head while knocked out.
func _ko_stars(delta: float) -> void:
	_ko_fx -= delta
	if fx and _ko_fx <= 0.0:
		_ko_fx = 0.12
		var a := _anim_time * 7.0
		var p := global_position + Vector3(cos(a) * 0.3, 1.05 * model_scale, sin(a) * 0.3)
		fx.spawn(p, Vector3(-sin(a), 0.1, cos(a)) * 1.2, 0.3, FxSprites.TILE_STAR, 6, 2, 5.0, 2.0, 0.0, 2.0)


## Starts a buffered jump if standing on the ground.
func _try_jump() -> void:
	if _jump_buffer <= 0.0 or not is_on_floor():
		return
	_jump_buffer = 0.0
	velocity.y = jump_velocity
	_squash_vel -= 7.0
	if fx:
		fx.puff(global_position + Vector3.UP * 0.05, 1.0)
	jumped.emit(self)


## Point between the hands, where gathered magic is held (world space).
func hand_anchor() -> Vector3:
	var p := _visual.global_position if _visual else global_position
	return p + facing * 0.42 + Vector3.UP * (0.42 + 0.12 * _cast_pose) * model_scale


## A small bob of the body on each correct syllable.
func cast_pulse() -> void:
	_cast_bob = 1.0
	_squash_vel += 2.5


func _xz() -> Vector2:
	return Vector2(global_position.x, global_position.z)


## While falling down a hole the walls hold the body in (they have no collision: the hole
## outline is analytic and may be animating).
func _keep_inside_hole() -> void:
	if _fall_hole.is_empty() or _fall_hole.scale <= 0.02:
		return
	var c: Vector2 = _fall_hole.center
	var d := _xz() - c
	var limit: float = maxf(_fall_hole.radius * _fall_hole.scale - RADIUS * 0.8, 0.0)
	if d.length() > limit:
		var n := d.normalized() if d.length() > 0.0001 else Vector2.RIGHT
		# Eased in over a few ticks so the body slides against the wall instead of snapping.
		var q := c + n * lerpf(d.length(), limit, 0.35)
		global_position.x = q.x
		global_position.z = q.y
		var out := Vector2(velocity.x, velocity.z).dot(n)
		if out > 0.0:
			velocity.x -= n.x * out
			velocity.z -= n.y * out


func _start_fall() -> void:
	_set_state(State.FALLING)
	_fall_time = 0.0
	_fall_hole = arena.hole_at(_xz())
	collision_mask = FALL_MASK
	velocity.y = minf(velocity.y, 0.0) - 1.0
	_squash_vel -= 5.0
	if fx:
		fx.dust_ring(global_position + Vector3.UP * 0.05, 5)
	if camera:
		camera.shake(0.12)
	fell.emit(self)


func _start_push() -> void:
	_set_state(State.PUSHING)
	_push_resolved = false
	_cooldown = push_cooldown + push_windup + push_active + push_recovery
	# Snap to the input direction so the push goes where the player is steering.
	var wish: Vector3 = brain.get_move(self) if brain else Vector3.ZERO
	if wish.length_squared() > 0.04:
		_facing_angle = atan2(wish.x, wish.z)
		facing = Vector3(sin(_facing_angle), 0.0, cos(_facing_angle))
	_squash_vel += 4.0


func _update_push(delta: float) -> void:
	var t := _state_time
	if t < push_windup:
		var h := Vector2(velocity.x, velocity.z).move_toward(Vector2.ZERO, deceleration * delta)
		velocity.x = h.x
		velocity.z = h.y
	elif not _push_resolved:
		_push_resolved = true
		velocity.x = facing.x * lunge_speed
		velocity.z = facing.z * lunge_speed
		_squash_vel -= 6.0
		_resolve_push()
	elif t < push_windup + push_active + push_recovery:
		var h := Vector2(velocity.x, velocity.z).move_toward(Vector2.ZERO, deceleration * 0.6 * delta)
		velocity.x = h.x
		velocity.z = h.y
	else:
		_set_state(State.ACTIVE)


## Shoves the nearest enemy (fighter or minion) inside the push cone.
func _resolve_push() -> void:
	var target: ArenaCharacter = null
	var best := INF
	for e in enemies():
		var to := e.global_position - global_position
		to.y = 0.0
		var dist := to.length()
		var angle := rad_to_deg(facing.angle_to(to.normalized())) if dist > 0.001 else 0.0
		if dist <= push_range and angle <= push_half_angle and dist < best:
			best = dist
			target = e
	if target:
		var to := target.global_position - global_position
		to.y = 0.0
		var dir := (facing * 0.65 + to.normalized() * 0.35).normalized()
		target.receive_push(dir, push_strength, self)
		velocity.x = -facing.x * recoil_speed
		velocity.z = -facing.z * recoil_speed
		_hitstop = hitstop_time
		if fx:
			fx.impact(global_position.lerp(target.global_position, 0.6) + Vector3.UP * 0.45, dir)
		if camera:
			camera.shake(0.22 * clampf(push_strength / 7.5, 0.3, 1.0))
	elif fx:
		fx.whoosh(global_position + facing * 0.5 + Vector3.UP * 0.35, facing)
	pushed.emit(self, target, target != null)


func receive_push(dir: Vector3, strength: float, _attacker: ArenaCharacter) -> void:
	if not is_alive() or state == State.OUT:
		return
	velocity.x = dir.x * strength
	velocity.z = dir.z * strength
	velocity.y = 1.5
	_dash_t = 0.0
	_set_state(State.HITSTUN)
	_hitstop = hitstop_time
	_flash = 1.0
	_squash_vel += 9.0
	_hit_lean = 1.0
	# Face the attacker while flying back: reads better than tumbling sideways.
	_facing_angle = atan2(-dir.x, -dir.z)
	facing = Vector3(sin(_facing_angle), 0.0, cos(_facing_angle))


## Push characters apart so they never overlap (called by the game for each pair).
static func separate(a: ArenaCharacter, b: ArenaCharacter) -> void:
	if not a.is_alive() or not b.is_alive() or a.state == State.SPAWNING or b.state == State.SPAWNING:
		return
	var d := b.global_position - a.global_position
	d.y = 0.0
	var dist := d.length()
	var min_dist := RADIUS * 2.0
	if dist >= min_dist:
		return
	var n := d / dist if dist > 0.0001 else Vector3.RIGHT
	var push := (min_dist - dist) * 0.5
	a.global_position -= n * push
	b.global_position += n * push
	# Remove the closing component of the relative velocity.
	var rel := (b.velocity - a.velocity).dot(n)
	if rel < 0.0:
		a.velocity += n * rel * 0.5
		b.velocity -= n * rel * 0.5


# ------------------------------------------------------------------ presentation

func _process(delta: float) -> void:
	if not _visual:
		return
	_anim_time += delta
	var xf := get_global_transform_interpolated()
	var pos := xf.origin
	if camera and state != State.FALLING:
		pos = camera.snap_point(pos)
	_visual.global_position = pos
	_visual.rotation = Vector3(0.0, _facing_angle + _spin, 0.0)

	# Squash & stretch spring, sub-stepped so a long frame can't make it diverge.
	var left := minf(delta, 0.25)
	while left > 0.0:
		var h := minf(left, SPRING_STEP)
		_squash_vel += (-320.0 * _squash - 15.0 * _squash_vel) * h
		_squash += _squash_vel * h
		left -= h
	if not is_finite(_squash) or not is_finite(_squash_vel):
		_squash = 0.0
		_squash_vel = 0.0
	var s := clampf(_squash * 0.06, -0.35, 0.35)
	_pivot.scale = Vector3(1.0 + s * 0.6, 1.0 - s, 1.0 + s * 0.6)

	_flash = move_toward(_flash, 0.0, delta * 8.0)
	var flash_value := 1.0 if _flash > 0.5 else 0.0
	# Sink into the dark when falling down a hole (not when falling off the outer edge).
	var sink := 0.0
	if state == State.FALLING and arena and arena.island_sdf(Vector2(pos.x, pos.z)) < -0.25:
		sink = clampf(-pos.y / 1.3, 0.0, 1.0)
	for mi in _meshes:
		mi.set_instance_shader_parameter("flash", flash_value)
		mi.set_instance_shader_parameter("sink", maxf(sink, shade))

	_animate_parts(delta)
	_emit_dust(delta)


func _animate_parts(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	var moving := state == State.ACTIVE and speed > 0.5
	_walk_phase += delta * (4.0 + speed * 2.6) if moving else 0.0
	var walk := clampf(speed / move_speed, 0.0, 1.0) if moving else 0.0
	var ph := _walk_phase
	var breathe := sin(_anim_time * 3.2) * 0.012

	var foot_l := Vector3(0.0, maxf(0.0, cos(ph)) * 0.08 * walk, sin(ph) * 0.13 * walk)
	var foot_r := Vector3(0.0, maxf(0.0, -cos(ph)) * 0.08 * walk, -sin(ph) * 0.13 * walk)
	var body_off := Vector3(0.0, absf(sin(ph)) * 0.04 * walk + breathe, 0.0)
	var body_rot := Vector3(0.0, sin(ph) * 0.12 * walk, sin(ph) * 0.07 * walk)
	var hand_l := Vector3(0.0, 0.0, -sin(ph) * 0.1 * walk)
	var hand_r := Vector3(0.0, 0.0, sin(ph) * 0.1 * walk)
	var head_rot := Vector3(-sin(ph * 2.0) * 0.04 * walk, 0.0, 0.0)
	var target_lean := walk * 0.18
	var eye_scale := 1.0
	var visual_lift := 0.0
	_spin = move_toward(_spin, 0.0, delta * 10.0) if state != State.FALLING else _spin

	match state:
		State.PUSHING:
			var t := _state_time
			if t < push_windup:
				var k := t / push_windup
				hand_l = Vector3(0.0, 0.03, -0.1 * k)
				hand_r = hand_l
				target_lean = -0.15 * k
			else:
				var k := clampf((t - push_windup) / (push_active + push_recovery), 0.0, 1.0)
				var thrust := 1.0 - pow(k, 2.0)
				hand_l = Vector3(-0.07 * thrust, 0.08 * thrust, 0.36 * thrust)
				hand_r = Vector3(0.07 * thrust, 0.08 * thrust, 0.36 * thrust)
				target_lean = 0.45 * thrust
			_lean = target_lean
		State.HITSTUN:
			eye_scale = 0.25
			var k := clampf(1.0 - _state_time / hitstun_time, 0.0, 1.0)
			hand_l = Vector3(0.05, 0.18 * k, -0.08 * k)
			hand_r = Vector3(-0.05, 0.18 * k, -0.08 * k)
			foot_l.z = 0.08 * k
			foot_r.z = 0.12 * k
			target_lean = -0.5 * k
		State.FALLING:
			eye_scale = 1.35
			var f := sin(_anim_time * 26.0)
			hand_l = Vector3(0.06, 0.32 + f * 0.06, 0.0)
			hand_r = Vector3(-0.06, 0.32 - f * 0.06, 0.0)
			foot_l = Vector3(0.0, -0.04 + f * 0.04, 0.06)
			foot_r = Vector3(0.0, -0.04 - f * 0.04, -0.06)
			target_lean = 0.0
			_spin += delta * 5.0
			_squash = minf(_squash, -2.5)
		State.VICTORY:
			var hop := absf(sin(_anim_time * 7.0))
			visual_lift = hop * 0.22
			hand_l = Vector3(0.05, 0.3, 0.0)
			hand_r = Vector3(-0.05, 0.3, 0.0)
			if hop < 0.15 and _squash_vel > -1.0:
				_squash_vel += 2.0
			target_lean = 0.0
		State.SPAWNING:
			hand_l = Vector3(0.05, 0.25, 0.0)
			hand_r = Vector3(-0.05, 0.25, 0.0)
			_squash = minf(_squash, -1.5)

	# Knocked out: slumped, eyes shut, arms dangling, head lolling.
	if _ko > 0.0 and state in [State.ACTIVE, State.HITSTUN]:
		eye_scale = 0.12
		target_lean = -0.12
		hand_l = Vector3(0.03, -0.06, -0.02)
		hand_r = Vector3(-0.03, -0.06, -0.02)
		head_rot = Vector3(0.15, 0.0, sin(_anim_time * 3.0) * 0.25)
	# Dash: lean hard into the burst, arms swept back.
	if _dash_t > 0.0 and state == State.ACTIVE:
		target_lean = 0.55
		hand_l = Vector3(-0.04, 0.06, -0.16)
		hand_r = Vector3(0.04, 0.06, -0.16)
		foot_l.z = -0.1
		foot_r.z = 0.08
	# Airborne: tuck the feet and lift the arms a little.
	var air := not is_on_floor() and state in [State.ACTIVE, State.PUSHING, State.HITSTUN]
	if air:
		foot_l = Vector3(0.0, 0.08, 0.05)
		foot_r = Vector3(0.0, 0.1, -0.03)
		hand_l.y += 0.12
		hand_r.y += 0.12
	# Casting: the hands come together in front of the chest, holding the gathered magic.
	# Only the hands are overridden, so walking, jumping and knockback keep animating.
	_cast_pose = lerpf(_cast_pose, 1.0 if cast_level > 0.0 else 0.0, 1.0 - exp(-16.0 * delta))
	_cast_bob = move_toward(_cast_bob, 0.0, delta * 6.0)
	if _cast_pose > 0.01 and state in [State.ACTIVE, State.HITSTUN, State.FROZEN]:
		var hold := Vector3(0.0, 0.1 + 0.06 * cast_level + 0.03 * _cast_bob, 0.2 + 0.05 * _cast_bob)
		hand_l = hand_l.lerp(Vector3(-0.1, hold.y, hold.z), _cast_pose)
		hand_r = hand_r.lerp(Vector3(0.1, hold.y, hold.z), _cast_pose)
		target_lean += 0.06 * _cast_pose
	if state != State.PUSHING:
		_lean = lerpf(_lean, target_lean, 1.0 - exp(-14.0 * delta))
	_hit_lean = move_toward(_hit_lean, 0.0, delta * 3.0)
	_pivot.rotation = Vector3(_lean, 0.0, 0.0)
	_pivot.position = Vector3(0.0, visual_lift, 0.0)

	# Blink.
	_blink_timer -= delta
	if _blink_timer < 0.0:
		_blink_timer = randf_range(2.0, 4.5)
	if _blink_timer < 0.11 and state != State.FALLING and state != State.HITSTUN and _ko <= 0.0:
		eye_scale = 0.15

	_pose("FootL", foot_l, Vector3.ZERO, Vector3.ONE, delta)
	_pose("FootR", foot_r, Vector3.ZERO, Vector3.ONE, delta)
	_pose("Body", body_off, body_rot, Vector3.ONE, delta)
	_pose("HandL", hand_l, Vector3.ZERO, Vector3.ONE, delta)
	_pose("HandR", hand_r, Vector3.ZERO, Vector3.ONE, delta)
	_pose("Head", Vector3.ZERO, head_rot, Vector3.ONE, delta)
	_pose("EyeL", Vector3.ZERO, Vector3.ZERO, Vector3(1.0, eye_scale, 1.0), delta, 40.0)
	_pose("EyeR", Vector3.ZERO, Vector3.ZERO, Vector3(1.0, eye_scale, 1.0), delta, 40.0)


## Blends a part toward rest + offset. Hands/feet offsets are in character space, which for
## these models equals each part's parent space (no rotation in the hierarchy).
func _pose(part: String, offset: Vector3, rot: Vector3, scl: Vector3, delta: float, sharpness := 22.0) -> void:
	var n: Node3D = _parts.get(part)
	if not n:
		return
	var rest: Transform3D = _rest[part]
	var k := 1.0 - exp(-sharpness * delta)
	n.position = n.position.lerp(rest.origin + offset, k)
	n.rotation = n.rotation.lerp(rest.basis.get_euler() + rot, k)
	n.scale = n.scale.lerp(rest.basis.get_scale() * scl, k)


func _emit_dust(delta: float) -> void:
	if not fx or state != State.ACTIVE:
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed < 2.5:
		_dust_timer = 0.0
		return
	_dust_timer -= delta
	if _dust_timer <= 0.0:
		_dust_timer = 0.16
		fx.puff(global_position - facing * 0.2 + Vector3.UP * 0.06, 0.5)


func _mcp_state() -> Dictionary:
	return {
		"name": display_name,
		"state": State.keys()[state],
		"pos": [snappedf(global_position.x, 0.01), snappedf(global_position.y, 0.01), snappedf(global_position.z, 0.01)],
		"vel": [snappedf(velocity.x, 0.01), snappedf(velocity.y, 0.01), snappedf(velocity.z, 0.01)],
		"facing_deg": snappedf(rad_to_deg(_facing_angle), 0.1),
		"cooldown": snappedf(_cooldown, 0.01),
		"ko": snappedf(_ko, 0.01),
		"squash": snappedf(_squash, 0.01),
		"ground_sdf": snappedf(arena.ground_sdf(Vector2(global_position.x, global_position.z)), 0.01) if arena else 0.0,
	}
