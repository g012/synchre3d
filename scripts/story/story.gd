class_name Story
extends Node3D
## Story mode, old-school JRPG style: Pip starts with nothing but the shove (RB) and walks a
## fixed world (the endless field with a set seed) to five shrines. Each shrine is guarded by a
## camp of grunts; once they are gone its sage teaches one song (a tutorial lesson for that
## spell's levels), the spell joins Pip's book and the shrine becomes the checkpoint.
## Grunts also wander the world, chasing Pip only when close. Falling or running out of
## health sends Pip back to the last shrine. Progress is saved to user://story.json.
##
## Dialogue, lessons and the quest compass go through the HUD; the game flow (tempo, pause)
## stays in main.gd, which calls begin() once the tempo is set.

signal quest_changed

const CHARACTER_SCENE := preload("res://scenes/character.tscn")
const GRUNT_MODEL := preload("res://assets/models/mog.glb")
const SAVE_PATH := "user://story.json"
## The story world's seed: the same holes, ponds and trees every time.
const WORLD_SEED := 20261024
const ELDER_SPOT := Vector2(2.2, -2.0)

## The five shrines, in order. pos: world (x, z); north is up the screen (-z).
const SHRINES: Array[Dictionary] = [
	{"name": "SHRINE OF FORCE", "sage": "SAGE PEONY", "pos": Vector2(0, -40), "spell": &"push",
		"palette": 15, "petals": 30, "guards": 2,
		"before": ["You chased those brutes off my shrine. Brave little one!",
			"I am Peony, sage of Force. Listen to my song, then sing it back to me. Mind the beat!"],
		"after": ["Well sung! The Push beam is yours. Longer chants hit harder.",
			"My sister Iris keeps the Shrine of Hex, to the east."]},
	{"name": "SHRINE OF HEX", "sage": "SAGE IRIS", "pos": Vector2(48, -26), "spell": &"swap_ball",
		"palette": 12, "petals": 12, "guards": 3,
		"before": ["Tricky, tricky... you found me!",
			"I am Iris, sage of Hex. My song lets you trade places with whatever you hit."],
		"after": ["Swap is yours. Try it on a grunt next to a hole... hee hee.",
			"Clover keeps the Shrine of Time, down south-east."]},
	{"name": "SHRINE OF TIME", "sage": "SAGE CLOVER", "pos": Vector2(44, 30), "spell": &"quicken",
		"palette": 22, "petals": 1, "guards": 3,
		"before": ["Right on the beat. I am Clover, sage of Time.",
			"My song makes your feet as quick as your voice."],
		"after": ["Quicken is yours. Run when you must, chant when you can.",
			"Thistle waits at the Shrine of the Storm, to the south-west."]},
	{"name": "SHRINE OF THE STORM", "sage": "SAGE THISTLE", "pos": Vector2(-34, 44), "spell": &"shockwave",
		"palette": 4, "petals": 4, "guards": 4,
		"before": ["So you are Peony's student. I am Thistle, the storm.",
			"When they crowd around you, my song blows them all away."],
		"after": ["Shockwave is yours. Let them come close... then BOOM.",
			"The last sage, Nightshade, hides in the Shrine of Shadows, far to the west."]},
	{"name": "SHRINE OF SHADOWS", "sage": "SAGE NIGHTSHADE", "pos": Vector2(-62, -8), "spell": &"raise_minion",
		"palette": 13, "petals": 31, "guards": 5,
		"before": ["Few reach me alive. I am Nightshade, sage of Shadows.",
			"My song raises shadows of yourself to fight at your side."],
		"after": ["Minion is yours. You know all five songs now.",
			"The meadow is yours to roam. Teach those grunts some manners!"]},
]
const INTRO: Array[String] = [
	"Ah, Pip! You are awake at last. The meadow has gone wild while you slept.",
	"Shadow grunts roam the land. A shove of your hands (RB) won't hold them back for long.",
	"Long ago, five sages hid their songs in shrines across the meadow.",
	"Find them, chase off the shrine guardians, and the sages will teach you to chant.",
	"The first shrine lies to the north. Follow the arrow at the top of the screen. Go!",
]
const ELDER := "ELDER BLOOM"

enum State { IDLE, TALK, LESSON, ROAM, DONE }

var arena: Arena
var fx: FxSprites
var camera: PixelCamera
var hud: Hud
var tutorial: Tutorial
var player: ArenaCharacter
var caster: SpellCaster
var full_book: SpellBook
## Pip's own book: the spells learnt so far.
var book := SpellBook.new()
## Shrines done (0..5).
var stage := 0
var state := State.IDLE
## Who the camera should also keep in view (the sage being talked to), or null.
var focus: Node3D

var _shrines: Array[Shrine] = []
var _elder: Shrine
var _guards: Array[ArenaCharacter] = []
var _guards_for := -1
var _wanderers: Array[ArenaCharacter] = []
var _spawn_timer := 3.0
var _calm := 0.0
var _rng := RandomNumberGenerator.new()


## Areas of the world kept clear of holes, ponds and props (shrines and the start).
static func clear_zones() -> Array[Vector3]:
	var out: Array[Vector3] = [Vector3(ELDER_SPOT.x, ELDER_SPOT.y, 5.0)]
	for s in SHRINES:
		out.append(Vector3(s.pos.x, s.pos.y, 6.5))
	return out


static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


static func erase_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


## Loads progress (or starts fresh), builds the shrines and Pip's book. Call before the tempo.
func setup(new_game: bool) -> void:
	_rng.randomize()
	stage = 0
	if new_game:
		erase_save()
	elif has_save():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
		if data is Dictionary:
			stage = clampi(int(data.get("stage", 0)), 0, SHRINES.size())
	_rebuild_book()
	for c in get_children():
		c.queue_free()
	_shrines.clear()
	_guards.clear()
	_wanderers.clear()
	_guards_for = -1
	_elder = Shrine.new()
	_elder.palette_index = 28
	_elder.petal_index = 6
	_elder.with_pillar = false
	_elder.fx = fx
	_elder.position = Vector3(ELDER_SPOT.x, 0.0, ELDER_SPOT.y)
	add_child(_elder)
	_elder.set_done(stage > 0)
	for i in SHRINES.size():
		var s: Dictionary = SHRINES[i]
		var shrine := Shrine.new()
		shrine.palette_index = s.palette
		shrine.petal_index = s.petals
		shrine.fx = fx
		shrine.position = Vector3(s.pos.x, 0.0, s.pos.y)
		add_child(shrine)
		shrine.set_done(i < stage)
		_shrines.append(shrine)
	state = State.IDLE


## Where Pip starts / comes back: the last shrine done, or the elder.
func checkpoint() -> Vector2:
	if stage == 0:
		return ELDER_SPOT + Vector2(0.0, 2.5)
	return (SHRINES[stage - 1].pos as Vector2) + Vector2(0.0, 2.5)


## Tempo set: the story starts (or goes on).
func begin() -> void:
	caster.listening = true
	if stage == 0:
		focus = _elder.sage()
		_talk(ELDER, INTRO, func(): _roam())
	elif stage >= SHRINES.size():
		_roam()
		hud.show_message("WELCOME BACK", hud.palette_color(28, 3), "ALL FIVE SONGS LEARNT: ROAM FREE")
	else:
		_roam()
		hud.show_message("WELCOME BACK", hud.palette_color(28, 3), "NEXT: " + SHRINES[stage].name)


func _roam() -> void:
	state = State.ROAM if stage < SHRINES.size() else State.DONE
	focus = null
	quest_changed.emit()


## Quest line and the world point the compass shows ({} without one).
func quest() -> Dictionary:
	if stage >= SHRINES.size():
		return {"text": "ALL SONGS LEARNT - ROAM THE MEADOW"}
	var s: Dictionary = SHRINES[stage]
	var guards := _alive(_guards)
	var text: String = "QUEST: REACH THE " + s.name
	if _guards_for == stage and guards > 0:
		text = "QUEST: DEFEAT THE GUARDIANS (%d LEFT)" % guards
	elif _guards_for == stage:
		text = "QUEST: TALK TO " + s.sage
	return {"text": text, "target": s.pos}


# ---------------------------------------------------------------- dialogue and lessons

func _talk(speaker: String, lines: Array, then: Callable) -> void:
	state = State.TALK
	hud.hide_message()
	player.set_frozen(true)
	caster.cancel()
	caster.listening = false
	caster.voice = false
	hud.show_dialogue(speaker, lines, func():
		caster.voice = true
		caster.listening = true
		player.set_frozen(false)
		then.call())


func _start_lesson() -> void:
	var s: Dictionary = SHRINES[stage]
	_clear_enemies(_wanderers)
	focus = _shrines[stage].sage()
	_talk(s.sage, s.before, func():
		# The song joins Pip's book first, so it can be chanted during the lesson.
		_learn(s.spell)
		state = State.LESSON
		tutorial.book = book
		tutorial.player = player
		tutorial.caster = caster
		tutorial.successes_needed = 2
		if not tutorial.finished.is_connected(_on_lesson_done):
			tutorial.finished.connect(_on_lesson_done)
		tutorial.start(full_book.find(s.spell))
		hud.set_tutorial(tutorial))


func _on_lesson_done() -> void:
	if state != State.LESSON:
		return
	tutorial.stop()
	hud.set_tutorial(null)
	var s: Dictionary = SHRINES[stage]
	_shrines[stage].set_done(true)
	stage += 1
	_save()
	_talk(s.sage, s.after, func():
		_roam()
		if stage >= SHRINES.size():
			hud.show_message("STORY COMPLETE!", hud.palette_color(6, 3), "ALL FIVE SONGS LEARNT")
		else:
			hud.show_message("SONG LEARNT!", hud.palette_color(s.palette, 3), "NEXT: " + SHRINES[stage].name))


func _learn(id: StringName) -> void:
	var spell := full_book.find(id)
	if not spell in book.spells:
		book.spells.append(spell)
	_sort_book()
	caster.refresh_spells()
	hud.set_rhythm_panels([caster] as Array[SpellCaster], ["P1"] as Array[String])


func _rebuild_book() -> void:
	book.spells.clear()
	for i in mini(stage, SHRINES.size()):
		book.spells.append(full_book.find(SHRINES[i].spell))
	_sort_book()


## The book keeps the full book's order, so each family's first spell gets level 1 there too.
func _sort_book() -> void:
	var order := full_book.spells
	book.spells.sort_custom(func(a: SpellDefinition, b: SpellDefinition) -> bool:
		return order.find(a) < order.find(b))


func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"stage": stage}))


# ---------------------------------------------------------------- the world

func _physics_process(delta: float) -> void:
	if state == State.IDLE or not player:
		return
	var p := Vector2(player.global_position.x, player.global_position.z)
	_regen(p, delta)
	if state == State.ROAM:
		var s: Dictionary = SHRINES[stage]
		var d := p.distance_to(s.pos)
		if d < 20.0 and _guards_for != stage:
			_spawn_guards()
		if _guards_for == stage and _alive(_guards) == 0 and not _guards.is_empty():
			_guards.clear()
			hud.show_message("SHRINE CLEARED", hud.palette_color(28, 3), "TALK TO " + s.sage)
		if _guards_for == stage and _alive(_guards) == 0 and d < 4.0 and player.is_alive():
			_start_lesson()
	if state == State.ROAM or state == State.DONE:
		_update_wanderers(p, delta)
	quest_changed.emit()


## Away from enemies for a few seconds, Pip slowly heals.
func _regen(p: Vector2, delta: float) -> void:
	var near := false
	for e in _guards + _wanderers:
		if is_instance_valid(e) and e.is_alive() and p.distance_to(Vector2(e.global_position.x, e.global_position.z)) < 9.0:
			near = true
	_calm = 0.0 if near else _calm + delta
	if _calm > 3.0 and player.is_alive() and player.hp < player.max_hp:
		player.hp = minf(player.hp + 8.0 * delta, player.max_hp)


func _spawn_guards() -> void:
	_clear_enemies(_guards)
	_guards_for = stage
	var s: Dictionary = SHRINES[stage]
	var c: Vector2 = s.pos
	var n: int = s.guards
	for k in n:
		var a := TAU * k / n + _rng.randf() * 0.5
		var spot := c + Vector2.from_angle(a) * _rng.randf_range(3.5, 5.0)
		var g := _spawn_grunt(spot, 22.0 + 8.0 * stage, 2.6 + 0.2 * stage, 12.0)
		if g:
			_guards.append(g)
	hud.show_message("GUARDIANS!", hud.palette_color(4, 3), s.name)


func _update_wanderers(p: Vector2, delta: float) -> void:
	for e in _wanderers.duplicate():
		if not is_instance_valid(e):
			_wanderers.erase(e)
		elif e.is_alive() and Vector2(e.global_position.x, e.global_position.z).distance_to(p) > 26.0:
			e.queue_free()
			_wanderers.erase(e)
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	_spawn_timer = _rng.randf_range(4.0, 7.0)
	if _alive(_wanderers) >= 2 + stage:
		return
	for attempt in 10:
		var spot := p + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(12.0, 15.0)
		var near_shrine := false
		for s in SHRINES:
			near_shrine = near_shrine or spot.distance_to(s.pos) < 9.0
		if near_shrine or spot.distance_to(ELDER_SPOT) < 8.0 or arena.ground_sdf(spot) > -0.7:
			continue
		var g := _spawn_grunt(spot, 18.0 + 6.0 * stage, 2.4 + 0.2 * stage, 8.0)
		if g:
			_wanderers.append(g)
		return


func _spawn_grunt(spot: Vector2, hp: float, speed: float, aggro: float) -> ArenaCharacter:
	if arena.ground_sdf(spot) > -0.7:
		return null
	var e := CHARACTER_SCENE.instantiate() as ArenaCharacter
	e.name = "Grunt"
	e.display_name = "Grunt"
	e.model_scene = GRUNT_MODEL
	e.model_scale = 0.85
	e.color_index = 11
	e.team = 1
	e.opponent = player
	e.arena = arena
	e.camera = camera
	e.fx = fx
	e.shade = 0.25
	e.spawn_height = 1.6
	e.auto_activate = true
	e.max_hp = hp
	e.move_speed = speed
	e.push_strength = 5.5
	e.push_damage = 8.0
	e.push_cooldown = 0.9
	add_child(e)
	var brain := SwarmBrain.new(arena, player, _rng.randi())
	brain.aggro_radius = aggro
	brain.home = spot
	e.brain = brain
	e.spawn(Vector3(spot.x, arena.height_at(spot), spot.y), Vector3.FORWARD)
	e.eliminated.connect(func(c: ArenaCharacter): c.queue_free())
	return e


func _alive(list: Array[ArenaCharacter]) -> int:
	var n := 0
	for e in list:
		if is_instance_valid(e) and e.is_alive():
			n += 1
	return n


func _clear_enemies(list: Array[ArenaCharacter]) -> void:
	for e in list:
		if is_instance_valid(e):
			e.queue_free()
	list.clear()


## Pip fell or ran out of health: back to the checkpoint, the nearby trouble cleared.
func respawn() -> void:
	_clear_enemies(_wanderers)
	_clear_enemies(_guards)
	_guards_for = -1
	if state == State.LESSON:
		tutorial.stop()
		hud.set_tutorial(null)
	hud.close_dialogue()
	caster.voice = true
	caster.listening = true
	var c := checkpoint()
	player.auto_activate = true
	player.spawn(Vector3(c.x, arena.height_at(c), c.y), Vector3.FORWARD)
	player.hp = player.max_hp
	_roam()
	hud.show_message("BACK AT THE SHRINE", hud.palette_color(28, 3), "YOUR SONGS ARE SAFE")


func stop() -> void:
	state = State.IDLE
	if tutorial and tutorial.running:
		tutorial.stop()
	for c in get_children():
		c.queue_free()
	_shrines.clear()
	_guards.clear()
	_wanderers.clear()
