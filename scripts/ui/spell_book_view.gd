class_name SpellBookView
extends Control
## The spell book page of the pause menu: every spell in play, grouped by family, with what
## it does and its three chants drawn to rhythm on the low-res pixel grid:
##
##   PUSH                                   (family color)
##   BEAM AHEAD. LV2+: GROUND PARTS ON BOTH SIDES
##   LV1  A A   Y
##   LV2  A A   B X   Y
##   LV3  A A   B X   Y        <- chords stacked upward (X+Y)
##        '   '   '   '        <- one tick per beat
##
## Two columns; pages when the book holds more than fits (D-pad left / right).

const GLYPH := 9
const BEAT_PX := 26.0
const COL_W := 300
const GAP := 8
const LABEL_W := 22

var book: SpellBook
var font: Font
var page := 0
var _palette: Image
# Per page: list of [spell, column, y].
var _pages: Array = []


func setup(b: SpellBook, pixel_font: Font, palette: Image) -> void:
	book = b
	font = pixel_font
	_palette = palette
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func page_count() -> int:
	return maxi(_pages.size(), 1)


## Lays the active spells out in two columns, paging when a column is full.
func _paginate() -> void:
	_pages.clear()
	var top := 26.0
	var bottom := size.y - 22.0
	var current: Array = []
	var col := 0
	var y := top
	for s in book.active():
		var h := _block_height(s)
		if y + h > bottom:
			col += 1
			y = top
			if col > 1:
				_pages.append(current)
				current = []
				col = 0
		current.append([s, col, y])
		y += h + GAP
	if not current.is_empty():
		_pages.append(current)
	page = clampi(page, 0, page_count() - 1)


func _row_height(s: SpellDefinition, level: int) -> float:
	var tallest := 1
	for m in s.masks(level):
		tallest = maxi(tallest, SpellDefinition.mask_buttons(m).size())
	return GLYPH + 5 + (tallest - 1) * (GLYPH + 1)


func _block_height(s: SpellDefinition) -> float:
	var h := 20.0
	for level in [1, 2, 3]:
		h += _row_height(s, level)
	return h + 4.0


## Static page: redrawn when opened, resized or turned (it is shown while the game is paused).
func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	if not book or not font:
		return
	_paginate()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.13, 0.1, 0.16, 0.97))
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.15), false, 1.0)
	_text(Vector2(8, 13), "SPELL BOOK", _palette.get_pixel(28, 3), 16)
	_text(Vector2(140, 12), "LV1 START+END   LV2 +MIDDLE   LV3 SAME WITH A CHORD (PRESS TOGETHER)", Color(1, 1, 1, 0.55))
	if _pages.is_empty():
		return
	for entry in _pages[page]:
		var s: SpellDefinition = entry[0]
		var x: float = 8.0 + entry[1] * (COL_W + 16)
		_draw_spell(s, Vector2(x, entry[2]))
	var footer := "B / BACK / ESC: CLOSE"
	if page_count() > 1:
		footer = "PAGE %d/%d   D-PAD </>: PAGE   " % [page + 1, page_count()] + footer
	_text(Vector2(8, size.y - 7), footer, Color(1, 1, 1, 0.45))
	_text(Vector2(size.x - 190, size.y - 7), "EVERY NOTE: +/- 0.2 BEAT", Color(1, 1, 1, 0.45))


func _draw_spell(s: SpellDefinition, at: Vector2) -> void:
	var color := _palette.get_pixel(s.palette_index, 3)
	_text(at + Vector2(0, 8), s.display_name.to_upper(), color)
	_text(at + Vector2(90, 8), s.family.display_name.to_upper() + " FAMILY", Color(1, 1, 1, 0.35))
	_text(at + Vector2(0, 17), s.summary, Color(1, 1, 1, 0.8))
	var y := at.y + 20.0
	var lowest := book.min_level(s)
	for level in [1, 2, 3]:
		var h := _row_height(s, level)
		var base := y + h - GLYPH - 4
		var available: bool = level >= lowest and level <= s.max_level
		_text(Vector2(at.x, base + 8), "LV%d" % level, Color(1, 1, 1, 0.7 if available else 0.25))
		if available:
			_draw_chant(s, level, Vector2(at.x + LABEL_W + 4, base))
		else:
			_text(Vector2(at.x + LABEL_W + 4, base + 8), "-  (ONLY THE FAMILY'S FIRST SPELL)", Color(1, 1, 1, 0.25))
		y += h


## The chant spaced by its rhythm: one tick per beat, chords stacked upward (the note's own
## syllable at the bottom).
func _draw_chant(s: SpellDefinition, level: int, at: Vector2) -> void:
	var p := s.to_pattern(level)
	var span := p.onset(p.size() - 1) - p.onset(0)
	for b in int(span) + 1:
		draw_rect(Rect2(at.x + b * BEAT_PX + GLYPH * 0.5, at.y + GLYPH + 1, 1, 2), Color(1, 1, 1, 0.3))
	for k in p.size():
		var x := roundf(at.x + (p.onset(k) - p.onset(0)) * BEAT_PX)
		var own := p.syllables[k]
		_glyph(Vector2(x, at.y), own)
		var row := 0
		for b in SpellDefinition.mask_buttons(p.masks[k]):
			if b != own:
				row += 1
				_glyph(Vector2(x, at.y - row * (GLYPH + 1)), b)
		if row > 0:
			# One box around the chord's buttons: pressed together.
			var top := at.y - row * (GLYPH + 1)
			draw_rect(Rect2(x - 2, top - 2, GLYPH + 4, at.y + GLYPH - top + 4), Color(1, 1, 1, 0.9), false, 1.0)


func _glyph(pos: Vector2, b: int) -> void:
	draw_rect(Rect2(pos, Vector2(GLYPH, GLYPH)), RhythmPanel.button_color(_palette, b))
	draw_string(font, pos + Vector2(2, 8), SpellDefinition.BUTTONS[b], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)


func _text(pos: Vector2, s: String, c: Color, font_size := 8) -> void:
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, c)
