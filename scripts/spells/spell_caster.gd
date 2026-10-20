class_name SpellCaster
extends Node
## Turns one player's timestamped syllables into spells.
##
## Pipeline: PlayerInput (timestamped button events) -> RhythmEngine (tempo + rhythm
## recognition ported from the original Synchre) -> this node (feedback: gathering orb,
## casting pose, metronome, UI signals) -> SpellEffects (what the spell does in the arena).
## Recognition runs on event timestamps only; `_process` just lets time-based rules
## (tempo lock/blank, incantation timeout) catch up and drives visuals.

signal judged(judgement: Dictionary)
signal progress(spell: SpellDefinition, step: int, steps: int)
signal fizzled(spell: SpellDefinition, step: int, reason: String)
signal cast(spell: SpellDefinition)
signal tempo_changed(bpm: float)
signal pressed(button: int, time: float)

const METRONOME_TICK := preload("res://assets/audio/metronome.wav")
const METRONOME_START := preload("res://assets/audio/metronome_start.wav")
## One chanted syllable per button (A "Ah", B "Bra", X "Ca", Y "Da"), see tools/gen_audio.py.
const SYLLABLE_SOUNDS: Array[AudioStream] = [
	preload("res://assets/audio/syl_ah.wav"), preload("res://assets/audio/syl_bra.wav"),
	preload("res://assets/audio/syl_ca.wav"), preload("res://assets/audio/syl_da.wav")]
const FIZZLE_SOUND := preload("res://assets/audio/fizzle.wav")

@export var book: SpellBook
## Metronome clicks once the tempo is locked (the original's behavior).
@export var metronome := true
@export var metronome_pitch := 1.0
@export var metronome_volume_db := -8.0
## False while the match tempo is being chosen: syllables only sound, nothing is cast.
var listening := true
## Chanted syllables: played the instant a button is pressed.
@export var voice := true
@export var voice_pitch := 1.0
@export var voice_volume_db := -4.0

var character: ArenaCharacter
var effects: SpellEffects
var fx: FxSprites
var engine: RhythmEngine
var orb: MagicOrb

var _player: AudioStreamPlayer
var _voice: AudioStreamPlayer
var _last_beat := -1


func _ready() -> void:
	engine = RhythmEngine.new(book.patterns())
	engine.note_pressed.connect(func(b: int, t: float): pressed.emit(b, t))
	engine.note_judged.connect(func(j: Dictionary): judged.emit(j))
	engine.progress_changed.connect(_on_progress)
	engine.incantation_failed.connect(_on_failed)
	engine.pattern_matched.connect(_on_matched)
	engine.tempo_locked.connect(_on_tempo_locked)
	engine.tempo_lost.connect(func(_t: float): tempo_changed.emit(0.0))
	_player = AudioStreamPlayer.new()
	_player.volume_db = metronome_volume_db
	_player.pitch_scale = metronome_pitch
	add_child(_player)
	# Polyphonic, so quick syllables ring over each other instead of cutting off.
	_voice = AudioStreamPlayer.new()
	var poly := AudioStreamPolyphonic.new()
	poly.polyphony = 8
	_voice.stream = poly
	add_child(_voice)
	_voice.play()
	orb = MagicOrb.new()
	orb.character = character
	orb.fx = fx
	add_child(orb)


## One syllable, at `time` seconds (PlayerInput clock). Safe to call at any time: moving,
## jumping or being knocked back never blocks the incantation.
func syllable(button: int, time: float) -> void:
	if voice:
		_play_voice(SYLLABLE_SOUNDS[button], voice_volume_db, voice_pitch)
	if listening:
		engine.press(button, time)


func syllable_released(button: int, time: float) -> void:
	if listening:
		engine.release(button, time)


## Locks this caster to the match tempo (see BeatClock).
func set_tempo(bpm: float, origin: float) -> void:
	engine.set_fixed_tempo(bpm, origin)


## Drops any incantation in progress (new round); the tempo is kept while the player
## keeps playing, exactly like the original (6 silent beats clear it).
func cancel() -> void:
	engine.progress_pattern = null
	engine.progress_step = 0
	character.cast_level = 0.0
	orb.fizzle()
	progress.emit(null, 0, 0)


func _process(_delta: float) -> void:
	var now := PlayerInput.now_seconds()
	engine.advance(now)
	if engine.bpm > 0.0:
		var beat := floori((now - engine.grid_origin) / engine.beat_duration())
		if beat != _last_beat:
			if _last_beat >= 0:
				_play(METRONOME_TICK)
			_last_beat = beat
	else:
		_last_beat = -1


func _on_tempo_locked(bpm: float, _time: float) -> void:
	_last_beat = floori((PlayerInput.now_seconds() - engine.grid_origin) / engine.beat_duration())
	_play(METRONOME_START)
	tempo_changed.emit(bpm)


func _on_progress(pattern: RhythmPattern, step: int, _time: float) -> void:
	if pattern == null or step <= 0:
		character.cast_level = 0.0
		return
	var spell := pattern.payload as SpellDefinition
	var level := float(step) / pattern.size()
	if step < pattern.size():
		character.cast_level = level
		character.cast_pulse()
		orb.set_progress(level, spell.palette_index)
	progress.emit(spell, step, pattern.size())


func _on_failed(pattern: RhythmPattern, step: int, reason: String, _time: float) -> void:
	character.cast_level = 0.0
	orb.fizzle()
	_play_voice(FIZZLE_SOUND, -10.0, 1.0)
	fizzled.emit(pattern.payload as SpellDefinition, step, reason)


func _on_matched(pattern: RhythmPattern, _time: float) -> void:
	var spell := pattern.payload as SpellDefinition
	character.cast_level = 0.0
	orb.release()
	cast.emit(spell)
	if effects:
		effects.cast(spell, character, character.hand_anchor())


func _play(stream: AudioStream) -> void:
	if not metronome:
		return
	_player.stream = stream
	_player.play()


func _play_voice(stream: AudioStream, volume_db: float, pitch: float) -> void:
	if not _voice.playing:
		_voice.play()
	var pb := _voice.get_stream_playback() as AudioStreamPlaybackPolyphonic
	if pb:
		pb.play_stream(stream, 0.0, volume_db, pitch)
