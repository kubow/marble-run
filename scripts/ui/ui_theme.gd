class_name UiTheme
extends RefCounted
## Touch-friendly toy-like theme built in code (no external assets).

const INK := Color("2b2d42")
const ACCENT := Color("6c63ff")
const ACCENT_2 := Color("ff5a5f")
const PANEL := Color(1, 1, 1, 0.94)

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 30
	t.set_color("font_color", "Label", INK)
	t.set_color("font_color", "Button", Color.WHITE)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.5))
	t.set_stylebox("normal", "Button", _box(ACCENT))
	t.set_stylebox("hover", "Button", _box(ACCENT.lightened(0.12)))
	t.set_stylebox("pressed", "Button", _box(ACCENT.darkened(0.15)))
	t.set_stylebox("focus", "Button", _box(ACCENT.lightened(0.12), 3))
	t.set_stylebox("disabled", "Button", _box(Color("b8b8d1")))
	t.set_stylebox("panel", "PanelContainer", _box(PANEL, 0, 28, 36))
	var le := _box(Color.WHITE, 3, 14, 16)
	le.border_color = ACCENT
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", le)
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_color", "CheckButton", INK)
	t.set_color("font_hover_color", "CheckButton", INK)
	t.set_color("font_pressed_color", "CheckButton", INK)
	t.set_color("font_hover_pressed_color", "CheckButton", INK)
	t.set_color("font_focus_color", "CheckButton", INK)
	t.set_stylebox("normal", "CheckButton", StyleBoxEmpty.new())
	t.set_stylebox("hover", "CheckButton", StyleBoxEmpty.new())
	t.set_stylebox("pressed", "CheckButton", StyleBoxEmpty.new())
	t.set_stylebox("hover_pressed", "CheckButton", StyleBoxEmpty.new())
	t.set_stylebox("focus", "CheckButton", StyleBoxEmpty.new())
	_theme = t
	return t


static func _box(c: Color, border := 0, radius := 22, margin := 22) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin + 6
	s.content_margin_right = margin + 6
	s.content_margin_top = margin * 0.55
	s.content_margin_bottom = margin * 0.55
	if border > 0:
		s.set_border_width_all(border)
		s.border_color = Color.WHITE
	return s


static func button(text: String, cb: Callable, min_w := 320.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 84)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


static func label(text: String, size := 30, color := INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func format_time(t: float) -> String:
	if t < 0.0:
		return "--:--.--"
	var m := int(t / 60.0)
	var s := t - m * 60.0
	return "%d:%05.2f" % [m, s]


static func gradient_background() -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color("8fd3ff"))
	g.set_color(1, Color("ffd6f0"))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	var tr := TextureRect.new()
	tr.texture = gt
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr
