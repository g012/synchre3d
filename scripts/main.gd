extends Node
## Game flow: spawns the two fighters, lets player 1 set the match tempo, runs rounds
## (intro -> fight -> winner -> reset), tracks wins, and handles the 1P / 2P toggle and
## debug keys.
##
## Tempo: before the first round player 1 taps four even beats (the original Synchre
## count-in rule, clamped to 80-160 BPM); the match starts as soon as they lock. That tempo
## drives the shared BeatClock (metronome, dancing flowers) and every caster's rhythm engine
## for the whole match (tempo spells slide it, and the new tempo carries over to the next rounds).
##
## Human players move/jump/shove through a PlayerBrain and cast rhythmic incantations:
## PlayerInput (timestamped A/B/X/Y) -> SpellCaster (rhythm engine) -> SpellEffects.
## The CPU opponent (AIBrain) shoves and chants through its own SpellCaster.

const CHARACTER_SCENE := preload("res://scenes/character.tscn")
const PIP_MODEL := preload("res://assets/models/pip.glb")
const MOG_MODEL := preload("res://assets/models/mog.glb")
const SPELLBOOK := preload("res://assets/spells/spellbook.tres")

enum Phase { TEMPO, INTRO, FIGHT, ROUND_OVER }

## Delay after a round ends before the next one starts.
@export var round_over_time := 2.6

@onready var view: PixelView = $PixelView
@onready var world: Node3D = $PixelView/GameViewport/World
@onready var camera: PixelCamera = $PixelView/GameViewport/World/Camera
@onready var arena: Arena = $PixelView/GameViewport/World/Arena
@onready var fx: FxSprites = $PixelView/GameViewport/World/Fx
@onready var hud: Hud = $PixelView/GameViewport/Hud
@onready var post: MeshInstance3D = $PixelView/GameViewport/World/Camera/PostProcess
@onready var spells: SpellEffects = $PixelView/GameViewport/World/Spells

var two_player := false
var scores := [0, 0]
var fighters: Array[ArenaCharacter] = []
var phase := Phase.INTRO
var phase_time := 0.0
var _landed := 0
var _round_decided := false
## Per fighter: its PlayerInput when human-controlled (else null), and its SpellCaster.
var inputs: Array[PlayerInput] = [null, null]
var casters: Array[SpellCaster] = [null, null]
var beat_clock: BeatClock
# Player 1's taps while choosing the tempo (newest last), and whether they changed since
# the last check.
var _tempo_taps := PackedFloat64Array()
var _tempo_dirty := false


func _ready() -> void:
	fighters.append(_make_fighter("Pip", PIP_MODEL, 4))
	fighters.append(_make_fighter("Mog", MOG_MODEL, 11))
	fighters[0].opponent = fighters[1]
	fighters[1].opponent = fighters[0]
	fighters[1].team = 1
	hud.set_names("Pip", 4, "Mog", 11)
	spells.setup(arena, fx, camera, fighters)
	_frame_arena()
	arena.rebuilt.connect(_frame_arena)
	beat_clock = BeatClock.new()
	beat_clock.name = "BeatClock"
	add_child(beat_clock)
	_apply_mode()
	begin_tempo_setup()


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
	var titles: Array[String] = []
	for i in fighters.size():
		var human := i == 0 or two_player
		_set_human(i, human)
		titles.append("P%d" % (i + 1) if human else "CPU")
		if human:
			var prefixes: Array[String] = []
			if not two_player:
				prefixes.append_array(["p1_", "p2_"]) # a single player may use either side / pad
			else:
				prefixes.append("p%d_" % (i + 1))
			inputs[i].prefixes = prefixes
			fighters[i].brain = PlayerBrain.new(inputs[i])
		else:
			var ai := AIBrain.new(arena, randi())
			ai.caster = casters[i]
			fighters[i].brain = ai
	hud.set_mode(two_player)
	hud.set_score(scores[0], scores[1])
	hud.set_rhythm_panels(casters, titles)


## Gives fighter `i` a SpellCaster (once), plus a PlayerInput feeding it when human.
func _set_human(i: int, human: bool) -> void:
	if casters[i] == null:
		var caster := SpellCaster.new()
		caster.name = "SpellCaster"
		caster.book = SPELLBOOK
		caster.character = fighters[i]
		caster.effects = spells
		caster.fx = fx
		caster.metronome = false # the shared BeatClock keeps time
		caster.voice_pitch = 1.0 if i == 0 else 1.12
		caster.listening = false
		fighters[i].add_child(caster)
		casters[i] = caster
	if human and inputs[i] == null:
		var input := PlayerInput.new()
		input.name = "Input%d" % (i + 1)
		input.camera = camera
		add_child(input)
		input.syllable_pressed.connect(casters[i].syllable)
		if i == 0:
			input.syllable_pressed.connect(_on_tempo_tap)
		input.syllable_released.connect(casters[i].syllable_released)
		inputs[i] = input
	elif not human and inputs[i] != null:
		inputs[i].queue_free()
		inputs[i] = null


## The camera follows the fighters but never wanders far past the island.
func _frame_arena() -> void:
	var r := arena.layout.radius
	camera.focus_bounds = Rect2(-r * 0.62, r * 1.24)


## New game: everyone stands on the island while player 1 taps the tempo.
func begin_tempo_setup() -> void:
	phase = Phase.TEMPO
	phase_time = 0.0
	beat_clock.stop()
	_tempo_taps.clear()
	_tempo_dirty = false
	for c in casters:
		if c:
			c.listening = false
	_reset_arena_and_spawn()
	hud.set_panels_visible(false)
	_show_tempo_message()


func _on_tempo_tap(_button: int, time: float) -> void:
	if phase != Phase.TEMPO:
		return
	_tempo_taps.append(time)
	if _tempo_taps.size() > 4:
		_tempo_taps.remove_at(0)
	_tempo_dirty = true
	_show_tempo_message()


## Same rule as the original count-in: the last four taps (and the wait after them) must be
## even within 20%. Re-run every frame while new taps are pending, because the rule also
## needs a short wait after the 4th tap. The match starts the moment it locks.
func _update_tempo_detection() -> void:
	if not _tempo_dirty or _tempo_taps.size() < 4:
		return
	var e := RhythmEngine.new()
	e.tempo_from_openings = false
	for t in _tempo_taps:
		e.press(0, t)
	e.advance(PlayerInput.now_seconds())
	if e.bpm <= 0.0:
		return
	_tempo_dirty = false
	var bpm := clampf(e.bpm, BeatClock.BPM_RANGE.x, BeatClock.BPM_RANGE.y)
	beat_clock.start(bpm, e.grid_origin)
	_start_match()


func _show_tempo_message() -> void:
	var sub := "P1: TAP A B X Y IN TIME, 4 TIMES  (80-160 BPM)"
	if not _tempo_taps.is_empty():
		sub += "   %d/4" % mini(_tempo_taps.size(), 4)
	hud.show_message("SET THE TEMPO", hud.palette_color(28, 3), sub)


## Tempo locked: every caster joins the shared tempo and the first round starts.
func _start_match() -> void:
	for c in casters:
		if c:
			c.set_tempo(beat_clock.bpm, beat_clock.origin)
			c.cancel()
			c.listening = true
	hud.set_panels_visible(true)
	start_round()


func _reset_arena_and_spawn() -> void:
	arena.reset_ground()
	spells.clear()
	for c in casters:
		if c:
			c.cancel()
	var sp := arena.layout.spawn_points
	for i in fighters.size():
		var p := sp[i % sp.size()]
		var other := sp[(i + 1) % sp.size()]
		var face := Vector3(other.x - p.x, 0.0, other.y - p.y)
		fighters[i].spawn(Vector3(p.x, 0.0, p.y), face)
	_update_camera_targets()
	camera.snap_to_targets()


func start_round() -> void:
	phase = Phase.INTRO
	phase_time = 0.0
	_landed = 0
	_round_decided = false
	_reset_arena_and_spawn()
	hud.show_message("READY?", hud.palette_color(1, 3), "%d BPM" % roundi(beat_clock.current_bpm()))


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
	var everyone := get_tree().get_nodes_in_group(ArenaCharacter.GROUP)
	for a in everyone.size():
		for b in range(a + 1, everyone.size()):
			ArenaCharacter.separate(everyone[a], everyone[b])
	match phase:
		Phase.TEMPO:
			_update_tempo_detection()
		Phase.INTRO:
			if _landed >= fighters.size() and phase_time > 1.0:
				hud.show_message("FIGHT!", hud.palette_color(6, 3))
				for f in fighters:
					f.set_frozen(false)
				phase = Phase.FIGHT
				phase_time = 0.0
		Phase.FIGHT:
			if phase_time > 0.7 and hud._message.text == "FIGHT!":
				hud.hide_message()
		Phase.ROUND_OVER:
			if phase_time > round_over_time:
				start_round()
	_update_grass_actors()
	_update_camera_targets()


func _update_camera_targets() -> void:
	var t: Array[Node3D] = []
	for f in fighters:
		if f.state != ArenaCharacter.State.OUT:
			t.append(f)
	camera.targets = t


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
		# A new game: scores reset and player 1 picks the tempo again.
		two_player = not two_player
		scores = [0, 0]
		_apply_mode()
		begin_tempo_setup()
	elif event.is_action_pressed("restart_round"):
		if phase != Phase.TEMPO:
			start_round()
	elif event.is_action_pressed("toggle_fullscreen"):
		var w := get_window()
		w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
	elif event.is_action_pressed("toggle_pixel_view"):
		# Debug: compare with/without the outline post-process.
		post.visible = not post.visible


func _mcp_state() -> Dictionary:
	return {"phase": Phase.keys()[phase], "scores": scores, "two_player": two_player,
		"bpm": beat_clock.current_bpm() if beat_clock else 0.0,
		"decided": _round_decided, "message": hud._message.text if hud._message.visible else ""}
