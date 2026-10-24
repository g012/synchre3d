class_name BeatBar
extends Control
## The shared beat, top centre: the tempo and four squares, one per beat of the bar, the
## current one lighting up yellow on the beat (the bar's first beat a bit bigger).
## Hidden while no tempo is set.

const SQUARE := 10
const DOWNBEAT := 12
const GAP := 6
const LIT := Color("f6d65a")

var font: Font


func setup(pixel_font: Font) -> void:
	font = pixel_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var text_w := ceilf(font.get_string_size("120 BPM", HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x)
	custom_minimum_size = Vector2(text_w + 8 + DOWNBEAT + 3 * (SQUARE + GAP), DOWNBEAT + 4)
	size = custom_minimum_size


func _process(_delta: float) -> void:
	var clock := BeatClock.instance
	visible = clock != null and clock.running
	if visible:
		queue_redraw()


func _draw() -> void:
	var clock := BeatClock.instance
	if not clock or not clock.running:
		return
	var b := clock.beats_now()
	var beat := floori(b)
	var phase := b - beat
	var text := "%d BPM" % roundi(clock.current_bpm())
	draw_string(font, Vector2(0, DOWNBEAT), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)
	var x := ceilf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x) + 8.0
	for k in 4:
		var s := DOWNBEAT if k == 0 else SQUARE
		var r := Rect2(x, (DOWNBEAT - s) * 0.5 + 2, s, s)
		var lit := posmod(beat, 4) == k
		var c := LIT if lit and phase < 0.35 else Color(1, 1, 1, 0.55 if lit else 0.22)
		draw_rect(r.grow(1), Color(0.17, 0.13, 0.21, 0.8))
		draw_rect(r, c)
		x += s + GAP
