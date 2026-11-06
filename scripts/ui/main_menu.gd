extends Control
## Main menu: Play (level select), Continue, Enter seed, Endless, Settings.

var _main: Control
var _levels: Control
var _seed: Control
var _settings: Control
var _seed_edit: LineEdit
var _seed_error: Label
var _diff_slider: HSlider
var _diff_label: Label


func _ready() -> void:
	theme = UiTheme.get_theme()
	add_child(UiTheme.gradient_background())
	_main = _build_main()
	_levels = _build_levels()
	_seed = _build_seed()
	_settings = _build_settings()
	_show(_main)


func _page() -> Array:
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(cc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	cc.add_child(v)
	return [cc, v]


func _show(page: Control) -> void:
	for p in [_main, _levels, _seed, _settings]:
		p.visible = p == page


func _build_main() -> Control:
	var pg := _page()
	var v: VBoxContainer = pg[1]
	var title := UiTheme.label("Marble Run", 84, Color.WHITE)
	title.add_theme_color_override("font_outline_color", UiTheme.ACCENT)
	title.add_theme_constant_override("outline_size", 18)
	v.add_child(title)
	v.add_child(UiTheme.label("procedural tracks · offline", 26, Color.WHITE))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	v.add_child(grid)
	grid.add_child(UiTheme.button("Play", _open_levels))
	var cont := UiTheme.button("Continue", func(): App.continue_last())
	cont.disabled = not App.can_continue()
	grid.add_child(cont)
	grid.add_child(UiTheme.button("Enter seed", _open_seed))
	grid.add_child(UiTheme.button("Endless", func(): App.start_endless()))
	grid.add_child(UiTheme.button("Settings", func(): _show(_settings)))
	if OS.get_name() != "Android":
		grid.add_child(UiTheme.button("Quit", func(): get_tree().quit()))
	var info := UiTheme.label("Unlocked level %d · best endless %d m · generator v%d" % [
		App.save.unlocked_level, int(App.save.best_endless), TrackGenerator.VERSION], 20, Color.WHITE)
	v.add_child(info)
	return pg[0]


var _level_grid: GridContainer


func _open_levels() -> void:
	_refresh_levels()
	_show(_levels)


func _open_seed() -> void:
	_seed_error.text = ""
	_show(_seed)


func _build_levels() -> Control:
	var pg := _page()
	var v: VBoxContainer = pg[1]
	v.add_child(UiTheme.label("Select level", 54, Color.WHITE))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(960, 420)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	_level_grid = GridContainer.new()
	_level_grid.columns = 5
	_level_grid.add_theme_constant_override("h_separation", 12)
	_level_grid.add_theme_constant_override("v_separation", 12)
	sc.add_child(_level_grid)
	v.add_child(UiTheme.button("Back", func(): _show(_main)))
	return pg[0]


func _refresh_levels() -> void:
	for c in _level_grid.get_children():
		c.queue_free()
	for n in range(1, App.save.unlocked_level + 1):
		var best := App.save.best_time(SaveData.level_key(n))
		var txt := "%d\n%s" % [n, UiTheme.format_time(best) if best >= 0.0 else "new"]
		var b := UiTheme.button(txt, func(): App.start_level(n), 180)
		b.custom_minimum_size = Vector2(180, 110)
		b.add_theme_font_size_override("font_size", 26)
		_level_grid.add_child(b)


func _build_seed() -> Control:
	var pg := _page()
	var v: VBoxContainer = pg[1]
	var panel := PanelContainer.new()
	v.add_child(panel)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 14)
	panel.add_child(pv)
	pv.add_child(UiTheme.label("Play a seed", 46))
	pv.add_child(UiTheme.label("Enter a number, a hex seed, or a full track code\n(SEED-DIFFICULTY-SEGMENTS) shown in game.", 22))
	_seed_edit = LineEdit.new()
	_seed_edit.custom_minimum_size = Vector2(720, 80)
	_seed_edit.placeholder_text = "e.g. 12345 or 94DF7E97AD170C8E-3-14"
	var last_code := str(App.save.last.get("code", ""))
	_seed_edit.text = last_code if App.save.last.get("kind", "") != "endless" else ""
	pv.add_child(_seed_edit)
	var h := HBoxContainer.new()
	pv.add_child(h)
	_diff_label = UiTheme.label("Difficulty 3 (if not in code)", 24)
	_diff_label.custom_minimum_size = Vector2(380, 0)
	h.add_child(_diff_label)
	_diff_slider = HSlider.new()
	_diff_slider.min_value = 1
	_diff_slider.max_value = 8
	_diff_slider.step = 1
	_diff_slider.value = 3
	_diff_slider.custom_minimum_size = Vector2(320, 60)
	_diff_slider.value_changed.connect(func(x): _diff_label.text = "Difficulty %d (if not in code)" % int(x))
	h.add_child(_diff_slider)
	_seed_error = UiTheme.label("", 22, UiTheme.ACCENT_2)
	pv.add_child(_seed_error)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	pv.add_child(row)
	row.add_child(UiTheme.button("Back", func(): _show(_main), 220))
	row.add_child(UiTheme.button("Random", _random_seed, 220))
	row.add_child(UiTheme.button("Play", _play_seed, 220))
	return pg[0]


func _random_seed() -> void:
	# Seeds the *choice* of seed from the clock; the track itself stays deterministic.
	var s := Hash64.splitmix64(Time.get_ticks_usec() ^ int(Time.get_unix_time_from_system()))
	_seed_edit.text = Hash64.to_hex(s)


func _play_seed() -> void:
	var cfg := GeneratorConfig.from_code(_seed_edit.text, _diff_slider.value, 20)
	if cfg == null:
		_seed_error.text = "Not a valid seed or track code."
		return
	App.start_custom(cfg.to_code())


func _build_settings() -> Control:
	var pg := _page()
	var v: VBoxContainer = pg[1]
	var panel := PanelContainer.new()
	v.add_child(panel)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 10)
	panel.add_child(pv)
	pv.add_child(UiTheme.label("Settings", 46))
	_slider_row(pv, "Steering sensitivity", "steer_sensitivity", 0.5, 2.0, 0.1)
	_slider_row(pv, "Camera distance", "camera_distance", 0.7, 1.5, 0.05)
	_check_row(pv, "Invert steering", "invert_steer")
	_check_row(pv, "Shadows", "shadows")
	_check_row(pv, "Show FPS", "show_fps")
	_check_row(pv, "Debug overlay (F3)", "debug")
	pv.add_child(UiTheme.button("Back", func(): _show(_main)))
	return pg[0]


func _slider_row(parent: Control, text: String, key: String, lo: float, hi: float, step: float) -> void:
	var h := HBoxContainer.new()
	parent.add_child(h)
	var l := UiTheme.label(text, 26)
	l.custom_minimum_size = Vector2(360, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(App.setting(key, 1.0))
	s.custom_minimum_size = Vector2(360, 60)
	s.value_changed.connect(func(x): App.set_setting(key, x))
	h.add_child(s)


func _check_row(parent: Control, text: String, key: String) -> void:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = bool(App.setting(key, false))
	c.custom_minimum_size = Vector2(0, 60)
	c.toggled.connect(func(on): App.set_setting(key, on))
	parent.add_child(c)
