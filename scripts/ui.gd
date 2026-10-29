class_name UI
extends CanvasLayer
## Menus: title, campaign level select, settings, how to play, pause, results.

var main: Node
var _root: Control
var _backdrop: ColorRect
var _screens: Dictionary = {}
var _current := ""
var _high_label: Label
var _level_box: VBoxContainer
var _result_title: Label
var _result_body: Label
var _result_primary: Button
var _last_result: Dictionary = {}


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	# The menu layer stays in the tree during a run; never let it swallow game touches.
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = _make_theme()
	add_child(_root)
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(0.04, 0.0, 0.01, 0.5)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_backdrop)
	_build_main()
	_build_levels()
	_build_settings()
	_build_help()
	_build_pause()
	_build_result()
	hide_screens()


# --- Navigation -----------------------------------------------------------------

func show_screen(id: String) -> void:
	for k in _screens:
		_screens[k].visible = (k == id)
	_current = id
	_backdrop.visible = true
	_backdrop.color = Color(0.04, 0.0, 0.01, 0.35 if id == "main" else 0.6)
	if id == "main":
		_high_label.text = "BEST ENDLESS SCORE  %d" % G.high_score if G.high_score > 0 else "Tilt to steer  ·  Right side fires  ·  Left side shocks"
	elif id == "levels":
		_refresh_levels()


func hide_screens() -> void:
	for k in _screens:
		_screens[k].visible = false
	_current = ""
	_backdrop.visible = false


func current() -> String:
	return _current


func on_back() -> void:
	match _current:
		"main":
			get_tree().quit()
		"levels", "settings", "help":
			show_screen("main")
		"pause":
			main.resume(false)
		"result":
			main.to_menu()
		"":
			main.request_pause()


# --- Builders ----------------------------------------------------------------

func _screen(id: String) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	_screens[id] = center
	return box


func _panel_screen(id: String, width: float) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	_screens[id] = center
	return box


func _label(text: String, fsize: int, col: Color = Color(1, 0.9, 0.88), align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	return l


func _button(text: String, cb: Callable, width: float = 440.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 72)
	b.pressed.connect(func():
		Sfx.play("blip", -8.0)
		cb.call())
	return b


func _centered(c: Control) -> Control:
	c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return c


func _build_main() -> void:
	var box := _screen("main")
	var title := _label("VEINTREK", 118, Color(1.0, 0.22, 0.16))
	title.add_theme_color_override("font_outline_color", Color(0.25, 0.0, 0.02))
	title.add_theme_constant_override("outline_size", 14)
	box.add_child(title)
	box.add_child(_label("MICRO-SHIP  ·  BLOODSTREAM OPS", 26, Color(1.0, 0.75, 0.6)))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 18)
	box.add_child(spacer)
	box.add_child(_centered(_button("CAMPAIGN", func(): show_screen("levels"))))
	box.add_child(_centered(_button("ENDLESS", func(): main.start_endless())))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	row.add_child(_button("HOW TO PLAY", func(): show_screen("help"), 212))
	row.add_child(_button("SETTINGS", func(): show_screen("settings"), 212))
	box.add_child(row)
	_high_label = _label("", 24, Color(1.0, 0.72, 0.3))
	box.add_child(_high_label)


func _build_levels() -> void:
	var box := _panel_screen("levels", 760)
	box.add_child(_label("CAMPAIGN", 48, Color(1.0, 0.3, 0.22)))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(700, 440)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_level_box = VBoxContainer.new()
	_level_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_level_box.add_theme_constant_override("separation", 10)
	scroll.add_child(_level_box)
	box.add_child(_centered(_button("BACK", func(): show_screen("main"), 260)))


func _refresh_levels() -> void:
	for c in _level_box.get_children():
		c.queue_free()
	for i in G.LEVELS.size():
		var lv: Dictionary = G.LEVELS[i]
		var locked := i > G.unlocked_level
		var txt := "%d.  %s  —  %s" % [i + 1, String(lv.name).to_upper(), lv.place]
		if locked:
			txt = "%d.  LOCKED" % (i + 1)
		elif G.level_best.has(i):
			txt += "   ★ %d" % int(G.level_best[i])
		var idx := i
		var b := _button(txt, func(): main.start_campaign(idx), 680)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = locked
		b.add_theme_font_size_override("font_size", 26)
		b.custom_minimum_size.y = 60
		_level_box.add_child(b)


func _build_settings() -> void:
	var box := _panel_screen("settings", 720)
	box.add_child(_label("SETTINGS", 48, Color(1.0, 0.3, 0.22)))
	box.add_child(_slider_row("Tilt sensitivity", 0.5, 2.0, G.tilt_sensitivity, func(v): G.tilt_sensitivity = v))
	box.add_child(_slider_row("Volume", 0.0, 1.0, G.volume, func(v):
		G.volume = v
		G.apply_audio()))
	box.add_child(_check_row("Invert left / right", G.invert_x, func(on): G.invert_x = on))
	box.add_child(_check_row("Invert up / down", G.invert_y, func(on): G.invert_y = on))
	box.add_child(_check_row("Auto-fire", G.auto_fire, func(on): G.auto_fire = on))
	box.add_child(_check_row("Vibration", G.vibration, func(on): G.vibration = on))
	box.add_child(_centered(_button("DONE", func():
		G.save_data()
		show_screen("main"), 260)))


func _slider_row(text: String, lo: float, hi: float, val: float, cb: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	var l := _label(text, 28, Color(1, 0.9, 0.88), HORIZONTAL_ALIGNMENT_LEFT)
	l.custom_minimum_size = Vector2(260, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.05
	s.value = val
	s.custom_minimum_size = Vector2(360, 50)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(func(v): cb.call(v))
	row.add_child(s)
	return row


func _check_row(text: String, val: bool, cb: Callable) -> Control:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = val
	c.add_theme_font_size_override("font_size", 28)
	c.toggled.connect(func(on): cb.call(on))
	return c


func _build_help() -> void:
	var box := _panel_screen("help", 900)
	box.add_child(_label("HOW TO PLAY", 48, Color(1.0, 0.3, 0.22)))
	var body := _label(
		"• Tilt the phone to steer and aim. The angle you hold it at when a run starts is centre.\n" +
		"• Hold the RIGHT side of the screen to fire. Lasers go where the crosshair points.\n" +
		"• Touch the LEFT side to shock the windshield. It fries white cells stuck to the glass. You start with 3 charges.\n" +
		"• When the arrows flash SHARP TURN, lean the way they point. Bends throw you toward the outside wall.\n" +
		"• Dark red cells are infected and shoot back. Ram any cell and your glass cracks.\n" +
		"• Cyan rings repair the window. Blue bolts add a shock charge. Gold crystals (rare) upgrade your lasers.",
		26, Color(1, 0.9, 0.88), HORIZONTAL_ALIGNMENT_LEFT)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(840, 0)
	box.add_child(body)
	box.add_child(_centered(_button("GOT IT", func(): show_screen("main"), 260)))


func _build_pause() -> void:
	var box := _panel_screen("pause", 560)
	box.add_child(_label("PAUSED", 56, Color(1.0, 0.3, 0.22)))
	box.add_child(_centered(_button("RESUME", func(): main.resume(false))))
	box.add_child(_centered(_button("RECALIBRATE TILT", func(): main.resume(true))))
	box.add_child(_centered(_button("QUIT TO MENU", func(): main.to_menu())))


func _build_result() -> void:
	var box := _panel_screen("result", 640)
	_result_title = _label("", 54, Color(1.0, 0.3, 0.22))
	box.add_child(_result_title)
	_result_body = _label("", 28)
	box.add_child(_result_body)
	_result_primary = _button("RETRY", func(): _on_primary())
	box.add_child(_centered(_result_primary))
	box.add_child(_centered(_button("MENU", func(): main.to_menu())))


func show_result(res: Dictionary) -> void:
	_last_result = res
	var lines: Array[String] = []
	if res.mode == "campaign":
		var lv: Dictionary = G.LEVELS[res.level]
		if res.victory:
			var last: bool = int(res.level) >= G.LEVELS.size() - 1
			_result_title.text = "THE HEART IS SAFE" if last else "MISSION COMPLETE"
			_result_title.add_theme_color_override("font_color", Color(0.4, 1.0, 0.7))
			lines.append("You reached the %s." % lv.place)
			_result_primary.text = "PLAY AGAIN" if last else "NEXT LEVEL"
		else:
			_result_title.text = "WINDOW BREACHED"
			_result_title.add_theme_color_override("font_color", Color(1.0, 0.3, 0.22))
			lines.append("Lost in the %s." % lv.place)
			_result_primary.text = "RETRY"
	else:
		_result_title.text = "NEW HIGH SCORE" if res.new_high else "RUN OVER"
		_result_title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3) if res.new_high else Color(1.0, 0.3, 0.22))
		_result_primary.text = "GO AGAIN"
	lines.append("Score  %d" % int(res.score))
	lines.append("Distance  %d m     Kills  %d" % [int(res.distance), int(res.kills)])
	if res.mode == "endless":
		lines.append("Best  %d" % G.high_score)
	_result_body.text = "\n".join(lines)
	show_screen("result")


func _on_primary() -> void:
	var res := _last_result
	if res.mode == "campaign":
		var next: int = int(res.level)
		if res.victory and next < G.LEVELS.size() - 1:
			next += 1
		main.start_campaign(next)
	else:
		main.start_endless()


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 30
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.16, 0.015, 0.03, 0.92)
	normal.border_color = Color(0.85, 0.16, 0.12)
	normal.set_border_width_all(3)
	normal.set_corner_radius_all(14)
	normal.content_margin_left = 24
	normal.content_margin_right = 24
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.32, 0.04, 0.05, 0.95)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.6, 0.08, 0.07, 0.95)
	pressed.border_color = Color(1.0, 0.5, 0.4)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.08, 0.03, 0.04, 0.8)
	disabled.border_color = Color(0.35, 0.18, 0.18)
	for kind in ["Button", "CheckButton"]:
		t.set_stylebox("normal", kind, normal)
		t.set_stylebox("hover", kind, hover)
		t.set_stylebox("pressed", kind, pressed)
		t.set_stylebox("hover_pressed", kind, pressed)
		t.set_stylebox("disabled", kind, disabled)
		t.set_stylebox("focus", kind, StyleBoxEmpty.new())
		t.set_color("font_color", kind, Color(1.0, 0.9, 0.88))
		t.set_color("font_hover_color", kind, Color(1, 1, 1))
		t.set_color("font_pressed_color", kind, Color(1, 1, 1))
		t.set_color("font_hover_pressed_color", kind, Color(1, 1, 1))
		t.set_color("font_disabled_color", kind, Color(0.5, 0.38, 0.38))
		t.set_font_size("font_size", kind, 32)
	t.set_color("font_color", "Label", Color(1.0, 0.9, 0.88))
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.06, 0.0, 0.012, 0.9)
	panel.border_color = Color(0.7, 0.12, 0.1)
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(18)
	panel.set_content_margin_all(30)
	t.set_stylebox("panel", "PanelContainer", panel)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.25, 0.05, 0.06)
	track.set_corner_radius_all(6)
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = Color(0.9, 0.2, 0.15)
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var vbar := StyleBoxFlat.new()
	vbar.bg_color = Color(0.6, 0.12, 0.1)
	vbar.set_corner_radius_all(4)
	t.set_stylebox("grabber", "VScrollBar", vbar)
	t.set_stylebox("grabber_highlight", "VScrollBar", vbar)
	return t
