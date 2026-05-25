extends Control

# This file handles the start menu.
# It lets the player choose mode, side, AI position, and match length.
@onready var main_panel: Control = $MainPanel
@onready var color_panel: Control = $ColorPanel
@onready var one_player_btn: Button = $MainPanel/Buttons/OnePlayerBtn
@onready var two_player_btn: Button = $MainPanel/Buttons/TwoPlayerBtn
@onready var four_player_btn: Button = $MainPanel/Buttons/FourPlayerBtn
@onready var red_btn: Button = $ColorPanel/Buttons/RedBtn
@onready var black_btn: Button = $ColorPanel/Buttons/BlackBtn
@onready var back_btn: Button = $ColorPanel/Buttons/BackBtn

@onready var title_label: Label = $MainPanel/Title
@onready var title_glow: TextureRect = $MainPanel/TitleGlow
@onready var color_title_glow: TextureRect = $ColorPanel/TitleGlow
@onready var decorations: Node2D = $Decorations

const TITLE_BASE_OUTLINE := Color(0.18, 0.02, 0.04, 1)
const TITLE_BRIGHT_OUTLINE := Color(0.55, 0.08, 0.10, 1)

var _decoration_tweens: Array[Tween] = []
var _title_tween: Tween
var _glow_tween: Tween
var _starting := false

var _best_of_panel: Control
var _position_panel: Control
var _prev_panel: Control


func _ready() -> void:
	# Build extra menu panels and play the intro animation.
	_setup_panels()
	_create_best_of_panel()
	_create_position_panel()
	_create_vs_ai_button()
	_connect_signals()
	_animate_title()
	_animate_decorations()
	_animate_panel_in(main_panel)


func _setup_panels() -> void:
	color_panel.hide()
	main_panel.show()
	title_label.pivot_offset = title_label.size * 0.5


func _connect_signals() -> void:
	# Connect all menu buttons once.
	one_player_btn.pressed.connect(_on_one_player_pressed)
	two_player_btn.pressed.connect(_on_two_player_pressed)
	four_player_btn.pressed.connect(_on_four_player_pressed)
	red_btn.pressed.connect(_on_red_pressed)
	black_btn.pressed.connect(_on_black_pressed)
	back_btn.pressed.connect(_on_back_pressed)

	for btn in [one_player_btn, two_player_btn, four_player_btn, red_btn, black_btn, back_btn]:
		_wire_button_hover(btn)


func _wire_button_hover(btn: Button) -> void:
	btn.mouse_entered.connect(func(): _btn_hover(btn, true))
	btn.mouse_exited.connect(func(): _btn_hover(btn, false))
	btn.button_down.connect(func(): _btn_press(btn))


func _btn_hover(btn: Button, hovering: bool) -> void:
	# Small size change on hover.
	btn.pivot_offset = btn.size * 0.5
	var tw := create_tween()
	tw.tween_property(btn, "scale", Vector2(1.035, 1.035) if hovering else Vector2.ONE, 0.18)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _btn_press(btn: Button) -> void:
	# Quick press animation for feedback.
	btn.pivot_offset = btn.size * 0.5
	var tw := create_tween()
	tw.tween_property(btn, "scale", Vector2(0.97, 0.97), 0.07)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(btn, "scale", Vector2(1.035, 1.035), 0.16)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _animate_title() -> void:
	if _title_tween and _title_tween.is_valid():
		_title_tween.kill()
	_title_tween = create_tween().set_loops()
	_title_tween.tween_property(title_label, "scale", Vector2(1.035, 1.035), 1.6)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_title_tween.tween_property(title_label, "scale", Vector2.ONE, 1.6)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	if _glow_tween and _glow_tween.is_valid():
		_glow_tween.kill()
	_glow_tween = create_tween().set_loops()
	_glow_tween.tween_property(title_glow, "modulate:a", 0.55, 1.4)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_glow_tween.tween_property(title_glow, "modulate:a", 1.0, 1.4)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Slowly change the outline color so the title does not feel static.
	var shimmer := create_tween().set_loops()
	shimmer.tween_method(_set_title_outline, 0.0, 1.0, 2.2)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	shimmer.tween_method(_set_title_outline, 1.0, 0.0, 2.2)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _set_title_outline(t: float) -> void:
	var c := TITLE_BASE_OUTLINE.lerp(TITLE_BRIGHT_OUTLINE, t)
	title_label.add_theme_color_override("font_outline_color", c)


func _animate_decorations() -> void:
	# Move background pieces slowly so the menu feels alive.
	for child in decorations.get_children():
		if not child is Sprite2D:
			continue
		var sprite: Sprite2D = child
		var origin := sprite.position
		var drift_x := randf_range(-22.0, 22.0)
		var drift_y := randf_range(-30.0, 30.0)
		var dur := randf_range(4.0, 7.0)
		var rot_amt := randf_range(-0.15, 0.15)
		var tw := create_tween().set_loops()
		tw.set_parallel(true)
		tw.tween_property(sprite, "position", origin + Vector2(drift_x, drift_y), dur)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(sprite, "rotation", rot_amt, dur)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.chain()
		tw.set_parallel(true)
		tw.tween_property(sprite, "position", origin, dur)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(sprite, "rotation", 0.0, dur)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_decoration_tweens.append(tw)


func _animate_panel_in(panel: Control) -> void:
	panel.modulate.a = 0.0
	panel.position.y = 30.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(panel, "modulate:a", 1.0, 0.35)
	tw.tween_property(panel, "position:y", 0.0, 0.45)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _animate_panel_out(panel: Control, on_done: Callable) -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(panel, "modulate:a", 0.0, 0.18)
	tw.tween_property(panel, "position:y", -20.0, 0.22)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(on_done)


func _on_one_player_pressed() -> void:
	_animate_panel_out(main_panel, func():
		main_panel.hide()
		main_panel.position.y = 0.0
		main_panel.modulate.a = 1.0
		color_panel.show()
		_animate_panel_in(color_panel)
	)


func _on_two_player_pressed() -> void:
	if _starting:
		return
	GameSettings.mode = GameSettings.Mode.TWO_PLAYER
	GameSettings.ai_enabled = false
	_show_best_of_panel(main_panel)

func _on_vs_ai_pressed() -> void:
	if _starting:
		return
	GameSettings.mode = GameSettings.Mode.TWO_PLAYER
	GameSettings.ai_enabled = true
	_animate_panel_out(main_panel, func():
		main_panel.hide()
		main_panel.position.y = 0.0
		main_panel.modulate.a = 1.0
		_position_panel.show()
		_animate_panel_in(_position_panel)
	)


func _on_position_pressed(human: int) -> void:
	if _starting:
		return
	GameSettings.human_player = human
	_show_best_of_panel(_position_panel)


func _on_position_back_pressed() -> void:
	_animate_panel_out(_position_panel, func():
		_position_panel.hide()
		_position_panel.position.y = 0.0
		_position_panel.modulate.a = 1.0
		main_panel.show()
		_animate_panel_in(main_panel)
	)


func _on_four_player_pressed() -> void:
	if _starting:
		return
	GameSettings.mode = GameSettings.Mode.FOUR_PLAYER
	GameSettings.ai_enabled = false
	_show_best_of_panel(main_panel)


func _on_red_pressed() -> void:
	if _starting:
		return
	GameSettings.mode = GameSettings.Mode.ONE_PLAYER
	GameSettings.ai_enabled = false
	GameSettings.single_color = 1
	_show_best_of_panel(color_panel)


func _on_black_pressed() -> void:
	if _starting:
		return
	GameSettings.mode = GameSettings.Mode.ONE_PLAYER
	GameSettings.ai_enabled = false
	GameSettings.single_color = 2
	_show_best_of_panel(color_panel)


func _on_back_pressed() -> void:
	_animate_panel_out(color_panel, func():
		color_panel.hide()
		color_panel.position.y = 0.0
		color_panel.modulate.a = 1.0
		main_panel.show()
		_animate_panel_in(main_panel)
	)


func _show_best_of_panel(from: Control) -> void:
	# Hide the current menu panel and open the match length panel.
	_prev_panel = from
	_animate_panel_out(from, func():
		from.hide()
		from.position.y = 0.0
		from.modulate.a = 1.0
		_best_of_panel.show()
		_animate_panel_in(_best_of_panel)
	)


func _on_bestof_back_pressed() -> void:
	_animate_panel_out(_best_of_panel, func():
		_best_of_panel.hide()
		_best_of_panel.position.y = 0.0
		_best_of_panel.modulate.a = 1.0
		_prev_panel.show()
		_animate_panel_in(_prev_panel)
	)


func _on_best_of_pressed(n: int) -> void:
	if _starting:
		return
	GameSettings.best_of = n
	_start_game_with_flash()


func _create_best_of_panel() -> void:
	# Build the match length panel in code.
	_best_of_panel = Control.new()
	_best_of_panel.size = Vector2(1080, 1920)
	_best_of_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_best_of_panel.hide()
	add_child(_best_of_panel)

	var title := Label.new()
	title.position = Vector2(0, 460)
	title.size = Vector2(1080, 160)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.text = "SETS TO PLAY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 96)
	title.add_theme_color_override("font_color", Color(0.95, 0.97, 1, 1))
	title.add_theme_color_override("font_outline_color", Color(0.05, 0.07, 0.13, 1))
	title.add_theme_constant_override("outline_size", 8)
	_best_of_panel.add_child(title)

	var sub := Label.new()
	sub.position = Vector2(0, 640)
	sub.size = Vector2(1080, 50)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub.text = "choose match format"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 30)
	sub.add_theme_color_override("font_color", Color(0.6, 0.65, 0.78, 0.9))
	_best_of_panel.add_child(sub)

	# 2×2 card grid
	var vbox := VBoxContainer.new()
	vbox.position = Vector2(80, 760)
	vbox.size = Vector2(920, 510)
	vbox.add_theme_constant_override("separation", 20)
	_best_of_panel.add_child(vbox)

	var row1 := HBoxContainer.new()
	row1.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row1.add_theme_constant_override("separation", 20)
	vbox.add_child(row1)

	var row2 := HBoxContainer.new()
	row2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row2.add_theme_constant_override("separation", 20)
	vbox.add_child(row2)

	var cards := [
		{"n": 1, "label": "SET",  "color": Color(0.55, 0.72, 0.98)},
		{"n": 3, "label": "SETS", "color": Color(0.93, 0.76, 0.22)},
		{"n": 5, "label": "SETS", "color": Color(0.95, 0.30, 0.36)},
		{"n": 7, "label": "SETS", "color": Color(0.68, 0.42, 0.98)},
	]
	for i in 4:
		var c: Dictionary = cards[i]
		var btn := _make_card_btn(str(c["n"]), c["label"], c["color"])
		btn.pressed.connect(_on_best_of_pressed.bind(c["n"]))
		(row1 if i < 2 else row2).add_child(btn)

	var back_sb := StyleBoxFlat.new()
	back_sb.bg_color = Color(0.10, 0.12, 0.18, 0.85)
	back_sb.set_border_width_all(1)
	back_sb.border_width_bottom = 2
	back_sb.border_color = Color(0.45, 0.52, 0.7, 0.7)
	back_sb.set_corner_radius_all(18)

	var back := Button.new()
	back.position = Vector2(290, 1330)
	back.size = Vector2(500, 90)
	back.text = "← BACK"
	back.add_theme_font_size_override("font_size", 38)
	back.add_theme_color_override("font_color", Color(0.65, 0.72, 0.85, 1))
	back.add_theme_stylebox_override("normal", back_sb)
	back.add_theme_stylebox_override("hover", back_sb)
	back.add_theme_stylebox_override("focus", back_sb)
	back.add_theme_stylebox_override("pressed", back_sb)
	back.pressed.connect(_on_bestof_back_pressed)
	_wire_button_hover(back)
	_best_of_panel.add_child(back)


func _create_position_panel() -> void:
	# This panel is only used for AI matches.
	_position_panel = Control.new()
	_position_panel.size = Vector2(1080, 1920)
	_position_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_position_panel.hide()
	add_child(_position_panel)

	var title := Label.new()
	title.position = Vector2(0, 460)
	title.size = Vector2(1080, 160)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.text = "YOUR POSITION"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 96)
	title.add_theme_color_override("font_color", Color(0.95, 0.97, 1, 1))
	title.add_theme_color_override("font_outline_color", Color(0.05, 0.07, 0.13, 1))
	title.add_theme_constant_override("outline_size", 8)
	_position_panel.add_child(title)

	var sub := Label.new()
	sub.position = Vector2(0, 640)
	sub.size = Vector2(1080, 50)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub.text = "who goes first?"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 30)
	sub.add_theme_color_override("font_color", Color(0.6, 0.65, 0.78, 0.9))
	_position_panel.add_child(sub)

	var vbox := VBoxContainer.new()
	vbox.position = Vector2(110, 820)
	vbox.size = Vector2(860, 700)
	vbox.add_theme_constant_override("separation", 26)
	_position_panel.add_child(vbox)

	var options := [
		{"human": 1, "title": "PLAYER 1",  "sub": "You go first",     "accent": Color(0.55, 0.72, 0.98)},
		{"human": 2, "title": "PLAYER 2",  "sub": "Computer starts",  "accent": Color(0.93, 0.76, 0.22)},
	]
	for o: Dictionary in options:
		var btn := _make_position_btn(o["title"], o["sub"], o["accent"])
		btn.pressed.connect(_on_position_pressed.bind(o["human"]))
		vbox.add_child(btn)

	var back_sb := StyleBoxFlat.new()
	back_sb.bg_color = Color(0.10, 0.12, 0.18, 0.85)
	back_sb.set_border_width_all(1)
	back_sb.border_width_bottom = 2
	back_sb.border_color = Color(0.45, 0.52, 0.7, 0.7)
	back_sb.set_corner_radius_all(18)

	var back := Button.new()
	back.custom_minimum_size = Vector2(0, 100)
	back.text = "← BACK"
	back.add_theme_font_size_override("font_size", 38)
	back.add_theme_color_override("font_color", Color(0.65, 0.72, 0.85, 1))
	back.add_theme_stylebox_override("normal",  back_sb)
	back.add_theme_stylebox_override("hover",   back_sb)
	back.add_theme_stylebox_override("focus",   back_sb)
	back.add_theme_stylebox_override("pressed", back_sb)
	back.pressed.connect(_on_position_back_pressed)
	_wire_button_hover(back)
	vbox.add_child(back)


func _make_position_btn(title_text: String, sub_text: String, accent: Color) -> Button:
	# Create one large menu button with title and subtitle.
	var bg := Color(accent.r * 0.09, accent.g * 0.09, accent.b * 0.12, 0.95)

	var normal_sb := StyleBoxFlat.new()
	normal_sb.bg_color = bg
	normal_sb.border_width_top = 2
	normal_sb.border_width_bottom = 6
	normal_sb.border_color = Color(accent.r, accent.g, accent.b, 0.80)
	normal_sb.set_corner_radius_all(22)
	normal_sb.shadow_color = Color(accent.r, accent.g, accent.b, 0.25)
	normal_sb.shadow_size = 16
	normal_sb.shadow_offset = Vector2(0, 4)

	var hover_sb := StyleBoxFlat.new()
	hover_sb.bg_color = Color(
		minf(bg.r * 2.2 + 0.05, 1.0),
		minf(bg.g * 2.2 + 0.05, 1.0),
		minf(bg.b * 2.2 + 0.05, 1.0), 1.0)
	hover_sb.border_width_top = 2
	hover_sb.border_width_bottom = 7
	hover_sb.border_color = Color(accent.r, accent.g, accent.b, 1.0)
	hover_sb.set_corner_radius_all(22)
	hover_sb.shadow_color = Color(accent.r, accent.g, accent.b, 0.52)
	hover_sb.shadow_size = 28
	hover_sb.shadow_offset = Vector2(0, 4)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 200)
	btn.add_theme_stylebox_override("normal",  normal_sb)
	btn.add_theme_stylebox_override("hover",   hover_sb)
	btn.add_theme_stylebox_override("focus",   hover_sb)
	btn.add_theme_stylebox_override("pressed", normal_sb)

	var t_lbl := Label.new()
	t_lbl.anchor_right = 1.0
	t_lbl.offset_top = 50.0
	t_lbl.offset_bottom = 130.0
	t_lbl.text = title_text
	t_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t_lbl.add_theme_font_size_override("font_size", 64)
	t_lbl.add_theme_color_override("font_color", Color(accent.r, accent.g, accent.b, 1.0))
	t_lbl.add_theme_color_override("font_outline_color",
		Color(accent.r * 0.18, accent.g * 0.18, accent.b * 0.22, 1.0))
	t_lbl.add_theme_constant_override("outline_size", 4)
	btn.add_child(t_lbl)

	var s_lbl := Label.new()
	s_lbl.anchor_right = 1.0
	s_lbl.offset_top = 132.0
	s_lbl.offset_bottom = 174.0
	s_lbl.text = sub_text
	s_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	s_lbl.add_theme_font_size_override("font_size", 26)
	s_lbl.add_theme_color_override("font_color", Color(accent.r, accent.g, accent.b, 0.60))
	btn.add_child(s_lbl)

	_wire_button_hover(btn)
	return btn


func _make_card_btn(number: String, label_text: String, accent: Color) -> Button:
	# Create one card for a best-of choice.
	var bg := Color(accent.r * 0.09, accent.g * 0.09, accent.b * 0.12, 0.95)

	var normal_sb := StyleBoxFlat.new()
	normal_sb.bg_color = bg
	normal_sb.border_width_top = 2
	normal_sb.border_width_bottom = 6
	normal_sb.border_color = Color(accent.r, accent.g, accent.b, 0.80)
	normal_sb.set_corner_radius_all(26)
	normal_sb.shadow_color = Color(accent.r, accent.g, accent.b, 0.25)
	normal_sb.shadow_size = 14
	normal_sb.shadow_offset = Vector2(0, 4)

	var hover_sb := StyleBoxFlat.new()
	hover_sb.bg_color = Color(
		minf(bg.r * 2.2 + 0.05, 1.0),
		minf(bg.g * 2.2 + 0.05, 1.0),
		minf(bg.b * 2.2 + 0.05, 1.0), 1.0)
	hover_sb.border_width_top = 2
	hover_sb.border_width_bottom = 7
	hover_sb.border_color = Color(accent.r, accent.g, accent.b, 1.0)
	hover_sb.set_corner_radius_all(26)
	hover_sb.shadow_color = Color(accent.r, accent.g, accent.b, 0.52)
	hover_sb.shadow_size = 28
	hover_sb.shadow_offset = Vector2(0, 4)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 245)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_stylebox_override("normal", normal_sb)
	btn.add_theme_stylebox_override("hover", hover_sb)
	btn.add_theme_stylebox_override("focus", hover_sb)
	btn.add_theme_stylebox_override("pressed", normal_sb)

	var num_lbl := Label.new()
	num_lbl.anchor_right = 1.0
	num_lbl.offset_top = 38.0
	num_lbl.offset_bottom = 182.0
	num_lbl.text = number
	num_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num_lbl.add_theme_font_size_override("font_size", 104)
	num_lbl.add_theme_color_override("font_color", Color(accent.r, accent.g, accent.b, 1.0))
	num_lbl.add_theme_color_override("font_outline_color",
		Color(accent.r * 0.18, accent.g * 0.18, accent.b * 0.22, 1.0))
	num_lbl.add_theme_constant_override("outline_size", 4)
	btn.add_child(num_lbl)

	var type_lbl := Label.new()
	type_lbl.anchor_right = 1.0
	type_lbl.offset_top = 184.0
	type_lbl.offset_bottom = 226.0
	type_lbl.text = label_text
	type_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	type_lbl.add_theme_font_size_override("font_size", 28)
	type_lbl.add_theme_color_override("font_color", Color(accent.r, accent.g, accent.b, 0.60))
	btn.add_child(type_lbl)

	_wire_button_hover(btn)
	return btn


func _create_vs_ai_button() -> void:
	# Add the AI option under the normal game modes.
	var buttons_container: VBoxContainer = $MainPanel/Buttons

	# Small divider before the AI option.
	var sep := Control.new()
	sep.custom_minimum_size = Vector2(0, 24)
	var sep_line := ColorRect.new()
	sep_line.color = Color(0.55, 0.62, 0.80, 0.20)
	sep_line.offset_left = 80.0
	sep_line.offset_top = 11.0
	sep_line.offset_right = 780.0
	sep_line.offset_bottom = 13.0
	sep.add_child(sep_line)
	buttons_container.add_child(sep)

	var normal_sb := StyleBoxFlat.new()
	normal_sb.bg_color       = Color(0.06, 0.14, 0.09, 0.95)
	normal_sb.set_border_width_all(1)
	normal_sb.border_width_bottom = 4
	normal_sb.border_color    = Color(0.35, 0.85, 0.45, 0.85)
	normal_sb.set_corner_radius_all(22)
	normal_sb.shadow_color    = Color(0.35, 0.85, 0.45, 0.35)
	normal_sb.shadow_size     = 18
	normal_sb.shadow_offset   = Vector2(0, 4)

	var hover_sb := StyleBoxFlat.new()
	hover_sb.bg_color         = Color(0.11, 0.22, 0.14, 1.0)
	hover_sb.set_border_width_all(1)
	hover_sb.border_width_bottom = 5
	hover_sb.border_color     = Color(0.45, 1.0, 0.55, 1.0)
	hover_sb.set_corner_radius_all(22)
	hover_sb.shadow_color     = Color(0.45, 1.0, 0.55, 0.55)
	hover_sb.shadow_size      = 28
	hover_sb.shadow_offset    = Vector2(0, 4)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 155)
	btn.add_theme_stylebox_override("normal",  normal_sb)
	btn.add_theme_stylebox_override("hover",   hover_sb)
	btn.add_theme_stylebox_override("focus",   hover_sb)
	btn.add_theme_stylebox_override("pressed", normal_sb)

	var title_lbl := Label.new()
	title_lbl.offset_left          = 0.0
	title_lbl.offset_top           = 34.0
	title_lbl.offset_right         = 860.0
	title_lbl.offset_bottom        = 100.0
	title_lbl.text                 = "COMPUTER"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 56)
	title_lbl.add_theme_color_override("font_color", Color(0.88, 1.0, 0.90, 1))
	btn.add_child(title_lbl)

	var sub_lbl := Label.new()
	sub_lbl.offset_left          = 0.0
	sub_lbl.offset_top           = 102.0
	sub_lbl.offset_right         = 860.0
	sub_lbl.offset_bottom        = 136.0
	sub_lbl.text                 = "Try to win the AI opponent"
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	sub_lbl.add_theme_font_size_override("font_size", 22)
	sub_lbl.add_theme_color_override("font_color", Color(0.5, 0.78, 0.55, 0.85))
	btn.add_child(sub_lbl)

	btn.pressed.connect(_on_vs_ai_pressed)
	_wire_button_hover(btn)

	buttons_container.add_child(btn)


func _start_game_with_flash() -> void:
	# Fade to black before switching to the game scene.
	_starting = true
	var flash := ColorRect.new()
	flash.color = Color(0, 0, 0, 0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.anchor_right = 1.0
	flash.anchor_bottom = 1.0
	add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "color:a", 1.0, 0.28)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): get_tree().change_scene_to_file("res://scenes/main.tscn"))
