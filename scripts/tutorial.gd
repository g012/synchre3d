class_name Tutorial
extends Node3D
## Tutorial: one lesson per spell in play and per level, in book order. Each lesson starts
## with the game chanting the spell itself on the beat (in the player's voice, its syllables
## lighting up on the TutorialCard), then it's the player's turn: cast it `SUCCESSES` times
## to move on. Training dummies stand in front so the spells have something to work on; they
## come back when they are knocked away or fall.

signal changed

const CHARACTER_SCENE := preload("res://scenes/character.tscn")
const DUMMY_MODEL := preload("res://assets/models/mog.glb")
## Good casts needed to finish a lesson.
const SUCCESSES := 3
## Dummies: distance in front of the player, and spacing.
const DUMMY_DISTANCE := 4.0
const DUMMY_SPACING := 1.6

enum Step { LISTEN, PLAY, DONE }

var arena: Arena
var fx: FxSprites
var camera: PixelCamera
var player: ArenaCharacter
var caster: SpellCaster
var book: SpellBook
## Lessons: { spell: SpellDefinition, level: int, pattern: RhythmPattern }.
var lessons: Array[Dictionary] = []
var index := 0
var successes := 0
var step := Step.LISTEN
## Demonstration: index of the syllable sounding now (-1 none), and the beat it starts on.
var demo_lit := -1
var demo_start := 0.0
## Feedback line under the chant, and its color.
var message := ""
var message_color := Color.WHITE
var running := false

var _demo_next := 0
var _done_timer := 0.0
var _home: Array[Vector2] = []
var _dummies: Array[ArenaCharacter] = []
var _check := 0.0


func start() -> void:
	lessons.clear()
	for s in book.active():
		for level in range(book.min_level(s), s.max_level + 1):
			lessons.append({"spell": s, "level": level, "pattern": s.to_pattern(level)})
	index = 0
	running = true
	if not caster.cast.is_connected(_on_cast):
		caster.cast.connect(_on_cast)
		caster.fizzled.connect(_on_fizzled)
	_place_dummies()
	_begin_lesson()


func stop() -> void:
	running = false
	for d in _dummies:
		if is_instance_valid(d):
			d.queue_free()
	_dummies.clear()
	_home.clear()


func lesson() -> Dictionary:
	return lessons[index] if running and index < lessons.size() else {}


func next_lesson() -> void:
	if running:
		index = mini(index + 1, lessons.size() - 1)
		_begin_lesson()


func previous_lesson() -> void:
	if running:
		index = maxi(index - 1, 0)
		_begin_lesson()


## Hear the chant again (and start this lesson's count over).
func replay() -> void:
	if running:
		_begin_lesson()


func _begin_lesson() -> void:
	successes = 0
	_begin_demo()
	changed.emit()


## The demonstration starts on the next bar, with at least a beat and a half to get ready.
func _begin_demo() -> void:
	step = Step.LISTEN
	caster.cancel()
	caster.listening = false
	var b := BeatClock.instance.beats_now()
	demo_start = ceilf(b / 4.0) * 4.0
	if demo_start - b < 1.5:
		demo_start += 4.0
	_demo_next = 0
	demo_lit = -1
	message = "LISTEN..."
	message_color = Color.WHITE


func _process(delta: float) -> void:
	if not running or lessons.is_empty():
		return
	var clock := BeatClock.instance
	if not clock or not clock.running:
		return
	var p: RhythmPattern = lessons[index].pattern
	match step:
		Step.LISTEN:
			var b := clock.beats_now()
			if b < demo_start:
				message = "LISTEN...  %d" % ceili(demo_start - b)
			while _demo_next < p.size() and b >= demo_start + p.onset(_demo_next) - p.onset(0):
				for button in SpellDefinition.mask_buttons(p.masks[_demo_next]):
					caster.sing(button)
				demo_lit = _demo_next
				_demo_next += 1
				message = "LISTEN..."
			var end := demo_start + p.onset(p.size() - 1) - p.onset(0)
			if _demo_next >= p.size() and b >= end + 1.0:
				step = Step.PLAY
				demo_lit = -1
				caster.listening = true
				message = "YOUR TURN!  START ON ANY BEAT"
				message_color = Color("f6d65a")
		Step.DONE:
			_done_timer -= delta
			if _done_timer <= 0.0:
				if index < lessons.size() - 1:
					next_lesson()
				else:
					step = Step.PLAY
					message = "ALL LESSONS DONE!  KEEP PRACTISING"
	_check -= delta
	if _check <= 0.0:
		_check = 1.0
		_tend_dummies()


func _on_cast(spell: SpellDefinition, level: int, precision: float) -> void:
	if not running or step != Step.PLAY or lessons.is_empty():
		return
	var l := lessons[index]
	if spell == l.spell and level == l.level:
		successes += 1
		var grade := "PERFECT" if precision > 0.85 else ("GOOD" if precision > 0.6 else "OK")
		message = "%s!  %d%%" % [grade, roundi(precision * 100.0)]
		message_color = Color("f6d65a") if precision > 0.85 else Color(1, 1, 1)
		if successes >= SUCCESSES:
			step = Step.DONE
			_done_timer = 1.8
			message = "LESSON DONE!  %d%%" % roundi(precision * 100.0)
	else:
		message = "THAT WAS %s LV%d - TRY %s LV%d" % [spell.display_name.to_upper(), level,
			l.spell.display_name.to_upper(), l.level]
		message_color = Color("e8873a")
	changed.emit()


func _on_fizzled(_spell: SpellDefinition, _step: int, reason: String) -> void:
	if running and step == Step.PLAY:
		message = "%s - TRY AGAIN" % reason.to_upper()
		message_color = Color("e66d47")


# ---------------------------------------------------------------- training dummies

func _place_dummies() -> void:
	stop_dummies()
	var p := Vector2(player.global_position.x, player.global_position.z)
	var f := Vector2(player.facing.x, player.facing.z).normalized()
	var side := Vector2(-f.y, f.x)
	# Up to three spots on solid ground in a fan ahead, apart from each other.
	var spots: Array[Vector2] = []
	for dist in [DUMMY_DISTANCE, DUMMY_DISTANCE - 1.0, DUMMY_DISTANCE + 1.2, DUMMY_DISTANCE - 1.8]:
		for k in [0, -1, 1, -2, 2]:
			var spot: Vector2 = p + f * dist + side * DUMMY_SPACING * k
			if spots.size() >= 3 or arena.ground_sdf(spot) > -0.7:
				continue
			var free := true
			for o in spots:
				free = free and o.distance_to(spot) > DUMMY_SPACING * 0.9
			for ob in arena.obstacles:
				free = free and spot.distance_to(Vector2(ob.x, ob.y)) > ob.z + 0.6
			if free:
				spots.append(spot)
	for spot in spots:
		_home.append(spot)
		var d := CHARACTER_SCENE.instantiate() as ArenaCharacter
		d.name = "Dummy"
		d.display_name = "Dummy"
		d.model_scene = DUMMY_MODEL
		d.model_scale = 0.85
		d.color_index = 11
		d.team = 1
		d.arena = arena
		d.camera = camera
		d.fx = fx
		d.shade = 0.25
		d.spawn_height = 1.2
		d.auto_activate = true
		add_child(d)
		d.brain = CharacterBrain.new()
		d.spawn(Vector3(spot.x, arena.height_at(spot), spot.y), Vector3(-f.x, 0.0, -f.y))
		_dummies.append(d)


func stop_dummies() -> void:
	for d in _dummies:
		if is_instance_valid(d):
			d.queue_free()
	_dummies.clear()
	_home.clear()


## Dummies that fell, or were knocked away and stopped, drop back in at home.
func _tend_dummies() -> void:
	for i in _dummies.size():
		var d := _dummies[i]
		if not is_instance_valid(d):
			continue
		var at := Vector2(d.global_position.x, d.global_position.z)
		var gone := d.state == ArenaCharacter.State.OUT
		var away := d.is_alive() and at.distance_to(_home[i]) > 1.5 and d.velocity.length() < 0.3
		if gone or away:
			var h := _home[i]
			var f := Vector2(player.facing.x, player.facing.z)
			d.spawn(Vector3(h.x, arena.height_at(h), h.y), Vector3(-f.x, 0.0, -f.y))
