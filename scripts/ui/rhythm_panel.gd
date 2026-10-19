class_name RhythmPanel
extends Control
## Small rhythm/incantation readout for one caster, drawn on the low-res pixel grid.
##
##   [tempo + beat lights]          | PUSH       A . B X . Y . A   <- spell sheets: notes on a
##   [last syllables + timing ticks]| OPEN PIT   . X Y . . X Y        4-beat timeline, lit as
##   [result: PUSH! / FIZZLE: LATE] | MEND       B . Y . B Y A        they are played
##
## Timing tick under each syllable: centred = on time, shifted left = early, right = late
## (proportional to the error / tolerance), red cross = outside tolerance.

const TRAIL := 8
const GLYPH := 9
const SHEET_W := 72
const PERFECT_COLOR := Color("f6d65a")

var caster: SpellCaster
var title := "P1"
var font: Font

var _trail: Array[Dictionary] = []
var _result := ""
var _result_color := Color.WHITE
var _result_time := -10.0
var _progress_spell: SpellDefinition
var _progress_step := 0
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
		_progress_step = step)
	caster.fizzled.connect(_on_fizzled)
	caster.cast.connect(_on_cast)
	custom_minimum_size = Vector2(108 + 54 + SHEET_W + GLYPH + 4, 48)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE


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
	_result = "%s FIZZLED: %s" % [spell.display_name.to_upper(), reason.to_upper()]
	_result_color = Color("e66d47")
	_result_time = PlayerInput.now_seconds()


func _on_cast(spell: SpellDefinition) -> void:
	_result = "%s!" % spell.display_name.to_upper()
	_result_color = _palette.get_pixel(spell.palette_index, 3)
	_result_time = PlayerInput.now_seconds()
	_progress_spell = spell
	_progress_step = spell.syllables.size()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not caster or not font:
		return
	var now := PlayerInput.now_seconds()
	var e := caster.engine
	var ink := Color(0.17, 0.13, 0.21, 0.72)
	draw_rect(Rect2(Vector2.ZERO, size), ink)
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.12), false, 1.0)

	# --- tempo row
	_text(Vector2(4, 9), title, Color.WHITE)
	if e.bpm > 0.0:
		_text(Vector2(18, 9), "%d BPM" % int(e.bpm), Color.WHITE)
		var beat := floori((now - e.grid_origin) / e.beat_duration())
		var phase := e.beat_phase(now)
		for k in 4:
			var lit := posmod(beat, 4) == k
			var c := PERFECT_COLOR if lit and phase < 0.35 else Color(1, 1, 1, 0.25 if not lit else 0.55)
			draw_rect(Rect2(64 + k * 7, 4, 4 if k > 0 else 5, 4 if k > 0 else 5), c)
	else:
		var n := e.count_in_streak()
		_text(Vector2(18, 9), "TAP 4 BEATS", Color(1, 1, 1, 0.8))
		for k in 4:
			draw_rect(Rect2(84 + k * 5, 4, 3, 3), PERFECT_COLOR if k < n else Color(1, 1, 1, 0.2))

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
	elif _progress_spell and _progress_step > 0 and _progress_step < _progress_spell.syllables.size():
		_text(Vector2(4, 44), _progress_spell.incantation().to_upper().substr(0, 26), Color(1, 1, 1, 0.75))
	elif e.bpm > 0.0:
		_text(Vector2(4, 44), "CHANT ON THE BEAT", Color(1, 1, 1, 0.45))
	else:
		_text(Vector2(4, 44), "OR START A SPELL", Color(1, 1, 1, 0.45))

	# --- spell sheets: each spell's notes on a 4-beat timeline
	var sx := 108.0
	var spells := caster.book.spells
	for r in spells.size():
		var s: SpellDefinition = spells[r]
		var y := 3 + r * 15
		var active := _progress_spell == s and _progress_step > 0 and now - _result_time >= 0.0
		var name_c := _palette.get_pixel(s.palette_index, 3) if active else Color(1, 1, 1, 0.6)
		_text(Vector2(sx, y + 8), s.display_name.to_upper(), name_c)
		var tx := sx + 54.0
		# beat ticks
		for k in 5:
			draw_rect(Rect2(tx + k * SHEET_W / 4.0, y + 9, 1, 2), Color(1, 1, 1, 0.25))
		var pattern := s.to_pattern()
		var total := pattern.length()
		for k in s.syllables.size():
			var x := tx + pattern.onset(k) / total * SHEET_W - GLYPH * 0.5
			var done := active and k < _progress_step
			_glyph(Vector2(roundf(x), y), s.syllables[k], 1.0 if done else 0.35, done)


func _glyph(pos: Vector2, b: int, alpha: float, outline := false) -> void:
	var c := button_color(_palette, b)
	c.a = alpha
	draw_rect(Rect2(pos, Vector2(GLYPH, GLYPH)), c)
	if outline:
		draw_rect(Rect2(pos - Vector2.ONE, Vector2(GLYPH + 2, GLYPH + 2)), Color(1, 1, 1, 0.9), false, 1.0)
	draw_string(font, pos + Vector2(2, 8), SpellDefinition.BUTTONS[b], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, alpha))


func _text(pos: Vector2, s: String, c: Color) -> void:
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, c)
