class_name SpellEffects
extends Node3D
## What spells do in the arena. Only this node touches gameplay for spells: the rhythm side
## just says "caster X completed spell Y"; this resolves it against the arena and the other
## characters (and could equally run on a server from replicated cast events).

## Emitted when a cast resolves; `ok` false = the spell found no valid target ("fizzled").
signal resolved(caster: ArenaCharacter, spell: SpellDefinition, ok: bool, note: String)

const RUNE_SHADER := preload("res://shaders/magic.gdshader")
const CHARACTER_SCENE := preload("res://scenes/character.tscn")
const SOUNDS := {
	"push": preload("res://assets/audio/spell_push.wav"),
	"pit": preload("res://assets/audio/spell_pit.wav"),
	"mend": preload("res://assets/audio/spell_mend.wav"),
	"raise": preload("res://assets/audio/spell_raise.wav"),
	"fizzle": preload("res://assets/audio/fizzle.wav"),
}

## Radius of holes opened by Open Pit.
@export var pit_radius := 0.85
## Distances in front of the caster where Open Pit tries to open, in order.
@export var pit_distances := PackedFloat32Array([2.4, 2.0, 2.9, 1.7])
## Mend Earth closes the nearest hole inside a cone in front of the caster: this half-angle
## (degrees, widened by the hole's own size as seen from the caster) and this reach
## (to the hole's rim).
@export var mend_cone := 25.0
@export var mend_reach := 3.6
## With no hole in reach, Mend Earth raises the ground this far ahead (a bump, then a hill,
## then a mountain when cast again on the same spot).
@export var raise_distance := 2.2
## Knockback given to characters standing where a mound rises, per level.
@export var raise_push := PackedFloat32Array([7.0, 9.5, 12.5])
@export var sound_volume_db := -3.0

@export_group("Book spells")
## Hasten / Slow: BPM change, and how many beats the slide takes.
@export var tempo_step := 20.0
@export var tempo_slide_beats := 4.0
## Raise Minion: lifetime in beats, size and shove.
@export var minion_beats := 16.0
@export var minion_scale := 0.62
@export var minion_push := 4.5
## Shockwave: reach around the caster and knockback (at the centre; 55% at the rim).
@export var shockwave_radius := 3.4
@export var shockwave_push := 14.0
## Knockout: beats the target stays down.
@export var knockout_beats := 4.0
## Quicken: speed multiplier on the caster (level 2) and how many beats it lasts.
@export var quicken_mult := 1.45
@export var quicken_beats := 8.0
## Snare: beats the target stays slowed (level 2).
@export var snare_beats := 6.0

var arena: Arena
var fx: FxSprites
var camera: PixelCamera
var characters: Array[ArenaCharacter] = []

# Holes currently animating because of a spell: id -> { palette, opening }.
var _animating := {}
var _debris_timer := 0.0
# Mounds currently rising because of a spell: id -> { caster, palette, pushed: {character: true} }.
var _rising := {}
# Summoned minions: minion -> beat (BeatClock) at which it crumbles.
var _minions := {}
var _sfx: AudioStreamPlayer
# The cast being resolved: its level (1..3) and power (precision multiplier, ~0.55..1).
var _level := 2
var _power := 1.0
# Where the caster faced before auto-aim turned them (Mend Earth closes holes there).
var _own_facing := Vector3.FORWARD


func setup(arena_node: Arena, fx_node: FxSprites, cam: PixelCamera, all_characters: Array[ArenaCharacter]) -> void:
	arena = arena_node
	fx = fx_node
	camera = cam
	characters = all_characters
	arena.hole_opened.connect(func(h: Dictionary): _animating.erase(h.id))
	arena.hole_closed.connect(func(h: Dictionary): _animating.erase(h.id))
	arena.mound_raised.connect(func(m: Dictionary): _rising.erase(m.id))
	_sfx = AudioStreamPlayer.new()
	var poly := AudioStreamPolyphonic.new()
	poly.polyphony = 6
	_sfx.stream = poly
	add_child(_sfx)
	_sfx.play()


## Resolves `spell` cast by `caster` at `level` (1 = start + end only, 2, 3 = longer chants)
## with `power` (from the chant's precision: 1 = dead on the beat).
func cast(spell: SpellDefinition, caster: ArenaCharacter, origin: Vector3, level := 2, power := 1.0) -> void:
	if not caster.is_alive():
		resolved.emit(caster, spell, false, "fallen")
		return
	_level = clampi(level, 1, 3)
	_power = power
	_own_facing = caster.facing
	if caster.auto_aim and spell.effect in AIMED:
		var target := _aim_target(caster)
		if target:
			var to := target.global_position - caster.global_position
			to.y = 0.0
			caster.face(to)
			origin = caster.hand_anchor()
	match spell.effect:
		SpellDefinition.Effect.PUSH:
			_cast_bolt(spell, caster, origin, MagicBolt.Kind.PUSH)
		SpellDefinition.Effect.CREATE_HOLE:
			_cast_open_pit(spell, caster)
		SpellDefinition.Effect.CLOSE_HOLE:
			_cast_mend(spell, caster)
		SpellDefinition.Effect.TEMPO_UP:
			_cast_tempo(spell, caster, roundf(tempo_step * _lv(0.5, 1.0, 1.5) * _power))
		SpellDefinition.Effect.TEMPO_DOWN:
			_cast_tempo(spell, caster, -roundf(tempo_step * _lv(0.5, 1.0, 1.5) * _power))
		SpellDefinition.Effect.RAISE_MINION:
			_cast_minion(spell, caster)
		SpellDefinition.Effect.SHOCKWAVE:
			_cast_shockwave(spell, caster)
		SpellDefinition.Effect.SWAP_BALL:
			_cast_bolt(spell, caster, origin, MagicBolt.Kind.SWAP)
		SpellDefinition.Effect.KNOCKOUT:
			_cast_bolt(spell, caster, origin, MagicBolt.Kind.KNOCKOUT)
		SpellDefinition.Effect.SNARE_BALL:
			_cast_bolt(spell, caster, origin, MagicBolt.Kind.SNARE)
		SpellDefinition.Effect.QUICKEN:
			_cast_quicken(spell, caster)


const AIMED: Array[SpellDefinition.Effect] = [SpellDefinition.Effect.PUSH,
	SpellDefinition.Effect.CREATE_HOLE, SpellDefinition.Effect.CLOSE_HOLE,
	SpellDefinition.Effect.RAISE_MINION, SpellDefinition.Effect.SWAP_BALL,
	SpellDefinition.Effect.KNOCKOUT, SpellDefinition.Effect.SNARE_BALL]
## Auto-aim only locks onto enemies this close.
const AIM_RANGE := 14.0


## The value for the current level (1, 2, 3).
func _lv(l1: float, l2: float, l3: float) -> float:
	return [l1, l2, l3][_level - 1]


## Auto-aim target: the opponent if in range, else the nearest enemy (minions included).
func _aim_target(caster: ArenaCharacter) -> ArenaCharacter:
	var o := caster.opponent
	if o and o.is_alive() and o.global_position.distance_to(caster.global_position) < AIM_RANGE:
		return o
	var best: ArenaCharacter = null
	var best_d := AIM_RANGE
	for e in caster.enemies():
		var d := e.global_position.distance_to(caster.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


## Removes in-flight spells (new round).
func clear() -> void:
	for c in get_children():
		if c != _sfx:
			c.queue_free()
	_animating.clear()
	_rising.clear()
	_minions.clear()


## Push: a big fast ball of light. Swap: a small, very fast ball. Knockout: a spinning star.
func _cast_bolt(spell: SpellDefinition, caster: ArenaCharacter, origin: Vector3, kind: MagicBolt.Kind) -> void:
	var bolt := MagicBolt.new()
	bolt.kind = kind
	bolt.caster = caster
	bolt.arena = arena
	bolt.fx = fx
	bolt.camera = camera
	bolt.direction = caster.facing.normalized()
	bolt.palette_index = spell.palette_index
	match kind:
		MagicBolt.Kind.PUSH:
			bolt.radius = _lv(0.26, 0.36, 0.46)
			bolt.speed = _lv(14.0, 16.0, 18.0)
			bolt.hit_radius = _lv(0.65, 0.8, 0.95)
			bolt.strength = _lv(10.0, 15.0, 19.0) * _power
		MagicBolt.Kind.SWAP:
			bolt.radius = 0.13
			bolt.speed = 24.0
			bolt.hit_radius = 0.55
			bolt.max_range = _lv(6.0, 10.0, 14.0) * lerpf(0.8, 1.0, _power)
		MagicBolt.Kind.KNOCKOUT:
			bolt.radius = 0.24
			bolt.speed = 13.0
			bolt.hit_radius = 0.7
			bolt.max_range = 8.0
			bolt.stun_time = knockout_beats * _lv(0.5, 1.0, 1.5) * _power * _beat_seconds()
		MagicBolt.Kind.SNARE:
			bolt.radius = 0.3
			bolt.speed = 7.0
			bolt.hit_radius = 0.75
			bolt.max_range = 8.0
			bolt.slow_mult = _lv(0.65, 0.5, 0.38)
			bolt.slow_time = snare_beats * _lv(0.6, 1.0, 1.4) * _power * _beat_seconds()
	add_child(bolt)
	bolt.global_position = origin
	# Recoil sells the release.
	caster.velocity -= caster.facing * (1.5 if kind == MagicBolt.Kind.PUSH else 0.6)
	if camera:
		camera.shake(0.1 if kind == MagicBolt.Kind.PUSH else 0.05)
	_sound("push", 1.0 if kind == MagicBolt.Kind.PUSH else 1.5)
	resolved.emit(caster, spell, true, "")


## Quicken: the caster runs faster for a while.
func _cast_quicken(spell: SpellDefinition, caster: ArenaCharacter) -> void:
	var mult := 1.0 + (quicken_mult - 1.0) * _lv(0.6, 1.0, 1.4) * _power
	caster.haste(mult, quicken_beats * _lv(0.5, 1.0, 1.5) * _power * _beat_seconds())
	caster.cast_pulse()
	if fx:
		fx.dust_ring(caster.global_position + Vector3.UP * 0.05, 10)
		for k in 10:
			var a := TAU * k / 10.0
			fx.spawn(caster.global_position + Vector3.UP * 0.3, Vector3(cos(a), 1.2, sin(a)) * 2.0, 0.35,
				FxSprites.TILE_SPARK, spell.palette_index, 2, 3.0, 1.0, 0.0, 3.0)
	_sound("raise", 1.5)
	resolved.emit(caster, spell, true, "")


## Seconds per beat right now (shared tempo), 0.6 without one.
func _beat_seconds() -> float:
	var clock := BeatClock.instance
	return 60.0 / clock.current_bpm() if clock and clock.running else 0.6


## Digs in front: a mound there sinks one level (mountain -> hill -> bump -> flat); only flat
## ground opens into a pit.
func _cast_open_pit(spell: SpellDefinition, caster: ArenaCharacter) -> void:
	var here := Vector2(caster.global_position.x, caster.global_position.z)
	var dir := Vector2(caster.facing.x, caster.facing.z).normalized()
	var mound := _mound_in_front(here, dir)
	if not mound.is_empty() and not arena.lower_mound(mound).has("error"):
		if _level >= 3:
			arena.lower_mound(mound) # level 3 digs two steps at once
		_rune(mound.center, mound.radius * 1.05, spell.palette_index)
		if fx:
			fx.dust_ring(Vector3(mound.center.x, arena.height_at(mound.center) + 0.05, mound.center.y), 8 + 3 * mound.level)
		if camera:
			camera.shake(0.12)
		_sound("pit", 0.85)
		resolved.emit(caster, spell, true, "")
		return
	var radius := pit_radius * _lv(0.7, 1.0, 1.3) * lerpf(0.8, 1.0, _power)
	for d in pit_distances:
		var c := here + dir * d
		var id := arena.open_hole(c, radius)
		if id >= 0:
			_animating[id] = {"palette": spell.palette_index, "opening": true}
			_rune(c, radius * 1.35, spell.palette_index)
			if fx:
				fx.dust_ring(Vector3(c.x, 0.05, c.y), 10)
			if camera:
				camera.shake(0.18)
			resolved.emit(caster, spell, true, "")
			return
	_fizzle_at(here + dir * pit_distances[0], spell.palette_index)
	resolved.emit(caster, spell, false, "no room")


## Closes the hole in front of the caster; with no hole in reach, raises the ground instead.
func _cast_mend(spell: SpellDefinition, caster: ArenaCharacter) -> void:
	var here := Vector2(caster.global_position.x, caster.global_position.z)
	var dir := Vector2(caster.facing.x, caster.facing.z).normalized()
	# Holes are closed where the caster was facing (auto-aim only steers the raised ground).
	var h := _hole_in_front(here, Vector2(_own_facing.x, _own_facing.z).normalized())
	if not h.is_empty() and arena.close_hole(h.id):
		_animating[h.id] = {"palette": spell.palette_index, "opening": false}
		_rune(h.center, h.radius * 1.35, spell.palette_index)
		_sound("mend")
		resolved.emit(caster, spell, true, "")
		return
	# Casting again at a mound in front grows it (bump -> hill -> mountain).
	var target := _mound_in_front(here, dir)
	var spot := here + dir * raise_distance
	var res := arena.grow_mound(target) if not target.is_empty() else arena.raise_ground(spot)
	if _level >= 3 and not res.has("error"):
		arena.grow_mound(res.mound) # level 3 raises two steps at once
	if res.has("error"):
		_fizzle_at(spot, spell.palette_index)
		resolved.emit(caster, spell, false, res.error)
		return
	var m: Dictionary = res.mound
	_rising[m.id] = {"caster": caster, "palette": spell.palette_index, "pushed": {},
		"force": _lv(0.8, 1.0, 1.2) * _power}
	_rune(m.center, m.to.x * 1.05, spell.palette_index)
	if fx:
		fx.dust_ring(Vector3(m.center.x, arena.height_at(m.center) + 0.05, m.center.y), 8 + 4 * m.level)
	if camera:
		camera.shake(0.12 + 0.08 * m.level)
	_sound("raise")
	resolved.emit(caster, spell, true, "")


## The open hole closest to the caster inside Mend Earth's cone; {} if none.
func _hole_in_front(here: Vector2, dir: Vector2) -> Dictionary:
	var best := {}
	var best_rim := INF
	for h in arena.holes:
		if h.target <= 0.0:
			continue
		var to: Vector2 = h.center - here
		var dist := to.length()
		var rim: float = maxf(dist - h.radius, 0.0)
		if rim > mend_reach or rim >= best_rim:
			continue
		if dist > h.radius * 0.5:
			# The cone widens by the part of the hole's disc seen from the caster.
			var widen := rad_to_deg(asin(clampf(h.radius * 0.6 / dist, 0.0, 1.0)))
			if rad_to_deg(absf(dir.angle_to(to))) > mend_cone + widen:
				continue
		best_rim = rim
		best = h
	return best


## The nearest mound whose footprint lies on the caster's line of sight, within reach.
func _mound_in_front(here: Vector2, dir: Vector2) -> Dictionary:
	var best := {}
	var best_along := INF
	for m in arena.mounds:
		var to: Vector2 = m.center - here
		var along := to.dot(dir)
		var lateral := absf(to.cross(dir))
		var r: float = maxf(m.radius, 1.0)
		if along > -0.5 and along < raise_distance + r and lateral < r * 0.9 and along < best_along:
			best_along = along
			best = m
	return best


## Hasten / Slow: slides the shared tempo by `amount` BPM over a bar.
func _cast_tempo(spell: SpellDefinition, caster: ArenaCharacter, amount: float) -> void:
	var clock := BeatClock.instance
	var here := Vector2(caster.global_position.x, caster.global_position.z)
	if not clock or not clock.running:
		_fizzle_at(here, spell.palette_index)
		resolved.emit(caster, spell, false, "no tempo")
		return
	var cur := clock.current_bpm()
	var target := clampf(cur + amount, BeatClock.BPM_RANGE.x, BeatClock.BPM_RANGE.y)
	if absf(target - cur) < 1.0:
		_fizzle_at(here, spell.palette_index)
		resolved.emit(caster, spell, false, "tempo limit")
		return
	clock.slide_to(target, tempo_slide_beats)
	_rune(here, 1.6, spell.palette_index)
	if fx:
		# Notes flying off in a spiral (up = faster, down = slower).
		for k in 12:
			var a := TAU * k / 12.0
			var v := Vector3(cos(a), 1.6 if amount > 0.0 else 0.4, sin(a)) * 2.2
			fx.spawn(caster.global_position + Vector3.UP * 0.5, v, 0.6, FxSprites.TILE_STAR, spell.palette_index, 2, 5.0, 2.0, 0.0, 2.0)
	_sound("raise", 1.25 if amount > 0.0 else 0.75)
	resolved.emit(caster, spell, true, "")


## Raise Minion: a small undead double of the caster climbs out of the ground in front and
## shoves enemies softly, until it crumbles after `minion_beats` beats.
func _cast_minion(spell: SpellDefinition, caster: ArenaCharacter) -> void:
	var here := Vector2(caster.global_position.x, caster.global_position.z)
	var dir := Vector2(caster.facing.x, caster.facing.z).normalized()
	var spot := here
	var found := false
	for d in [1.2, 0.8, 1.7]:
		spot = here + dir * d
		if arena.ground_sdf(spot) < -0.45:
			found = true
			break
	if not found:
		_fizzle_at(here + dir * 1.2, spell.palette_index)
		resolved.emit(caster, spell, false, "no ground")
		return
	var m := CHARACTER_SCENE.instantiate() as ArenaCharacter
	m.name = "Minion"
	m.display_name = "Minion"
	m.model_scene = caster.model_scene
	m.model_scale = caster.model_scale * minion_scale
	m.color_index = caster.color_index
	m.team = caster.team
	m.opponent = caster.opponent
	m.arena = arena
	m.camera = camera
	m.fx = fx
	m.shade = 0.5
	m.spawn_height = 0.9
	m.auto_activate = true
	m.move_speed = 3.6
	m.push_strength = minion_push * _lv(0.8, 1.0, 1.2)
	m.push_range = 0.95
	m.push_cooldown = 0.8
	var col := m.get_node("Collision") as CollisionShape3D
	var cap := CapsuleShape3D.new()
	cap.radius = 0.2
	cap.height = 0.6
	col.shape = cap
	col.position = Vector3(0.0, 0.3, 0.0)
	add_child(m)
	m.brain = AIBrain.new(arena, randi())
	m.spawn(Vector3(spot.x, arena.height_at(spot), spot.y), caster.facing)
	m.eliminated.connect(_minion_gone)
	var clock := BeatClock.instance
	_minions[m] = (clock.beats_now() if clock and clock.running else 0.0) + minion_beats * _lv(0.5, 1.0, 1.5) * _power
	_rune(spot, 0.9, spell.palette_index)
	if fx:
		fx.dust_ring(Vector3(spot.x, arena.height_at(spot) + 0.05, spot.y), 8)
		for k in 6:
			var a := TAU * k / 6.0
			fx.spawn(Vector3(spot.x, arena.height_at(spot) + 0.1, spot.y), Vector3(cos(a) * 0.5, 2.0, sin(a) * 0.5), 0.5,
				FxSprites.TILE_SPARK, spell.palette_index, 2, 3.0, 1.0, 2.0, 1.0)
	_sound("raise", 1.4)
	resolved.emit(caster, spell, true, "")


func _minion_gone(m: ArenaCharacter) -> void:
	_minions.erase(m)
	if fx:
		fx.vanish(m.global_position + Vector3.UP * 0.2)
	m.queue_free()


## Shockwave: every enemy around the caster is blown away.
func _cast_shockwave(spell: SpellDefinition, caster: ArenaCharacter) -> void:
	var c := caster.global_position
	var radius := shockwave_radius * _lv(0.7, 1.0, 1.3)
	var force := shockwave_push * _lv(0.8, 1.0, 1.2) * _power
	for e in caster.enemies():
		var d := e.global_position - c
		d.y = 0.0
		var dist := d.length()
		if dist > radius:
			continue
		var out := d / dist if dist > 0.05 else caster.facing
		e.receive_push(out, force * (1.0 - 0.45 * dist / radius), caster)
		e.velocity.y = 3.0
		if fx:
			fx.impact(e.global_position + Vector3.UP * 0.4, out)
	caster.cast_pulse()
	_rune(Vector2(c.x, c.z), radius, spell.palette_index)
	if fx:
		fx.spawn(c + Vector3.UP * 0.4, Vector3.ZERO, 0.3, FxSprites.TILE_RING, spell.palette_index, 2, 12.0, 90.0 * radius / shockwave_radius)
		fx.spawn(c + Vector3.UP * 0.4, Vector3.ZERO, 0.22, FxSprites.TILE_RING, 1, 2, 8.0, 60.0 * radius / shockwave_radius)
		fx.dust_ring(c + Vector3.UP * 0.05, 16)
		for k in 16:
			var a := TAU * k / 16.0
			fx.spawn(c + Vector3.UP * 0.3, Vector3(cos(a), 0.3, sin(a)) * 7.0, 0.35, FxSprites.TILE_SPARK, spell.palette_index, 2, 4.0, 1.0, 0.0, 4.0)
	if camera:
		camera.shake(0.3)
	_sound("push", 0.7)
	resolved.emit(caster, spell, true, "")


func _sound(key: String, pitch := 1.0) -> void:
	var pb := _sfx.get_stream_playback() as AudioStreamPlaybackPolyphonic
	if pb:
		pb.play_stream(SOUNDS[key], 0.0, sound_volume_db, pitch * randf_range(0.96, 1.04))


## Rising ground shoves whoever stands on it outward (once per growth); the caster just
## rides it.
func _physics_process(_delta: float) -> void:
	_expire_minions()
	if _rising.is_empty():
		return
	for m in arena.mounds:
		if not _rising.has(m.id):
			continue
		var info: Dictionary = _rising[m.id]
		for c in (info.caster as ArenaCharacter).enemies():
			if info.pushed.has(c):
				continue
			var d := Vector2(c.global_position.x, c.global_position.z) - (m.center as Vector2)
			if d.length() > m.radius * 1.05 + ArenaCharacter.RADIUS:
				continue
			var out := d.normalized() if d.length() > 0.05 else Vector2(info.caster.facing.x, info.caster.facing.z)
			var level: int = clampi(m.level, 1, raise_push.size())
			c.receive_push(Vector3(out.x, 0.0, out.y), raise_push[level - 1] * info.force, info.caster)
			# Launched upward too: the ground heaves under them.
			c.velocity.y = 2.5 + 1.5 * level
			info.pushed[c] = true
			if fx:
				fx.impact(c.global_position + Vector3.UP * 0.2, Vector3(out.x, 0.6, out.y))


## Minions crumble to dust when their beats are up.
func _expire_minions() -> void:
	if _minions.is_empty():
		return
	var clock := BeatClock.instance
	var now := clock.beats_now() if clock and clock.running else INF
	for m in _minions.keys():
		if not is_instance_valid(m):
			_minions.erase(m)
		elif now >= _minions[m] and m.is_alive():
			_minion_gone(m)


## A short-lived glowing disc on the ground marking where the magic acts.
func _rune(c: Vector2, radius: float, palette_index: int) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = RUNE_SHADER
	mat.set_shader_parameter("palette_index", palette_index)
	mat.set_shader_parameter("disc", true)
	mat.set_shader_parameter("energy", 0.2)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * radius * 2.0
	quad.orientation = PlaneMesh.FACE_Y
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = Vector3(c.x, arena.height_at(c) + 0.03, c.y)
	var tw := create_tween()
	tw.tween_property(mi, "scale", Vector3(0.2, 1.0, 0.2), 0.0)
	tw.tween_property(mi, "scale", Vector3.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.25)
	tw.tween_property(mi, "scale", Vector3(1.4, 1.0, 1.4), 0.2)
	tw.tween_callback(mi.queue_free)


func _fizzle_at(c: Vector2, palette_index: int) -> void:
	_sound("fizzle")
	if not fx:
		return
	for k in 8:
		var a := TAU * k / 8.0
		fx.spawn(Vector3(c.x, 0.3, c.y), Vector3(cos(a), 0.7, sin(a)) * 1.2, 0.4, FxSprites.TILE_PUFF, 17, 1, 6.0, 2.0, -1.0, 4.0)
	fx.spawn(Vector3(c.x, 0.3, c.y), Vector3.ZERO, 0.2, FxSprites.TILE_SPARK, palette_index, 2, 5.0, 1.0)


func _process(delta: float) -> void:
	if not fx or (_animating.is_empty() and _rising.is_empty()):
		return
	_debris_timer -= delta
	if _debris_timer > 0.0:
		return
	_debris_timer = 0.03
	# Crumbling earth on the rim of holes that are opening; earth rising into closing ones.
	for h in arena.holes:
		if not _animating.has(h.id):
			continue
		var info: Dictionary = _animating[h.id]
		var a := randf() * TAU
		var r: float = h.radius * maxf(h.scale, 0.15)
		var p := Vector3(h.center.x + cos(a) * r, 0.05, h.center.y + sin(a) * r)
		if info.opening:
			fx.spawn(p, Vector3(cos(a) * 0.6, randf_range(1.5, 3.0), sin(a) * 0.6), 0.5, FxSprites.TILE_SPARK, 25, 2, 3.0, 2.0, 9.0, 0.5)
			fx.spawn(p, Vector3(cos(a), 0.6, sin(a)) * 0.8, 0.45, FxSprites.TILE_PUFF, 26, 1, 7.0, 3.0, -1.0, 3.0)
		else:
			fx.spawn(p - Vector3.UP * 0.4, Vector3(-cos(a) * 0.8, 2.2, -sin(a) * 0.8), 0.4, FxSprites.TILE_PUFF, 25, 2, 6.0, 2.0, 2.0, 2.0)
			fx.spawn(p + Vector3.UP * 0.4, Vector3.UP * 1.2, 0.35, FxSprites.TILE_SPARK, info.palette, 2, 3.0, 1.0, -1.0, 1.0)
	# Earth crumbling down the flanks of rising mounds.
	for m in arena.mounds:
		if not _rising.has(m.id):
			continue
		for k in 2:
			var a := randf() * TAU
			var r: float = m.radius * randf_range(0.5, 1.0)
			var q: Vector2 = m.center + Vector2(cos(a), sin(a)) * r
			var p := Vector3(q.x, arena.height_at(q) + 0.05, q.y)
			fx.spawn(p, Vector3(cos(a) * 1.2, randf_range(0.8, 2.0), sin(a) * 1.2), 0.5, FxSprites.TILE_PUFF, 25, 2, 6.0, 2.0, -1.0, 3.0)
