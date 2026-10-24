class_name TutorialCard
extends Control
## The tutorial's lesson card, top centre, on the low-res pixel grid:
##
##   LESSON 2/13          PUSH  LEVEL 3            [x][x][ ]   <- good casts so far
##                     Y                                       <- chords stacked upward
##   A  A     B  X     Y                                       <- the chant, spaced by its rhythm
##   '  '  '  '  '  '  '                                          (one tick per beat)
##   YOUR TURN!  START ON ANY BEAT                             <- listen / feedback
##
## Syllables light up as the game sings them, then as the player chants them.

const GLYPH := 11
const BEAT_PX := 26.0
const W := 300
const H := 86
## Baseline row of the chant (chords stack upward from it).
const ROW := 42

var tutorial: Tutorial
var font: Font
var _palette: Image


func setup(t: Tutorial, pixel_font: Font, palette: Image) -> void:
	tutorial = t
	font = pixel_font
	_palette = palette
	custom_minimum_size = Vector2(W, H)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	visible = tutorial != null and tutorial.running
	if visible:
		queue_redraw()


func _draw() -> void:
	var l := tutorial.lesson()
	if l.is_empty():
		return
	var spell: SpellDefinition = l.spell
	var p: RhythmPattern = l.pattern
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.17, 0.13, 0.21, 0.78))
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.15), false, 1.0)
	_text(Vector2(6, 11), "LESSON %d/%d" % [tutorial.index + 1, tutorial.lessons.size()], Color(1, 1, 1, 0.6))
	_text(Vector2(84, 11), "%s  LEVEL %d" % [spell.display_name.to_upper(), l.level], _palette.get_pixel(spell.palette_index, 3))
	for k in tutorial.successes_needed:
		var r := Rect2(W - 8 - (tutorial.successes_needed - k) * 11, 4, 8, 8)
		if k < tutorial.successes:
			draw_rect(r, Color("f6d65a"))
		draw_rect(r, Color(1, 1, 1, 0.6), false, 1.0)

	# The chant, spaced by its rhythm, centred.
	var span := p.onset(p.size() - 1) - p.onset(0)
	var x0 := floorf((W - span * BEAT_PX - GLYPH) * 0.5)
	var lit := _lit_count(p)
	for b in int(span) + 1:
		draw_rect(Rect2(x0 + b * BEAT_PX + GLYPH * 0.5, ROW + GLYPH + 4, 1, 3), Color(1, 1, 1, 0.35))
	for k in p.size():
		var x := x0 + (p.onset(k) - p.onset(0)) * BEAT_PX
		var on := k < lit or k == tutorial.demo_lit
		# A chord: its buttons stacked, the note's own one at the bottom.
		var buttons := SpellDefinition.mask_buttons(p.masks[k])
		var row := 0
		for b in buttons:
			if b != p.syllables[k]:
				row += 1
				_glyph(Vector2(roundf(x), ROW - row * (GLYPH + 1)), b, on)
		_glyph(Vector2(roundf(x), ROW), p.syllables[k], on)

	_text(Vector2(6, 72), tutorial.message, tutorial.message_color)
	_text(Vector2(6, 81), "D-PAD </> (P/N): LESSON    UP (H): LISTEN AGAIN", Color(1, 1, 1, 0.4))


## Syllables done: the demo's progress while listening, else how far the player's chant
## follows this lesson's.
func _lit_count(p: RhythmPattern) -> int:
	if tutorial.step == Tutorial.Step.LISTEN:
		return tutorial.demo_lit + 1
	var chanted := tutorial.caster.chanted()
	if chanted.size() > p.size():
		return 0
	for k in chanted.size():
		if chanted[k] != p.masks[k]:
			return 0
	return chanted.size()


func _glyph(pos: Vector2, b: int, on: bool) -> void:
	var c := RhythmPanel.button_color(_palette, b)
	c.a = 1.0 if on else 0.35
	draw_rect(Rect2(pos, Vector2(GLYPH, GLYPH)), c)
	if on:
		draw_rect(Rect2(pos - Vector2.ONE, Vector2(GLYPH + 2, GLYPH + 2)), Color(1, 1, 1, 0.95), false, 1.0)
	draw_string(font, pos + Vector2(3, 9), SpellDefinition.BUTTONS[b], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, c.a))


func _text(pos: Vector2, s: String, c: Color) -> void:
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, c)
