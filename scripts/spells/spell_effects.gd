class_name SpellEffects
extends Node3D
## What spells do in the arena. Only this node touches gameplay for spells: the rhythm side
## just says "caster X completed spell Y"; this resolves it against the arena and the other
## characters (and could equally run on a server from replicated cast events).

## Emitted when a cast resolves; `ok` false = the spell found no valid target ("fizzled").
signal resolved(caster: ArenaCharacter, spell: SpellDefinition, ok: bool, note: String)

const RUNE_SHADER := preload("res://shaders/magic.gdshader")

## Radius of holes opened by Open Pit.
@export var pit_radius := 0.85
## Distances in front of the caster where Open Pit tries to open, in order.
@export var pit_distances := PackedFloat32Array([2.4, 2.0, 2.9, 1.7])
## How far in front of the caster Mend Earth looks for a hole, and its reach.
@export var mend_probe := 1.6
@export var mend_reach := 2.6

var arena: Arena
var fx: FxSprites
var camera: PixelCamera
var characters: Array[ArenaCharacter] = []

# Holes currently animating because of a spell: id -> { palette, opening }.
var _animating := {}
var _debris_timer := 0.0


func setup(arena_node: Arena, fx_node: FxSprites, cam: PixelCamera, all_characters: Array[ArenaCharacter]) -> void:
	arena = arena_node
	fx = fx_node
	camera = cam
	characters = all_characters
	arena.hole_opened.connect(func(h: Dictionary): _animating.erase(h.id))
	arena.hole_closed.connect(func(h: Dictionary): _animating.erase(h.id))


func cast(spell: SpellDefinition, caster: ArenaCharacter, origin: Vector3) -> void:
	if not caster.is_alive():
		resolved.emit(caster, spell, false, "fallen")
		return
	match spell.effect:
		SpellDefinition.Effect.PUSH:
			_cast_push(spell, caster, origin)
		SpellDefinition.Effect.CREATE_HOLE:
			_cast_open_pit(spell, caster)
		SpellDefinition.Effect.CLOSE_HOLE:
			_cast_mend(spell, caster)


## Removes in-flight spells (new round).
func clear() -> void:
	for c in get_children():
		c.queue_free()
	_animating.clear()


func _cast_push(spell: SpellDefinition, caster: ArenaCharacter, origin: Vector3) -> void:
	var bolt := MagicBolt.new()
	bolt.caster = caster
	bolt.targets = characters
	bolt.arena = arena
	bolt.fx = fx
	bolt.camera = camera
	bolt.direction = caster.facing.normalized()
	bolt.strength = caster.push_strength * 1.05
	bolt.palette_index = spell.palette_index
	add_child(bolt)
	bolt.global_position = origin
	# Recoil sells the release.
	caster.velocity -= caster.facing * 1.5
	if camera:
		camera.shake(0.08)
	resolved.emit(caster, spell, true, "")


func _cast_open_pit(spell: SpellDefinition, caster: ArenaCharacter) -> void:
	var here := Vector2(caster.global_position.x, caster.global_position.z)
	var dir := Vector2(caster.facing.x, caster.facing.z).normalized()
	for d in pit_distances:
		var c := here + dir * d
		var id := arena.open_hole(c, pit_radius)
		if id >= 0:
			_animating[id] = {"palette": spell.palette_index, "opening": true}
			_rune(c, pit_radius * 1.35, spell.palette_index)
			if fx:
				fx.dust_ring(Vector3(c.x, 0.05, c.y), 10)
			if camera:
				camera.shake(0.18)
			resolved.emit(caster, spell, true, "")
			return
	_fizzle_at(here + dir * pit_distances[0], spell.palette_index)
	resolved.emit(caster, spell, false, "no room")


func _cast_mend(spell: SpellDefinition, caster: ArenaCharacter) -> void:
	var here := Vector2(caster.global_position.x, caster.global_position.z)
	var dir := Vector2(caster.facing.x, caster.facing.z).normalized()
	var h := arena.nearest_hole(here + dir * mend_probe, mend_reach)
	if h.is_empty() or not arena.close_hole(h.id):
		_fizzle_at(here + dir * mend_probe, spell.palette_index)
		resolved.emit(caster, spell, false, "no hole near")
		return
	_animating[h.id] = {"palette": spell.palette_index, "opening": false}
	_rune(h.center, h.radius * 1.35, spell.palette_index)
	resolved.emit(caster, spell, true, "")


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
	mi.global_position = Vector3(c.x, 0.03, c.y)
	var tw := create_tween()
	tw.tween_property(mi, "scale", Vector3(0.2, 1.0, 0.2), 0.0)
	tw.tween_property(mi, "scale", Vector3.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.25)
	tw.tween_property(mi, "scale", Vector3(1.4, 1.0, 1.4), 0.2)
	tw.tween_callback(mi.queue_free)


func _fizzle_at(c: Vector2, palette_index: int) -> void:
	if not fx:
		return
	for k in 8:
		var a := TAU * k / 8.0
		fx.spawn(Vector3(c.x, 0.3, c.y), Vector3(cos(a), 0.7, sin(a)) * 1.2, 0.4, FxSprites.TILE_PUFF, 17, 1, 6.0, 2.0, -1.0, 4.0)
	fx.spawn(Vector3(c.x, 0.3, c.y), Vector3.ZERO, 0.2, FxSprites.TILE_SPARK, palette_index, 2, 5.0, 1.0)


func _process(delta: float) -> void:
	if not fx or _animating.is_empty():
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
