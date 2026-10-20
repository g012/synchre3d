class_name BeatClock
extends Node
## The match's shared tempo, set once by player 1 before the game starts.
##
## Everything that moves to the music reads it: the metronome (here), the dancing flowers
## (`DancingFlower`), the flowers in the grass (shader global `beat_time`), and the rhythm
## engines, which get the same tempo through `RhythmEngine.set_fixed_tempo`.
## Time is the PlayerInput clock (seconds), so beats line up with the timestamped taps.

## Beat `index` started (0 = the tempo's first downbeat; a bar is 4 beats).
signal beat(index: int)

const TICK := preload("res://assets/audio/metronome.wav")
const START := preload("res://assets/audio/metronome_start.wav")
## Valid tempo range: tapped tempos are clamped into it.
const BPM_RANGE := Vector2(80.0, 160.0)

static var instance: BeatClock

@export var metronome := true
@export var volume_db := -9.0

var bpm := 0.0
## A time (seconds) that falls on a downbeat.
var origin := 0.0
var running := false

var _last := 0
var _player: AudioStreamPlayer


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null
	RenderingServer.global_shader_parameter_set("beat_time", -1.0)


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.volume_db = volume_db
	add_child(_player)


func start(value: float, downbeat: float) -> void:
	bpm = value
	origin = downbeat
	running = true
	_last = floori(beats_at(PlayerInput.now_seconds()))
	_play(START, 1.0)


func stop() -> void:
	running = false
	bpm = 0.0
	RenderingServer.global_shader_parameter_set("beat_time", -1.0)


func beat_duration() -> float:
	return 60.0 / bpm if bpm > 0.0 else 1.0


## Beats elapsed since `origin` at time `t` (fractional).
func beats_at(t: float) -> float:
	return (t - origin) / beat_duration() if running else -1.0


## Beats elapsed now, or -1 without a tempo.
func beats_now() -> float:
	return beats_at(PlayerInput.now_seconds())


func _process(_delta: float) -> void:
	if not running:
		return
	var b := beats_now()
	RenderingServer.global_shader_parameter_set("beat_time", b)
	var idx := floori(b)
	if idx != _last:
		_last = idx
		beat.emit(idx)
		# Accent on the downbeat of each bar.
		_play(TICK, 1.25 if posmod(idx, 4) == 0 else 1.0)


func _play(stream: AudioStream, pitch: float) -> void:
	if not metronome:
		return
	_player.stream = stream
	_player.pitch_scale = pitch
	_player.play()
