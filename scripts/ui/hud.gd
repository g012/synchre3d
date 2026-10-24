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
var _top: HBoxContainer
var _status: Label
var _menu: VBoxContainer
var _menu_plate: ColorRect
## Spell sheets on the rhythm panels (toggled to practise without reading them).
var sheets_visible := true
var _menu_title: Label
var _menu_items: Array[Label] = []
var _tutorial_card: TutorialCard
var _spell_book: SpellBookView
var _beat_bar: BeatBar
var _menu_footer: Label


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
	_top = top

	# The shared beat, under the score / status / lesson card (see _layout).
	_beat_bar = BeatBar.new()
	_beat_bar.setup(_font)
	_root.add_child(_beat_bar)

	# Survival: health, time and kills instead of names and score.
	_status = _label(16)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.position.y = 6
	_status.visible = false
	_root.add_child(_status)

	# Title menu, on a dark plate so it reads over the grass.
	_menu_plate = ColorRect.new()
	_menu_plate.color = Color(0.17, 0.13, 0.21, 0.72)
	_menu_plate.visible = false
	_menu_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_menu_plate)
	_menu = VBoxContainer.new()
	_menu.alignment = BoxContainer.ALIGNMENT_CENTER
	_menu.add_theme_constant_override("separation", 6)
	_menu.visible = false
	_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_menu)
	_menu_title = _label(32)
	_menu_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu.add_child(_menu_title)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	_menu.add_child(gap)
	for i in 4:
		var l := _label(16)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_menu.add_child(l)
		_menu_items.append(l)
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 10)
	_menu.add_child(gap2)
	_menu_footer = _label(8)
	_menu_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu.add_child(_menu_footer)

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
	if _spell_book:
		_spell_book.position = Vector2(8, 8)
		_spell_book.size = s - Vector2(16, 16)
	var below := 30.0
	if _tutorial_card:
		_tutorial_card.position = Vector2(floorf((s.x - _tutorial_card.size.x) * 0.5), 6)
		below = 6.0 + _tutorial_card.size.y + 4.0
	if _beat_bar:
		_beat_bar.position = Vector2(floorf((s.x - _beat_bar.size.x) * 0.5), below)
	if _menu:
		_menu.size = Vector2(s.x, 0)
		var mh := _menu.get_combined_minimum_size().y
		_menu.position = Vector2(0, floorf((s.y - mh) * 0.45))
		_menu_plate.size = Vector2(360, mh + 20)
		_menu_plate.position = Vector2(floorf((s.x - 360) * 0.5), _menu.position.y - 10)
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


## `mode`: "menu", "cpu", "human" or "survival".
func set_mode(mode: String) -> void:
	_top.visible = mode == "cpu" or mode == "human"
	_status.visible = mode == "survival"
	_hint.visible = mode != "menu"
	_mode.visible = mode != "menu"
	match mode:
		"human":
			_mode.text = "DUEL VS HUMAN"
			_hint.text = "PADS 1+2 / P1 WASD IJKL SPC SHIFT E Q / P2 ARROWS NUM 2468 0 + . -  START PAUSE"
		"cpu":
			_mode.text = "DUEL VS CPU"
			_hint.text = "STICK/WASD MOVE  ABXY (KLJI) CHANT  RT/SPC JUMP  LB/SHIFT DASH  RB/E SHOVE  LT/Q STRAFE  START PAUSE"
		"tutorial":
			_mode.text = "TUTORIAL"
			_hint.text = "STICK/WASD MOVE  ABXY (KLJI) CHANT  RT/SPC JUMP  LB/SHIFT DASH  RB/E SHOVE  LT/Q STRAFE  START PAUSE"
		"survival":
			_mode.text = "SURVIVAL"
			_hint.text = "STICK/WASD MOVE  ABXY (KLJI) CHANT  RT/SPC JUMP  LB/SHIFT DASH  RB/E SHOVE  LT/Q STRAFE  START PAUSE"


## Shows the spell book page (pause menu), or hides it with null.
func show_spell_book(book: SpellBook) -> void:
	if not book:
		if _spell_book:
			_spell_book.queue_free()
			_spell_book = null
		return
	if not _spell_book:
		_spell_book = SpellBookView.new()
		_spell_book.setup(book, _font, _palette)
		_root.add_child(_spell_book)
	_layout()
	_spell_book.queue_redraw()


func spell_book_open() -> bool:
	return _spell_book != null


func turn_spell_book(step: int) -> void:
	if _spell_book:
		_spell_book.page = posmod(_spell_book.page + step, _spell_book.page_count())
		_spell_book.queue_redraw()


## Shows the tutorial's lesson card (null hides it).
func set_tutorial(t: Tutorial) -> void:
	if _tutorial_card:
		_tutorial_card.queue_free()
		_tutorial_card = null
	if t:
		_tutorial_card = TutorialCard.new()
		_tutorial_card.setup(t, _font, _palette)
		_root.add_child(_tutorial_card)
	_layout()


## Survival readout at the top (health, time, kills).
func set_status(text: String, color := Color.WHITE) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)
	_status.size = Vector2(_root.size.x, 18)
	_status.position.x = 0


func show_menu(title: String, items: Array[String], selected: int, footer: String) -> void:
	_menu.visible = true
	_menu_plate.visible = true
	_menu_title.text = title
	_menu_title.add_theme_color_override("font_color", palette_color(28, 3))
	for i in _menu_items.size():
		var l := _menu_items[i]
		l.visible = i < items.size()
		if i >= items.size():
			continue
		var on := i == selected
		l.text = ("> %s <" if on else "%s") % items[i]
		l.add_theme_color_override("font_color", palette_color(6, 3) if on else Color(1, 1, 1, 0.7))
	_menu_footer.text = footer
	_layout()


func hide_menu() -> void:
	_menu.visible = false
	_menu_plate.visible = false


## Shows or hides the spell sheets on the players' rhythm panels.
func toggle_sheets() -> void:
	sheets_visible = not sheets_visible
	for p in _panels:
		if p.title != "CPU":
			p.set_sheets(sheets_visible)
	_layout()


## One rhythm readout per human caster: P1 bottom-left, P2 bottom-right.
func set_rhythm_panels(casters: Array[SpellCaster], titles: Array[String] = []) -> void:
	for p in _panels:
		p.queue_free()
	_panels.clear()
	for i in casters.size():
		if casters[i] == null:
			continue
		var panel := RhythmPanel.new()
		panel.show_sheets = (titles.is_empty() or titles[i] != "CPU") and sheets_visible
		panel.setup(casters[i], titles[i] if i < titles.size() else "P%d" % (i + 1), _font, _palette)
		_root.add_child(panel)
		_panels.append(panel)
	_layout()


func set_panels_visible(on: bool) -> void:
	for p in _panels:
		p.visible = on


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
