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
	test_blank_after_twelve_beats()
	test_opening_sets_tempo()
	test_opening_each_spell_any_tempo()
	test_opening_rejects_wrong_rhythm_or_buttons()
	test_opening_then_tempo_kept()
	test_fixed_tempo_never_blanks()
	test_spell_starts_on_any_beat()
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
	test_shared_openings_progress()
	test_shared_opening_timeout_waits_for_slowest()
	test_tempo_slide_followed()
	test_tempo_slide_almost_finished_spell()
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


func test_blank_after_twelve_beats() -> void:
	var e := make_engine()
	count_in(e, 0.0, 0.5)
	e.advance(1.5 + 6.0 - 0.001)
	check(e.bpm == 120.0, "tempo kept just before 12 beats of silence")
	e.advance(1.5 + 6.0 + 0.001)
	check(e.bpm == 0.0 and has("lost @7.5000"), "tempo lost after 12 beats of silence: %s" % [_log])
	# The original's 6 beats are still available.
	e = make_engine()
	e.blank_beats = RhythmEngine.BLANK_DURATION
	count_in(e, 0.0, 0.5)
	e.advance(1.5 + 3.0 + 0.001)
	check(e.bpm == 0.0 and has("lost @4.5000"), "blank_beats = 6 reproduces the original: %s" % [_log])


# ------------------------------------------------------------------------------ shared fixed tempo

func test_fixed_tempo_never_blanks() -> void:
	var e := make_engine()
	e.set_fixed_tempo(120.0, 0.0)
	e.press(A, 0.25)
	e.advance(300.0)
	check(e.bpm == 120.0 and not has("lost"), "a fixed tempo survives 5 minutes of silence: %s" % [_log])
	play(e, e.patterns[0], 301.3, 0.5)
	check(has("match push"), "and still casts afterwards: %s" % [_log])
	# No count-in or opening can change it.
	count_in(e, 320.0, 0.8)
	e.advance(330.0)
	check(e.bpm == 120.0, "taps at another tempo do not change a fixed tempo")


func test_spell_starts_on_any_beat() -> void:
	# The tempo grid starts at 0 (beat 1 of bar 1). Each spell is started on every beat of
	# the bar, on off-beats, and on an arbitrary phase: all cast.
	var beat := 0.5
	var bad := []
	for pi in 3:
		for start in [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 0.5, 2.5, 1.37]:
			var e := make_engine()
			e.set_fixed_tempo(120.0, 0.0)
			var p: RhythmPattern = e.patterns[pi]
			# `play` takes the measure start; the first note sits onset(0) beats after it.
			var m: float = 10.0 + (start - p.onset(0)) * beat
			play(e, p, m, beat)
			if not has("match %s" % p.pattern_name):
				bad.append("%s from beat %s" % [p.pattern_name, start])
	check(bad.is_empty(), "every spell casts starting on any beat of the bar (or between): %s" % [bad])


# ------------------------------------------------------------------------------ tempo from a spell opening

func test_opening_sets_tempo() -> void:
	# ABXYA at 100 BPM with no count-in: the tempo locks on the 3rd note (X) and it casts.
	# (A note's beats are the time before it, so ABX sits at beats 1, 1.5, 2 of the measure.)
	var e := make_engine()
	var beat := 0.6
	var p: RhythmPattern = e.patterns[0]
	play(e, p, 1.0, beat)
	check(has("lock 100 @%.4f" % (1.0 + p.onset(2) * beat)), "push opening locks 100 bpm on its 3rd note: %s" % [_log])
	check(has("match push"), "and the incantation completes: %s" % [_log])
	check(is_equal_approx(fposmod(e.grid_origin - 1.0, beat), 0.0), "beat grid aligned with the notes (%s)" % e.grid_origin)


func test_opening_each_spell_any_tempo() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var bad := []
	for bpm: float in [85.0, 100.0, 120.0, 140.0, 150.0]:
		for pi in 3:
			var e := make_engine()
			var p: RhythmPattern = e.patterns[pi]
			var beat: float = 60.0 / bpm
			# Human-ish timing: each note off by up to 20% of its own tolerance.
			var offsets := {}
			for k in p.size():
				offsets[k] = rng.randf_range(-0.2, 0.2) * 0.2 * p.beats[k] * beat
			offsets[0] = 0.0
			play(e, p, 3.0, beat, offsets)
			# The inferred tempo is as precise as the player (a few % with sloppy timing).
			if not has("match %s" % p.pattern_name) or absf(e.bpm - bpm) > bpm * 0.06:
				bad.append("%s@%d -> %s" % [p.pattern_name, bpm, _log])
	check(bad.is_empty(), "every spell casts from a cold start at 85-150 bpm: %s" % [bad])


func test_opening_rejects_wrong_rhythm_or_buttons() -> void:
	var e := make_engine()
	# A B X with intervals 0.25 s then 0.75 s: push wants two equal half beats.
	var times := [0.0, 0.25, 1.0]
	for k in 3:
		e.press([A, B, X][k], times[k])
	check(e.bpm == 0.0, "push buttons with the wrong rhythm do not set a tempo")
	e = make_engine()
	var beat := 0.5
	for k in 3:
		e.press([A, X, B][k], 5.0 + e.patterns[0].onset(k) * beat)
	check(e.bpm == 0.0, "push rhythm with the wrong buttons does not set a tempo")
	e = make_engine()
	e.tempo_from_openings = false
	play(e, e.patterns[0], 1.0, 0.6)
	check(e.bpm == 0.0 and not has("match"), "openings can be disabled (count-in only, like the original)")


func test_opening_then_tempo_kept() -> void:
	# After a cold cast the tempo stays for the next spell, played on the grid.
	var e := make_engine()
	var beat := 0.5
	play(e, e.patterns[1], 0.0, beat)
	var m := 0.0 + e.patterns[1].length() * beat
	play(e, e.patterns[0], m + 2.0 * beat, beat)
	var n := 0
	for l in _log:
		if l.begins_with("match"):
			n += 1
	check(n == 2 and _log.count("lock 120 @%.4f" % (e.patterns[1].onset(2) * beat)) == 1,
		"open pit cold, then push on the kept tempo: %s" % [_log])


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
		e.advance(m + 12.0) # same end time for every rate (past the 12-beat blank)
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
		e.blank_beats = RhythmEngine.BLANK_DURATION
		e.tempo_from_openings = false
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
	check(book != null and book.active().size() >= 3, "spellbook: at least 3 spells in play (%d)" % book.active().size())
	check(book.spells.size() == 9, "spellbook keeps 9 spells including ideas (%d)" % book.spells.size())
	var basic1: RhythmPattern = RhythmPattern.all()[0]
	var push: SpellDefinition = book.spells[0]
	check(push.button_string() == "A B X Y A", "push is ABXYA (%s)" % push.button_string())
	check(push.beats == basic1.beats, "push uses the original basic1 rhythm")
	for s in book.spells:
		var p := s.to_pattern()
		check(is_equal_approx(p.length(), 4.0), "%s fills one 4-beat measure" % s.id)
		check(p.syllables.size() == p.beats.size(), "%s: one button per note" % s.id)
	# Every spell of the whole book (ideas enabled too) is castable at 100 bpm and is never
	# mistaken for another one.
	var all: Array[RhythmPattern] = []
	for s in book.spells:
		all.append(s.to_pattern())
	for i in all.size():
		var e := make_engine(all)
		var m := count_in(e, 0.0, 0.6)
		play(e, all[i], m, 0.6)
		var matches := _log.filter(func(l: String): return l.begins_with("match"))
		check(matches.size() == 1 and matches[0].begins_with("match %s @" % book.spells[i].id), "%s recognized alone: %s" % [book.spells[i].id, matches])

# ------------------------------------------------------------------------------ tempo slides

## A clock at 100 bpm (origin 0) sliding to 120 over 4 beats from beat 8, and an engine fed
## warped timestamps (as SpellCaster does).
func _sliding_setup() -> Array:
	var clock := BeatClock.new()
	clock.metronome = false
	clock.start(100.0, 0.0)
	var e := make_engine(load("res://assets/spells/spellbook.tres").patterns())
	e.set_fixed_tempo(100.0, 0.0)
	_log.clear()
	return [clock, e]


## Time at which `clock` reaches `beat` (bisection; the map is monotonic).
func _time_at(clock: BeatClock, beat: float) -> float:
	var lo := 0.0
	var hi := 100.0
	for k in 60:
		var mid := (lo + hi) * 0.5
		if clock.beats_at(mid) < beat:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


func test_tempo_slide_followed() -> void:
	var r := _sliding_setup()
	var clock: BeatClock = r[0]
	var e: RhythmEngine = r[1]
	clock.slide_to(120.0, 4.0, 4.8)
	check(is_equal_approx(clock.bpm_at(4.7), 100.0) and is_equal_approx(clock.bpm_at(100.0), 120.0), "slide: 100 before, 120 after")
	check(clock.bpm_at(5.8) > 100.0 and clock.bpm_at(5.8) < 120.0, "slide is gradual (%s)" % clock.bpm_at(5.8))
	check(is_equal_approx(clock.warp(3.0), 3.0), "warp is identity before any slide")
	# A push played on the sliding beat (starting mid-slide) is recognized.
	var push: RhythmPattern = e.patterns[0]
	for k in push.size():
		var t := _time_at(clock, 9.0 + push.onset(k) - push.onset(0))
		e.press(push.syllables[k], clock.warp(t))
	check(has("match push"), "push following the slide is cast: %s" % [_log])
	# Long after the slide, 120 bpm beats map to whole match-tempo beats.
	var t0 := _time_at(clock, 40.0)
	check(is_equal_approx(clock.warp(t0 + 0.5) - clock.warp(t0), 0.6), "after the slide a 120 bpm beat counts as one beat")
	clock.free()


func test_tempo_slide_almost_finished_spell() -> void:
	var r := _sliding_setup()
	var clock: BeatClock = r[0]
	var e: RhythmEngine = r[1]
	# Push started at beat 8 at 100 bpm; the opponent's slide lands just after its 4th note.
	var push: RhythmPattern = e.patterns[0]
	for k in push.size():
		var t := 4.8 + (push.onset(k) - push.onset(0)) * 0.6
		if k == push.size() - 1:
			clock.slide_to(120.0, 4.0, 4.8 + 2.05 * 0.6)
		e.press(push.syllables[k], clock.warp(t))
	check(has("match push"), "a nearly finished push still lands when the tempo starts sliding: %s" % [_log])
	clock.free()


# ------------------------------------------------------------------------------ shared openings

func _whole_book() -> Array[RhythmPattern]:
	var out: Array[RhythmPattern] = []
	for sp in (load("res://assets/spells/spellbook.tres") as SpellBook).spells:
		out.append(sp.to_pattern())
	return out


func _names(ps: Array[RhythmPattern]) -> Array[String]:
	var out: Array[String] = []
	for p in ps:
		out.append(p.pattern_name)
	return out


## Swap (X A X A) shares its X with Open Pit and Knockout: progress follows all three, then
## narrows to Swap, never fizzling on the way.
func test_shared_openings_progress() -> void:
	var e := make_engine(_whole_book())
	e.set_fixed_tempo(100.0, 0.0)
	var swap: RhythmPattern
	for p in e.patterns:
		if p.pattern_name == "swap_ball":
			swap = p
	var seen: Array = []
	var m := 10.0
	for k in swap.size():
		e.press(swap.syllables[k], m + (swap.onset(k) - swap.onset(0)) * 0.6)
		seen.append(_names(e.candidate_patterns()))
	check(seen[0] == ["create_hole", "swap_ball", "knockout"], "X opens pit, swap and knockout: %s" % [seen[0]])
	check(seen[1] == ["swap_ball"], "X A narrows to swap: %s" % [seen[1]])
	check(has("match swap_ball") and not has("fail"), "swap cast without a fizzle: %s" % [_log])
	# A chant no spell can continue still fizzles, once.
	_log.clear()
	e.press(X, 20.0)
	e.press(X, 20.3)
	var fails := _log.filter(func(l: String): return l.begins_with("fail"))
	check(fails.size() == 1, "X X (no such spell) fizzles once: %s" % [_log])


## After X, Open Pit expects its next note half a beat later, Knockout a full beat later:
## waiting past Open Pit's deadline must only drop Open Pit, and Knockout still casts.
func test_shared_opening_timeout_waits_for_slowest() -> void:
	var e := make_engine(_whole_book())
	e.set_fixed_tempo(100.0, 0.0)
	var ko: RhythmPattern
	for p in e.patterns:
		if p.pattern_name == "knockout":
			ko = p
	var m := 10.0
	e.press(X, m)
	e.advance(m + 0.97 * 0.6)
	check(not has("fail") and not "create_hole" in _names(e.candidate_patterns()), "pit dropped silently once late: %s %s" % [_log, _names(e.candidate_patterns())])
	for k in range(1, ko.size()):
		e.press(ko.syllables[k], m + (ko.onset(k) - ko.onset(0)) * 0.6)
	check(has("match knockout") and not has("fail"), "knockout cast without a fizzle: %s" % [_log])
