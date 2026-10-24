class_name DancingFlower
extends Node3D
## A little flower with a face that dances to the match tempo (BeatClock), in the spirit of
## the dancing flowers of Super Mario Bros. Wonder: a stomp-squash on every beat, swaying
## left/right on alternate beats with the head counter-tilting, leaves waving like arms,
## petals pulsing, and a happy hop with squinted eyes on each bar's downbeat.
## Before a tempo exists it just sways gently. Model: tools/blender/build_props.py.
## A flower that ends up in pond water (swapped there by the Swap spell) is ecstatic: it
## floats, bobs, dances twice as hard with its eyes squeezed shut, and gives off sparkles.

const MODEL := preload("res://assets/models/dancing_flower.glb")

## Palette index of the petals.
@export var petal_index := 30
## Mirrors the choreography (neighbours lean opposite ways).
@export var mirrored := false

var _body: Node3D
var _parts := {}
var _rest := {}
var _petals: Array[Node3D] = []
var _idle_seed := 0.0
## In the water and loving it (see class doc).
var happy := false
## Sparkles of happy flowers (set by the game).
static var fx_sprites: FxSprites
var _sparkle := 0.0


## Things the Swap spell can trade places with besides characters.
const SWAP_GROUP := &"swap_targets"


func _ready() -> void:
	add_to_group(SWAP_GROUP)
	_idle_seed = randf() * TAU
	_body = MODEL.instantiate() as Node3D
	add_child(_body)
	var petal_mat := ToonMaterials.SOLID.duplicate() as ShaderMaterial
	petal_mat.set_shader_parameter("palette_index", petal_index)
	for mi in ToonMaterials.mesh_instances(_body):
		mi.material_override = petal_mat if mi.name.begins_with("Petal") else ToonMaterials.SOLID
	for part in ["Stem", "LeafL", "LeafR", "Head", "EyeL", "EyeR", "Mouth"]:
		var n := _body.find_child(part, true, false) as Node3D
		if n:
			_parts[part] = n
			_rest[part] = n.transform
	for n in _body.find_children("Petal*", "Node3D", true, false):
		_petals.append(n)
		_rest[n.name] = n.transform


func _process(_delta: float) -> void:
	var clock := BeatClock.instance
	var b := clock.beats_now() if clock and clock.running else -1.0
	var mirror := -1.0 if mirrored else 1.0
	var lean := 0.0
	var hit := 0.0
	var downbeat := false
	var t := Time.get_ticks_msec() * 0.001
	if b < 0.0:
		# No tempo yet: a slow idle sway.
		lean = sin(t * 1.4 + _idle_seed) * 0.07 * mirror
	else:
		var n := floori(b)
		var p := b - n
		# Sharp attack on the beat, quick decay.
		hit = pow(1.0 - p, 3.0)
		downbeat = posmod(n, 4) == 0
		# Extremes land on the beats, alternating sides; snappy in between.
		var s := cos(PI * b)
		lean = signf(s) * pow(absf(s), 0.45) * 0.24 * mirror
	var strength := 1.5 if downbeat else 1.0
	var bob := 0.0
	if happy:
		# Every beat is a downbeat when you're this happy.
		strength = 2.2
		lean *= 1.6
		bob = sin(t * 3.0 + _idle_seed) * 0.03
		_happy_sparkles()
	_body.rotation = Vector3(0.0, 0.0, lean)
	_body.scale = Vector3(1.0 + 0.1 * hit * strength, 1.0 - 0.16 * hit * strength, 1.0 + 0.1 * hit * strength)
	_body.position.y = (0.12 * hit if happy else (0.07 * hit if downbeat else 0.0)) + bob

	_pose("Head", Vector3(0.0, 0.03 * (1.0 - hit), 0.0), Vector3(0.22 * hit, 0.0, -lean * 1.4))
	_pose("LeafL", Vector3.ZERO, Vector3(0.0, 0.0, -0.55 * (lean / 0.24) * mirror - 0.3 * hit))
	_pose("LeafR", Vector3.ZERO, Vector3(0.0, 0.0, -0.55 * (lean / 0.24) * mirror + 0.3 * hit))
	var squint := 0.25 if happy else (0.35 if downbeat and hit > 0.35 else 1.0)
	for eye in ["EyeL", "EyeR"]:
		_pose(eye, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, squint, 1.0))
	_pose("Mouth", Vector3.ZERO, Vector3.ZERO, Vector3(1.0 + 0.4 * hit, 1.0 + 1.2 * hit, 1.0))
	for petal in _petals:
		var rest: Transform3D = _rest[petal.name]
		petal.transform = rest.scaled_local(Vector3.ONE * (1.0 + 0.2 * hit * strength))


## Pink and yellow sparkles floating up, and a little splash now and then.
func _happy_sparkles() -> void:
	var fx := fx_sprites
	if not fx:
		return
	_sparkle -= get_process_delta_time()
	if _sparkle > 0.0:
		return
	_sparkle = 0.12
	var top := global_position + Vector3.UP * 0.7 * scale.y
	var a := randf() * TAU
	fx.spawn(top + Vector3(cos(a) * 0.25, 0.0, sin(a) * 0.25), Vector3(cos(a) * 0.3, 1.1, sin(a) * 0.3), 0.8,
		FxSprites.TILE_STAR, 30 if randf() < 0.6 else 6, 2, 14.0, 8.0, -0.5, 1.0)
	if randf() < 0.3:
		for k in 4:
			var b := TAU * k / 4.0 + randf()
			fx.spawn(global_position + Vector3(cos(b) * 0.2, 0.05, sin(b) * 0.2), Vector3(cos(b), 2.0, sin(b)) * 0.8, 0.35,
				FxSprites.TILE_SPARK, 15, 3, 3.0, 2.0, 8.0, 0.5)


func _pose(part: String, offset: Vector3, rot: Vector3, scl := Vector3.ONE) -> void:
	var n: Node3D = _parts.get(part)
	if not n:
		return
	var rest: Transform3D = _rest[part]
	n.transform = Transform3D(rest.basis * Basis.from_euler(rot).scaled(scl), rest.origin + offset)
