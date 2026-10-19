extends SceneTree
## Automated tests for the rhythm engine. Run headless:
##   godot --headless --path . -s tests/test_rhythm.gd
## Exits with code 1 if any check fails.

const A := 0
const B := 1
const X := 2
const Y := 3

var _failures := 0
var _checks := 0
var _log: Array[String] = []


func _init() -> void:
	test_tempo_lock_time_and_bpm()
	test_tempo_tolerance_boundaries()
	test_no_lock_before_wait()
	test_blank_after_six_beats()
	test_tempo_change_after_blank()
	test_push_spell_matches()
	test_spell_at_other_tempos()
	test_wrong_syllable()
	test_missed_note()
	test_last_note_late_boundary()
	test_inner_note_tolerance_boundary()
	test_timing_ratings()
	test_timeout_and_granularity()
	test_rapid_successive_casts()
	test_consumed_notes_not_reused()
	test_tempo_drift_within_and_beyond_tolerance()
	test_extra_tap_restarts_incantation()
	test_multiple_spells_distinguished()
	test_matches_original_frame_sampled_algorithm()
	test_spellbook()
	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


# ------------------------------------------------------------------------------ helpers

func check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL: ", what)


func spells() -> Array[RhythmPattern]:
	var N := RhythmPattern.NOIRE
	var C := RhythmPattern.CROCHE
	var NP := RhythmPattern.NOIREP
	return [
		RhythmPattern.new("push", PackedFloat32Array([N, C, C, N, N]), PackedInt32Array([A, B, X, Y, A])),
		RhythmPattern.new("create_hole", PackedFloat32Array([NP, C, NP, C]), PackedInt32Array([X, Y, X, Y])),
		RhythmPattern.new("close_hole", PackedFloat32Array([N, N, C, C, N]), PackedInt32Array([B, Y, B, Y, A])),
	]


## Engine plus an event log (signals are recorded as strings).
func make_engine(patterns: Array[RhythmPattern] = spells()) -> RhythmEngine:
	var e := RhythmEngine.new(patterns)
	_log = []
	e.tempo_locked.connect(func(bpm: float, t: float): _log.append("lock %d @%.4f" % [bpm, t]))
	e.tempo_lost.connect(func(t: float): _log.append("lost @%.4f" % t))
	e.pattern_matched.connect(func(p: RhythmPattern, t: float): _log.append("match %s @%.4f" % [p.pattern_name, t]))
	e.incantation_failed.connect(func(p: RhythmPattern, s: int, r: String, t: float):
		_log.append("fail %s %d %s @%.4f" % [p.pattern_name, s, r, t]))
	return e


func has(prefix: String) -> bool:
	for l in _log:
		if l.begins_with(prefix):
			return true
	return false


## Four even count-in taps starting at t0; returns the time of the next beat.
func count_in(e: RhythmEngine, t0: float, beat: float, instr := A) -> float:
	for i in 4:
		e.press(instr, t0 + i * beat)
	return t0 + 4 * beat


## Plays `pattern` with its measure starting at `m`; optional per-note offsets (seconds).
func play(e: RhythmEngine, pattern: RhythmPattern, m: float, beat: float, offsets := {}, buttons := PackedInt32Array()) -> float:
	var last := 0.0
	for k in pattern.size():
		var t: float = m + pattern.onset(k) * beat + offsets.get(k, 0.0)
		var b := buttons[k] if k < buttons.size() else pattern.syllables[k]
		e.press(b, t)
		last = t
	return last


# ------------------------------------------------------------------------------ tempo

func test_tempo_lock_time_and_bpm() -> void:
	var e := make_engine()
	count_in(e, 1.0, 0.5)
	e.advance(2.5 + 0.374)
	check(e.bpm == 0.0, "no lock before 0.25*D after the 4th tap")
	e.advance(2.5 + 0.376)
	check(e.bpm == 120.0, "locks at 120 bpm (got %s)" % e.bpm)
	check(has("lock 120 @2.8750"), "lock time = 4th tap + 0.25 * sum(intervals): %s" % [_log])


func test_tempo_tolerance_boundaries() -> void:
	# Intervals 0.5, 0.5, 0.62: within 20% of the average once x is chosen -> lock.
	var e := make_engine()
	for t in [0.0, 0.5, 1.0, 1.6]:
		e.press(A, t)
	e.advance(2.1)
	check(e.bpm > 0.0, "uneven but tolerated count-in locks")
	# Intervals 0.5, 0.5, 0.9: impossible -> never locks.
	e = make_engine()
	for t in [0.0, 0.5, 1.0, 1.9]:
		e.press(A, t)
	e.advance(5.0)
	check(e.bpm == 0.0, "too uneven count-in does not lock")


func test_no_lock_before_wait() -> void:
	# The original also requires the wait after the 4th tap to be beat-like: a 5th tap that
	# comes much too early prevents locking on taps 1-4.
	var e := make_engine()
	for t in [0.0, 0.5, 1.0, 1.5, 1.6]:
		e.press(A, t)
	e.advance(1.62)
	check(e.bpm == 0.0, "early 5th tap prevents the lock")


func test_blank_after_six_beats() -> void:
	var e := make_engine()
	count_in(e, 0.0, 0.5)
	e.advance(1.5 + 3.0 - 0.001)
	check(e.bpm == 120.0, "tempo kept just before 6 beats of silence")
	e.advance(1.5 + 3.0 + 0.001)
	check(e.bpm == 0.0 and has("lost @4.5000"), "tempo lost after 6 beats of silence: %s" % [_log])


func test_tempo_change_after_blank() -> void:
	var e := make_engine()
	count_in(e, 0.0, 0.5)
	e.advance(10.0)
	check(e.bpm == 0.0, "blanked")
	count_in(e, 10.0, 60.0 / 90.0)
	e.advance(14.0)
	check(e.bpm == 90.0, "relocks at the new tempo (got %s)" % e.bpm)


# ------------------------------------------------------------------------------ spells

func test_push_spell_matches() -> void:
	var e := make_engine()
	var m := count_in(e, 0.0, 0.5)
	play(e, e.patterns[0], m, 0.5)
	check(has("match push"), "ABXYA in rhythm casts push: %s" % [_log])


func test_spell_at_other_tempos() -> void:
	for bpm in [70.0, 100.0, 160.0]:
		var beat: float = 60.0 / bpm
		var e := make_engine()
		var m := count_in(e, 0.0, beat)
		play(e, e.patterns[0], m, beat)
		check(has("match push"), "push at %d bpm" % bpm)
		check(absf(e.bpm - bpm) <= 1.0, "bpm %d inferred (%s)" % [bpm, e.bpm])


func test_wrong_syllable() -> void:
	var e := make_engine()
	var m := count_in(e, 0.0, 0.5)
	play(e, e.patterns[0], m, 0.5, {}, PackedInt32Array([A, B, X, B, A]))
	check(not has("match"), "ABXBA does not cast")
	check(has("fail push 3 wrong syllable"), "wrong syllable reported: %s" % [_log])


func test_missed_note() -> void:
	var e := make_engine()
	var m := count_in(e, 0.0, 0.5)
	var p: RhythmPattern = e.patterns[0]
	for k in [0, 1, 3, 4]:
		e.press(p.syllables[k], m + p.onset(k) * 0.5)
	check(not has("match"), "missing X does not cast")
	check(has("fail push 2"), "missed note reported: %s" % [_log])


func test_last_note_late_boundary() -> void:
	# At 120 bpm the tightest inner tolerance is 20% of an eighth = 50 ms; the original lets
	# the measure grid slide by at most that much to absorb a late last note.
	var e := make_engine()
	var m := count_in(e, 0.0, 0.5)
	play(e, e.patterns[0], m, 0.5, {4: 0.049})
	check(has("match push"), "last note 49 ms late still casts")
	e = make_engine()
	m = count_in(e, 0.0, 0.5)
	play(e, e.patterns[0], m, 0.5, {4: 0.051})
	check(not has("match"), "last note 51 ms late does not cast: %s" % [_log])
	# Early last note: its own tolerance (20% of a quarter = 100 ms) plus the 50 ms the grid
	# may slide while every other note stays within tolerance -> 150 ms.
	e = make_engine()
	m = count_in(e, 0.0, 0.5)
	play(e, e.patterns[0], m, 0.5, {4: -0.149})
	check(has("match push"), "last note 149 ms early casts")
	e = make_engine()
	m = count_in(e, 0.0, 0.5)
	play(e, e.patterns[0], m, 0.5, {4: -0.151})
	check(not has("match"), "last note 151 ms early does not cast")


func test_inner_note_tolerance_boundary() -> void:
	# Note 2 (X, an eighth after B): own tolerance 50 ms, plus 50 ms of grid slide limited by
	# B's tolerance -> 100 ms.
	var e := make_engine()
	var m := count_in(e, 0.0, 0.5)
	play(e, e.patterns[0], m, 0.5, {2: 0.099})
	check(has("match push"), "inner note 99 ms late casts")
	e = make_engine()
	m = count_in(e, 0.0, 0.5)
	play(e, e.patterns[0], m, 0.5, {2: 0.101})
	check(not has("match"), "inner note 101 ms late does not cast")
	check(has("fail push 2 too late"), "reported as too late: %s" % [_log])


func test_timing_ratings() -> void:
	var e := make_engine()
	var ratings: Array[int] = []
	e.note_judged.connect(func(j: Dictionary): ratings.append(j.rating))
	var m := count_in(e, 0.0, 0.5)
	play(e, e.patterns[0], m, 0.5, {1: -0.03, 2: 0.0, 3: 0.06})
	# k=0 start (NONE), k=1 early by 30 ms of 50 -> EARLY, k=2 perfect-ish, k=3 late 60/100 -> LATE
	check(ratings.size() == 5, "one judgement per note (%s)" % [ratings])
	check(ratings[0] == RhythmEngine.Rating.NONE, "first syllable has no timing reference")
	check(ratings[1] == RhythmEngine.Rating.EARLY, "30 ms early judged EARLY (%s)" % [ratings])
	check(ratings[3] == RhythmEngine.Rating.LATE, "60 ms late judged LATE (%s)" % [ratings])


func test_timeout_and_granularity() -> void:
	var logs := []
	for step in [0.001, 0.016, 0.1, 5.0]:
		var e := make_engine()
		var m := count_in(e, 0.0, 0.5)
		e.press(A, m + 0.5)
		e.press(B, m + 0.75)
		var t := m + 0.75
		while t < m + 6.0:
			t += step
			e.advance(t)
		logs.append(_log.duplicate())
	check(logs[0] == logs[1] and logs[1] == logs[2] and logs[2] == logs[3],
		"same events whatever the update rate: %s" % [logs])
	check(" ".join(PackedStringArray(logs[0])).contains("fail push 2 too late"), "stalled incantation times out")


func test_rapid_successive_casts() -> void:
	var e := make_engine()
	var m := count_in(e, 0.0, 0.5)
	play(e, e.patterns[0], m, 0.5)
	play(e, e.patterns[0], m + 2.0, 0.5)
	play(e, e.patterns[0], m + 4.0, 0.5)
	var n := 0
	for l in _log:
		if l.begins_with("match push"):
			n += 1
	check(n == 3, "three consecutive measures cast three times (%d)" % n)


func test_consumed_notes_not_reused() -> void:
	# After a cast, a single extra A must not re-trigger using the previous taps.
	var e := make_engine()
	var m := count_in(e, 0.0, 0.5)
	play(e, e.patterns[0], m, 0.5)
	e.press(A, m + 2.5)
	var n := 0
	for l in _log:
		if l.begins_with("match"):
			n += 1
	check(n == 1, "consumed taps are not reused")


func test_tempo_drift_within_and_beyond_tolerance() -> void:
	# Playing the incantation 5% faster than the locked tempo still casts...
	var e := make_engine()
	var m := count_in(e, 0.0, 0.5)
	play(e, e.patterns[0], m, 0.5 * 0.95)
	check(has("match push"), "5% faster still casts")
	# ...25% faster does not.
	e = make_engine()
	m = count_in(e, 0.0, 0.5)
	play(e, e.patterns[0], m, 0.5 * 0.75)
	check(not has("match"), "25% faster does not cast")


func test_extra_tap_restarts_incantation() -> void:
	var e := make_engine()
	var m := count_in(e, 0.0, 0.5)
	e.press(A, m + 0.5)
	e.press(B, m + 0.75)
	# Player restarts from the top in the next measure.
	play(e, e.patterns[0], m + 2.0, 0.5)
	check(has("match push"), "can restart after abandoning an incantation: %s" % [_log])


func test_multiple_spells_distinguished() -> void:
	var e := make_engine()
	var m := count_in(e, 0.0, 0.5)
	play(e, e.patterns[1], m, 0.5)
	play(e, e.patterns[2], m + 2.0, 0.5)
	check(has("match create_hole") and has("match close_hole"), "each spell recognized: %s" % [_log])
	check(not has("match push"), "no false push")


# ------------------------------------------------------------------------------ original

## Line-by-line port of the original _detect_blank/_detect_bpm/_detect_rhythm, run once per
## simulated frame like the original. Returns its event log.
func original_reference(presses: Array, fps: float, patterns: Array[RhythmPattern]) -> Array[String]:
	var TOL := 0.2
	var key_timings: Array[Dictionary] = []
	var bpm := 0.0
	var bpm_r := 999.0
	var has_blanked := true
	var out: Array[String] = []
	var pi := 0
	var now := 0.0
	var end_t: float = presses[-1][1] + 5.0
	# Frames tick at `fps`; like the original, a frame also runs right when a press arrives
	# (the tap is timestamped in _input and _process runs in that same frame).
	while now < end_t:
		var next_frame := now + 1.0 / fps
		if pi < presses.size() and presses[pi][1] < next_frame:
			next_frame = presses[pi][1] + 1e-6
		now = next_frame
		while pi < presses.size() and presses[pi][1] <= now:
			key_timings.append({"instr": presses[pi][0], "t": presses[pi][1], "consumed": false})
			pi += 1
		# _detect_blank
		if bpm <= 0.0 or key_timings.is_empty():
			has_blanked = true
		elif now - key_timings[-1].t < 6 * 60.0 * bpm_r:
			has_blanked = false
		else:
			key_timings.clear()
			bpm = 0.0
			bpm_r = 999.0
			has_blanked = true
			out.append("lost")
		# _detect_bpm
		if key_timings.size() >= 4 and has_blanked:
			var durations := []
			var duration := 0.0
			for i in 3:
				var v: float = key_timings[key_timings.size() - 3 + i].t - key_timings[key_timings.size() - 4 + i].t
				durations.append(v)
				duration += v
			if duration > 0.0:
				durations.append(now - key_timings[-1].t)
				var average: float = 0.25 * (duration + durations[3])
				var ok := true
				for v in durations:
					if absf(v - average) > TOL * average:
						ok = false
				if ok:
					bpm = floorf(0.5 + 3.0 * 60.0 / duration)
					bpm_r = 1.0 / bpm
					has_blanked = false
					out.append("lock %d" % bpm)
		# _detect_rhythm
		if bpm > 0.0:
			var beat_duration := 60.0 * bpm_r
			var measure_duration := 4.0 * beat_duration
			var capture := measure_duration * (1.0 + TOL)
			var idx: Array[int] = []
			for i in range(key_timings.size() - 1, -1, -1):
				if key_timings[i].consumed or now - key_timings[i].t > capture:
					break
				idx.append(i)
			if idx.size() >= 2:
				idx.reverse()
				var measure_start := now - measure_duration
				for p in patterns:
					if p.beats.size() > idx.size():
						continue
					var first := idx.size() - p.beats.size()
					var bt := 0.0
					var ok := true
					for bi in p.beats.size():
						var b := p.beats[bi] * beat_duration
						bt += b
						if absf(key_timings[idx[first + bi]].t - measure_start - bt) > TOL * b:
							ok = false
							break
					if ok:
						out.append("match %s" % p.pattern_name)
						for k in range(first, idx.size()):
							key_timings[idx[k]].consumed = true
						break
	return out


func test_matches_original_frame_sampled_algorithm() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var originals := RhythmPattern.all()
	var mismatches := 0
	var trials := 150
	for trial in trials:
		var bpm := rng.randf_range(70.0, 160.0)
		var beat: float = 60.0 / bpm
		var presses := []
		var t := rng.randf_range(0.0, 1.0)
		for i in 4:
			presses.append([A, t + i * beat * rng.randf_range(0.96, 1.04)])
		t = presses[-1][1] + beat
		for rep in 3:
			var p: RhythmPattern = originals[rng.randi() % originals.size()]
			var jitter := rng.randf_range(0.0, 0.3) # up to 30% of each note's 20% tolerance... and beyond
			for k in p.size():
				var dt := p.onset(k) * beat + rng.randf_range(-1.0, 1.0) * jitter * 0.2 * p.beats[k] * beat * 1.6
				presses.append([rng.randi() % 4, t + dt])
			t += p.length() * beat
		presses.sort_custom(func(a, b): return a[1] < b[1])
		var ref := original_reference(presses, 4000.0, originals)
		var e := make_engine(originals)
		for p in presses:
			e.press(p[0], p[1])
		e.advance(presses[-1][1] + 5.0)
		var mine: Array[String] = []
		for l in _log:
			var parts := l.split(" @")[0].split(" ")
			if parts[0] == "lock":
				mine.append("lock %s" % parts[1])
			elif parts[0] == "match":
				mine.append("match %s" % parts[1])
			elif parts[0] == "lost":
				mine.append("lost")
		if mine != ref:
			mismatches += 1
			if mismatches <= 3:
				print("  original: ", ref, "\n  engine:   ", _log, "\n  presses: ", presses)
	check(mismatches == 0, "engine agrees with the original algorithm on %d random takes (%d mismatches)" % [trials, mismatches])


# ------------------------------------------------------------------------------ spellbook

func test_spellbook() -> void:
	var book: SpellBook = load("res://assets/spells/spellbook.tres")
	check(book != null and book.spells.size() == 3, "spellbook loads with 3 spells")
	var basic1: RhythmPattern = RhythmPattern.all()[0]
	var push: SpellDefinition = book.spells[0]
	check(push.button_string() == "A B X Y A", "push is ABXYA (%s)" % push.button_string())
	check(push.beats == basic1.beats, "push uses the original basic1 rhythm")
	for s in book.spells:
		var p := s.to_pattern()
		check(is_equal_approx(p.length(), 4.0), "%s fills one 4-beat measure" % s.id)
		check(p.syllables.size() == p.beats.size(), "%s: one button per note" % s.id)
	# Every spell is castable through the engine at 100 bpm.
	for i in book.spells.size():
		var e := make_engine(book.patterns())
		var m := count_in(e, 0.0, 0.6)
		play(e, e.patterns[i], m, 0.6)
		check(has("match %s" % book.spells[i].id), "%s recognized: %s" % [book.spells[i].id, _log])
