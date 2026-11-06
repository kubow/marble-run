class_name Hud
extends CanvasLayer
## In-game HUD plus pause / completion / game-over panels.

signal pause_pressed
signal resume_pressed
signal restart_pressed
signal next_pressed
signal menu_pressed

var _title: Label
var _seed: Label
var _timer: Label
var _progress: ProgressBar
var _distance: Label
var _lives: Label
var _debug: Label
var _fps: Label
var _toast: Label
var _toast_time := 0.0
var _pause_panel: Control
var _end_panel: Control
var _end_title: Label
var _end_body: Label
var _next_btn: Button
var show_fps := false


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.theme = UiTheme.get_theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 24
	top.offset_right = -24
	top.offset_top = 16
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	var left := VBoxContainer.new()
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(left)
	_title = _outlined(UiTheme.label("", 34, Color.WHITE))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	left.add_child(_title)
	_seed = _outlined(UiTheme.label("", 20, Color.WHITE))
	_seed.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	left.add_child(_seed)
	_lives = _outlined(UiTheme.label("", 26, Color("ff5a5f")))
	_lives.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	left.add_child(_lives)
	_timer = _outlined(UiTheme.label("0:00.00", 44, Color.WHITE))
	_timer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_timer)
	var right := HBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.alignment = BoxContainer.ALIGNMENT_END
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(right)
	var pause_btn := UiTheme.button("II", func(): pause_pressed.emit(), 96)
	right.add_child(pause_btn)

	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 40
	bottom.offset_right = -40
	bottom.offset_top = -70
	bottom.offset_bottom = -20
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom)
	_distance = _outlined(UiTheme.label("", 28, Color.WHITE))
	bottom.add_child(_distance)
	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(0, 14)
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = UiTheme.ACCENT_2
	fill.set_corner_radius_all(7)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.5)
	bg.set_corner_radius_all(7)
	_progress.add_theme_stylebox_override("fill", fill)
	_progress.add_theme_stylebox_override("background", bg)
	bottom.add_child(_progress)

	_debug = Label.new()
	_debug.position = Vector2(24, 170)
	_debug.add_theme_font_size_override("font_size", 18)
	_debug.add_theme_color_override("font_color", Color.WHITE)
	_debug.add_theme_color_override("font_outline_color", Color.BLACK)
	_debug.add_theme_constant_override("outline_size", 4)
	_debug.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_debug)
	_fps = _outlined(UiTheme.label("", 18, Color.WHITE))
	_fps.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_fps.position = Vector2(-140, -110)
	root.add_child(_fps)

	_toast = _outlined(UiTheme.label("", 40, Color.WHITE))
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_top = 150
	_toast.offset_left = -400
	_toast.offset_right = 400
	root.add_child(_toast)

	_pause_panel = _panel(root, "Paused", [
		["Resume", func(): resume_pressed.emit()],
		["Restart", func(): restart_pressed.emit()],
		["Main menu", func(): menu_pressed.emit()],
	])
	var end := _panel_with_body(root)
	_end_panel = end[0]
	_end_title = end[1]
	_end_body = end[2]
	var box: VBoxContainer = end[3]
	_next_btn = UiTheme.button("Next level", func(): next_pressed.emit())
	box.add_child(_next_btn)
	box.add_child(UiTheme.button("Retry", func(): restart_pressed.emit()))
	box.add_child(UiTheme.button("Main menu", func(): menu_pressed.emit()))


func _outlined(l: Label) -> Label:
	l.add_theme_color_override("font_outline_color", Color(0.17, 0.18, 0.26, 0.85))
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _center_container(root: Control) -> CenterContainer:
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.1, 0.1, 0.2, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(dim)
	root.add_child(cc)
	cc.visible = false
	return cc


func _panel(root: Control, title: String, buttons: Array) -> Control:
	var cc := _center_container(root)
	var pc := PanelContainer.new()
	cc.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	pc.add_child(v)
	v.add_child(UiTheme.label(title, 48))
	for b in buttons:
		v.add_child(UiTheme.button(b[0], b[1]))
	return cc


func _panel_with_body(root: Control) -> Array:
	var cc := _center_container(root)
	var pc := PanelContainer.new()
	cc.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	pc.add_child(v)
	var t := UiTheme.label("", 48)
	v.add_child(t)
	var b := UiTheme.label("", 30)
	v.add_child(b)
	return [cc, t, b, v]


func set_title(title: String, seed_text: String) -> void:
	_title.text = title
	_seed.text = seed_text


func set_time(t: float) -> void:
	_timer.text = UiTheme.format_time(t)


func set_progress(fraction: float, text: String) -> void:
	_progress.visible = fraction >= 0.0
	_progress.value = fraction * 100.0
	_distance.text = text


func set_lives(n: int) -> void:
	_lives.text = "●".repeat(maxi(n, 0))


func set_debug(text: String) -> void:
	_debug.text = text
	_debug.visible = text != ""


func toast(text: String, seconds := 1.5) -> void:
	_toast.text = text
	_toast_time = seconds


func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		_toast.modulate.a = clampf(_toast_time * 2.0, 0.0, 1.0)
	else:
		_toast.text = ""
	_fps.visible = show_fps
	if show_fps:
		_fps.text = "%d FPS" % Engine.get_frames_per_second()


func _unhandled_input(event: InputEvent) -> void:
	# The game node is paused while the pause panel is shown, so resume here.
	if _pause_panel.visible and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		resume_pressed.emit()


func show_pause(on: bool) -> void:
	_pause_panel.visible = on


func show_complete(time: float, best: float, new_best: bool, has_next: bool) -> void:
	_end_title.text = "Level complete!"
	_end_body.text = "Time  %s\nBest  %s%s" % [UiTheme.format_time(time), UiTheme.format_time(best), "  (new!)" if new_best else ""]
	_next_btn.visible = has_next
	_next_btn.text = "Next level"
	_end_panel.visible = true


func show_game_over(body: String) -> void:
	_end_title.text = "Game over"
	_end_body.text = body
	_next_btn.visible = false
	_end_panel.visible = true


func hide_panels() -> void:
	_pause_panel.visible = false
	_end_panel.visible = false
