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
##   Progress follows every spell the syllables so far could still become (spells sharing an
##   opening), and only fails when none of them can continue.

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
## Timing tolerance of each note, as a fraction of its own duration (the original's 0.2).
## The count-in rule always uses the original TOLERANCE.
var tolerance := TOLERANCE
## When > 0: the same window for every note, in beats, whatever its duration (the arena game
## uses this and rewards precision instead, see `last_precision`); replaces `tolerance`.
var tolerance_beats := 0.0
## Precision of the last matched pattern: 1 = every note dead on the beat grid that fits
## them best, 0 = every note at the edge of its tolerance.
var last_precision := 1.0
var bpm := 0.0
var bpm_r := DEFAULT_BPM_R
var has_blanked := true
## A time that falls on the tempo grid (the last count-in tap); for metronome/UI only.
var grid_origin := 0.0
var now := 0.0
## Taps: { instr, t, duration, consumed } (same fields as the original _key_timings).
var notes: Array[Dictionary] = []

## Incantation in progress: how many syllables are done, every spell those syllables could
## still become (`progress_candidates`: { pattern, lo, hi } with lo/hi the feasible measure
## start, as from `_fit`), and the one leading (stable while it stays a candidate; visuals
## and failure reasons use it).
var progress_pattern: RhythmPattern = null
var progress_step := 0
var progress_candidates: Array[Dictionary] = []


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
			# The first candidate to run out of time drops out; the last one fails.
			var deadline := INF
			for c in progress_candidates:
				deadline = minf(deadline, _deadline(c))
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
				_drop_late_candidates(next_t)
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


## Timing window (seconds, either side) of note `k` of `pattern`.
func _tol(pattern: RhythmPattern, k: int) -> float:
	if tolerance_beats > 0.0:
		return tolerance_beats * beat_duration()
	return tolerance * pattern.beats[k] * beat_duration()


func _set_bpm(value: float) -> void:
	bpm = value
	bpm_r = 1.0 / bpm if bpm > 0.0 else DEFAULT_BPM_R


# ------------------------------------------------------------------------------ patterns

## Indices of the newest unconsumed taps that are young enough for `pattern` (oldest first),
## like the original's event_indices: stop at a consumed tap or past the capture window.
func _recent(pattern: RhythmPattern, time: float) -> Array[int]:
	var capture := (pattern.length() + tolerance_beats) * beat_duration() if tolerance_beats > 0.0 \
		else pattern.length() * beat_duration() * (1.0 + tolerance)
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
		var tol := _tol(pattern, k)
		lo = maxf(lo, note.t - on - tol)
		hi = minf(hi, note.t - on + tol)
	if final:
		lo = maxf(lo, notes[idx[-1]].t - pattern.length() * bd)
	if lo > hi:
		return []
	return [lo, hi]


## Longest patterns are tried first, so a chant whose ending happens to spell a shorter
## pattern still casts as the long one.
func _match_patterns(time: float) -> RhythmPattern:
	for pattern in _by_length():
		var idx := _recent(pattern, time)
		if idx.size() < maxi(2, pattern.size()):
			continue
		var fit := _fit(pattern, idx, pattern.size(), true)
		if fit.is_empty():
			continue
		var first := idx.size() - pattern.size()
		last_precision = _precision(pattern, idx.slice(first), fit)
		for k in range(first, idx.size()):
			notes[idx[k]].consumed = true
		return pattern
	return null


var _sorted: Array[RhythmPattern] = []
var _sorted_from: Array[RhythmPattern] = []


func _by_length() -> Array[RhythmPattern]:
	if _sorted_from != patterns or _sorted.size() != patterns.size():
		_sorted_from = patterns.duplicate()
		_sorted = patterns.duplicate()
		# Stable: equal lengths keep their order.
		var order := {}
		for i in _sorted.size():
			order[_sorted[i]] = i
		_sorted.sort_custom(func(a: RhythmPattern, b: RhythmPattern) -> bool:
			return a.size() > b.size() or (a.size() == b.size() and order[a] < order[b]))
	return _sorted


## 1 - mean(|offset| / tolerance) of the notes `idx` against the beat grid that fits them
## best (least squares, kept inside the feasible window [lo, hi]).
func _precision(pattern: RhythmPattern, idx: Array[int], fit: Array[float]) -> float:
	var bd := beat_duration()
	var m := 0.0
	for k in idx.size():
		m += notes[idx[k]].t - pattern.onset(k) * bd
	m = clampf(m / idx.size(), fit[0], fit[1])
	var err := 0.0
	for k in idx.size():
		var off: float = notes[idx[k]].t - (m + pattern.onset(k) * bd)
		err += absf(off) / _tol(pattern, k)
	return clampf(1.0 - err / idx.size(), 0.0, 1.0)


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

	# Longest incantation prefix that the newest taps satisfy (buttons + timing), and every
	# spell that satisfies it.
	var best_k := 0
	var found: Array[Dictionary] = []
	for pattern in patterns:
		if pattern.syllables.is_empty():
			continue
		var idx := _recent(pattern, time)
		for k in range(mini(pattern.size() - 1, idx.size()), 0, -1):
			if k < best_k:
				break
			var fit := _fit(pattern, idx, k, false)
			if not fit.is_empty():
				if k > best_k:
					best_k = k
					found.clear()
				found.append({"pattern": pattern, "lo": fit[0], "hi": fit[1]})
				break

	# Any candidate reaching one more syllable means the incantation goes on (it was a
	# candidate before: its first syllables fit the very same taps).
	var continues := progress_step > 0 and best_k == progress_step + 1
	if progress_step > 0 and not continues:
		var reason := _break_reason(note, time)
		var miss := {"instr": note.instr, "t": time, "pattern": progress_pattern,
			"step": progress_step, "steps": progress_pattern.size(), "rating": Rating.MISS,
			"offset": reason.offset, "tolerance": reason.tolerance}
		note_judged.emit(miss)
		_fail_progress(reason.text, time)
		# A tap that just broke an incantation may only start a new one from its first note.
		if best_k > 1:
			best_k = 0
			found.clear()
			var bd := beat_duration()
			for pattern in patterns:
				if not pattern.syllables.is_empty() and pattern.syllables[0] == note.instr:
					var on := time - pattern.onset(0) * bd
					var tol := _tol(pattern, 0)
					found.append({"pattern": pattern, "lo": on - tol, "hi": on + tol})
					best_k = 1
	if best_k == 0:
		if progress_step == 0:
			note_judged.emit({"instr": note.instr, "t": time, "pattern": null, "step": 0,
				"steps": 0, "rating": Rating.NONE, "offset": 0.0, "tolerance": 0.0})
		_clear_progress()
		return
	progress_candidates = found
	progress_step = best_k
	progress_pattern = _leader(progress_pattern)
	note_judged.emit(_judge(progress_pattern, best_k, time, note))
	progress_changed.emit(progress_pattern, best_k, time)


## The candidate shown as "the" incantation: `previous` while it is still one, else the
## first in book order.
func _leader(previous: RhythmPattern) -> RhythmPattern:
	for c in progress_candidates:
		if c.pattern == previous:
			return previous
	return progress_candidates[0].pattern if not progress_candidates.is_empty() else null


## Every spell the incantation in progress could still become (book order).
func candidate_patterns() -> Array[RhythmPattern]:
	var out: Array[RhythmPattern] = []
	for c in progress_candidates:
		out.append(c.pattern)
	return out


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
	var tol := _tol(pattern, step - 1)
	j.offset = time - expected
	j.tolerance = tol
	if absf(j.offset) <= PERFECT_FRACTION * tol:
		j.rating = Rating.PERFECT
	else:
		j.rating = Rating.EARLY if j.offset < 0.0 else Rating.LATE
	return j


## Why the newest tap broke the incantation in progress: a syllable no candidate expects,
## else its timing against the candidate that expected that syllable (or the leader).
func _break_reason(note: Dictionary, time: float) -> Dictionary:
	var c: Dictionary = progress_candidates[0]
	var wrong := true
	for cand in progress_candidates:
		if cand.pattern.syllables[progress_step] == note.instr:
			c = cand
			wrong = false
			break
		if cand.pattern == progress_pattern:
			c = cand
	var p: RhythmPattern = c.pattern
	var bd := beat_duration()
	var expected: float = (c.lo + c.hi) * 0.5 + p.onset(progress_step) * bd
	var tol := _tol(p, progress_step)
	var offset := time - expected
	if wrong:
		return {"text": "wrong syllable", "offset": offset, "tolerance": tol}
	return {"text": "too early" if offset < 0.0 else "too late", "offset": offset, "tolerance": tol}


## Latest time candidate `c`'s next note may arrive.
func _deadline(c: Dictionary) -> float:
	var p: RhythmPattern = c.pattern
	var bd := beat_duration()
	var s := progress_step
	var late_tol := _tol(p, s) if s < p.size() - 1 else 0.0
	return c.hi + p.onset(s) * bd + late_tol


## Candidates whose next note can no longer arrive in time drop out; the incantation fails
## when none is left.
func _drop_late_candidates(time: float) -> void:
	var left: Array[Dictionary] = []
	for c in progress_candidates:
		if _deadline(c) > time:
			left.append(c)
	if left.is_empty():
		_fail_progress("too late", time)
		return
	progress_candidates = left
	progress_pattern = _leader(progress_pattern)
	progress_changed.emit(progress_pattern, progress_step, time)


func _fail_progress(reason: String, time: float) -> void:
	if progress_step <= 0:
		return
	var p := progress_pattern
	var s := progress_step
	_clear_progress()
	incantation_failed.emit(p, s, reason, time)
	progress_changed.emit(null, 0, time)


## Drops the incantation in progress without a failure (new round).
func clear_progress() -> void:
	_clear_progress()


func _clear_progress() -> void:
	progress_pattern = null
	progress_step = 0
	progress_candidates.clear()
