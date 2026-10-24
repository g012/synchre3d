class_name BeatClock
extends Node
## The match's shared tempo, set once by player 1 before the game starts.
##
## Everything that moves to the music reads it: the metronome (here), the dancing flowers
## (`DancingFlower`), the flowers in the grass (shader global `beat_time`), and the rhythm
## engines, which get the same tempo through `RhythmEngine.set_fixed_tempo`.
## Time is the PlayerInput clock (seconds), so beats line up with the timestamped taps.
##
## The tempo can slide (the Hasten / Slow spells): the clock keeps a tempo map, a list of
## segments where the BPM ramps linearly from one value to another and then holds. Rhythm
## engines keep their fixed match BPM and receive *warped* timestamps (`warp`): a time
## stretched so that beats of the current tempo fall exactly where beats of the match tempo
## would. Recognition is therefore done in beats, and a slide never breaks a chant in progress
## as long as the player follows the metronome.

## Beat `index` started (0 = the tempo's first downbeat; a bar is 4 beats).
signal beat(index: int)
signal tempo_changed(bpm: float)

const TICK := preload("res://assets/audio/metronome.wav")
const START := preload("res://assets/audio/metronome_start.wav")
## Valid tempo range: tapped tempos are clamped into it.
const BPM_RANGE := Vector2(80.0, 160.0)

static var instance: BeatClock

@export var metronome := true
## Just above the chanted syllables (their loudness at SpellCaster.voice_volume_db sits about
## 2 dB under the click's at this setting), so the beat stays audible over the chanting.
@export var volume_db := 2.0

## The match tempo (what the rhythm engines are locked to).
var bpm := 0.0
## A time (seconds) that falls on a downbeat.
var origin := 0.0
var running := false

# Tempo map, oldest first: { t, b (beats at t), from, to (BPM), dur (s of the ramp) }.
var _segments: Array[Dictionary] = []
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
	_segments.assign([{"t": downbeat, "b": 0.0, "from": value, "to": value, "dur": 0.0}])
	_last = floori(beats_at(PlayerInput.now_seconds()))
	_play(START, 1.0)
	tempo_changed.emit(bpm)


func stop() -> void:
	running = false
	bpm = 0.0
	_segments.clear()
	RenderingServer.global_shader_parameter_set("beat_time", -1.0)


## Slides the tempo to `target` BPM (clamped to BPM_RANGE) over `beats` beats, starting now
## (or at time `t`). Returns the BPM it will reach.
func slide_to(target: float, beats := 4.0, t := -1.0) -> float:
	if not running:
		return 0.0
	target = clampf(target, BPM_RANGE.x, BPM_RANGE.y)
	if t < 0.0:
		t = PlayerInput.now_seconds()
	var cur := bpm_at(t)
	# Ramp duration: `beats` beats at the average tempo.
	var dur := beats * 60.0 / ((cur + target) * 0.5)
	_add_segment(t, cur, target, dur)
	tempo_changed.emit(target)
	return target


func _add_segment(t: float, from: float, to: float, dur: float) -> void:
	var b := beats_at(t)
	# Segments only ever start at the present, so later ones can't exist; keep a short history
	# for timestamps that arrive slightly late.
	while _segments.size() > 1 and _segments[-1].t >= t:
		_segments.pop_back()
	_segments.append({"t": t, "b": b, "from": from, "to": to, "dur": dur})
	if _segments.size() > 8:
		_segments.remove_at(0)


func _segment(t: float) -> Dictionary:
	for i in range(_segments.size() - 1, -1, -1):
		if _segments[i].t <= t:
			return _segments[i]
	return _segments[0]


## Tempo (BPM) at time `t`.
func bpm_at(t: float) -> float:
	if not running:
		return 0.0
	var s := _segment(t)
	var u: float = t - s.t
	if u >= s.dur:
		return s.to
	return lerpf(s.from, s.to, maxf(u, 0.0) / s.dur)


func current_bpm() -> float:
	return bpm_at(PlayerInput.now_seconds())


## Duration of a beat at the match tempo.
func beat_duration() -> float:
	return 60.0 / bpm if bpm > 0.0 else 1.0


## Beats elapsed since `origin` at time `t` (fractional), following the tempo map.
func beats_at(t: float) -> float:
	if not running:
		return -1.0
	var s := _segment(t)
	var u: float = t - s.t
	if u <= s.dur:
		# Integral of a linear BPM ramp.
		var slope: float = (s.to - s.from) / s.dur if s.dur > 0.0 else 0.0
		return s.b + (s.from * u + 0.5 * slope * u * u) / 60.0
	var ramp: float = (s.from + s.to) * 0.5 * s.dur / 60.0
	return s.b + ramp + (u - s.dur) * s.to / 60.0


## Beats elapsed now, or -1 without a tempo.
func beats_now() -> float:
	return beats_at(PlayerInput.now_seconds())


## `t` mapped to the match tempo's timeline: identical to `t` while the tempo is unchanged.
## Rhythm engines (locked to `bpm`) are fed these.
func warp(t: float) -> float:
	if not running:
		return t
	return origin + beats_at(t) * beat_duration()


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
