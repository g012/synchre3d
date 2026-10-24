class_name RhythmPanel
extends Control
## Small rhythm/incantation readout for one caster, drawn on the low-res pixel grid.
##
##   [tempo + beat lights]          | PUSH       A A B X . Y   <- spell sheets: each spell's
##   [last syllables + timing ticks]| SHOCKWAVE  A A . X . X . Y  level-2 chant on a beat
##   [result: PUSH LV2 87%]         | ---------                   timeline, grouped by family
##                                  | OPEN PIT   X Y Y Y . X      (shared start and end dimmed),
##                                                                  lit as they are played
##
## Timing tick under each syllable: centred = on time, shifted left = early, right = late
## (proportional to the error / tolerance), red cross = outside tolerance.

const TRAIL := 8
const GLYPH := 9
const SHEET_W := 72
## Sheet scale: pixels per beat.
const BEAT_PX := 18.0
const ROW := 11
const NAME_W := 64
const PERFECT_COLOR := Color("f6d65a")

var caster: SpellCaster
## Spell sheets on the right (off for the CPU: its ring shows what it chants).
var show_sheets := true
var title := "P1"
var font: Font

var _trail: Array[Dictionary] = []
var _result := ""
var _result_color := Color.WHITE
var _result_time := -10.0
var _progress_spell: SpellDefinition
var _progress_step := 0
var _candidates: Array[SpellDefinition] = []
var _palette: Image


func setup(c: SpellCaster, player_title: String, pixel_font: Font, palette: Image) -> void:
	caster = c
	title = player_title
	font = pixel_font
	_palette = palette
	caster.pressed.connect(_on_pressed)
	caster.judged.connect(_on_judged)
	caster.progress.connect(func(s: SpellDefinition, step: int, _n: int):
		_progress_spell = s
		_progress_step = step
		_candidates = caster.candidates())
	caster.fizzled.connect(_on_fizzled)
	caster.cast.connect(_on_cast)
	_resize()
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_sheets(on: bool) -> void:
	show_sheets = on
	_resize()


func _resize() -> void:
	var w := 108 + NAME_W + SHEET_W + GLYPH + 4 if show_sheets else 108
	custom_minimum_size = Vector2(w, maxi(48, 5 + ROW * caster.book.active().size()) if show_sheets else 48)
	size = custom_minimum_size


static func button_color(palette: Image, b: int) -> Color:
	# Xbox face colors from the game palette: A green, B red, X blue, Y yellow.
	var idx: int = [22, 4, 31, 6][b]
	return palette.get_pixel(idx, 2)


func _on_pressed(button: int, time: float) -> void:
	_trail.append({"b": button, "t": time, "rating": -1, "offset": 0.0, "tol": 0.0})
	if _trail.size() > TRAIL:
		_trail.remove_at(0)


func _on_judged(j: Dictionary) -> void:
	for i in range(_trail.size() - 1, -1, -1):
		if is_equal_approx(_trail[i].t, j.t):
			_trail[i].rating = j.rating
			_trail[i].offset = j.offset
			_trail[i].tol = j.tolerance
			return


func _on_fizzled(spell: SpellDefinition, _step: int, reason: String) -> void:
	# Just the reason (in red): it has to fit the left column.
	_result = reason.to_upper()
	_result_color = Color("e66d47")
	_result_time = PlayerInput.now_seconds()


func _on_cast(spell: SpellDefinition, level: int, precision: float) -> void:
	_result = "%s LV%d %d%%" % [spell.display_name.to_upper(), level, roundi(precision * 100.0)]
	_result_color = _palette.get_pixel(spell.palette_index, 3)
	_result_time = PlayerInput.now_seconds()
	_progress_spell = spell
	_progress_step = 99
	_candidates.clear()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not caster or not font:
		return
	var now := PlayerInput.now_seconds()
	var e := caster.engine
	var clock := BeatClock.instance
	var ink := Color(0.17, 0.13, 0.21, 0.72)
	draw_rect(Rect2(Vector2.ZERO, size), ink)
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.12), false, 1.0)

	# --- tempo row
	_text(Vector2(4, 9), title, Color.WHITE)
	if clock and clock.running:
		_text(Vector2(18, 9), "%d BPM" % roundi(clock.current_bpm()), Color.WHITE)
		var b := clock.beats_now()
		var beat := floori(b)
		var phase := b - beat
		for k in 4:
			var lit := posmod(beat, 4) == k
			var c := PERFECT_COLOR if lit and phase < 0.35 else Color(1, 1, 1, 0.25 if not lit else 0.55)
			draw_rect(Rect2(64 + k * 7, 4, 4 if k > 0 else 5, 4 if k > 0 else 5), c)
	else:
		var n := e.count_in_streak()
		_text(Vector2(18, 9), "TAP 4 BEATS", Color(1, 1, 1, 0.8))
		for k in 4:
			draw_rect(Rect2(84 + k * 5, 4, 3, 3), PERFECT_COLOR if k < n else Color(1, 1, 1, 0.2))

	# Aim mode: auto or manual, and strafing while LT is held.
	var ch := caster.character
	if ch.strafe:
		_text(Vector2(4, 35), "STRAFE + AUTO-AIM" if ch.auto_aim else "STRAFE / AIM", Color("86a2ea"))
	elif ch.auto_aim:
		_text(Vector2(4, 35), "AUTO-AIM", PERFECT_COLOR)
	else:
		_text(Vector2(4, 35), "MANUAL AIM", Color(1, 1, 1, 0.45))

	# --- syllable trail with timing ticks
	for i in _trail.size():
		var entry: Dictionary = _trail[i]
		var x := 4 + i * (GLYPH + 3)
		var age := now - float(entry.t)
		var alpha := clampf(1.6 - age * 0.4, 0.25, 1.0)
		_glyph(Vector2(x, 14), entry.b, alpha)
		var tick_y := 14 + GLYPH + 2
		match int(entry.rating):
			RhythmEngine.Rating.PERFECT:
				draw_rect(Rect2(x + 3, tick_y, 3, 2), PERFECT_COLOR * Color(1, 1, 1, alpha))
			RhythmEngine.Rating.EARLY, RhythmEngine.Rating.LATE:
				var shift := clampf(entry.offset / maxf(entry.tol, 0.001), -1.0, 1.0) * 4.0
				var c := Color("86a2ea") if entry.offset < 0.0 else Color("e8873a")
				draw_rect(Rect2(x + 3 + roundf(shift), tick_y, 3, 2), c * Color(1, 1, 1, alpha))
			RhythmEngine.Rating.MISS:
				var c := Color("e66d47") * Color(1, 1, 1, alpha)
				draw_line(Vector2(x + 2, tick_y - 1), Vector2(x + 6, tick_y + 2), c)
				draw_line(Vector2(x + 6, tick_y - 1), Vector2(x + 2, tick_y + 2), c)

	# --- result / status line
	if now - _result_time < 1.6:
		_text(Vector2(4, 44), _result, _result_color)
	elif e.progress_pattern:
		var lead := e.progress_pattern.payload as SpellDefinition
		_text(Vector2(4, 44), lead.incantation(e.progress_pattern.level).to_upper().substr(0, 17), Color(1, 1, 1, 0.75))
	elif e.bpm > 0.0:
		_text(Vector2(4, 44), "CHANT ON THE BEAT", Color(1, 1, 1, 0.45))
	else:
		_text(Vector2(4, 44), "OR START A SPELL", Color(1, 1, 1, 0.45))

	# --- spell sheets: each spell's level-2 chant on a beat timeline, grouped by family
	if not show_sheets:
		return
	var sx := 108.0
	var spells := caster.book.active()
	var family: SpellFamily = null
	for r in spells.size():
		var s: SpellDefinition = spells[r]
		var y := 2 + r * ROW
		if family and s.family != family:
			draw_rect(Rect2(sx, y - 1, NAME_W + SHEET_W + 4, 1), Color(1, 1, 1, 0.18))
		family = s.family
		# Every spell the chant could still become is lit (they share their opening).
		var active := _progress_step > 0 and (_progress_spell == s or s in _candidates)
		var name_c := _palette.get_pixel(s.palette_index, 3) if active else Color(1, 1, 1, 0.6)
		_text(Vector2(sx, y + 8), s.display_name.to_upper(), name_c)
		var tx := sx + NAME_W
		var pattern := s.to_pattern(2)
		var span := pattern.onset(pattern.size() - 1) - pattern.onset(0)
		for k in int(span) + 1:
			draw_rect(Rect2(tx + k * BEAT_PX + GLYPH * 0.5, y + 9, 1, 2), Color(1, 1, 1, 0.25))
		var start := s.family.start.size()
		var end := pattern.size() - s.family.end.size()
		for k in pattern.size():
			var x := tx + (pattern.onset(k) - pattern.onset(0)) * BEAT_PX
			var done := active and k < _progress_step and (k < end or _progress_step == 99)
			# The family's shared start and end are dimmer than the spell's own middle.
			var own := k >= start and k < end
			_glyph(Vector2(roundf(x), y), pattern.syllables[k], 1.0 if done else (0.5 if own else 0.25), done)


func _glyph(pos: Vector2, b: int, alpha: float, outline := false) -> void:
	var c := button_color(_palette, b)
	c.a = alpha
	draw_rect(Rect2(pos, Vector2(GLYPH, GLYPH)), c)
	if outline:
		draw_rect(Rect2(pos - Vector2.ONE, Vector2(GLYPH + 2, GLYPH + 2)), Color(1, 1, 1, 0.9), false, 1.0)
	draw_string(font, pos + Vector2(2, 8), SpellDefinition.BUTTONS[b], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, alpha))


func _text(pos: Vector2, s: String, c: Color) -> void:
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, c)
