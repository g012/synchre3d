class_name BeatBar
extends Control
## The shared beat, top centre: the tempo and a circle that pulses on every beat (it swells
## and flashes yellow on the beat, then settles). Spells start on any beat, so there is no
## bar to show. Hidden while no tempo is set.

const RADIUS := 7.0
const SWELL := 4.0
const LIT := Color("f6d65a")

var font: Font


func setup(pixel_font: Font) -> void:
	font = pixel_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var text_w := ceilf(font.get_string_size("120 BPM", HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x)
	custom_minimum_size = Vector2(text_w + 8 + (RADIUS + SWELL) * 2.0, (RADIUS + SWELL) * 2.0 + 2.0)
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
	var hit := pow(1.0 - (b - floorf(b)), 3.0)
	var text := "%d BPM" % roundi(clock.current_bpm())
	var cy := RADIUS + SWELL + 1.0
	draw_string(font, Vector2(0, cy + 3.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)
	var c := Vector2(ceilf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x) + 8.0 + RADIUS + SWELL, cy)
	# Whole pixels only, so the circle stays crisp on the pixel grid.
	var r := roundf(RADIUS + SWELL * hit)
	draw_circle(c, r + 1.0, Color(0.17, 0.13, 0.21, 0.8))
	draw_circle(c, r, Color(1, 1, 1, 0.3).lerp(LIT, clampf(hit * 1.6, 0.0, 1.0)))
	draw_circle(c, roundf(r * 0.45), Color(1, 1, 1, 0.25 + 0.6 * hit))
