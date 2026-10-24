class_name DialogueBox
extends Control
## Old-school JRPG text box at the bottom of the screen: the speaker's name, the line typed
## out letter by letter, and a blinking ">" when it is complete. A (or Enter) shows the whole
## line at once, then goes to the next; after the last line the box closes and `done` runs.

const CHARS_PER_SECOND := 45.0
const W := 440
const H := 58

var _font: Font
var _name: Label
var _text: Label
var _more: Label
var _lines: Array = []
var _index := 0
var _shown := 0.0
var _done: Callable


func setup(font: Font, name_color: Color) -> void:
	_font = font
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(W, H)
	size = custom_minimum_size
	var plate := ColorRect.new()
	plate.color = Color(0.13, 0.1, 0.16, 0.92)
	plate.size = size
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(plate)
	var border := ReferenceRect.new()
	border.border_color = Color(1, 1, 1, 0.5)
	border.editor_only = false
	border.size = size
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(border)
	_name = _label(name_color)
	_name.position = Vector2(8, 3)
	_text = _label(Color.WHITE)
	_text.position = Vector2(8, 16)
	_text.size = Vector2(W - 24, H - 20)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_more = _label(Color("f6d65a"))
	_more.text = ">"
	_more.position = Vector2(W - 14, H - 14)
	visible = false


func _label(color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", 8)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func open(speaker: String, lines: Array, done: Callable) -> void:
	_name.text = speaker
	_lines = lines
	_index = 0
	_done = done
	visible = true
	_show_line()


func close() -> void:
	visible = false
	_lines = []


func is_open() -> bool:
	return visible


## A pressed: finish typing the line, or move on.
func advance() -> void:
	if not visible:
		return
	if _text.visible_characters >= 0 and _text.visible_characters < _text.text.length():
		_shown = _text.text.length()
		_text.visible_characters = -1
		return
	_index += 1
	if _index >= _lines.size():
		visible = false
		if _done.is_valid():
			_done.call()
		return
	_show_line()


func _show_line() -> void:
	_text.text = String(_lines[_index]).to_upper()
	_shown = 0.0
	_text.visible_characters = 0


func _process(delta: float) -> void:
	if not visible:
		return
	if _text.visible_characters >= 0 and _text.visible_characters < _text.text.length():
		_shown += delta * CHARS_PER_SECOND
		_text.visible_characters = mini(int(_shown), _text.text.length())
	var complete := _text.visible_characters < 0 or _text.visible_characters >= _text.text.length()
	_more.visible = complete and fmod(Time.get_ticks_msec() * 0.001, 0.8) < 0.5
