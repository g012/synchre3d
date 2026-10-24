class_name QuestMarker
extends Control
## Story mode quest line (top left, under the mode name) with a compass arrow pointing, on
## screen, toward the quest's target and its distance.

const LIT := Color("f6d65a")

var font: Font
var text := ""
## Direction to the target on screen (x right, y down), and its distance; dist < 0 = none.
var direction := Vector2.ZERO
var distance := -1.0


func setup(pixel_font: Font) -> void:
	font = pixel_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(300, 22)
	size = custom_minimum_size


func set_quest(t: String, dir: Vector2, dist: float) -> void:
	text = t
	direction = dir
	distance = dist
	visible = t != ""
	queue_redraw()


func _draw() -> void:
	if text == "":
		return
	var c := Vector2(9, 11)
	if distance >= 0.0:
		draw_circle(c, 9.0, Color(0.13, 0.1, 0.16, 0.85))
		draw_arc(c, 9.0, 0.0, TAU, 20, Color(1, 1, 1, 0.4), 1.0)
		var d := direction.normalized() if direction.length() > 0.001 else Vector2.UP
		var side := Vector2(-d.y, d.x)
		draw_colored_polygon(PackedVector2Array([c + d * 7.0, c - d * 3.0 + side * 4.0, c - d * 1.0, c - d * 3.0 - side * 4.0]), LIT)
	var x := 22.0 if distance >= 0.0 else 0.0
	draw_string(font, Vector2(x, 9), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)
	if distance >= 0.0:
		draw_string(font, Vector2(x, 19), "%d M" % roundi(distance), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, 0.6))
