extends Node
## Game flow: the title menu, then one of three modes, and debug keys.
##
## * Duel vs CPU / vs human: two fighters on the island, rounds (intro -> fight -> winner ->
##   reset) and wins.
## * Single player (survival): Pip alone on the endless field (Arena.endless) while the
##   Survival director sends enemies, until Pip falls or runs out of health.
## Start / Back / Esc pauses (resume, restart, quit to the menu); so does leaving the window.
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

enum Mode { MENU, SURVIVAL, DUEL_CPU, DUEL_HUMAN }
enum Phase { MENU, TEMPO, INTRO, FIGHT, ROUND_OVER, RUN, GAME_OVER }

const MENU_ITEMS: Array[String] = ["SINGLE PLAYER - SURVIVAL", "DUEL VS CPU", "DUEL VS HUMAN"]
const PAUSE_ITEMS: Array[String] = ["RESUME", "RESTART", "QUIT TO MENU"]
## Survival: Pip's health.
const SURVIVAL_HP := 100.0

## Pause when the window loses focus (alt-tab).
@export var pause_on_focus_loss := true
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

var mode := Mode.MENU
var two_player := false
var scores := [0, 0]
var fighters: Array[ArenaCharacter] = []
var phase := Phase.MENU
var survival: Survival
var _menu_index := 0
var paused := false
var _pause_index := 0
var _camera_home := Vector3.ZERO
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
	# The flow (menus, pause) keeps running while the game is paused; everything else stops.
	process_mode = Node.PROCESS_MODE_ALWAYS
	for c in get_children():
		c.process_mode = Node.PROCESS_MODE_PAUSABLE
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
	beat_clock.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(beat_clock)
	survival = Survival.new()
	survival.name = "Survival"
	survival.arena = arena
	survival.fx = fx
	survival.camera = camera
	world.add_child(survival)
	_camera_home = camera.focus
	enter_menu()


# ------------------------------------------------------------------ menu and modes

## Title menu over the island: everything stops, fighters leave the stage.
func enter_menu() -> void:
	_set_paused(false)
	mode = Mode.MENU
	phase = Phase.MENU
	survival.stop()
	survival.clear()
	beat_clock.stop()
	for c in casters:
		if c:
			c.listening = false
			c.cancel()
	if arena.endless:
		arena.endless = false
		arena.rebuild()
	else:
		arena.reset_ground()
	spells.clear()
	for f in fighters:
		_bench(f, true)
	camera.targets = []
	camera.focus = _camera_home
	hud.set_panels_visible(false)
	hud.hide_message()
	hud.set_mode("menu")
	_show_menu()


func _show_menu() -> void:
	hud.show_menu("SYNCHRE", MENU_ITEMS, _menu_index,
		"STICK / D-PAD: CHOOSE    A / ENTER: START\nIN GAME  R3 / F2: HIDE SPELL SHEETS    BACK: MENU")


func _start_mode(m: Mode) -> void:
	hud.hide_menu()
	mode = m
	scores = [0, 0]
	if m == Mode.SURVIVAL:
		arena.endless = true
		arena.focus = Vector2.ZERO
		arena.rebuild()
		_bench(fighters[0], false)
		_bench(fighters[1], true)
	else:
		two_player = m == Mode.DUEL_HUMAN
		for f in fighters:
			_bench(f, false)
	_apply_mode()
	begin_tempo_setup()


## A benched fighter is out of the game: hidden, frozen, untouchable.
func _bench(f: ArenaCharacter, benched: bool) -> void:
	f.visible = not benched
	f.process_mode = Node.PROCESS_MODE_DISABLED if benched else Node.PROCESS_MODE_INHERIT
	f.collision_layer = 0 if benched else Arena.LAYER_CHARACTERS
	# The caster's ring and orb hang under a plain Node, which visibility doesn't pass through.
	var i := fighters.find(f)
	if i >= 0 and casters[i]:
		for n in casters[i].get_children():
			if n is Node3D:
				n.visible = not benched
	if benched:
		f.remove_from_group(ArenaCharacter.GROUP)
	elif not f.is_in_group(ArenaCharacter.GROUP):
		f.add_to_group(ArenaCharacter.GROUP)


func _is_benched(f: ArenaCharacter) -> bool:
	return f.process_mode == Node.PROCESS_MODE_DISABLED


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
	if mode == Mode.SURVIVAL:
		_apply_survival()
		return
	fighters[0].opponent = fighters[1]
	fighters[1].opponent = fighters[0]
	for f in fighters:
		f.max_hp = 0.0
		f.auto_activate = false
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
	hud.set_mode("human" if two_player else "cpu")
	hud.set_score(scores[0], scores[1])
	hud.set_rhythm_panels(casters, titles)


## Survival: Pip alone, played with either pad or keyboard side, with health.
func _apply_survival() -> void:
	_set_human(0, true)
	_set_human(1, false)
	_bench(fighters[1], true) # again: its caster (and ring) may have just been created
	inputs[0].prefixes = ["p1_", "p2_"]
	var pip := fighters[0]
	var brain := PlayerBrain.new(inputs[0])
	brain.no_auto_aim = true
	pip.brain = brain
	pip.auto_aim = false
	pip.opponent = null
	pip.max_hp = SURVIVAL_HP
	# Frozen until the tempo is set (see _start_run).
	pip.auto_activate = false
	survival.player = pip
	hud.set_mode("survival")
	var solo: Array[SpellCaster] = [casters[0]]
	hud.set_rhythm_panels(solo, ["P1"] as Array[String])


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
		input.process_mode = Node.PROCESS_MODE_PAUSABLE
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
	survival.stop()
	survival.clear()
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
	for i in casters.size():
		var c := casters[i]
		if c and not _is_benched(fighters[i]):
			c.set_tempo(beat_clock.bpm, beat_clock.origin)
			c.cancel()
			c.listening = true
	hud.set_panels_visible(true)
	# Straight into the action: everyone is already standing there.
	if mode == Mode.SURVIVAL:
		_start_run(false)
	else:
		_round_decided = false
		_start_fight()


## A survival run. Right after the tempo: Pip is already on the field, just let go.
## Otherwise (again / restart): a fresh endless field and Pip dropped at its origin.
func _start_run(new_field := true) -> void:
	phase = Phase.RUN
	phase_time = 0.0
	var pip := fighters[0]
	if new_field:
		arena.focus = Vector2.ZERO
		arena.rebuild()
		_reset_arena_and_spawn()
	# Still dropping in: it starts moving when it lands.
	pip.auto_activate = true
	pip.set_frozen(false)
	survival.start()
	hud.show_message("SURVIVE!", hud.palette_color(6, 3), "PUSH THEM INTO THE HOLES")


func _reset_arena_and_spawn() -> void:
	if not arena.endless:
		arena.reset_ground()
	spells.clear()
	for c in casters:
		if c:
			c.cancel()
	if mode == Mode.SURVIVAL:
		fighters[0].spawn(Vector3.ZERO, Vector3.FORWARD)
		_update_camera_targets()
		camera.snap_to_targets()
		return
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
	for f in fighters:
		f.auto_activate = false
	_reset_arena_and_spawn()
	hud.show_message("READY?", hud.palette_color(1, 3), "%d BPM" % roundi(beat_clock.current_bpm()))


## Fighters let go (anyone still dropping in starts when it lands).
func _start_fight() -> void:
	hud.show_message("FIGHT!", hud.palette_color(6, 3))
	for f in fighters:
		f.auto_activate = true
		f.set_frozen(false)
	phase = Phase.FIGHT
	phase_time = 0.0


func _on_landed(_c: ArenaCharacter) -> void:
	_landed += 1


func _on_fell(c: ArenaCharacter) -> void:
	if mode == Mode.SURVIVAL or phase != Phase.FIGHT or _round_decided:
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
	if mode == Mode.SURVIVAL:
		if phase == Phase.RUN:
			_game_over(c.hp <= 0.0 and c.max_hp > 0.0)
		return
	# Both fell before the round was decided (e.g. simultaneous): a draw.
	if not _round_decided:
		_round_decided = true
		hud.show_message("DRAW!", hud.palette_color(1, 3))
		phase = Phase.ROUND_OVER
		phase_time = 0.0


## Survival run over: the field keeps going behind the score.
func _game_over(defeated: bool) -> void:
	phase = Phase.GAME_OVER
	phase_time = 0.0
	survival.stop()
	var t := int(survival.time)
	hud.show_message("DEFEATED" if defeated else "YOU FELL", hud.palette_color(4, 3),
		"SURVIVED %d:%02d  -  %d KILLS     START / R: AGAIN    BACK / ESC: MENU" % [t / 60, t % 60, survival.kills])


func _update_survival_status() -> void:
	var pip := fighters[0]
	var t := int(survival.time)
	var hp_color := hud.palette_color(4, 3) if pip.hp < SURVIVAL_HP * 0.3 else Color.WHITE
	hud.set_status("HP %d    %d:%02d    KILLS %d" % [ceili(pip.hp), t / 60, t % 60, survival.kills], hp_color)


func _process(_delta: float) -> void:
	if mode == Mode.MENU:
		var moved := _menu_move()
		if moved != 0:
			_menu_index = posmod(_menu_index + moved, MENU_ITEMS.size())
			_show_menu()
		if _menu_accept(true):
			_start_mode([Mode.SURVIVAL, Mode.DUEL_CPU, Mode.DUEL_HUMAN][_menu_index])
	elif paused:
		var moved := _menu_move()
		if moved != 0:
			_pause_index = posmod(_pause_index + moved, PAUSE_ITEMS.size())
			_show_pause()
		# Start resumes (see _unhandled_input), so only A / Enter pick an item here.
		if _menu_accept(false):
			match _pause_index:
				0: _set_paused(false)
				1: _restart()
				2: enter_menu()


func _menu_move() -> int:
	var moved := 0
	for a in ["ui_up", "p1_up", "p2_up"]:
		if Input.is_action_just_pressed(a):
			moved = -1
	for a in ["ui_down", "p1_down", "p2_down"]:
		if Input.is_action_just_pressed(a):
			moved = 1
	return moved


func _menu_accept(with_start: bool) -> bool:
	for a in ["ui_accept", "p1_syl_a", "p2_syl_a"]:
		if Input.is_action_just_pressed(a):
			return true
	return with_start and Input.is_action_just_pressed("restart_round")


# ------------------------------------------------------------------ pause

func _set_paused(on: bool) -> void:
	if on == paused:
		return
	paused = on
	get_tree().paused = on
	if on:
		_pause_index = 0
		_show_pause()
	else:
		hud.hide_menu()
		# A chant can't survive a pause (the beat went on meanwhile).
		for c in casters:
			if c:
				c.cancel()


func _show_pause() -> void:
	hud.show_menu("PAUSED", PAUSE_ITEMS, _pause_index, "STICK / D-PAD: CHOOSE    A / ENTER: SELECT\nSTART / BACK / ESC: RESUME")


## Pause menu "restart": a new survival run, or the duel from 0 - 0 (same tempo).
func _restart() -> void:
	_set_paused(false)
	if phase == Phase.TEMPO:
		begin_tempo_setup()
	elif mode == Mode.SURVIVAL:
		_start_run()
	else:
		scores = [0, 0]
		hud.set_score(0, 0)
		start_round()


func _notification(what: int) -> void:
	# Alt-tabbing away mid-game pauses it.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and pause_on_focus_loss and mode != Mode.MENU and is_node_ready():
		_set_paused(true)


func _physics_process(delta: float) -> void:
	if paused:
		return
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
				_start_fight()
		Phase.FIGHT:
			if phase_time > 0.7 and hud._message.text == "FIGHT!":
				hud.hide_message()
		Phase.ROUND_OVER:
			if phase_time > round_over_time:
				start_round()
		Phase.RUN:
			if phase_time > 1.5 and hud._message.text == "SURVIVE!":
				hud.hide_message()
	if mode == Mode.SURVIVAL:
		_update_survival_status()
	_update_grass_actors()
	_update_camera_targets()


func _update_camera_targets() -> void:
	var t: Array[Node3D] = []
	for f in fighters:
		if f.state != ArenaCharacter.State.OUT and not _is_benched(f):
			t.append(f)
	if mode != Mode.MENU:
		camera.targets = t


func _update_grass_actors() -> void:
	var names := ["actor_a", "actor_b"]
	for i in fighters.size():
		var f := fighters[i]
		var v := Vector4(0.0, -100.0, 0.0, 0.0)
		if f.is_alive() and f.state != ArenaCharacter.State.SPAWNING and not _is_benched(f):
			var p := f.global_position
			v = Vector4(p.x, p.y, p.z, 0.75)
		RenderingServer.global_shader_parameter_set(names[i], v)


func _unhandled_input(event: InputEvent) -> void:
	# Window-manager shortcuts (alt-tab, super-...) are not for the game.
	if event is InputEventKey and (event.alt_pressed or event.meta_pressed or event.ctrl_pressed):
		return
	var back := event.is_action_pressed("toggle_two_player")
	var start := event.is_action_pressed("restart_round")
	if back or start:
		if mode == Mode.MENU:
			return
		if paused:
			_set_paused(false)
		elif mode == Mode.SURVIVAL and phase == Phase.GAME_OVER:
			if start:
				_start_run()
			else:
				enter_menu()
		else:
			_set_paused(true)
		get_viewport().set_input_as_handled()
	elif (event is InputEventJoypadButton and event.pressed and (event as InputEventJoypadButton).button_index == JOY_BUTTON_RIGHT_STICK) \
			or (event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_F2):
		# Hide / show the spell sheets: practise chanting from memory.
		hud.toggle_sheets()
	elif event.is_action_pressed("toggle_fullscreen"):
		var w := get_window()
		w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
	elif event.is_action_pressed("toggle_pixel_view"):
		# Debug: compare with/without the outline post-process.
		post.visible = not post.visible


func _mcp_state() -> Dictionary:
	return {"mode": Mode.keys()[mode], "phase": Phase.keys()[phase], "paused": paused, "scores": scores, "two_player": two_player,
		"survival": {"time": snappedf(survival.time, 0.1), "kills": survival.kills, "alive": survival.alive_enemies()} if survival else {},
		"bpm": beat_clock.current_bpm() if beat_clock else 0.0,
		"decided": _round_decided, "message": hud._message.text if hud._message.visible else ""}
