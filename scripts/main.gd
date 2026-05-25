extends Node

const SetFlowState = preload("res://scripts/set_flow_state.gd")

# This file controls the full match
# It spawns pieces, handles turns, checks fouls, and updates the HUD
@export var red_disc_scene: PackedScene
@export var black_disc_scene: PackedScene
@export var puck_scene: PackedScene

const DISC_DIAMETER := 32
const DISC_SPACING := 33
const DISCS_PER_SIDE := 8

const TABLE_MIN := Vector2(70, 607)
const TABLE_MAX := Vector2(1012, 1549)

const TOP_ROW_Y := 620
const BOTTOM_ROW_Y := 1535
const LEFT_COL_X := 84
const RIGHT_COL_X := 998
const ROW_START_X := 426
const COL_START_Y := 962.5

# Center between 4th (i=3) and 5th (i=4) disc on a starting line:
#   row: 426 + 3.5 * 33 = 541.5
#   col: 962.5 + 3.5 * 33 = 1078.0
const ROW_CENTER_X := 541.5
const COL_CENTER_Y := 1078.0

# Center circle - measured from table PNG (1920×1920) scaled at 0.55
const CIRCLE_CENTER := Vector2(541.0, 1078.0)
const CIRCLE_RADIUS := 117.2

const START_POSITION_PLAYER_1 := Vector2(198.5, 1430)
const START_POSITION_PLAYER_2 := Vector2(198.5, 725)
const START_POSITION_4P_P1 := Vector2(198.5, 1431)
const START_POSITION_4P_P2 := Vector2(894, 736)
const START_POSITION_4P_P3 := Vector2(198.5, 725)
const START_POSITION_4P_P4 := Vector2(188, 736)

const BOUNDS_P1 := Rect2(Vector2(198.5, 1431), Vector2(684.5, 65))
const BOUNDS_P2 := Rect2(Vector2(198.5, 660),  Vector2(684.5, 65))
const BOUNDS_4P_P1 := Rect2(Vector2(198.5, 1431), Vector2(684.5, 65))
const BOUNDS_4P_P2 := Rect2(Vector2(894, 736),   Vector2(65, 684))
const BOUNDS_4P_P3 := Rect2(Vector2(198.5, 660), Vector2(684.5, 65))
const BOUNDS_4P_P4 := Rect2(Vector2(123, 736),   Vector2(65, 684))

const MAX_POWER := 30.0
const MOVE_THRESHOLD := 2.0
const WAIT_THRESHOLD := 0.03
const CLAMP_VELOCITY_DAMP := 0.1
const SLOW_DAMP_THRESHOLD := 200.0  # px/s - extra drag kicks in below this speed
const SLOW_EXTRA_DAMP := 5.0        # additional damping multiplier at low speeds

# Hole radii (world px) - used to determine when a boundary line is no longer
# visible through the hole(when a body has crossed a zone line)
const DISC_HOLE_RADIUS := 4.2   # measured: ~200px in 1920 image × scale 0.021
const PUCK_HOLE_RADIUS := 5.0   # measured: ~160px in 1920 image × scale 0.031

const PENALTY_STEP := 0.5
const PENALTY_MAX_DIST := 500.0

# Puck potting: center must cross inside the pocket visual edge (more than half over)
# Discs use the Area2D body_entered signal directly (radius 70 local = 38.5 world)
const POCKET_CENTERS := [
	Vector2(132.0, 669.0), Vector2(950.0, 669.0),
	Vector2(950.0, 1488.0), Vector2(132.0, 1488.0),
]
const PUCK_POCKET_RADIUS := 38.5  # world px - puck center must be within this

const RED_COLOR := Color(0.95, 0.27, 0.32)
const BLACK_COLOR := Color(0.18, 0.20, 0.26)

@onready var hud: CanvasLayer = $HUD
@onready var aim_line: Node2D = $AimLine
@onready var pocket_fx: Node2D = $PocketFX
@onready var cue: Sprite2D = $Cue
@onready var power_bar: ProgressBar = $PowerBar

var num_players := 2
var single_color := 1
var puck: RigidBody2D
var current_player := 1

var moving := false
var taking_shot := false
var shot_taken := false
var dragging_puck := false
var dragged_position: Vector2 = Vector2.ZERO

# These flags are reset every shot and checked when the shot ends
var puck_potted := false
var valid_hit := false
var first_hit_wrong := false
var first_hit_checked := false
var puck_hit_cushion := false
var puck_hit_opposite_wall := false  
var dark_disc_foul := false
var _directly_hit_opponent_ids: Array = []  # instance IDs of opponent discs puck contacted directly
var puck_left_zone := false      # puck has exited shooter's edge zone this shot
var puck_returned_to_zone := false  # puck re-entered shooter's edge zone after leaving
var _shot_has_dark_disc := false    # shooter had ≥1 dark disc when shot fired
var _shot_all_discs_dark := false   # ALL shooter's discs were dark when shot fired
var opponent_disc_potted := false    # an opponent disc was pocketed this shot
var penalty_animating := false       # true while penalty disc animation plays
var _pending_shooter  := 0
var _pending_keep_turn := false

var game_over := false
var disc_debt: Array = []         # pending penalties: [{color, fouler}, ...]
var _dark_disc_snapshots: Dictionary = {}  # instance_id → {node, position, color_group}
var _opponent_light_snapshots: Dictionary = {}  # opponent non-dark discs at shot time

var sets_red := 0
var sets_black := 0


var _ai_thinking := false
var ai_moving_puck := false
var _ai: AIPlayer
var _thinking_panel: Panel
var _thinking_text: Label
var _thinking_dots_timer := 0.0
var _thinking_dots_step := 0

var wait_time := 0.0

var _set_flow := SetFlowState.new()


func _ready() -> void:
	# Connect HUD buttons and pocket events
	$Table/Pockets.body_entered.connect(_on_potted)
	hud.restart_requested.connect(_on_restart)
	hud.new_match_requested.connect(_on_new_match)
	hud.menu_requested.connect(_on_menu_requested)
	hud.penalty_animation_done.connect(_on_penalty_animation_done)

	match GameSettings.mode:
		GameSettings.Mode.ONE_PLAYER:
			num_players = 1
			single_color = GameSettings.single_color
		GameSettings.Mode.TWO_PLAYER:
			num_players = 2
		GameSettings.Mode.FOUR_PLAYER:
			num_players = 4

	if GameSettings.ai_enabled and num_players == 2:
		# Create the AI helper only in AI mode
		_ai = AIPlayer.new()
		_ai.setup(self)
		add_child(_ai)

	# AI thinking card - shown while AI plans its shot
	const CARD_W := 480.0
	const CARD_H := 96.0
	_thinking_panel = Panel.new()
	_thinking_panel.size = Vector2(CARD_W, CARD_H)
	_thinking_panel.position = Vector2((1080.0 - CARD_W) * 0.5, 1078.0 - CARD_H * 0.5)
	_thinking_panel.pivot_offset = Vector2(CARD_W * 0.5, CARD_H * 0.5)
	var _tp_sb := StyleBoxFlat.new()
	_tp_sb.bg_color = Color(0.07, 0.06, 0.10, 0.92)
	_tp_sb.border_color = Color(0.85, 0.86, 0.94, 0.30)
	_tp_sb.set_border_width_all(1)
	_tp_sb.set_corner_radius_all(26)
	_tp_sb.shadow_color = Color(0.0, 0.0, 0.0, 0.50)
	_tp_sb.shadow_size = 16
	_tp_sb.shadow_offset = Vector2(0.0, 6.0)
	_thinking_panel.add_theme_stylebox_override("panel", _tp_sb)
	var _accent := ColorRect.new()
	_accent.size = Vector2(6.0, CARD_H - 34.0)
	_accent.position = Vector2(22.0, 17.0)
	_accent.color = Color(0.85, 0.86, 0.94, 0.70)
	_thinking_panel.add_child(_accent)
	_thinking_text = Label.new()
	_thinking_text.text = "THINKING"
	_thinking_text.size = Vector2(CARD_W - 56.0, CARD_H)
	_thinking_text.position = Vector2(48.0, 0.0)
	_thinking_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_thinking_text.add_theme_font_size_override("font_size", 40)
	_thinking_text.add_theme_color_override("font_color", Color(0.92, 0.92, 0.96, 1.0))
	_thinking_text.add_theme_constant_override("outline_size", 0)
	_thinking_panel.add_child(_thinking_text)
	_thinking_panel.hide()
	$HUD.add_child(_thinking_panel)
	call_deferred("_fit_thinking_panel")

	hud.set_mode(num_players, single_color)
	new_game()

func _fit_thinking_panel() -> void:
	var font := _thinking_text.get_theme_font("font")
	var text_w: float = font.get_string_size("THINKING...", HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	var new_w: float = text_w + 72.0
	_thinking_panel.size.x = new_w
	_thinking_panel.position.x = (1080.0 - new_w) * 0.5
	_thinking_panel.pivot_offset.x = new_w * 0.5
	_thinking_text.size.x = text_w + 4.0

func new_game() -> void:
	# Reset the board for a new set
	game_over = false
	_ai_thinking = false
	current_player = _set_flow.next_set_starter
	_set_flow.reset_for_new_set(current_player, num_players)
	dragged_position = Vector2.ZERO
	_reset_shot_flags()
	taking_shot = false
	shot_taken = false
	# sets_red / sets_black are intentionally NOT reset here - they persist across sets
	moving = false
	wait_time = 0.0
	disc_debt.clear()
	clear_discs()
	generate_discs()
	reset_puck()
	show_cue()
	hud.set_active_player(current_player)
	_update_score_hud()
	hud.hide_winner()

func _reset_shot_flags() -> void:
	# Clear all shot result flags before the next turn
	puck_potted = false
	valid_hit = false
	first_hit_wrong = false
	first_hit_checked = false
	puck_hit_cushion = false
	puck_hit_opposite_wall = false
	dark_disc_foul = false
	_directly_hit_opponent_ids.clear()
	puck_left_zone = false
	puck_returned_to_zone = false
	_shot_has_dark_disc = false
	_shot_all_discs_dark = false
	opponent_disc_potted = false


# === DISC SPAWNING ===
func clear_discs() -> void:
	# Remove every live piece before making a new layout
	for group in ["all_red_discs", "all_black_discs"]:
		for disc in get_tree().get_nodes_in_group(group):
			disc.free()
	if puck and is_instance_valid(puck):
		puck.free()
	puck = null

func generate_discs() -> void:
	# Build the starting layout based on the selected mode
	if num_players == 1:
		if single_color == 1:
			_spawn_horizontal_row(red_disc_scene, "res://assets/red_piece.png", TOP_ROW_Y)
		else:
			_spawn_horizontal_row(black_disc_scene, "res://assets/black_piece.png", BOTTOM_ROW_Y)
	elif num_players == 2:
		_spawn_horizontal_row(red_disc_scene, "res://assets/red_piece.png", TOP_ROW_Y)
		_spawn_horizontal_row(black_disc_scene, "res://assets/black_piece.png", BOTTOM_ROW_Y)
	else:
		_spawn_horizontal_row(red_disc_scene, "res://assets/red_piece.png", TOP_ROW_Y)
		_spawn_horizontal_row(red_disc_scene, "res://assets/red_piece.png", BOTTOM_ROW_Y)
		_spawn_vertical_column(black_disc_scene, "res://assets/black_piece.png", LEFT_COL_X)
		_spawn_vertical_column(black_disc_scene, "res://assets/black_piece.png", RIGHT_COL_X)

func _spawn_horizontal_row(scene: PackedScene, texture_path: String, y: int) -> void:
	for i in DISCS_PER_SIDE:
		var disc := scene.instantiate()
		add_child(disc)
		disc.position = Vector2(ROW_START_X + i * DISC_SPACING, y)
		disc.get_node("Sprite2D").texture = load(texture_path)

func _spawn_vertical_column(scene: PackedScene, texture_path: String, x: int) -> void:
	for i in DISCS_PER_SIDE:
		var disc := scene.instantiate()
		add_child(disc)
		disc.position = Vector2(float(x), COL_START_Y + i * DISC_SPACING)
		disc.get_node("Sprite2D").texture = load(texture_path)


# === PUCK / CUE ===
func reset_puck() -> void:
	# Create a new striker for the current player.
	puck = puck_scene.instantiate()
	add_child(puck)
	if dragging_puck:
		puck.position = dragged_position
	else:
		puck.position = _current_start_position()
	dragged_position = Vector2.ZERO
	wait_time = 0.0
	puck.get_node("Sprite2D").texture = load("res://assets/striker1.png")
	taking_shot = false
	_reset_shot_flags()
	puck.contact_monitor = true
	puck.max_contacts_reported = 4
	puck.body_entered.connect(_on_puck_body_entered)

func remove_puck() -> void:
	if puck and is_instance_valid(puck):
		puck.queue_free()

func _aim_corners() -> Array:
	var tl := TABLE_MIN
	var tr := Vector2(TABLE_MAX.x, TABLE_MIN.y)
	var bl := Vector2(TABLE_MIN.x, TABLE_MAX.y)
	var br := TABLE_MAX
	if num_players == 1:
		return [bl, br] if single_color == 1 else [tr, tl]
	elif num_players == 2:
		return [bl, br] if current_player == 1 else [tr, tl]
	else:
		match current_player:
			1: return [bl, br]
			2: return [br, tr]
			3: return [tr, tl]
			4: return [tl, bl]
	return [bl, br]

func _update_cue_geometry(reset_aim: bool = false) -> void:
	if not (puck and is_instance_valid(puck)):
		return
	var corners := _aim_corners()
	cue.set_aim_geometry(puck.position, corners[0], corners[1], reset_aim)

func show_cue() -> void:
	# Show aiming only when the next shot is ready
	_update_cue_geometry(true)
	cue.set_process(true)
	cue.show()
	power_bar.position.x = puck.position.x - (0.5 * power_bar.size.x)
	power_bar.position.y = puck.position.y + power_bar.size.y
	power_bar.show()
	aim_line.set_enabled(true)
	_maybe_trigger_ai_shot()

func _maybe_trigger_ai_shot() -> void:
	if _ai == null or _ai_thinking:
		return
	if current_player == GameSettings.human_player:
		return
	# Lock player aiming while the AI is choosing a shot
	_ai_thinking = true
	_thinking_dots_timer = 0.0
	_thinking_dots_step = 0
	_thinking_text.text = "THINKING"
	_thinking_panel.show()
	aim_line.set_enabled(false)
	cue.set_process(false)
	_ai.decide_and_shoot()

func hide_cue() -> void:
	cue.set_process(false)
	cue.hide()
	power_bar.hide()
	aim_line.set_enabled(false)


# === PLAYER / COLOR META ===
func _player_color(player: int) -> int:
	if num_players == 1:
		return single_color
	elif num_players == 2:
		return player
	else:
		return 1 if player % 2 == 1 else 2

func _current_bounds() -> Rect2:
	if num_players == 1:
		return BOUNDS_P1 if single_color == 1 else BOUNDS_P2
	elif num_players == 2:
		return BOUNDS_P1 if current_player == 1 else BOUNDS_P2
	else:
		match current_player:
			1: return BOUNDS_4P_P1
			2: return BOUNDS_4P_P2
			3: return BOUNDS_4P_P3
			4: return BOUNDS_4P_P4
		return BOUNDS_4P_P1

func _current_start_position() -> Vector2:
	if num_players == 1:
		return START_POSITION_PLAYER_1 if single_color == 1 else START_POSITION_PLAYER_2
	elif num_players == 2:
		return START_POSITION_PLAYER_1 if current_player == 1 else START_POSITION_PLAYER_2
	else:
		match current_player:
			1: return START_POSITION_4P_P1
			2: return START_POSITION_4P_P2
			3: return START_POSITION_4P_P3
			4: return START_POSITION_4P_P4
		return START_POSITION_4P_P1


# === DISC QUERY HELPERS ===
func _all_discs() -> Array:
	return get_tree().get_nodes_in_group("all_red_discs") + get_tree().get_nodes_in_group("all_black_discs")

func _live_discs() -> Array:
	var result: Array = []
	for d in _all_discs():
		if is_instance_valid(d) and not d.is_queued_for_deletion():
			result.append(d)
	return result

func _count_remaining(group: String) -> int:
	var count := 0
	for disc in get_tree().get_nodes_in_group(group):
		if is_instance_valid(disc) and not disc.is_queued_for_deletion():
			count += 1
	return count

func is_overlapping_with_discs(pos: Vector2) -> bool:
	for disc in _live_discs():
		if pos.distance_to(disc.position) < (DISC_DIAMETER + 3):
			return true
	return false

func find_closest_valid_position(pos: Vector2) -> Vector2:
	if not is_overlapping_with_discs(pos):
		return pos
	var bounds := _current_bounds()
	var bounds_min := bounds.position
	var bounds_max := bounds.position + bounds.size
	var best_pos := pos
	var best_distance := INF
	for r in range(0, 100, 5):
		for angle in range(0, 360, 15):
			var test_pos := pos + Vector2(r, 0).rotated(deg_to_rad(angle))
			test_pos = test_pos.clamp(bounds_min, bounds_max)
			if not is_overlapping_with_discs(test_pos):
				var dist: float = pos.distance_to(test_pos)
				if dist < best_distance:
					best_distance = dist
					best_pos = test_pos
	return best_pos


# === MAIN LOOP ===
func _process(delta: float) -> void:
	# Update the small AI thinking text
	if not _ai_thinking or game_over:
		if _thinking_panel.visible:
			_thinking_panel.hide()
	elif _thinking_panel.visible:
		_thinking_dots_timer += delta
		if _thinking_dots_timer >= 0.45:
			_thinking_dots_timer = 0.0
			_thinking_dots_step = (_thinking_dots_step + 1) % 4
			_thinking_text.text = "THINKING" + ".".repeat(_thinking_dots_step)

	if game_over:
		return
	if penalty_animating:
		return

	if dragging_puck:
		# Keep the striker inside the allowed start area.
		var bounds := _current_bounds()
		var mouse_pos: Vector2 = get_viewport().get_mouse_position().clamp(
			bounds.position, bounds.position + bounds.size
		)
		if not is_overlapping_with_discs(mouse_pos):
			puck.position = mouse_pos
			dragged_position = mouse_pos
		else:
			puck.position = lerp(puck.position, find_closest_valid_position(mouse_pos), 0.1)
		_update_cue_geometry()
		_update_aim_line()
		return

	moving = false
	# Check if any piece is still moving
	for i in _live_discs():
		var v: float = i.linear_velocity.length()
		if v > 0.0 and v < MOVE_THRESHOLD:
			i.sleeping = true
		elif v >= MOVE_THRESHOLD:
			moving = true

	if puck and is_instance_valid(puck):
		var sv: float = puck.linear_velocity.length()
		if sv > 0.0 and sv < MOVE_THRESHOLD:
			puck.sleeping = true
		elif sv >= MOVE_THRESHOLD:
			moving = true

	_update_aim_line()

	if shot_taken:
		# The puck uses a distance check to decide if it fell into a pocket
		if puck and is_instance_valid(puck):
			for pc: Vector2 in POCKET_CENTERS:
				if puck.position.distance_to(pc) < PUCK_POCKET_RADIUS:
					puck_potted = true
					pocket_fx.burst_at(puck.position, Color(1, 1, 1, 0.9))
					remove_puck()
					break
		if puck and is_instance_valid(puck):
			# This tracks the return-to-zone foul.
			if not puck_left_zone and not _is_in_player_edge_zone(puck.position, -2.0):
				puck_left_zone = true
			elif puck_left_zone and not puck_returned_to_zone and _is_in_player_edge_zone(puck.position, 2.0):
				puck_returned_to_zone = true

		if not moving:
			# Wait a tiny moment so sleeping bodies fully stop
			wait_time += delta
			if wait_time >= WAIT_THRESHOLD:
				evaluate_shot()
				if game_over or penalty_animating:
					return
				remove_puck()
				reset_puck()
				show_cue()
				shot_taken = false
			else:
				if not taking_shot:
					taking_shot = true
		else:
			if taking_shot:
				taking_shot = false
				hide_cue()

func _physics_process(delta: float) -> void:
	if game_over:
		return
	# Keep pieces inside the board and slow them down a little
	for p in _live_discs():
		_clamp_in_bounds(p)
		_apply_slow_damp(p, delta)
	if puck and is_instance_valid(puck):
		_clamp_in_bounds(puck)
		_apply_slow_damp(puck, delta)

func _apply_slow_damp(body: RigidBody2D, delta: float) -> void:
	var spd := body.linear_velocity.length()
	if spd > MOVE_THRESHOLD:
		var factor := clampf(1.0 - spd / SLOW_DAMP_THRESHOLD, 0.0, 1.0)
		body.linear_velocity *= maxf(0.0, 1.0 - SLOW_EXTRA_DAMP * factor * delta)

func _clamp_in_bounds(body: RigidBody2D) -> void:
	var pos: Vector2 = body.position
	var v: Vector2 = body.linear_velocity
	var clamped := false
	if pos.x < TABLE_MIN.x:
		pos.x = TABLE_MIN.x
		if v.x < 0.0:
			v.x = -v.x * CLAMP_VELOCITY_DAMP
		clamped = true
	elif pos.x > TABLE_MAX.x:
		pos.x = TABLE_MAX.x
		if v.x > 0.0:
			v.x = -v.x * CLAMP_VELOCITY_DAMP
		clamped = true
	if pos.y < TABLE_MIN.y:
		pos.y = TABLE_MIN.y
		if v.y < 0.0:
			v.y = -v.y * CLAMP_VELOCITY_DAMP
		clamped = true
	elif pos.y > TABLE_MAX.y:
		pos.y = TABLE_MAX.y
		if v.y > 0.0:
			v.y = -v.y * CLAMP_VELOCITY_DAMP
		clamped = true
	if clamped:
		body.position = pos
		body.linear_velocity = v

func _update_aim_line() -> void:
	if not (cue.visible and puck and is_instance_valid(puck)) or _ai_thinking:
		aim_line.set_enabled(false)
		return
	# The aim line follows the cue direction
	aim_line.set_enabled(true)
	var aim_target: Vector2 = puck.position + cue.aim_dir * 2000.0 if cue.aim_dir.length() > 0.1 else get_viewport().get_mouse_position()
	aim_line.aim_from(puck.position, aim_target, [puck.get_rid()])


# === INPUT ===
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_S:
			var img = get_viewport().get_texture().get_image()
			
			img.save_png("C:\\Users\\User\\Desktop\\maijs\\screenshots\\ai_thinking.png")
	if moving or game_over or _ai_thinking:
		return
	if event is InputEventMouseButton:
		if event.pressed and puck and puck.get_node("Area2D/pointer_circle").shape:
			# Let the player drag the striker from its pointer area.
			var shape: Shape2D = puck.get_node("Area2D/pointer_circle").shape
			var local_mouse_pos: Vector2 = puck.to_local(event.position)
			var hit_pointer := false
			if shape is RectangleShape2D:
				var half: Vector2 = shape.size * 0.5
				hit_pointer = Rect2(-half, shape.size).has_point(local_mouse_pos)
			elif shape is CircleShape2D:
				hit_pointer = local_mouse_pos.length() <= shape.radius
			if hit_pointer:
				dragging_puck = true
				puck.set_deferred("collision_layer", 0)
				hide_cue()
		elif not event.pressed and dragging_puck:
			# Put the striker back on a valid free spot when dragging ends.
			dragging_puck = false
			puck.set_deferred("collision_layer", 0)
			puck.position = find_closest_valid_position(puck.position)
			await get_tree().process_frame
			puck.set_deferred("collision_layer", 1)
			show_cue()
			


# === SHOT FLOW ===
func _on_cue_shoot(power: Vector2) -> void:
	if moving or dragging_puck:
		return
	for p in _live_discs():
		p.sleeping = false
	_update_dark_discs()
	_snapshot_dark_discs()
	_snapshot_opponent_light_discs()
	var sc := _player_color(current_player)
	var sg := "all_red_discs" if sc == 1 else "all_black_discs"
	var s_remaining := _count_remaining(sg)
	var s_dark := 0
	for d in get_tree().get_nodes_in_group("dark_discs"):
		if is_instance_valid(d) and not d.is_queued_for_deletion() and d.is_in_group(sg):
			s_dark += 1
	_shot_has_dark_disc = s_dark > 0
	_shot_all_discs_dark = s_remaining > 0 and s_dark == s_remaining
	# Apply the shot and hide aiming until motion ends.
	puck.apply_central_impulse(power)
	shot_taken = true
	hide_cue()

func _on_puck_body_entered(body: Node) -> void:
	if not shot_taken:
		return
	# Some fouls depend on whether the puck touched a wall first
	if body is StaticBody2D:
		if not first_hit_checked:
			puck_hit_cushion = true
			if not puck_hit_opposite_wall and _is_opposite_wall_hit(puck.position):
				puck_hit_opposite_wall = true
		return
	if not (body.is_in_group("all_red_discs") or body.is_in_group("all_black_discs")):
		return
	# Track every direct puck→opponent contact (used for the light disc to dark rule)
	var shooter_color := _player_color(current_player)
	var opponent_group := "all_black_discs" if shooter_color == 1 else "all_red_discs"
	if body.is_in_group(opponent_group) and not first_hit_checked:
		var bid := body.get_instance_id()
		if not _directly_hit_opponent_ids.has(bid):
			_directly_hit_opponent_ids.append(bid)
	# Only the first disc contact matters for this rule
	if first_hit_checked:
		return
	first_hit_checked = true
	if shooter_color == 1 and body.is_in_group("all_black_discs"):
		first_hit_wrong = true
	elif shooter_color == 2 and body.is_in_group("all_red_discs"):
		first_hit_wrong = true
	if body.is_in_group("dark_discs") and not puck_hit_cushion:
		dark_disc_foul = true

func _on_potted(body: Node) -> void:
	if body == puck:
		return  # puck potting is handled by per-frame distance check in _process

	var disc_color := 0
	if body.is_in_group("all_red_discs"):
		disc_color = 1
		pocket_fx.burst_at(body.position, RED_COLOR)
	elif body.is_in_group("all_black_discs"):
		disc_color = 2
		pocket_fx.burst_at(body.position, BLACK_COLOR)
	else:
		return

	body.queue_free()

	if not shot_taken:
		return
	if disc_color == _player_color(current_player):
		valid_hit = true
	else:
		opponent_disc_potted = true

func _is_set_opener_shot(player: int) -> bool:
	return _set_flow.is_set_opener_shot(player)

func _is_opening_turn_shot(player: int) -> bool:
	return _set_flow.is_opening_turn_shot(player, num_players)

func _clear_answer_source_player(player: int) -> int:
	return _set_flow.clear_answer_source_player(player, num_players)

func _clear_answer_winner_if_fail(cleared_color: int) -> int:
	return cleared_color

func _record_clear_answer_flags(shooter: int, foul: bool, keep_turn: bool, award_penalty: bool) -> void:
	_set_flow.record_clear_answer_flags(
		num_players,
		shooter,
		foul,
		keep_turn,
		award_penalty,
		opponent_disc_potted,
		valid_hit
	)

func evaluate_shot() -> void:
	# This function turns all shot flags into the final result.
	var shooter       := current_player
	var shooter_color := _player_color(shooter)

	var has_dark_disc  := _shot_has_dark_disc
	var all_discs_dark := _shot_all_discs_dark

	var opposite_wall_exempt := all_discs_dark and puck_hit_opposite_wall
	var effective_wrong_hit  := first_hit_wrong and not opposite_wall_exempt
	var return_foul          := puck_returned_to_zone and not has_dark_disc

	var exemptable_foul := effective_wrong_hit or not first_hit_checked or dark_disc_foul or return_foul
	var foul       := puck_potted or (exemptable_foul and not opposite_wall_exempt)
	var keep_turn  := valid_hit and not foul and not opponent_disc_potted
	var award_penalty := puck_potted or effective_wrong_hit or dark_disc_foul or not first_hit_checked

	_set_flow.last_shot_was_nopfoul = foul and not award_penalty
	_record_clear_answer_flags(shooter, foul, keep_turn, award_penalty)

	if foul:
		# Some fouls can restore dark discs to their old positions
		if dark_disc_foul or (effective_wrong_hit and puck_hit_opposite_wall and has_dark_disc):
			_restore_dark_discs()
		if award_penalty:
			# Get the target now because the debt list can still change
			var color  := _player_color(shooter)
			var target: Vector2
			var landing_size: float
			if not _has_room_for(color):
				target = hud.get_debt_target_pos(color, _debt_count_for(color))
				landing_size = 20.0
			else:
				target = _find_penalty_placement(shooter)
				landing_size = 40.0
			hud.show_foul_with_penalty(color, target, landing_size)
			_pending_shooter   = shooter
			_pending_keep_turn = keep_turn
			penalty_animating  = true
			return  # _on_penalty_animation_done continues after animation
		# Return to zone (no penalty) fouls are silent, turn passes, no label

	_check_opponent_moved_to_dark(shooter)
	_finish_shot(shooter, keep_turn)

func _finish_shot(shooter: int, keep_turn: bool) -> void:
	# Finish the turn, update the HUD, then check for set end
	if _set_flow.answer_phase and not keep_turn:
		var _answer_winner := _set_flow.answer_winner
		_set_flow.answer_phase = false
		if _set_flow.opener_cleared_with_nopfoul and _set_flow.last_shot_was_nopfoul:
			var ac := _player_color(shooter)
			var grp := "all_red_discs" if ac == 1 else "all_black_discs"
			if _count_remaining(grp) == 0 and _debt_count_for(ac) == 0:
				_set_flow.opener_cleared_with_nopfoul = false
				_set_flow.opener_cleared_with_opp_disc = false
				_replay_set(_set_flow.answer_source_player if _set_flow.answer_source_player >= 1 else -1)
				return
		_set_flow.opener_cleared_with_nopfoul = false
		_set_flow.opener_cleared_with_opp_disc = false
		_end_game(_answer_winner, false)  # answerer failed
		return
	if not keep_turn:
		if num_players != 1:
			_swap_player()
		_resolve_pending_debt()
	else:
		var c   := _player_color(shooter)
		var grp := "all_red_discs" if c == 1 else "all_black_discs"
		if _count_remaining(grp) == 0:
			_resolve_pending_debt()
	_reset_shot_flags()
	_update_dark_discs()
	hud.set_active_player(current_player)
	_update_score_hud()
	_check_winner(shooter)
	_advance_opening_turn_state(shooter, keep_turn)

func _on_penalty_animation_done() -> void:
	# The real penalty is added only after the HUD animation ends
	penalty_animating = false
	_award_penalty(_pending_shooter)
	_check_opponent_moved_to_dark(_pending_shooter)
	_finish_shot(_pending_shooter, _pending_keep_turn)
	if not game_over:
		remove_puck()
		reset_puck()
		show_cue()
	shot_taken = false

func _swap_player() -> void:
	if num_players == 4:
		# Clockwise: bottom(1) → left(4) → top(3) → right(2) → bottom(1)
		const CW := {1: 4, 4: 3, 3: 2, 2: 1}
		current_player = CW[current_player]
	elif num_players == 2:
		current_player = 2 if current_player == 1 else 1

func _next_player_in_order(p: int) -> int:
	if num_players == 2:
		return 3 - p
	const CW := {1: 4, 4: 3, 3: 2, 2: 1}
	return CW[p]

func _is_opening_turn_active_for(player: int) -> bool:
	return _set_flow.is_opening_turn_active_for(player, num_players)

func _advance_opening_turn_state(shooter: int, keep_turn: bool) -> void:
	_set_flow.advance_opening_turn_state(num_players, shooter, current_player, keep_turn, game_over)

func _start_answer_phase(winner_if_fail: int, source_player: int = -1) -> void:
	var actual_source := source_player if source_player >= 1 else _set_flow.set_opener
	_set_flow.begin_answer_phase(winner_if_fail, actual_source)
	current_player = _next_player_in_order(actual_source)
	hud.set_active_player(current_player)

func _void_set_and_start_next() -> void:
	_set_flow.answer_phase = false
	_set_flow.next_set_starter = current_player
	game_over = true
	hide_cue()
	if puck and is_instance_valid(puck):
		puck.set_deferred("freeze", true)
	call_deferred("new_game")

func _replay_set(next_starter: int = -1) -> void:
	var replay_starter := _set_flow.replay_starter(next_starter)
	_set_flow.clear_answer_phase()
	_set_flow.next_set_starter = replay_starter
	game_over = true
	hide_cue()
	if puck and is_instance_valid(puck):
		puck.set_deferred("freeze", true)
	call_deferred("new_game")

func _resolve_answer_phase_clear() -> void:
	if _set_flow.opener_cleared_with_nopfoul:
		_set_flow.opener_cleared_with_nopfoul = false
		_end_game(3 - _set_flow.answer_winner, _set_flow.last_shot_was_nopfoul)
	elif _set_flow.opener_cleared_with_opp_disc:
		_set_flow.opener_cleared_with_opp_disc = false
		_end_game(3 - _set_flow.answer_winner, _set_flow.last_shot_was_nopfoul)
	else:
		_void_set_and_start_next()

func _try_start_clear_answer_phase(cleared_color: int, shooter: int) -> bool:
	if num_players == 4 and _is_opening_turn_shot(shooter) and _set_flow.opening_turn_perfect_run:
		_start_answer_phase(_clear_answer_winner_if_fail(cleared_color), shooter)
		return true
	if _is_set_opener_shot(shooter) and _set_flow.opener_perfect_run:
		_start_answer_phase(_clear_answer_winner_if_fail(cleared_color))
		return true
	if _set_flow.opener_perfect_nopfoul_clear:
		_set_flow.opener_cleared_with_nopfoul = true
		_start_answer_phase(_clear_answer_winner_if_fail(cleared_color), _clear_answer_source_player(shooter))
		hud.show_last_shot_foul(shooter)
		return true
	if _set_flow.opener_perfect_opp_disc_clear:
		_set_flow.opener_cleared_with_opp_disc = true
		_start_answer_phase(_clear_answer_winner_if_fail(cleared_color), _clear_answer_source_player(shooter))
		return true
	return false


# =============================================================================
# PENALTY DISC SYSTEM
# =============================================================================
# Placement rule (enforced precisely, never moves other discs):
#   1. Target = exact center of the opponent's edge-zone middle line, i.e. the
#      point between the 4th and 5th starting disc on that line.
#   2. If that target is free, place there.
#   3. Otherwise sweep outward along the same line in 0.5px steps. Return the
#      first position with full DISC_SPACING (33px) clearance from every live
#      disc. This naturally lands touching the disc that blocked us (same 1px
#      visual gap used in the startup layout).
#
# Debt rule: if the fouler's color already has the maximum number of discs on
# the table (8 in 1P/2P, 16 in 4P), the penalty is queued and spawned later
# whenever a slot of that color opens.
# =============================================================================

func _award_penalty(fouler: int) -> void:
	var color := _player_color(fouler)
	if _has_room_for(color):
		_spawn_penalty_disc(color, fouler)
	else:
		disc_debt.append({"color": color, "fouler": fouler})

func _has_room_for(color: int) -> bool:
	var group := "all_red_discs" if color == 1 else "all_black_discs"
	var max_discs := 16 if num_players == 4 else 8
	return _count_remaining(group) < max_discs

func _resolve_pending_debt() -> void:
	# Try to place queued penalty discs when space opens.
	var i := 0
	while i < disc_debt.size():
		var entry = disc_debt[i]
		if _has_room_for(entry.color):
			var debt_index := _debt_index_for_entry(i, entry.color)
			disc_debt.remove_at(i)
			_spawn_debt_disc_with_animation(entry.color, entry.fouler, debt_index)
		else:
			i += 1

func _debt_index_for_entry(entry_index: int, color: int) -> int:
	var index := 0
	for n in range(entry_index):
		if disc_debt[n].color == color:
			index += 1
	return index

func _debt_count_for(color: int) -> int:
	var count := 0
	for e in disc_debt:
		if e.color == color:
			count += 1
	return count

func _spawn_penalty_disc(color: int, fouler: int) -> void:
	_spawn_penalty_disc_at(color, _find_penalty_placement(fouler), true)

func _spawn_debt_disc_with_animation(color: int, fouler: int, debt_index: int) -> void:
	# Spawn the disc hidden first, then let the HUD fly it in
	var target := _find_penalty_placement(fouler)
	var disc := _spawn_penalty_disc_at(color, target, false)
	hud.animate_debt_disc_to_field(color, debt_index, target, _reveal_debt_disc.bind(disc))

func _spawn_penalty_disc_at(color: int, pos: Vector2, visible: bool = true) -> RigidBody2D:
	var scene: PackedScene = red_disc_scene if color == 1 else black_disc_scene
	var tex: String = "res://assets/red_piece.png" if color == 1 else "res://assets/black_piece.png"
	var disc: RigidBody2D = scene.instantiate() as RigidBody2D
	# Set position BEFORE add_child so the physics body registers at the correct
	# location from the very first physics tick - prevents any overlap
	disc.position = pos
	add_child(disc)
	var sprite: Sprite2D = disc.get_node("Sprite2D")
	sprite.texture = load(tex)
	sprite.modulate.a = 1.0 if visible else 0.0
	return disc

func _reveal_debt_disc(disc: RigidBody2D) -> void:
	# Fade the hidden penalty disc in after the animation ends.
	if not is_instance_valid(disc) or disc.is_queued_for_deletion():
		return
	var sprite: Sprite2D = disc.get_node("Sprite2D")
	var tw := create_tween()
	tw.tween_property(sprite, "modulate:a", 1.0, 0.12)

func _penalty_base_pos(fouler: int) -> Vector2:
	if num_players == 1:
		if single_color == 1:
			return Vector2(ROW_CENTER_X, TOP_ROW_Y)
		else:
			return Vector2(ROW_CENTER_X, BOTTOM_ROW_Y)
	elif num_players == 2:
		return Vector2(ROW_CENTER_X, TOP_ROW_Y if fouler == 1 else BOTTOM_ROW_Y)
	else:
		match fouler:
			1: return Vector2(ROW_CENTER_X, TOP_ROW_Y)
			2: return Vector2(float(LEFT_COL_X), COL_CENTER_Y)
			3: return Vector2(ROW_CENTER_X, BOTTOM_ROW_Y)
			4: return Vector2(float(RIGHT_COL_X), COL_CENTER_Y)
	return Vector2(ROW_CENTER_X, TOP_ROW_Y)

# 4P P2/P4 shoot from the side, so their penalty line is a vertical column.
func _is_penalty_horizontal(fouler: int) -> bool:
	if num_players != 4:
		return true
	return fouler == 1 or fouler == 3

func _find_penalty_placement(fouler: int) -> Vector2:
	# Start from the middle of the line, then search outward.
	var base := _penalty_base_pos(fouler)
	var horizontal := _is_penalty_horizontal(fouler)
	var r := float(DISC_DIAMETER) * 0.5

	if _penalty_spot_free(base):
		return base

	var axis_min: float = (TABLE_MIN.x + r) if horizontal else (TABLE_MIN.y + r)
	var axis_max: float = (TABLE_MAX.x - r) if horizontal else (TABLE_MAX.y - r)
	var center_axis: float = base.x if horizontal else base.y
	var sp := float(DISC_SPACING)

	# --- Phase 1: exact touching positions ---
	# For each live disc, compute the two points on the penalty line that are
	# exactly DISC_SPACING away (touching with 1px gap, same as startup layout).
	# Try them sorted by closeness to the center. This avoids the rounding error
	# of the pixel sweep and guarantees the disc literally touches its neighbour.
	var candidates: Array = []
	for disc in _live_discs():
		var disc_axis: float = disc.position.x if horizontal else disc.position.y
		var disc_perp: float = disc.position.y if horizontal else disc.position.x
		var base_perp: float = base.y          if horizontal else base.x
		var perp_dist: float = abs(disc_perp - base_perp)
		if perp_dist >= sp:
			continue  # disc is too far off the line to produce a touch point on it
		var axis_offset: float = sqrt(sp * sp - perp_dist * perp_dist)
		for side in [-1.0, 1.0]:
			var av: float = disc_axis + side * axis_offset
			if av < axis_min or av > axis_max:
				continue
			var pos: Vector2 = Vector2(av, base.y) if horizontal else Vector2(base.x, av)
			candidates.append({"pos": pos, "dist": abs(av - center_axis)})

	candidates.sort_custom(func(a, b): return a.dist < b.dist)
	for c in candidates:
		if _penalty_spot_free(c.pos):
			return c.pos

	# --- Phase 2: fine-grained sweep (fallback) ---
	# Used only when every exact touching candidate is itself blocked (e.g. by a
	# disc that drifted far off the line). Still returns the closest free position.
	var d := PENALTY_STEP
	while d <= PENALTY_MAX_DIST:
		for side_sign in [-1.0, 1.0]:
			var av: float = center_axis + side_sign * d
			if av < axis_min or av > axis_max:
				continue
			var pos: Vector2 = Vector2(av, base.y) if horizontal else Vector2(base.x, av)
			if _penalty_spot_free(pos):
				return pos
		d += PENALTY_STEP
	return base  # unreachable in practice

# A position is free iff every live disc's centre is at least DISC_DIAMETER (32)
# away - the true physics no-overlap threshold. Phase-1 candidates are placed at
# DISC_SPACING (33 px), which is always > 32, so floating-point rounding in the
# sqrt never causes a false-negative that sends placement to the wrong side.
func _penalty_spot_free(pos: Vector2) -> bool:
	for disc in _live_discs():
		if pos.distance_to(disc.position) < float(DISC_DIAMETER):
			return false
	return true


# === DARK DISC ===
func _snapshot_dark_discs() -> void:
	# Save dark discs so they can be restored after some fouls.
	_dark_disc_snapshots.clear()
	for disc in get_tree().get_nodes_in_group("dark_discs"):
		if is_instance_valid(disc) and not disc.is_queued_for_deletion():
			_dark_disc_snapshots[disc.get_instance_id()] = {
				"node": disc,
				"position": disc.position,
				"color_group": "all_red_discs" if disc.is_in_group("all_red_discs") else "all_black_discs"
			}

func _restore_dark_discs() -> void:
	# Rebuild saved dark discs for the current shooter color.
	var shooter_group := "all_red_discs" if _player_color(current_player) == 1 else "all_black_discs"
	for id in _dark_disc_snapshots:
		var snap: Dictionary = _dark_disc_snapshots[id]
		if snap["color_group"] != shooter_group:
			continue
		var disc = snap["node"]
		if is_instance_valid(disc) and not disc.is_queued_for_deletion():
			disc.queue_free()
		var is_red: bool = snap["color_group"] == "all_red_discs"
		var scene: PackedScene = red_disc_scene if is_red else black_disc_scene
		var new_disc := scene.instantiate()
		new_disc.position = snap["position"]
		add_child(new_disc)
		new_disc.get_node("Sprite2D").texture = load("res://assets/red_piece.png" if is_red else "res://assets/black_piece.png")
	_dark_disc_snapshots.clear()

func _is_in_disc_own_dark_zone(pos: Vector2, disc_color: int) -> bool:
	if pos.distance_to(CIRCLE_CENTER) < (CIRCLE_RADIUS - DISC_HOLE_RADIUS - 0.5):
		return true
	if num_players == 2:
		return pos.y >= 1431.0 if disc_color == 1 else pos.y <= 725.0
	# 4P: red discs are dark in P1 bottom zone or P3 top zone; black in P2 right or P4 left
	if disc_color == 1:
		return pos.y >= 1431.0 or pos.y <= 725.0
	return pos.x >= 894.0 or pos.x <= 188.0

func _snapshot_opponent_light_discs() -> void:
	# Save opponent discs that are still outside dark zones.
	_opponent_light_snapshots.clear()
	if num_players == 1:
		return
	var shooter_color := _player_color(current_player)
	var opponent_group := "all_black_discs" if shooter_color == 1 else "all_red_discs"
	var disc_color := 2 if shooter_color == 1 else 1
	for disc in get_tree().get_nodes_in_group(opponent_group):
		if not is_instance_valid(disc) or disc.is_queued_for_deletion():
			continue
		if _is_in_disc_own_dark_zone(disc.position, disc_color):
			continue
		_opponent_light_snapshots[disc.get_instance_id()] = {
			"node": disc,
			"position": disc.position,
			"color_group": opponent_group,
			"disc_color": disc_color
		}

func _check_opponent_moved_to_dark(shooter: int) -> void:
	# If the shot pushed an opponent disc into dark, add a penalty.
	if num_players == 1 or _opponent_light_snapshots.is_empty() or _directly_hit_opponent_ids.is_empty():
		_opponent_light_snapshots.clear()
		return
	var moved: Array = []
	for id in _opponent_light_snapshots:
		if not _directly_hit_opponent_ids.has(id):
			continue
		var snap: Dictionary = _opponent_light_snapshots[id]
		var disc = snap["node"]
		if not is_instance_valid(disc) or disc.is_queued_for_deletion():
			continue
		if _is_in_disc_own_dark_zone(disc.position, snap["disc_color"]):
			moved.append(snap)
	if not moved.is_empty():
		if num_players == 2:
			for snap in moved:
				var disc = snap["node"]
				if is_instance_valid(disc) and not disc.is_queued_for_deletion():
					disc.queue_free()
				var is_red: bool = snap["disc_color"] == 1
				var scene: PackedScene = red_disc_scene if is_red else black_disc_scene
				var new_disc := scene.instantiate()
				new_disc.position = snap["position"]
				add_child(new_disc)
				new_disc.get_node("Sprite2D").texture = load("res://assets/red_piece.png" if is_red else "res://assets/black_piece.png")
		_award_penalty(shooter)
	_opponent_light_snapshots.clear()

# inset > 0 shifts the boundary INTO the zone (body must be further in to count).
# inset < 0 shifts the boundary OUT of the zone (body counts as in zone sooner).
# Used with PUCK_HOLE_RADIUS / DISC_HOLE_RADIUS to detect definitive zone crossings.
func _is_in_player_edge_zone(pos: Vector2, inset: float = 0.0) -> bool:
	if num_players == 1:
		return pos.y >= (1431.0 + inset) if single_color == 1 else pos.y <= (725.0 - inset)
	if num_players == 2:
		return pos.y >= (1431.0 + inset) if current_player == 1 else pos.y <= (725.0 - inset)
	match current_player:
		1: return pos.y >= (1431.0 + inset)
		2: return pos.x >= (894.0 + inset)
		3: return pos.y <= (725.0 - inset)
		4: return pos.x <= (188.0 - inset)
	return false

func _is_opposite_wall_hit(pos: Vector2) -> bool:
	const MARGIN := 60.0
	match current_player:
		1: return pos.y <= TABLE_MIN.y + MARGIN
		2: return pos.y >= TABLE_MAX.y - MARGIN if num_players == 2 else pos.x <= TABLE_MIN.x + MARGIN
		3: return pos.y >= TABLE_MAX.y - MARGIN
		4: return pos.x >= TABLE_MAX.x - MARGIN
	return false

func _update_dark_discs() -> void:
	# Mark which discs are dark for the current shooter.
	var shooter_group := "all_red_discs" if _player_color(current_player) == 1 else "all_black_discs"
	for disc in _live_discs():
		var is_dark: bool = disc.is_in_group(shooter_group) and (
			disc.position.distance_to(CIRCLE_CENTER) < (CIRCLE_RADIUS - DISC_HOLE_RADIUS - 0.5)
			or _is_in_player_edge_zone(disc.position, -1.0)
		)
		if is_dark:
			if not disc.is_in_group("dark_discs"):
				disc.add_to_group("dark_discs")
		else:
			if disc.is_in_group("dark_discs"):
				disc.remove_from_group("dark_discs")

func _count_dark_discs_by_color(color: int) -> int:
	var group := "all_red_discs" if color == 1 else "all_black_discs"
	var count := 0
	for d in get_tree().get_nodes_in_group("dark_discs"):
		if is_instance_valid(d) and not d.is_queued_for_deletion() and d.is_in_group(group):
			count += 1
	return count

# Returns dark disc count for display purposes. In 1P/2P each color always has
# a fixed edge zone, so both panels update regardless of whose turn it is.
# In 4P, falls back to the game-group count (only current player's discs are dark).
func _display_dark_count(color: int) -> int:
	if num_players == 4:
		return _count_dark_discs_by_color(color)
	var group := "all_red_discs" if color == 1 else "all_black_discs"
	var count := 0
	for disc in _live_discs():
		if not disc.is_in_group(group):
			continue
		var in_center: bool = disc.position.distance_to(CIRCLE_CENTER) < (CIRCLE_RADIUS - DISC_HOLE_RADIUS - 0.5)
		var in_edge: bool = disc.position.y >= 1430.0 if color == 1 else disc.position.y <= 726.0
		if in_center or in_edge:
			count += 1
	return count


# === UI / END-GAME ===
func _update_score_hud() -> void:
	# Refresh counts on the HUD after every finished shot.
	hud.update_score(
		_count_remaining("all_red_discs"),
		_count_remaining("all_black_discs"),
		_debt_count_for(1),
		_debt_count_for(2),
		sets_red,
		sets_black
	)
	hud.update_dark_count(_display_dark_count(1), _display_dark_count(2))

func _check_winner(shooter: int = 0) -> void:
	# Check normal win rules and answer-phase rules.
	var red_left := _count_remaining("all_red_discs")
	var black_left := _count_remaining("all_black_discs")

	if _set_flow.answer_phase:
		var ac := _player_color(current_player)
		var al := red_left if ac == 1 else black_left
		if al == 0 and _debt_count_for(ac) == 0:
			_resolve_answer_phase_clear()
		return

	if num_players == 1:
		var color := single_color
		var left := red_left if color == 1 else black_left
		if left == 0 and _debt_count_for(color) == 0:
			_end_game(0, _set_flow.last_shot_was_nopfoul)
	else:
		# Both colors cleared simultaneously (last 1v1 pot) → replay, same player starts.
		if red_left == 0 and black_left == 0 and _debt_count_for(1) == 0 and _debt_count_for(2) == 0:
			_replay_set(shooter)
			return
		if red_left == 0 and _debt_count_for(1) == 0:
			if not _try_start_clear_answer_phase(1, shooter):
				_end_game(1, _set_flow.last_shot_was_nopfoul)
		elif black_left == 0 and _debt_count_for(2) == 0:
			if not _try_start_clear_answer_phase(2, shooter):
				_end_game(2, _set_flow.last_shot_was_nopfoul)

func _end_game(winner: int, foul_note: bool = false) -> void:
	# Freeze the board and show the winner panel.
	game_over = true
	hide_cue()
	if puck and is_instance_valid(puck):
		puck.set_deferred("freeze", true)

	if num_players == 1:
		if single_color == 1:
			sets_red += 1
		else:
			sets_black += 1
	elif winner == 1:
		sets_red += 1
	elif winner == 2:
		sets_black += 1

	# Next set always starts the opponent of whoever just won.
	if num_players != 1:
		_set_flow.next_set_starter = 2 if winner == 1 else 1

	var sets_to_win: int = (GameSettings.best_of + 1) / 2
	var is_match_win: bool
	if num_players == 1:
		is_match_win = (sets_red >= sets_to_win if single_color == 1 else sets_black >= sets_to_win)
	else:
		is_match_win = sets_red >= sets_to_win or sets_black >= sets_to_win

	if foul_note:
		hud.show_foul()
		await get_tree().create_timer(1.3).timeout

	hud.show_winner(winner, sets_red, sets_black, is_match_win, foul_note)

func _on_restart() -> void:
	new_game()

func _on_new_match() -> void:
	sets_red = 0
	sets_black = 0
	_set_flow.next_set_starter = 1
	new_game()

func _on_menu_requested() -> void:
	sets_red = 0
	sets_black = 0
	get_tree().change_scene_to_file("res://scenes/menu.tscn")
