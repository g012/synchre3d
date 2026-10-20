class_name RhythmEngine
extends RefCounted
## Tempo inference and rhythm recognition for one player.
##
## A port of `RhythmInput` from the original Synchre prototype
## (~/godot/synchre/scripts/rhythm_input.gd) keeping its rules and constants:
##
## * Tempo: four consecutive taps whose three intervals AND the wait after the last tap all
##   lie within +-20% of their average lock the tempo; BPM = round(3 * 60 / sum(intervals)).
##   It stays fixed until `blank_beats` beats pass without a tap, which clears everything
##   (the original used 6 = BLANK_DURATION; Synchre's arena keeps the tempo twice as long).
## * Patterns fill a measure whose end is "now"; note i must fall within +-20% of its own
##   duration around its slot; the last note is the newest unconsumed tap. Matched taps are
##   consumed so they cannot be reused.
##
## Differences, all deliberate:
## * The arena game sets one shared tempo before the match (`set_fixed_tempo`): it never
##   blanks, and count-in/opening detection are off. Recognition itself is unchanged: like
##   the original, a pattern is matched relative to its own taps, never to a bar, so a spell
##   may start on any beat.
## * A tempo can also be set by the opening notes of a spell (`tempo_from_openings`): when
##   the newest OPENING_NOTES+ taps play a spell's first syllables with its rhythm (each
##   note within the usual +-20% of its own duration around a least-squares beat fit), the
##   tempo locks right away at that beat, aligned with the notes, and the
##   incantation simply continues. No count-in is needed; the 4-tap count-in still works.
## * Time is injected (press/advance take timestamps in seconds) and every rule is solved in
##   closed form instead of being sampled once per rendered frame. The result is exactly the
##   original's behavior at infinite frame rate: it no longer depends on FPS or physics ticks,
##   and the same timestamps always give the same result (deterministic, testable, network-ready).
## * Patterns may require specific buttons per note (`RhythmPattern.syllables`).
## * Prefix progress, per-note early/late judgement and "fizzle" events are derived from the
##   very same tolerance math, for feedback/visuals only; the full match stays authoritative.

signal note_pressed(instr: int, time: float)
signal tempo_locked(bpm: float, time: float)
signal tempo_lost(time: float)
## Emitted for every press once a tempo is locked (see `_judge`).
signal note_judged(judgement: Dictionary)
signal progress_changed(pattern: RhythmPattern, step: int, time: float)
signal incantation_failed(pattern: RhythmPattern, step: int, reason: String, time: float)
signal pattern_matched(pattern: RhythmPattern, time: float)

## The original's silence (in beats) that clears the tempo.
const BLANK_DURATION := 6
## Notes of a spell needed to infer the tempo from it (2 intervals: a real rhythm).
const OPENING_NOTES := 3
## Tempo range accepted from a spell opening.
const OPENING_BPM := Vector2(80.0, 160.0)
const TOLERANCE := 0.2
const DEFAULT_BPM_R := 999.0
## Within this fraction of a note's tolerance a tap is judged "perfect".
const PERFECT_FRACTION := 0.4
const MAX_NOTES := 64

enum Rating { NONE, PERFECT, EARLY, LATE, MISS }

var patterns: Array[RhythmPattern] = []
## Beats of silence after which the tempo is dropped.
var blank_beats := BLANK_DURATION * 2
## Lock the tempo from a spell's opening notes (see class doc).
var tempo_from_openings := true
## A tempo set from outside (`set_fixed_tempo`): never blanked, never re-detected.
var fixed_tempo := false
var bpm := 0.0
var bpm_r := DEFAULT_BPM_R
var has_blanked := true
## A time that falls on the tempo grid (the last count-in tap); for metronome/UI only.
var grid_origin := 0.0
var now := 0.0
## Taps: { instr, t, duration, consumed } (same fields as the original _key_timings).
var notes: Array[Dictionary] = []

var progress_pattern: RhythmPattern = null
var progress_step := 0
var _progress_lo := 0.0
var _progress_hi := 0.0


func _init(pattern_list: Array[RhythmPattern] = []) -> void:
	patterns = pattern_list


## Uses `bpm` from now on, with beats falling on `origin` (seconds); silence never clears it.
func set_fixed_tempo(value: float, origin: float) -> void:
	fixed_tempo = true
	tempo_from_openings = false
	_set_bpm(value)
	has_blanked = false
	grid_origin = origin
	tempo_locked.emit(bpm, origin)


func beat_duration() -> float:
	return 60.0 * bpm_r


func clear() -> void:
	notes.clear()
	_set_bpm(0.0)
	has_blanked = true
	_clear_progress()


## Registers a tap of `instr` at `time` (seconds, monotonic clock).
func press(instr: int, time: float) -> void:
	advance(time)
	notes.append({"instr": instr, "t": time, "duration": 0.0, "consumed": false})
	if notes.size() > MAX_NOTES:
		notes.remove_at(0)
	note_pressed.emit(instr, time)
	if bpm <= 0.0 and not (tempo_from_openings and _lock_from_opening(time)):
		return
	var matched := _match_patterns(time)
	_track_progress(time, matched)


## Same as the original: remembers how long the newest matching tap was held.
func release(instr: int, time: float) -> void:
	for i in range(notes.size() - 1, -1, -1):
		if notes[i].instr == instr and is_zero_approx(notes[i].duration):
			notes[i].duration = time - notes[i].t
			break


## Processes time-based transitions (tempo lock, blank, incantation timeout) up to `time`,
## in chronological order. Calling it often or rarely gives identical results.
func advance(time: float) -> void:
	time = maxf(time, now)
	while true:
		var next_t := INF
		var kind := ""
		if bpm <= 0.0 and notes.size() >= 4:
			var lock_t := _tempo_lock_time()
			if lock_t >= 0.0 and lock_t < next_t:
				next_t = lock_t
				kind = "lock"
		if bpm > 0.0 and not notes.is_empty() and not fixed_tempo:
			var blank_t: float = notes[-1].t + blank_beats * beat_duration()
			if blank_t < next_t:
				next_t = blank_t
				kind = "blank"
		if progress_step > 0 and bpm > 0.0:
			var deadline := _progress_deadline()
			if deadline < next_t:
				next_t = deadline
				kind = "timeout"
		if kind == "" or next_t > time:
			break
		now = maxf(now, next_t)
		match kind:
			"lock":
				_lock_tempo(next_t)
			"blank":
				_fail_progress("tempo lost", next_t)
				notes.clear()
				_set_bpm(0.0)
				has_blanked = true
				tempo_lost.emit(next_t)
			"timeout":
				_fail_progress("too late", next_t)
	now = time


## Beat phase in [0, 1) at `time` (0 = on the beat); -1 without tempo.
func beat_phase(time: float) -> float:
	if bpm <= 0.0:
		return -1.0
	return fposmod(time - grid_origin, beat_duration()) / beat_duration()


## Number of evenly spaced trailing taps while waiting for a tempo (UI hint), 0..4.
func count_in_streak() -> int:
	if bpm > 0.0 or notes.is_empty():
		return 0
	var n := notes.size()
	if n < 2:
		return 1
	var ref: float = notes[n - 1].t - notes[n - 2].t
	var streak := 2
	for i in range(n - 2, 0, -1):
		if streak >= 4:
			break
		var d: float = notes[i].t - notes[i - 1].t
		if absf(d - ref) > TOLERANCE * ref:
			break
		streak += 1
	return streak


# ------------------------------------------------------------------------------ tempo

## Earliest time at which the original `_detect_bpm` accepts the last four taps, or -1.
## With D = sum of the 3 intervals and x = time since the last tap, every value
## v in {d1, d2, d3, x} must satisfy |v - (D + x) / 4| <= TOLERANCE * (D + x) / 4; this is
## linear in x, so the accepted x form one interval [lo, hi].
func _tempo_lock_time() -> float:
	var n := notes.size()
	var d := PackedFloat64Array([notes[n - 3].t - notes[n - 4].t, notes[n - 2].t - notes[n - 3].t,
		notes[n - 1].t - notes[n - 2].t])
	var total := d[0] + d[1] + d[2]
	if total <= 0.0:
		return -1.0
	var lo := (1.0 - TOLERANCE) * total / (3.0 + TOLERANCE)
	var hi := (1.0 + TOLERANCE) * total / (3.0 - TOLERANCE)
	for v in d:
		lo = maxf(lo, 4.0 * v / (1.0 + TOLERANCE) - total)
		hi = minf(hi, 4.0 * v / (1.0 - TOLERANCE) - total)
	if lo > hi:
		return -1.0
	return notes[n - 1].t + lo


func _lock_tempo(time: float) -> void:
	var n := notes.size()
	var total: float = notes[n - 1].t - notes[n - 4].t
	_set_bpm(floorf(0.5 + 3.0 * 60.0 / total))
	has_blanked = false
	grid_origin = notes[n - 1].t
	tempo_locked.emit(bpm, time)


## Tries to infer the tempo from the newest taps playing the start of a spell. Picks the
## longest matching opening; the beat comes from a least-squares fit of tap times against
## the notes' onsets, rounded to whole BPM like the count-in, then every note must sit
## within its usual tolerance (checked with the same `_fit` as recognition).
func _lock_from_opening(time: float) -> bool:
	var best_k := 0
	var best_bpm := 0.0
	var best_origin := 0.0
	for pattern in patterns:
		if pattern.syllables.is_empty():
			continue
		for k in range(mini(pattern.size(), notes.size()), OPENING_NOTES - 1, -1):
			if k <= best_k:
				break
			var first := notes.size() - k
			var idx: Array[int] = []
			var ok := true
			for j in k:
				var note: Dictionary = notes[first + j]
				if note.consumed or note.instr != pattern.syllables[j]:
					ok = false
					break
				idx.append(first + j)
			if not ok:
				continue
			var mx := 0.0
			var my := 0.0
			for j in k:
				mx += pattern.onset(j)
				my += notes[idx[j]].t
			mx /= k
			my /= k
			var sxy := 0.0
			var sxx := 0.0
			for j in k:
				var dx := pattern.onset(j) - mx
				sxy += dx * (notes[idx[j]].t - my)
				sxx += dx * dx
			if sxx <= 0.0 or sxy <= 0.0:
				continue
			var beat := sxy / sxx
			var candidate := floorf(0.5 + 60.0 / beat)
			if candidate < OPENING_BPM.x or candidate > OPENING_BPM.y:
				continue
			_set_bpm(candidate)
			var fit := _fit(pattern, idx, k, k == pattern.size())
			_set_bpm(0.0)
			if fit.is_empty():
				continue
			best_k = k
			best_bpm = candidate
			best_origin = (fit[0] + fit[1]) * 0.5
			break
	if best_k == 0:
		return false
	_set_bpm(best_bpm)
	has_blanked = false
	grid_origin = best_origin
	tempo_locked.emit(bpm, time)
	return true


func _set_bpm(value: float) -> void:
	bpm = value
	bpm_r = 1.0 / bpm if bpm > 0.0 else DEFAULT_BPM_R


# ------------------------------------------------------------------------------ patterns

## Indices of the newest unconsumed taps that are young enough for `pattern` (oldest first),
## like the original's event_indices: stop at a consumed tap or past the capture window.
func _recent(pattern: RhythmPattern, time: float) -> Array[int]:
	var capture := pattern.length() * beat_duration() * (1.0 + TOLERANCE)
	var out: Array[int] = []
	for i in range(notes.size() - 1, -1, -1):
		if notes[i].consumed or time - notes[i].t > capture:
			break
		out.append(i)
	out.reverse()
	return out


## Fits the first `count` notes of `pattern` onto the taps `idx` (the newest `count` taps).
## Returns [lo, hi] = the feasible range of measure-start times, or [] if impossible.
## `final` adds the original's constraint that detection happens at/after the last tap,
## i.e. the measure may not end before the last note.
func _fit(pattern: RhythmPattern, idx: Array[int], count: int, final: bool) -> Array[float]:
	var bd := beat_duration()
	var first := idx.size() - count
	var lo := -INF
	var hi := INF
	for k in count:
		var note: Dictionary = notes[idx[first + k]]
		if not pattern.syllables.is_empty() and note.instr != pattern.syllables[k]:
			return []
		var on := pattern.onset(k) * bd
		var tol := TOLERANCE * pattern.beats[k] * bd
		lo = maxf(lo, note.t - on - tol)
		hi = minf(hi, note.t - on + tol)
	if final:
		lo = maxf(lo, notes[idx[-1]].t - pattern.length() * bd)
	if lo > hi:
		return []
	return [lo, hi]


func _match_patterns(time: float) -> RhythmPattern:
	for pattern in patterns:
		var idx := _recent(pattern, time)
		if idx.size() < maxi(2, pattern.size()):
			continue
		if _fit(pattern, idx, pattern.size(), true).is_empty():
			continue
		var first := idx.size() - pattern.size()
		for k in range(first, idx.size()):
			notes[idx[k]].consumed = true
		return pattern
	return null


# ------------------------------------------------------------------------------ progress

func _track_progress(time: float, matched: RhythmPattern) -> void:
	var note: Dictionary = notes[-1]
	if matched:
		var j := _judge(matched, matched.size(), time, note)
		note_judged.emit(j)
		_clear_progress()
		progress_changed.emit(matched, matched.size(), time)
		pattern_matched.emit(matched, time)
		return

	# Longest incantation prefix that the newest taps satisfy (buttons + timing).
	var best: RhythmPattern = null
	var best_k := 0
	var best_fit: Array[float] = []
	for pattern in patterns:
		if pattern.syllables.is_empty():
			continue
		var idx := _recent(pattern, time)
		for k in range(mini(pattern.size() - 1, idx.size()), 0, -1):
			if k <= best_k:
				break
			var fit := _fit(pattern, idx, k, false)
			if not fit.is_empty():
				best = pattern
				best_k = k
				best_fit = fit
				break

	var continues := best != null and best == progress_pattern and best_k == progress_step + 1
	if progress_step > 0 and not continues:
		var reason := _break_reason(note, time)
		var miss := {"instr": note.instr, "t": time, "pattern": progress_pattern,
			"step": progress_step, "steps": progress_pattern.size(), "rating": Rating.MISS,
			"offset": reason.offset, "tolerance": reason.tolerance}
		note_judged.emit(miss)
		_fail_progress(reason.text, time)
		# A tap that just broke an incantation may only start a new one from its first note.
		if best_k > 1:
			best = _pattern_starting_with(note.instr)
			best_k = 1 if best else 0
			if best:
				best_fit = [time - best.onset(0) * beat_duration() - TOLERANCE * best.beats[0] * beat_duration(),
					time - best.onset(0) * beat_duration() + TOLERANCE * best.beats[0] * beat_duration()]
	if best_k == 0:
		if progress_step == 0:
			note_judged.emit({"instr": note.instr, "t": time, "pattern": null, "step": 0,
				"steps": 0, "rating": Rating.NONE, "offset": 0.0, "tolerance": 0.0})
		_clear_progress()
		return
	var j := _judge(best, best_k, time, note)
	note_judged.emit(j)
	progress_pattern = best
	progress_step = best_k
	_progress_lo = best_fit[0]
	_progress_hi = best_fit[1]
	progress_changed.emit(best, best_k, time)


## Early/late judgement of the newest tap as note `step` (1-based) of `pattern`, measured
## against the measure start implied by the previous taps.
func _judge(pattern: RhythmPattern, step: int, time: float, note: Dictionary) -> Dictionary:
	var j := {"instr": note.instr, "t": time, "pattern": pattern, "step": step,
		"steps": pattern.size(), "rating": Rating.NONE, "offset": 0.0, "tolerance": 0.0}
	if step <= 1 or notes.size() < step:
		return j
	# The previous step-1 taps (just before the newest), whether or not already consumed.
	var idx: Array[int] = []
	for i in range(notes.size() - step, notes.size() - 1):
		idx.append(i)
	var prev := _fit(pattern, idx, step - 1, false)
	if prev.is_empty():
		return j
	var bd := beat_duration()
	var expected := (prev[0] + prev[1]) * 0.5 + pattern.onset(step - 1) * bd
	var tol := TOLERANCE * pattern.beats[step - 1] * bd
	j.offset = time - expected
	j.tolerance = tol
	if absf(j.offset) <= PERFECT_FRACTION * tol:
		j.rating = Rating.PERFECT
	else:
		j.rating = Rating.EARLY if j.offset < 0.0 else Rating.LATE
	return j


func _pattern_starting_with(instr: int) -> RhythmPattern:
	for pattern in patterns:
		if not pattern.syllables.is_empty() and pattern.syllables[0] == instr:
			return pattern
	return null


## Why the newest tap broke the incantation in progress.
func _break_reason(note: Dictionary, time: float) -> Dictionary:
	var p := progress_pattern
	var bd := beat_duration()
	var expected := (_progress_lo + _progress_hi) * 0.5 + p.onset(progress_step) * bd
	var tol := TOLERANCE * p.beats[progress_step] * bd
	var offset := time - expected
	if note.instr != p.syllables[progress_step]:
		return {"text": "wrong syllable", "offset": offset, "tolerance": tol}
	return {"text": "too early" if offset < 0.0 else "too late", "offset": offset, "tolerance": tol}


## Latest time the next note of the incantation in progress may arrive.
func _progress_deadline() -> float:
	var p := progress_pattern
	var bd := beat_duration()
	var s := progress_step
	var late_tol := TOLERANCE * p.beats[s] * bd if s < p.size() - 1 else 0.0
	return _progress_hi + p.onset(s) * bd + late_tol


func _fail_progress(reason: String, time: float) -> void:
	if progress_step <= 0:
		return
	var p := progress_pattern
	var s := progress_step
	_clear_progress()
	incantation_failed.emit(p, s, reason, time)
	progress_changed.emit(null, 0, time)


func _clear_progress() -> void:
	progress_pattern = null
	progress_step = 0
