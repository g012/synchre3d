class_name Survival
extends Node3D
## Single-player survival on the endless field: enemies keep spawning in a ring just off
## screen and rush the player, forever, faster and tougher as time goes on. They die when
## they fall into a hole or run out of health; the run ends when the player does.
##
## Enemies are ordinary fighters (ArenaCharacter, team 1) with health and a SwarmBrain, so
## shoves, spells, minions, holes and mounds all work on them as in duels.

signal enemy_down(enemy: ArenaCharacter)

const CHARACTER_SCENE := preload("res://scenes/character.tscn")
const ENEMY_MODEL := preload("res://assets/models/mog.glb")

## Ring around the player where enemies appear (just off screen) and distance at which
## stragglers are dropped.
@export var spawn_radius := Vector2(11.0, 13.5)
@export var despawn_distance := 21.0
## Seconds between spawns at the start and at full pressure, and how long the ramp takes.
@export var spawn_interval := Vector2(3.0, 0.4)
@export var ramp_time := 180.0
## Enemies alive at once: at the start, and at most.
@export var max_alive := Vector2i(6, 45)
@export var enemy_hp := Vector2(20.0, 60.0)
@export var enemy_speed := Vector2(2.6, 4.0)
@export var enemy_damage := Vector2(6.0, 12.0)

var arena: Arena
var fx: FxSprites
var camera: PixelCamera
var player: ArenaCharacter
var time := 0.0
var kills := 0
var running := false
var _spawn_timer := 0.0
var _rng := RandomNumberGenerator.new()


func start() -> void:
	clear()
	_rng.randomize()
	time = 0.0
	kills = 0
	running = true
	_spawn_timer = 3.0


func stop() -> void:
	running = false


func clear() -> void:
	for c in get_children():
		c.queue_free()


## 0 at the start of a run, 1 once the pressure is at its peak.
func pressure() -> float:
	return clampf(time / ramp_time, 0.0, 1.0)


func alive_enemies() -> int:
	var n := 0
	for c in get_children():
		if c is ArenaCharacter and (c as ArenaCharacter).is_alive():
			n += 1
	return n


func _physics_process(delta: float) -> void:
	if not player:
		return
	var p := Vector2(player.global_position.x, player.global_position.z)
	arena.focus = p
	if not running:
		return
	time += delta
	var k := pressure()
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = lerpf(spawn_interval.x, spawn_interval.y, k)
		var cap := int(lerpf(max_alive.x, max_alive.y, k))
		# Later on they come in small packs.
		var pack := 1 + int(k * 2.5 + _rng.randf() * k)
		for i in pack:
			if alive_enemies() < cap:
				_spawn_enemy(p)
	for c in get_children():
		var e := c as ArenaCharacter
		if e and e.is_alive() and Vector2(e.global_position.x, e.global_position.z).distance_to(p) > despawn_distance:
			e.queue_free()


func _spawn_enemy(around: Vector2) -> void:
	var spot := Vector2.INF
	for attempt in 16:
		var a := _rng.randf() * TAU
		var q := around + Vector2(cos(a), sin(a)) * _rng.randf_range(spawn_radius.x, spawn_radius.y)
		if arena.ground_sdf(q) < -0.7:
			spot = q
			break
	if spot == Vector2.INF:
		return
	var k := pressure()
	var e := CHARACTER_SCENE.instantiate() as ArenaCharacter
	e.name = "Enemy"
	e.display_name = "Grunt"
	e.model_scene = ENEMY_MODEL
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
	e.max_hp = lerpf(enemy_hp.x, enemy_hp.y, k)
	e.move_speed = lerpf(enemy_speed.x, enemy_speed.y, k) * _rng.randf_range(0.9, 1.1)
	e.push_strength = 5.5
	e.push_damage = lerpf(enemy_damage.x, enemy_damage.y, k)
	e.push_cooldown = 0.9
	add_child(e)
	e.brain = SwarmBrain.new(arena, player, _rng.randi())
	var to := around - spot
	e.spawn(Vector3(spot.x, arena.height_at(spot), spot.y), Vector3(to.x, 0.0, to.y))
	e.eliminated.connect(_on_enemy_out)


func _on_enemy_out(e: ArenaCharacter) -> void:
	if running:
		kills += 1
	enemy_down.emit(e)
	e.queue_free()
