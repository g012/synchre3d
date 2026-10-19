class_name Hud
extends CanvasLayer
## Pixel HUD drawn inside the low-res game viewport (same pixel grid as the world).
## Uses the generated 5x7 bitmap font at integer scales only.

var _font: FontFile = load("res://assets/fonts/pixel_font.fnt")
const PALETTE := preload("res://assets/palette/palette_ramp.png")

var _root: Control
var _name_a: Label
var _name_b: Label
var _score: Label
var _message: Label
var _sub: Label
var _hint: Label
var _mode: Label
var _message_time := 0.0
var _message_base_y := 0.0
var _palette: Image
var _panels: Array[RhythmPanel] = []


func _ready() -> void:
	_font.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_INTEGER_ONLY
	_palette = PALETTE.get_image()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The viewport has a hidden 1 px border (sub-pixel camera offset margin).
	_root.offset_left = 1
	_root.offset_top = 1
	_root.offset_right = -1
	_root.offset_bottom = -1
	add_child(_root)

	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 10)
	top.position.y = 6
	_root.add_child(top)
	_name_a = _label(16)
	_score = _label(16)
	_name_b = _label(16)
	for l in [_name_a, _score, _name_b]:
		top.add_child(l)
	top.resized.connect(func(): top.position.x = (_root.size.x - top.size.x) * 0.5)

	_message = _label(24)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.set_anchors_preset(Control.PRESET_CENTER)
	_root.add_child(_message)
	_sub = _label(8)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_sub)

	_hint = _label(8)
	_hint.modulate = Color(1, 1, 1, 0.9)
	_root.add_child(_hint)
	_mode = _label(8)
	_root.add_child(_mode)
	_root.resized.connect(_layout)
	_layout()


func _label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func palette_color(index: int, band := 2) -> Color:
	return _palette.get_pixel(index, band)


func _layout() -> void:
	var s := _root.size
	_message.size = Vector2(s.x, 30)
	_message_base_y = floorf(s.y * 0.16)
	_message.position = Vector2(0, _message_base_y)
	_sub.size = Vector2(s.x, 10)
	_sub.position = Vector2(0, _message_base_y + 32)
	_hint.position = Vector2(6, s.y - 14)
	_mode.position = Vector2(6, 6)
	for i in _panels.size():
		var p := _panels[i]
		var x := 6.0 if i == 0 else s.x - p.size.x - 6.0
		p.position = Vector2(x, s.y - 16 - p.size.y)


func set_names(a: String, color_a: int, b: String, color_b: int) -> void:
	_name_a.text = a.to_upper()
	_name_a.add_theme_color_override("font_color", palette_color(color_a, 3))
	_name_b.text = b.to_upper()
	_name_b.add_theme_color_override("font_color", palette_color(color_b, 3))


func set_score(a: int, b: int) -> void:
	_score.text = "%d - %d" % [a, b]


func set_mode(two_player: bool) -> void:
	_mode.text = "2P LOCAL" if two_player else "1P VS CPU"
	if two_player:
		_hint.text = "PADS 1+2 / P1 WASD IJKL SPACE E / P2 ARROWS NUM 2468 0 .   BACK/TAB 1P"
	else:
		_hint.text = "STICK/WASD MOVE  ABXY (KLJI) CHANT  RT/SPACE JUMP  RB/E SHOVE  BACK/TAB 2P"


## One rhythm readout per human caster: P1 bottom-left, P2 bottom-right.
func set_rhythm_panels(casters: Array[SpellCaster]) -> void:
	for p in _panels:
		p.queue_free()
	_panels.clear()
	for i in casters.size():
		if casters[i] == null:
			continue
		var panel := RhythmPanel.new()
		panel.setup(casters[i], "P%d" % (i + 1), _font, _palette)
		_root.add_child(panel)
		_panels.append(panel)
	_layout()


func show_message(text: String, color := Color.WHITE, sub := "") -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", color)
	_sub.text = sub
	_message_time = 0.0
	_message.visible = true
	_sub.visible = sub != ""


func hide_message() -> void:
	_message.visible = false
	_sub.visible = false


func _process(delta: float) -> void:
	# Drop-in bounce, moved in whole pixels so the text never resamples.
	_message_time += delta
	var t := _message_time
	var off := 0.0
	if t < 0.35:
		off = -14.0 * (1.0 - t / 0.35) + sin(t / 0.35 * PI) * 5.0
	_message.position.y = roundf(_message_base_y + off)
