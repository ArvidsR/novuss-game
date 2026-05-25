extends CanvasLayer

# This file builds and updates the match HUD.
# It also shows foul animations, debt discs, and the winner screen.
const RED_ACCENT    := Color(0.95, 0.27, 0.32)
const BLACK_ACCENT  := Color(0.85, 0.86, 0.94)
const DIM_GLOW      := 0.12
const PULSE_LOW     := 0.45
const PULSE_HIGH    := 1.0
const PULSE_TIME    := 0.9
const INACTIVE_BADGE_ALPHA := 0.4
const ACTIVE_BADGE_ALPHA   := 1.0

const RED_DISC_TEX:   Texture2D = preload("res://assets/red_piece.png")
const BLACK_DISC_TEX: Texture2D = preload("res://assets/black_piece.png")

# Debt icons are drawn in the extra space below each panel.
const DEBT_ICON_SIZE    := 40.0
const DEBT_ICON_STRIDE  := 44.0
const DEBT_ICON_START_X := 46.0
const DEBT_ICON_Y       := 164.0
const DEBT_MAX_ICONS    := 8

@onready var top_panel:      Panel      = $TopPanel
@onready var top_name:       Label      = $TopPanel/NameLabel
@onready var top_sub:        Label      = $TopPanel/SubLabel
@onready var top_score:      Label      = $TopPanel/Score
@onready var top_disc_count: Label      = $TopPanel/DiscCount
@onready var top_score_bg:   Panel      = $TopPanel/ScoreBg
@onready var top_glow:       ColorRect  = $TopPanel/Glow
@onready var top_badge:      TextureRect = $TopPanel/ColorBadge
@onready var top_accent:     ColorRect  = $TopPanel/TopAccent
@onready var top_dark_pill:  Panel      = $TopPanel/DarkPill
@onready var top_dark_icon:  Panel      = $TopPanel/DarkPill/DarkIcon
@onready var top_dark_count: Label      = $TopPanel/DarkPill/DarkCount

@onready var bottom_panel:      Panel      = $BottomPanel
@onready var bottom_name:       Label      = $BottomPanel/NameLabel
@onready var bottom_sub:        Label      = $BottomPanel/SubLabel
@onready var bottom_score:      Label      = $BottomPanel/Score
@onready var bottom_disc_count: Label      = $BottomPanel/DiscCount
@onready var bottom_score_bg:   Panel      = $BottomPanel/ScoreBg
@onready var bottom_glow:       ColorRect  = $BottomPanel/Glow
@onready var bottom_badge:      TextureRect = $BottomPanel/ColorBadge
@onready var bottom_accent:     ColorRect  = $BottomPanel/TopAccent
@onready var bottom_dark_pill:  Panel      = $BottomPanel/DarkPill
@onready var bottom_dark_icon:  Panel      = $BottomPanel/DarkPill/DarkIcon
@onready var bottom_dark_count: Label      = $BottomPanel/DarkPill/DarkCount

var _top_highlight:    Panel
var _bottom_highlight: Panel
var _turn_arrow_top:   Label
var _turn_arrow_bottom: Label
var _top_set_dots:    Array = []
var _bottom_set_dots: Array = []
var _active_team:     int   = 0

@onready var foul_label:      Label   = $FoulLabel
@onready var winner_overlay:  Control = $WinnerOverlay
@onready var winner_disc:     TextureRect = $WinnerOverlay/Center/WinnerDisc
@onready var winner_glow:     TextureRect = $WinnerOverlay/Glow
@onready var winner_title:    Label   = $WinnerOverlay/Center/Title
@onready var winner_subtitle: Label   = $WinnerOverlay/Center/Subtitle
@onready var restart_button:  Button  = $WinnerOverlay/Center/RestartButton
@onready var menu_button:     Button  = $WinnerOverlay/Center/MenuButton

signal restart_requested
signal new_match_requested
signal menu_requested
signal penalty_animation_done

var _pulse_tween: Tween
var _num_players  := 2
var _single_color := 1
var _is_match_win := false

var _foul_card:        Panel
var _foul_card_title:  Label
var _penalty_row:      Control
var _penalty_disc_icon: TextureRect
var _flying_disc:      Sprite2D
var _top_debt_icons:    Array = []
var _bottom_debt_icons: Array = []
var _foul_note_label:  Label
var _top_last_shot_foul: Label
var _bottom_last_shot_foul: Label

func _ready() -> void:
	# Prepare HUD elements before the match starts.
	winner_overlay.hide()
	foul_label.hide()
	top_dark_pill.hide()
	bottom_dark_pill.hide()
	top_dark_icon.modulate   = BLACK_ACCENT
	bottom_dark_icon.modulate = RED_ACCENT
	restart_button.pressed.connect(_on_restart_pressed)
	menu_button.pressed.connect(func(): menu_requested.emit())
	_expand_panels()
	_create_highlight_overlays()
	_create_turn_arrows()
	_create_debt_rows()
	_create_last_shot_foul_labels()
	_create_foul_card()
	_create_flying_disc()
	_create_foul_note()
	set_active_player(1)
	update_score(0, 0)
	update_dark_count(0, 0)


func _on_restart_pressed() -> void:
	if _is_match_win:
		new_match_requested.emit()
	else:
		restart_requested.emit()

# =============================================================================
# PANEL EXPANSION — adds 26 px to each panel for the debt icon row
# =============================================================================

func _expand_panels() -> void:
	const EXTRA      := 48.0
	const SCORE_GAP  := 6.0
	# Stretch both score panels a little lower.
	top_panel.size = Vector2(top_panel.size.x, top_panel.size.y + EXTRA)
	bottom_panel.position = Vector2(bottom_panel.position.x, bottom_panel.position.y - EXTRA)
	bottom_panel.size     = Vector2(bottom_panel.size.x,     bottom_panel.size.y + EXTRA)
	top_score_bg.position = Vector2(top_score_bg.position.x, SCORE_GAP)
	top_score_bg.size     = Vector2(top_score_bg.size.x, top_panel.size.y - SCORE_GAP * 2)
	bottom_score_bg.position = Vector2(bottom_score_bg.position.x, SCORE_GAP)
	bottom_score_bg.size     = Vector2(bottom_score_bg.size.x, bottom_panel.size.y - SCORE_GAP * 2)

# =============================================================================
# HIGHLIGHT OVERLAYS — subtle brightness lift on the active panel
# =============================================================================

func _create_highlight_overlays() -> void:
	_top_highlight    = _make_highlight_overlay(top_panel)
	_bottom_highlight = _make_highlight_overlay(bottom_panel)

func _make_highlight_overlay(panel: Panel) -> Panel:
	# This bright layer fades in on the active side.
	var overlay := Panel.new()
	overlay.position     = Vector2.ZERO
	overlay.size         = panel.size
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.modulate.a   = 0.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 1.0, 1.0, 0.07)
	sb.set_corner_radius_all(26)
	overlay.add_theme_stylebox_override("panel", sb)
	panel.add_child(overlay)
	panel.move_child(overlay, 0)
	return overlay

# =============================================================================
# TURN ARROWS — glowing chevron pointing toward the board from active panel
# =============================================================================

func _create_turn_arrows() -> void:
	# Top panel faces downward toward the board
	_turn_arrow_top = _make_turn_arrow("▼", Vector2(0.0, top_panel.position.y + top_panel.size.y + 2.0))
	# Bottom panel faces upward toward the board (positioned after _expand_panels shifts it)
	_turn_arrow_bottom = _make_turn_arrow("▲", Vector2(0.0, bottom_panel.position.y - 32.0))

func _make_turn_arrow(glyph: String, pos: Vector2) -> Label:
	# Small arrow that points from the active panel to the board.
	var lbl := Label.new()
	lbl.text     = glyph
	lbl.position = pos
	lbl.size     = Vector2(1080.0, 30.0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	lbl.modulate.a = 0.0
	add_child(lbl)
	return lbl

# =============================================================================
# SET-PROGRESS DOTS — visual match progress below the sets number
# =============================================================================

const DOT_SIZE   := 36.0
const DOT_GAP    := 12.0
const DOT_Y      := 54.0
const SCORE_LEFT := 640.0
const SCORE_W    := 370.0

func _create_set_dots() -> void:
	for d in _top_set_dots:
		d.queue_free()
	for d in _bottom_set_dots:
		d.queue_free()
	_top_set_dots.clear()
	_bottom_set_dots.clear()

	# Show how many sets are needed to win the match.
	var wins_needed  := (GameSettings.best_of + 1) / 2
	var total_w      := wins_needed * DOT_SIZE + maxf(0.0, wins_needed - 1.0) * DOT_GAP
	var start_x      := SCORE_LEFT + (SCORE_W - total_w) * 0.5

	for i in wins_needed:
		var x := start_x + i * (DOT_SIZE + DOT_GAP)
		_top_set_dots.append(_make_dot(top_panel,    x, DOT_Y))
		_bottom_set_dots.append(_make_dot(bottom_panel, x, DOT_Y))

func _make_dot(panel: Panel, x: float, y: float) -> Panel:
	var dot := Panel.new()
	dot.size         = Vector2(DOT_SIZE, DOT_SIZE)
	dot.position     = Vector2(x, y)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 1.0, 1.0, 0.18)
	sb.set_corner_radius_all(DOT_SIZE / 2)
	panel.add_child(dot)
	dot.add_theme_stylebox_override("panel", sb)
	return dot

func _update_set_dots(top_sets: int, bottom_sets: int) -> void:
	var top_color    := BLACK_ACCENT
	var bottom_color := RED_ACCENT
	if _num_players == 1:
		top_color    = RED_ACCENT if _single_color == 1 else BLACK_ACCENT
		bottom_color = top_color
	_fill_dots(_top_set_dots,    top_sets,    top_color)
	_fill_dots(_bottom_set_dots, bottom_sets, bottom_color)

func _fill_dots(dots: Array, filled: int, color: Color) -> void:
	for i in dots.size():
		var sb := (dots[i] as Panel).get_theme_stylebox("panel") as StyleBoxFlat
		sb.bg_color = Color(color.r, color.g, color.b, 0.88) if i < filled else Color(1, 1, 1, 0.18)

# =============================================================================
# DEBT ICON ROWS
# =============================================================================

func _create_debt_rows() -> void:
	_create_icons_for_panel(top_panel,    _top_debt_icons,    BLACK_DISC_TEX)
	_create_icons_for_panel(bottom_panel, _bottom_debt_icons, RED_DISC_TEX)

func _create_icons_for_panel(panel: Panel, icons: Array, tex: Texture2D) -> void:
	# Prebuild empty debt slots so they can fade in fast.
	for i in DEBT_MAX_ICONS:
		var icon := TextureRect.new()
		icon.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
		icon.texture      = tex
		icon.size         = Vector2(DEBT_ICON_SIZE, DEBT_ICON_SIZE)
		icon.position     = Vector2(DEBT_ICON_START_X + i * DEBT_ICON_STRIDE, DEBT_ICON_Y)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.modulate.a   = 0.0
		panel.add_child(icon)
		icons.append(icon)

func _create_last_shot_foul_labels() -> void:
	_top_last_shot_foul = _create_last_shot_foul_label(top_panel, BLACK_ACCENT)
	_bottom_last_shot_foul = _create_last_shot_foul_label(bottom_panel, RED_ACCENT)

func _create_last_shot_foul_label(panel: Panel, accent: Color) -> Label:
	var label := Label.new()
	label.text = "FOUL"
	label.size = Vector2(302.0, 32.0)
	label.position = Vector2(118.0, 124.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.36, 1.0))
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_color_override("font_outline_color", Color(0.12, 0.07, 0.02, 1.0))

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(accent.r, accent.g, accent.b, 0.18)
	sb.border_color = Color(1.0, 0.78, 0.25, 0.72)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	label.add_theme_stylebox_override("normal", sb)
	label.hide()
	panel.add_child(label)
	return label

func update_debt_display(red_debt: int, black_debt: int) -> void:
	_update_panel_debt(_bottom_debt_icons, red_debt)
	_update_panel_debt(_top_debt_icons,    black_debt)

func _update_panel_debt(icons: Array, count: int) -> void:
	# Show or hide debt icons to match the current debt count.
	for i in icons.size():
		var icon: TextureRect = icons[i]
		var should_show := i < count
		if should_show and icon.modulate.a < 0.5:
			icon.scale        = Vector2(0.5, 0.5)
			icon.pivot_offset = icon.size * 0.5
			var tw := create_tween().set_parallel(true)
			tw.tween_property(icon, "modulate:a", 1.0, 0.20)
			tw.tween_property(icon, "scale", Vector2.ONE, 0.28)\
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		elif not should_show and icon.modulate.a > 0.0:
			create_tween().tween_property(icon, "modulate:a", 0.0, 0.15)

# Used when a penalty disc animation must land exactly on a debt slot.
func get_debt_target_pos(disc_color: int, n: int) -> Vector2:
	var panel: Panel = bottom_panel if disc_color == 1 else top_panel
	var local_center := Vector2(
		DEBT_ICON_START_X + n * DEBT_ICON_STRIDE + DEBT_ICON_SIZE * 0.5,
		DEBT_ICON_Y + DEBT_ICON_SIZE * 0.5
	)
	return panel.position + local_center

func animate_debt_disc_to_field(disc_color: int, debt_index: int, target_pos: Vector2, arrived: Callable) -> void:
	# Fly one debt disc from the HUD into the board.
	var tex := RED_DISC_TEX if disc_color == 1 else BLACK_DISC_TEX
	var disc := Sprite2D.new()
	disc.texture = tex
	disc.position = get_debt_target_pos(disc_color, debt_index)
	disc.scale = Vector2(0.021, 0.021)
	disc.modulate.a = 1.0
	add_child(disc)

	var fly := create_tween()
	fly.tween_property(disc, "position", target_pos, 0.85)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	fly.tween_callback(func() -> void:
		if arrived.is_valid():
			arrived.call()
	)
	fly.tween_property(disc, "modulate:a", 0.0, 0.18)
	fly.tween_callback(disc.queue_free)

# =============================================================================
# FOUL CARD + FLYING DISC
# =============================================================================

func _create_foul_card() -> void:
	# Build the popup that appears after a foul.
	const W := 560.0
	const H := 210.0

	_foul_card          = Panel.new()
	_foul_card.size     = Vector2(W, H)
	_foul_card.position = Vector2((1080.0 - W) * 0.5, 840.0)
	_foul_card.pivot_offset = Vector2(W * 0.5, H * 0.5)
	_foul_card.modulate.a   = 0.0

	var sb := StyleBoxFlat.new()
	sb.bg_color     = Color(0.06, 0.04, 0.04, 0.95)
	sb.border_color = Color(0.80, 0.18, 0.20, 0.88)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(26)
	sb.shadow_color  = Color(0.0, 0.0, 0.0, 0.60)
	sb.shadow_size   = 20
	sb.shadow_offset = Vector2(0.0, 6.0)
	_foul_card.add_theme_stylebox_override("panel", sb)
	add_child(_foul_card)

	# Large "FOUL" title
	_foul_card_title = Label.new()
	_foul_card_title.text = "FOUL"
	_foul_card_title.size     = Vector2(W, 122.0)
	_foul_card_title.position = Vector2(0.0, 6.0)
	_foul_card_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_foul_card_title.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_foul_card_title.add_theme_font_size_override("font_size", 100)
	_foul_card_title.add_theme_color_override("font_color", Color(1.0, 0.28, 0.28, 1.0))
	_foul_card_title.add_theme_constant_override("outline_size", 10)
	_foul_card_title.add_theme_color_override("font_outline_color", Color(0.18, 0.03, 0.03, 1.0))
	_foul_card.add_child(_foul_card_title)

	# Penalty row (disc icon + "PENALTY" label)
	_penalty_row          = Control.new()
	_penalty_row.size     = Vector2(W, 80.0)
	_penalty_row.position = Vector2(0.0, 122.0)
	_foul_card.add_child(_penalty_row)

	# Disc icon — centered group starts at x=145
	_penalty_disc_icon              = TextureRect.new()
	_penalty_disc_icon.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	_penalty_disc_icon.size         = Vector2(58.0, 58.0)
	_penalty_disc_icon.position     = Vector2(145.0, 11.0)
	_penalty_disc_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_penalty_row.add_child(_penalty_disc_icon)

	# "PENALTY" label — 12 px gap after disc
	var pen_lbl := Label.new()
	pen_lbl.text     = "PENALTY"
	pen_lbl.size     = Vector2(220.0, 58.0)
	pen_lbl.position = Vector2(215.0, 11.0)
	pen_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	pen_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	pen_lbl.add_theme_font_size_override("font_size", 36)
	pen_lbl.add_theme_color_override("font_color", Color(0.95, 0.88, 0.78, 1.0))
	pen_lbl.add_theme_constant_override("outline_size", 4)
	pen_lbl.add_theme_color_override("font_outline_color", Color(0.12, 0.07, 0.04, 1.0))
	_penalty_row.add_child(pen_lbl)

func _create_flying_disc() -> void:
	# This sprite is reused for penalty flight animation.
	_flying_disc           = Sprite2D.new()
	_flying_disc.scale     = Vector2(0.021, 0.021)
	_flying_disc.modulate.a = 0.0
	add_child(_flying_disc)

# Foul without penalty disc — card pops in and auto-fades.
func show_foul() -> void:
	_penalty_row.hide()
	_foul_card.modulate.a   = 0.0
	_foul_card.scale        = Vector2(0.65, 0.65)
	_foul_card.pivot_offset = _foul_card.size * 0.5
	_foul_card.show()

	var pop := create_tween().set_parallel(true)
	pop.tween_property(_foul_card, "modulate:a", 1.0, 0.22)
	pop.tween_property(_foul_card, "scale", Vector2.ONE, 0.30)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var fade := create_tween()
	fade.tween_interval(1.0)
	fade.tween_property(_foul_card, "modulate:a", 0.0, 0.4)

func show_last_shot_foul(player: int) -> void:
	# Mark the side that committed the last foul.
	hide_last_shot_foul()
	var team := _player_team(player)
	var label: Label = _bottom_last_shot_foul if team == 1 else _top_last_shot_foul
	label.text = "P%d FOUL" % player if _num_players == 4 else "FOUL"
	label.modulate.a = 0.0
	label.scale = Vector2(0.86, 0.86)
	label.pivot_offset = label.size * 0.5
	label.show()

	var tw := create_tween().set_parallel(true)
	tw.tween_property(label, "modulate:a", 1.0, 0.18)
	tw.tween_property(label, "scale", Vector2.ONE, 0.24)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func hide_last_shot_foul() -> void:
	if _top_last_shot_foul:
		_top_last_shot_foul.hide()
	if _bottom_last_shot_foul:
		_bottom_last_shot_foul.hide()

# Foul with penalty disc — card pops in, disc flies to target, emits signal.
# target_pos is the screen-space CENTER where the disc should land (~3 s total).
func show_foul_with_penalty(disc_color: int, target_pos: Vector2, landing_size: float = 40.0) -> void:
	var tex := RED_DISC_TEX if disc_color == 1 else BLACK_DISC_TEX
	_penalty_disc_icon.texture = tex
	_penalty_disc_icon.show()
	_flying_disc.texture       = tex
	_penalty_row.show()

	_foul_card.modulate.a   = 0.0
	_foul_card.scale        = Vector2(0.65, 0.65)
	_foul_card.pivot_offset = _foul_card.size * 0.5
	_foul_card.show()

	var pop := create_tween().set_parallel(true)
	pop.tween_property(_foul_card, "modulate:a", 1.0, 0.25)
	pop.tween_property(_foul_card, "scale", Vector2.ONE, 0.32)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# 0.8 s hold → launch disc (total: 0.8 + 2.0 = 2.8 s ≈ 3 s)
	var seq := create_tween()
	seq.tween_interval(0.8)
	seq.tween_callback(_launch_disc.bind(target_pos, landing_size))

func _launch_disc(target_pos: Vector2, _landing_size: float) -> void:
	# The static icon hands off to the Sprite2D — hide it to avoid a double.
	_penalty_disc_icon.hide()

	# Start exactly at the card's disc icon center at real-disc size.
	var icon_center := _foul_card.position + _penalty_row.position \
		+ _penalty_disc_icon.position + _penalty_disc_icon.size * 0.5
	_flying_disc.position   = icon_center
	_flying_disc.scale      = Vector2(0.021, 0.021)
	_flying_disc.modulate.a = 1.0

	create_tween().tween_property(_foul_card, "modulate:a", 0.0, 0.42)

	var fly := create_tween()
	fly.tween_property(_flying_disc, "position", target_pos, 2.0)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	fly.tween_callback(_on_disc_arrived)

func _on_disc_arrived() -> void:
	penalty_animation_done.emit()
	var fade := create_tween()
	fade.tween_interval(0.15)
	fade.tween_property(_flying_disc, "modulate:a", 0.0, 0.28)

# =============================================================================
# MODE / PLAYER SETUP
# =============================================================================

func set_mode(num_players: int, single_color: int = 1) -> void:
	# Update labels and colors for the selected game mode.
	_num_players  = num_players
	_single_color = single_color

	top_disc_count.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	top_disc_count.add_theme_color_override("font_outline_color", BLACK_ACCENT)
	top_disc_count.add_theme_constant_override("outline_size", 6)
	bottom_disc_count.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	bottom_disc_count.add_theme_color_override("font_outline_color", RED_ACCENT)
	bottom_disc_count.add_theme_constant_override("outline_size", 6)
	_create_set_dots()

	if num_players == 1:
		if single_color == 1:
			top_panel.hide()
			bottom_panel.show()
			bottom_name.text = "PLAYER 1"
			bottom_sub.text  = "RED"
			bottom_sub.add_theme_color_override("font_color", RED_ACCENT)
			bottom_badge.texture  = RED_DISC_TEX
			bottom_accent.color   = RED_ACCENT
			bottom_glow.color     = RED_ACCENT
		else:
			bottom_panel.hide()
			top_panel.show()
			top_name.text = "PLAYER 1"
			top_sub.text  = "BLACK"
			top_sub.add_theme_color_override("font_color", BLACK_ACCENT)
			top_badge.texture  = BLACK_DISC_TEX
			top_accent.color   = BLACK_ACCENT
			top_glow.color     = BLACK_ACCENT
	elif num_players == 2:
		top_panel.show()
		bottom_panel.show()
		top_name.text = "AI" if GameSettings.ai_enabled else "PLAYER 2"
		top_sub.text  = "BLACK"
		top_sub.add_theme_color_override("font_color", BLACK_ACCENT)
		top_badge.texture  = BLACK_DISC_TEX
		top_accent.color   = BLACK_ACCENT
		top_glow.color     = BLACK_ACCENT
		bottom_name.text = "PLAYER 1"
		bottom_sub.text  = "RED"
		bottom_sub.add_theme_color_override("font_color", RED_ACCENT)
		bottom_badge.texture  = RED_DISC_TEX
		bottom_accent.color   = RED_ACCENT
		bottom_glow.color     = RED_ACCENT
	else:
		top_panel.show()
		bottom_panel.show()
		top_name.text = "BLACK TEAM"
		top_sub.text  = "P2 + P4"
		top_sub.add_theme_color_override("font_color", BLACK_ACCENT)
		top_badge.texture  = BLACK_DISC_TEX
		top_accent.color   = BLACK_ACCENT
		top_glow.color     = BLACK_ACCENT
		bottom_name.text = "RED TEAM"
		bottom_sub.text  = "P1 + P3"
		bottom_sub.add_theme_color_override("font_color", RED_ACCENT)
		bottom_badge.texture  = RED_DISC_TEX
		bottom_accent.color   = RED_ACCENT
		bottom_glow.color     = RED_ACCENT

func _player_team(player: int) -> int:
	if _num_players == 1:
		return _single_color
	elif _num_players == 2:
		return player
	else:
		return 1 if player % 2 == 1 else 2

func set_active_player(player: int) -> void:
	# Highlight the side that should play now.
	if _num_players == 1:
		var only_glow:  ColorRect   = bottom_glow  if _single_color == 1 else top_glow
		var only_badge: TextureRect = bottom_badge if _single_color == 1 else top_badge
		if _pulse_tween and _pulse_tween.is_valid():
			_pulse_tween.kill()
		only_glow.modulate.a  = PULSE_HIGH
		only_badge.modulate.a = ACTIVE_BADGE_ALPHA
		_pulse_tween = create_tween().set_loops()
		_pulse_tween.tween_property(only_glow, "modulate:a", PULSE_LOW,  PULSE_TIME)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_pulse_tween.tween_property(only_glow, "modulate:a", PULSE_HIGH, PULSE_TIME)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		var only_hl := _bottom_highlight if _single_color == 1 else _top_highlight
		create_tween().tween_property(only_hl, "modulate:a", 1.0, 0.3)
		_turn_arrow_top.modulate.a    = 0.0
		_turn_arrow_bottom.modulate.a = 0.0
		return

	var team := _player_team(player)
	var active_glow:   ColorRect   = bottom_glow  if team == 1 else top_glow
	var inactive_glow: ColorRect   = top_glow     if team == 1 else bottom_glow
	var active_badge:  TextureRect = bottom_badge if team == 1 else top_badge
	var inactive_badge:TextureRect = top_badge    if team == 1 else bottom_badge
	var active_name:   Label       = bottom_name  if team == 1 else top_name

	inactive_glow.modulate.a  = DIM_GLOW
	inactive_badge.modulate.a = INACTIVE_BADGE_ALPHA
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()
	active_glow.modulate.a  = PULSE_HIGH
	active_badge.modulate.a = ACTIVE_BADGE_ALPHA
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_property(active_glow, "modulate:a", PULSE_LOW,  PULSE_TIME)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.tween_property(active_glow, "modulate:a", PULSE_HIGH, PULSE_TIME)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	if _num_players == 4:
		active_name.text = ("RED TEAM — P%d" % player) if team == 1 else ("BLACK TEAM — P%d" % player)

	# Highlight overlay
	var active_hl   := _bottom_highlight if team == 1 else _top_highlight
	var inactive_hl := _top_highlight    if team == 1 else _bottom_highlight
	create_tween().tween_property(active_hl,   "modulate:a", 1.0, 0.3)
	create_tween().tween_property(inactive_hl, "modulate:a", 0.0, 0.3)

	# Turn arrow
	var arrow_color   := RED_ACCENT   if team == 1 else BLACK_ACCENT
	var active_arrow  := _turn_arrow_bottom if team == 1 else _turn_arrow_top
	var inactive_arrow := _turn_arrow_top   if team == 1 else _turn_arrow_bottom
	active_arrow.add_theme_color_override("font_color", arrow_color)
	create_tween().tween_property(active_arrow,   "modulate:a", 1.0, 0.25)
	create_tween().tween_property(inactive_arrow, "modulate:a", 0.0, 0.2)

	# In 4-player mode this helps show which player on the team is active.
	if team != _active_team and _active_team != 0:
		var orig_x := active_name.position.x
		active_name.position.x = orig_x - 22.0
		create_tween().tween_property(active_name, "position:x", orig_x, 0.22)\
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_active_team = team

# =============================================================================
# SCORE / DARK COUNT
# =============================================================================

func update_score(red_left: int, black_left: int, red_debt: int = 0, black_debt: int = 0,
		red_sets: int = 0, black_sets: int = 0) -> void:
	if _num_players == 1:
		var disc_label := bottom_disc_count if _single_color == 1 else top_disc_count
		var disc_val   := red_left          if _single_color == 1 else black_left
		var sets_val   := red_sets          if _single_color == 1 else black_sets
		_bump_label(disc_label, str(disc_val))
		_update_set_dots(sets_val if _single_color == 2 else 0,
		                 sets_val if _single_color == 1 else 0)
	else:
		_bump_label(bottom_disc_count, str(red_left))
		_bump_label(top_disc_count,    str(black_left))
		_update_set_dots(black_sets, red_sets)
	update_debt_display(red_debt, black_debt)

func _bump_label(label: Label, new_text: String) -> void:
	# Animate score text when the value changes.
	if label.text == new_text:
		return
	label.text         = new_text
	label.pivot_offset = label.size * 0.5
	label.scale        = Vector2(1.45, 1.45)
	var tw := create_tween()
	tw.tween_property(label, "scale", Vector2.ONE, 0.28)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func update_dark_count(red_count: int, black_count: int) -> void:
	_set_dark_pill(bottom_dark_pill, bottom_dark_count, red_count)
	_set_dark_pill(top_dark_pill,    top_dark_count,    black_count)

func _set_dark_pill(pill: Panel, count_label: Label, count: int) -> void:
	# Show the dark-disc counter only when it is needed.
	if count <= 0:
		pill.hide()
		return
	var was_hidden := not pill.visible
	count_label.text = str(count)
	pill.show()
	if was_hidden:
		pill.modulate.a   = 0.0
		pill.scale        = Vector2(0.85, 0.85)
		pill.pivot_offset = pill.size * 0.5
		var tw := create_tween().set_parallel(true)
		tw.tween_property(pill, "modulate:a", 1.0, 0.22)
		tw.tween_property(pill, "scale", Vector2.ONE, 0.28)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		count_label.pivot_offset = count_label.size * 0.5
		count_label.scale        = Vector2(1.35, 1.35)
		create_tween().tween_property(count_label, "scale", Vector2.ONE, 0.22)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# =============================================================================
# WINNER OVERLAY
# =============================================================================

func _create_foul_note() -> void:
	_foul_note_label = Label.new()
	_foul_note_label.text = "foul on last shot"
	_foul_note_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_foul_note_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_foul_note_label.custom_minimum_size = Vector2(0, 42)
	_foul_note_label.add_theme_font_size_override("font_size", 30)
	_foul_note_label.add_theme_color_override("font_color", Color(0.95, 0.78, 0.30, 0.90))
	_foul_note_label.add_theme_constant_override("outline_size", 4)
	_foul_note_label.add_theme_color_override("font_outline_color", Color(0.12, 0.08, 0.01, 1.0))
	_foul_note_label.hide()
	var center := winner_subtitle.get_parent()
	center.add_child(_foul_note_label)
	center.move_child(_foul_note_label, winner_subtitle.get_index() + 1)


func show_winner(winner: int, red_sets: int, black_sets: int, is_match_win: bool, had_foul: bool = false) -> void:
	# Fill the winner panel with the final result text.
	# Dismiss any lingering foul card immediately.
	_foul_card.modulate.a = 0.0
	_foul_card.hide()
	hide_last_shot_foul()
	if had_foul:
		_foul_note_label.show()
	else:
		_foul_note_label.hide()

	_is_match_win = is_match_win
	var is_red    := winner == 1 if _num_players != 1 else _single_color == 1
	var accent    := RED_ACCENT   if is_red else BLACK_ACCENT
	var disc_tex  := RED_DISC_TEX if is_red else BLACK_DISC_TEX

	if _num_players == 1:
		var my_sets := red_sets if _single_color == 1 else black_sets
		var best_of := GameSettings.best_of
		if is_match_win:
			winner_title.text    = "MATCH COMPLETE"
			winner_subtitle.text = "Best of %d — You won!" % best_of
			restart_button.text  = "PLAY AGAIN"
		else:
			winner_title.text    = "SET COMPLETE"
			winner_subtitle.text = "Set %d of %d" % [my_sets, best_of]
			restart_button.text  = "NEXT SET"
	elif is_match_win:
		var w_sets := red_sets   if is_red else black_sets
		var l_sets := black_sets if is_red else red_sets
		if _num_players == 4:
			winner_title.text = "RED TEAM WINS!" if is_red else "BLACK TEAM WINS!"
		else:
			winner_title.text = "RED WINS!" if is_red else "BLACK WINS!"
		winner_subtitle.text = "%d — %d" % [w_sets, l_sets]
		restart_button.text  = "PLAY AGAIN"
	else:
		var w_sets := red_sets   if is_red else black_sets
		var l_sets := black_sets if is_red else red_sets
		if _num_players == 4:
			winner_title.text = "RED TEAM WINS SET" if is_red else "BLACK TEAM WINS SET"
		else:
			winner_title.text = "RED WINS SET" if is_red else "BLACK WINS SET"
		winner_subtitle.text = "%d — %d" % [w_sets, l_sets]
		restart_button.text  = "NEXT SET"

	winner_title.add_theme_color_override("font_color", accent)
	winner_disc.texture      = disc_tex
	winner_glow.modulate     = Color(accent.r, accent.g, accent.b, 1.0)
	winner_overlay.modulate.a = 0.0
	winner_overlay.show()
	create_tween().tween_property(winner_overlay, "modulate:a", 1.0, 0.45)
	winner_disc.pivot_offset = winner_disc.size * 0.5
	winner_disc.scale        = Vector2(0.5, 0.5)
	create_tween().tween_property(winner_disc, "scale", Vector2.ONE, 0.55)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func hide_winner() -> void:
	winner_overlay.hide()
	hide_last_shot_foul()
