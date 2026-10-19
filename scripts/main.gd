extends Node
## Game flow: spawns the two fighters, runs rounds (intro -> fight -> winner -> reset),
## tracks wins, and handles the 1P / 2P toggle and debug keys.

const CHARACTER_SCENE := preload("res://scenes/character.tscn")
const PIP_MODEL := preload("res://assets/models/pip.glb")
const MOG_MODEL := preload("res://assets/models/mog.glb")

enum Phase { INTRO, FIGHT, ROUND_OVER }

## Delay after a round ends before the next one starts.
@export var round_over_time := 2.6

@onready var view: PixelView = $PixelView
@onready var world: Node3D = $PixelView/GameViewport/World
@onready var camera: PixelCamera = $PixelView/GameViewport/World/Camera
@onready var arena: Arena = $PixelView/GameViewport/World/Arena
@onready var fx: FxSprites = $PixelView/GameViewport/World/Fx
@onready var hud: Hud = $PixelView/GameViewport/Hud
@onready var post: MeshInstance3D = $PixelView/GameViewport/World/Camera/PostProcess

var two_player := false
var scores := [0, 0]
var fighters: Array[ArenaCharacter] = []
var phase := Phase.INTRO
var phase_time := 0.0
var _landed := 0
var _round_decided := false


func _ready() -> void:
	fighters.append(_make_fighter("Pip", PIP_MODEL, 4))
	fighters.append(_make_fighter("Mog", MOG_MODEL, 11))
	fighters[0].opponent = fighters[1]
	fighters[1].opponent = fighters[0]
	hud.set_names("Pip", 4, "Mog", 11)
	_apply_mode()
	start_round()


func _make_fighter(display: String, model: PackedScene, color: int) -> ArenaCharacter:
	var c := CHARACTER_SCENE.instantiate() as ArenaCharacter
	c.display_name = display
	c.model_scene = model
	c.color_index = color
	c.arena = arena
	c.camera = camera
	c.fx = fx
	c.name = display
	world.add_child(c)
	c.eliminated.connect(_on_eliminated)
	c.fell.connect(_on_fell)
	c.landed.connect(_on_landed)
	return c


func _apply_mode() -> void:
	if two_player:
		fighters[0].brain = PlayerBrain.new(["p1_"], camera)
		fighters[1].brain = PlayerBrain.new(["p2_"], camera)
	else:
		fighters[0].brain = PlayerBrain.new(["p1_", "p2_"], camera)
		fighters[1].brain = AIBrain.new(arena, randi())
	hud.set_mode(two_player)
	hud.set_score(scores[0], scores[1])


func start_round() -> void:
	phase = Phase.INTRO
	phase_time = 0.0
	_landed = 0
	_round_decided = false
	var sp := arena.config.spawn_points
	for i in fighters.size():
		var p := sp[i % sp.size()]
		var other := sp[(i + 1) % sp.size()]
		var face := Vector3(other.x - p.x, 0.0, other.y - p.y)
		fighters[i].spawn(Vector3(p.x, 0.0, p.y), face)
	hud.show_message("READY?", hud.palette_color(1, 3))


func _on_landed(_c: ArenaCharacter) -> void:
	_landed += 1


func _on_fell(c: ArenaCharacter) -> void:
	if phase != Phase.FIGHT or _round_decided:
		return
	# The round is decided the moment someone loses their footing.
	_round_decided = true
	var winner := c.opponent
	if winner.is_alive():
		var wi := fighters.find(winner)
		scores[wi] += 1
		hud.set_score(scores[0], scores[1])
		winner.celebrate()
		var sub := "%d - %d" % [scores[0], scores[1]]
		hud.show_message("%s WINS!" % winner.display_name.to_upper(), hud.palette_color(winner.color_index, 3), sub)
	phase = Phase.ROUND_OVER
	phase_time = 0.0


func _on_eliminated(c: ArenaCharacter) -> void:
	fx.vanish(c.global_position + Vector3.UP * 0.3)
	camera.shake(0.3)
	# Both fell before the round was decided (e.g. simultaneous): a draw.
	if not _round_decided:
		_round_decided = true
		hud.show_message("DRAW!", hud.palette_color(1, 3))
		phase = Phase.ROUND_OVER
		phase_time = 0.0


func _physics_process(delta: float) -> void:
	phase_time += delta
	ArenaCharacter.separate(fighters[0], fighters[1])
	match phase:
		Phase.INTRO:
			if _landed >= fighters.size() and phase_time > 1.0:
				if hud._message.text != "PUSH!":
					hud.show_message("PUSH!", hud.palette_color(6, 3))
					for f in fighters:
						f.set_frozen(false)
					phase = Phase.FIGHT
					phase_time = 0.0
		Phase.FIGHT:
			if phase_time > 0.7 and hud._message.text == "PUSH!":
				hud.hide_message()
		Phase.ROUND_OVER:
			if phase_time > round_over_time:
				start_round()
	_update_grass_actors()


func _update_grass_actors() -> void:
	var names := ["actor_a", "actor_b"]
	for i in fighters.size():
		var f := fighters[i]
		var v := Vector4(0.0, -100.0, 0.0, 0.0)
		if f.is_alive() and f.state != ArenaCharacter.State.SPAWNING:
			var p := f.global_position
			v = Vector4(p.x, p.y, p.z, 0.75)
		RenderingServer.global_shader_parameter_set(names[i], v)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_two_player"):
		two_player = not two_player
		scores = [0, 0]
		_apply_mode()
		start_round()
	elif event.is_action_pressed("restart_round"):
		start_round()
	elif event.is_action_pressed("toggle_fullscreen"):
		var w := get_window()
		w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
	elif event.is_action_pressed("toggle_pixel_view"):
		# Debug: compare with/without the outline post-process.
		post.visible = not post.visible


func _mcp_state() -> Dictionary:
	return {"phase": Phase.keys()[phase], "scores": scores, "two_player": two_player,
		"decided": _round_decided, "message": hud._message.text if hud._message.visible else ""}
