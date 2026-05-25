extends Node
class_name AIPlayer

# This file picks AI shots.
# It tries normal pots first, then bank shots, then fallback hits.
const SHOT_SCALE    := 1500.0
const DISC_DIAMETER := 32.0
const DISC_RADIUS   := 16.0
const PUCK_RADIUS   := 16.0

const PUCK_MASS            := 4.5
const DISC_TRANSFER        := 0.85
const GLOBAL_DAMP          := 2.2
const SLOW_DAMP_BASELINE_V := 200.0
const SLOW_DAMP_DISTANCE   := 57.0

const NOISE_POT_DEG  := 0.0
const NOISE_BANK_DEG := 0.05
const NOISE_HIT_DEG  := 0.0

var _main: Node

func setup(main_node: Node) -> void:
	_main = main_node


func decide_and_shoot() -> void:
	await get_tree().process_frame

	# Build the best shot plan for the current board.
	var plan := _plan_shot()

	var noise_deg : float
	match plan.get("type", "fallback"):
		"pot":  noise_deg = NOISE_POT_DEG
		"bank": noise_deg = NOISE_BANK_DEG
		_:      noise_deg = NOISE_HIT_DEG

	var noise     : float   = deg_to_rad(randf_range(-noise_deg, noise_deg))
	var final_dir : Vector2 = (plan["shot"]["direction"] as Vector2).rotated(noise)

	await get_tree().create_timer(2).timeout
	if not _can_shoot():
		_main._ai_thinking = false
		return

	# Move the striker into the planned start spot.
	await _animate_puck_to(plan["puck_pos"])

	_main._ai_thinking = false

	await _animate_cue_aim(final_dir)
	await _animate_pullback(plan["shot"]["power"])

	if not _can_shoot():
		return

	var impulse : Vector2 = (plan["shot"]["power"] as float) * SHOT_SCALE * final_dir
	_main._on_cue_shoot(impulse)


func _can_shoot() -> bool:
	return (not _main.game_over
		and not _main.moving
		and not _main.shot_taken
		and not _main.penalty_animating)


func _is_top_player() -> bool:
	var zone     : Rect2  = _main._current_bounds()
	var center_y : float  = (_main.TABLE_MIN.y + _main.TABLE_MAX.y) * 0.5
	return (zone.position.y + zone.size.y * 0.5) < center_y


func _is_shooting_into_board(dir: Vector2) -> bool:
	return dir.y > 0.0 if _is_top_player() else dir.y < 0.0


func _near_wall_y() -> float:
	return _main.TABLE_MAX.y if _is_top_player() else _main.TABLE_MIN.y


func _discs_at_start(disc_grp: String) -> bool:
	var start_y : float = float(_main.BOTTOM_ROW_Y if _is_top_player() else _main.TOP_ROW_Y)
	for d in _main.get_tree().get_nodes_in_group(disc_grp):
		if not is_instance_valid(d) or d.is_queued_for_deletion():
			continue
		if absf((d as Node2D).position.y - start_y) > 60.0:
			return false
	return true


func _discs_at_exact_start(disc_grp: String) -> bool:
	var start_y : float = float(_main.BOTTOM_ROW_Y if _is_top_player() else _main.TOP_ROW_Y)
	for d in _main.get_tree().get_nodes_in_group(disc_grp):
		if not is_instance_valid(d) or d.is_queued_for_deletion():
			continue
		if absf((d as Node2D).position.y - start_y) > 5.0:
			return false
	return true


func _opening_thin_contact_point(puck_pos: Vector2, disc_pos: Vector2) -> Vector2:
	var to_disc : Vector2 = disc_pos - puck_pos
	if to_disc.length() < 0.001:
		return disc_pos
	var perp         : Vector2 = Vector2(-to_disc.y, to_disc.x).normalized()
	var table_center : Vector2 = (_main.TABLE_MIN + _main.TABLE_MAX) * 0.5
	var sign_dir     : float   = 1.0 if (disc_pos - table_center).dot(perp) > 0.0 else -1.0
	var offset       : float   = randf_range(DISC_RADIUS * 1.55, DISC_RADIUS * 2)
	return disc_pos + perp * sign_dir * offset


# If the starting row is no longer perfect, aim at the highest free disc first.
func _plan_shot_at_highest_disc(all_live: Array, disc_grp: String) -> Dictionary:
	var target : Node  = null
	var top_y  : float = INF
	for d in _main.get_tree().get_nodes_in_group(disc_grp):
		if not is_instance_valid(d) or d.is_queued_for_deletion():
			continue
		if d.is_in_group("dark_discs"):
			continue
		var dy : float = (d as Node2D).position.y
		if dy < top_y:
			top_y  = dy
			target = d

	if target == null:
		return {}

	var pockets   : Array   = _main.POCKET_CENTERS
	var zone      : Rect2   = _main._current_bounds()
	var best_score    := -INF
	var best_puck_pos : Vector2 = _main._current_start_position()
	var best_shot     := {}

	var candidates : Array = []
	var disc_pos   : Vector2 = (target as Node2D).position
	for pocket in pockets:
		var d2p : Vector2 = pocket - disc_pos
		if d2p.length() < 1.0:
			continue
		var d2p_norm   : Vector2 = d2p.normalized()
		var ghost_ball : Vector2 = disc_pos - d2p_norm * DISC_DIAMETER
		for dist_px in [35.0, 55.0, 75.0, 100.0, 130.0, 180.0, 240.0, 320.0, 420.0, 540.0]:
			var c : Vector2 = ghost_ball - d2p_norm * dist_px
			if zone.has_point(c):
				candidates.append(c)
	for pos in _candidate_puck_positions(false):
		candidates.append(pos)

	for pos in candidates:
		if _main.is_overlapping_with_discs(pos):
			continue
		for pocket in pockets:
			var result := _evaluate_pot_shot(pos, target, pocket, all_live, false)
			if not result.is_empty() and (result["score"] as float) > best_score:
				best_score    = result["score"] as float
				best_puck_pos = pos
				best_shot     = result

	if not best_shot.is_empty():
		return {"puck_pos": best_puck_pos, "shot": best_shot, "type": "pot"}

	var dir   : Vector2 = (disc_pos - best_puck_pos).normalized()
	if not _aim_dir_is_valid(best_puck_pos, dir):
		return {}
	var power : float = clampf(best_puck_pos.distance_to(disc_pos) / 1700.0,
								0.18, 0.55) * float(_main.MAX_POWER)
	return {"puck_pos": best_puck_pos, "shot": {"direction": dir, "power": power, "score": 0.0},
			"type": "fallback"}


func _plan_shot() -> Dictionary:
	# Try easy direct shots first, then harder options.
	var all_live : Array  = _main._live_discs()
	var color    : int    = _main._player_color(_main.current_player)
	var disc_grp : String = "all_red_discs" if color == 1 else "all_black_discs"
	var own_count : int   = 0
	for d in _main.get_tree().get_nodes_in_group(disc_grp):
		if is_instance_valid(d) and not d.is_queued_for_deletion():
			own_count += 1

	var is_opening : bool = (own_count >= 8) and _discs_at_start(disc_grp)

	if own_count >= 8 and not is_opening:
		# Early in the set, break the row in a simple way.
		return _plan_shot_at_highest_disc(all_live, disc_grp)

	var best_score    := -INF
	var best_puck_pos : Vector2 = _main._current_start_position()
	var best_shot     := {}

	var candidate_positions : Array = []
	if not is_opening:
		candidate_positions = _straight_shot_candidates(all_live)
		for pos in _close_half_shot_candidates():
			candidate_positions.append(pos)
	for pos in _candidate_puck_positions(is_opening):
		candidate_positions.append(pos)

	for pos in candidate_positions:
		if _main.is_overlapping_with_discs(pos):
			continue
		var shot := _find_best_shot_from(pos, all_live, is_opening)
		if not shot.is_empty() and (shot["score"] as float) > best_score:
			best_score    = shot["score"] as float
			best_puck_pos = pos
			best_shot     = shot

	if not best_shot.is_empty():
		if is_opening:
			best_shot = _soften_opening_shot(best_shot)
		return {"puck_pos": best_puck_pos, "shot": best_shot, "type": "pot"}

	# If no direct pot is good, try a bank shot.
	var bot_score    := -INF
	var bot_puck_pos : Vector2 = _main._current_start_position()
	var bot_shot     := {}

	for pos in _candidate_puck_positions(is_opening):
		if _main.is_overlapping_with_discs(pos):
			continue
		var shot := _find_best_bottom_bank_shot_from(pos, all_live)
		if not shot.is_empty() and (shot["score"] as float) > bot_score:
			bot_score    = shot["score"] as float
			bot_puck_pos = pos
			bot_shot     = shot

	if not bot_shot.is_empty():
		if is_opening:
			bot_shot = _soften_opening_shot(bot_shot)
		return {"puck_pos": bot_puck_pos, "shot": bot_shot, "type": "bank"}

	if is_opening:
		# Opening shots can fall back to a lighter contact plan.
		var open_shot := _opening_fallback_shot(best_puck_pos, all_live)
		if not open_shot.is_empty():
			return {"puck_pos": best_puck_pos, "shot": _soften_opening_shot(open_shot), "type": "fallback"}

	var dark_score    := -INF
	var dark_puck_pos : Vector2 = _main._current_start_position()
	var dark_shot_res := {}

	for pos in candidate_positions:
		if _main.is_overlapping_with_discs(pos):
			continue
		var dshot := _find_best_dark_disc_shot_from(pos, all_live)
		if not dshot.is_empty() and (dshot["score"] as float) > dark_score:
			dark_score    = dshot["score"] as float
			dark_puck_pos = pos
			dark_shot_res = dshot

	if not dark_shot_res.is_empty():
		return {"puck_pos": dark_puck_pos, "shot": dark_shot_res, "type": "bank"}

	# Last fallback is just to hit something legal.
	var last := _last_resort_hit(best_puck_pos)
	if is_opening:
		last = _soften_opening_shot(last)
	return {"puck_pos": best_puck_pos, "shot": last, "type": "fallback"}


func _candidate_puck_positions(is_opening: bool) -> Array:
	# Sample many legal striker positions inside the current start zone.
	var zone  : Rect2 = _main._current_bounds()
	var left  : float = zone.position.x + 14.0
	var right : float = zone.position.x + zone.size.x - 14.0
	var y_far : float = zone.position.y + zone.size.y - 2.0
	var y_2_3 : float = zone.position.y + zone.size.y * 0.67
	var y_1_3 : float = zone.position.y + zone.size.y * 0.33

	if is_opening:
		var positions : Array = []
		for i in range(22):
			var t : float = i / 21.0
			positions.append(Vector2(left + (right - left) * t, y_far))
		return positions

	var y_4_5 : float = zone.position.y + zone.size.y * 0.84
	var y_1_5 : float = zone.position.y + zone.size.y * 0.16
	var positions : Array = []
	for row_y in [y_far, y_4_5, y_2_3, y_1_3, y_1_5]:
		for i in range(81):
			var t : float = i / 80.0
			positions.append(Vector2(left + (right - left) * t, row_y))
	return positions


func _straight_shot_candidates(all_live: Array) -> Array:
	var color    : int    = _main._player_color(_main.current_player)
	var disc_grp : String = "all_red_discs" if color == 1 else "all_black_discs"
	var pockets  : Array  = _main.POCKET_CENTERS
	var zone     : Rect2  = _main._current_bounds()
	var positions : Array = []

	for disc in _main.get_tree().get_nodes_in_group(disc_grp):
		if not is_instance_valid(disc) or disc.is_queued_for_deletion():
			continue
		if disc.is_in_group("dark_discs"):
			continue
		var disc_pos : Vector2 = (disc as Node2D).position
		for pocket in pockets:
			var d2p : Vector2 = pocket - disc_pos
			if d2p.length() < 1.0:
				continue
			var d2p_norm   : Vector2 = d2p.normalized()
			var ghost_ball : Vector2 = disc_pos - d2p_norm * DISC_DIAMETER
			for dist_px in [5.0, 10.0, 16.0, 22.0, 30.0, 40.0, 52.0, 66.0, 82.0, 100.0, 122.0, 148.0, 178.0, 212.0, 252.0, 298.0, 352.0, 414.0, 486.0, 570.0, 666.0]:
				var candidate : Vector2 = ghost_ball - d2p_norm * dist_px
				if zone.has_point(candidate):
					positions.append(candidate)

	return positions


func _soften_opening_shot(shot: Dictionary) -> Dictionary:
	var softened := shot.duplicate()
	var power : float = softened.get("power", 0.0) as float
	softened["power"] = minf(power, float(_main.MAX_POWER) * 0.34)
	return softened


func _find_best_shot_from(puck_pos: Vector2, all_live: Array, is_opening: bool = false) -> Dictionary:
	var color    : int    = _main._player_color(_main.current_player)
	var disc_grp : String = "all_red_discs" if color == 1 else "all_black_discs"
	var pockets  : Array  = _main.POCKET_CENTERS
	var best_score := -INF
	var best_shot  := {}

	for disc in _main.get_tree().get_nodes_in_group(disc_grp):
		if not is_instance_valid(disc) or disc.is_queued_for_deletion():
			continue
		if disc.is_in_group("dark_discs"):
			continue
		for pocket in pockets:
			var result := _evaluate_pot_shot(puck_pos, disc, pocket, all_live, is_opening)
			if not result.is_empty() and (result["score"] as float) > best_score:
				best_score = result["score"] as float
				best_shot  = result

	return best_shot


func _evaluate_pot_shot(puck_pos: Vector2, disc: Node, pocket: Vector2, all_live: Array,
		is_opening: bool = false) -> Dictionary:
	# Score one possible pot line.
	var disc_pos    : Vector2 = (disc as Node2D).position
	var disc_to_pkt : Vector2 = pocket - disc_pos
	if disc_to_pkt.length() < 1.0:
		return {}
	var d2p_norm : Vector2 = disc_to_pkt.normalized()
	var is_close : bool    = _is_in_close_half(disc_pos)

	# A disc on the near half should only go to the far pockets.
	if is_close:
		var gz_center_y : float = (_main.TABLE_MIN.y + _main.TABLE_MAX.y) * 0.5
		var gz_zone     : Rect2  = _main._current_bounds()
		var gz_is_top   : bool   = (gz_zone.position.y + gz_zone.size.y * 0.5) < gz_center_y
		if (pocket.y > gz_center_y) != gz_is_top:
			return {}

	var ghost_ball    : Vector2 = disc_pos - d2p_norm * DISC_DIAMETER
	var puck_to_ghost : Vector2 = ghost_ball - puck_pos
	if puck_to_ghost.length() < 1.0:
		return {}
	var aim_dir : Vector2 = puck_to_ghost.normalized()

	if not _aim_dir_is_valid(puck_pos, aim_dir):
		return {}

	if (ghost_ball.x < _main.TABLE_MIN.x or ghost_ball.x > _main.TABLE_MAX.x
			or ghost_ball.y < _main.TABLE_MIN.y or ghost_ball.y > _main.TABLE_MAX.y):
		return {}

	if _is_segment_blocked(puck_pos, ghost_ball, disc, all_live, DISC_RADIUS + PUCK_RADIUS):
		return {}
	if _is_dark_disc_in_path(puck_pos, ghost_ball, disc, all_live):
		return {}
	var color2 : int = _main._player_color(_main.current_player)
	if _path_has_illegal_first_contact(puck_pos, ghost_ball, disc, all_live, color2):
		return {}
	if _is_segment_blocked(disc_pos, pocket, disc, all_live, DISC_RADIUS * 2):
		return {}

	var pkt_r : float = float(_main.PUCK_POCKET_RADIUS) + 24.0
	for pkt in _main.POCKET_CENTERS:
		if _segment_hits_circle(puck_pos, ghost_ball, pkt, pkt_r):
			return {}

	var dist_puck_ghost : float = puck_pos.distance_to(ghost_ball)
	var dist_disc_pkt   : float = disc_pos.distance_to(pocket)
	var total_dist      : float = dist_puck_ghost + dist_disc_pkt

	var score        : float = 100.0
	var angle_q      : float = aim_dir.dot(d2p_norm)

	if angle_q < 0.05:
		return {}

	var puck_after_dir : Vector2 = _puck_post_collision_dir(aim_dir, d2p_norm)
	var puck_risk      : bool    = _puck_path_risks_pocketing(ghost_ball, puck_after_dir, 6)
	var close_pocket   : bool    = dist_disc_pkt < 250.0

	if puck_risk:
		return {}

	if is_close:
		score += 80.0
		var c_center_y   : float = (_main.TABLE_MIN.y + _main.TABLE_MAX.y) * 0.5
		var c_zone       : Rect2 = _main._current_bounds()
		var c_is_top     : bool  = (c_zone.position.y + c_zone.size.y * 0.5) < c_center_y
		var nearest_far  : Vector2 = _nearest_far_pocket(disc_pos, c_is_top)
		var is_side_strip : bool   = (disc_pos.x <= 170.0 or disc_pos.x >= 882.0)
		if pocket.distance_to(nearest_far) < 1.0:
			score += (120.0 if is_side_strip else 35.0)
		else:
			score -= (80.0 if is_side_strip else 15.0)
		if angle_q > 0.90:
			score += (80.0 if is_side_strip else 55.0)
		elif angle_q > 0.65:
			score += (25.0 if is_side_strip else 15.0)
		else:
			score -= (85.0 if is_side_strip else 45.0)

	score += angle_q * 40.0

	if close_pocket:
		score += 30.0
	else:
		if angle_q < 0.50:
			score -= 25.0

	score -= dist_puck_ghost * 0.15

	if dist_disc_pkt < 80.0:
		score += 45.0
	elif dist_disc_pkt < 150.0:
		score += 28.0
	elif dist_disc_pkt < 300.0:
		score += 12.0
	score -= dist_disc_pkt * 0.020

	var near_count : int = _count_discs_near_segment(puck_pos, ghost_ball, disc, all_live, 55.0)
	score -= near_count * 5.0

	if is_opening:
		if angle_q > 0.93:
			score -= (angle_q - 0.93) * 180.0
		score -= maxf(0.0, total_dist - 420.0) * 0.02

	score -= _opponent_proximity_penalty(disc, all_live, color2)

	if not is_close:
		score += _combo_nudge_bonus(ghost_ball, puck_after_dir, disc, all_live, color2)

	score += _runout_safety_bonus(ghost_ball, puck_after_dir, disc, all_live, color2)

	score += randf_range(-7.0, 7.0)

	var power : float
	if is_opening:
		# Opening shots stay softer so the board does not explode too much.
		power = clampf(total_dist / 2000.0, 0.16, 0.48) * float(_main.MAX_POWER)
	else:
		var safe_dist      : float = dist_disc_pkt + 70.0
		var v_disc_min     : float = (SLOW_DAMP_BASELINE_V
				+ maxf(0.0, safe_dist - SLOW_DAMP_DISTANCE) * GLOBAL_DAMP) * 1.15
		var transfer       : float = maxf(angle_q, 0.60) * DISC_TRANSFER
		var v_puck_initial : float = v_disc_min / transfer + GLOBAL_DAMP * dist_puck_ghost
		power = clampf(v_puck_initial * PUCK_MASS / SHOT_SCALE, 1.0, float(_main.MAX_POWER) * 0.90)

	if _main._count_dark_discs_by_color(color2) == 0:
		var v_at_ghost    : float = power * SHOT_SCALE / PUCK_MASS
		var puck_post_spd : float = v_at_ghost * (1.0 - 2.0 / (PUCK_MASS + 1.0))
		var max_travel    : float = puck_post_spd / GLOBAL_DAMP
		if _puck_returns_to_zone(ghost_ball, puck_after_dir, max_travel):
			return {}

	return {"score": score, "direction": aim_dir, "power": power}


func _is_edge_dark_middle_zone(disc_pos: Vector2) -> bool:
	var unit : float = (_main.TABLE_MAX.x - _main.TABLE_MIN.x) / 4.0
	return disc_pos.x >= _main.TABLE_MIN.x + unit and disc_pos.x <= _main.TABLE_MAX.x - unit


func _is_far_pocket_for_player(pocket: Vector2) -> bool:
	var center_y : float = (_main.TABLE_MIN.y + _main.TABLE_MAX.y) * 0.5
	return pocket.y < center_y if not _is_top_player() else pocket.y > center_y


func _find_best_dark_disc_shot_from(puck_pos: Vector2, all_live: Array) -> Dictionary:
	var color    : int    = _main._player_color(_main.current_player)
	var disc_grp : String = "all_red_discs" if color == 1 else "all_black_discs"
	var pockets  : Array  = _main.POCKET_CENTERS
	var walls    : Array  = [{"coord": _near_wall_y(), "vertical": false}]
	var best_score := -INF
	var best_shot  := {}

	for disc in _main.get_tree().get_nodes_in_group(disc_grp):
		if not is_instance_valid(disc) or disc.is_queued_for_deletion():
			continue
		if not disc.is_in_group("dark_discs"):
			continue
		var disc_pos2 : Vector2 = (disc as Node2D).position
		var is_center : bool    = disc_pos2.distance_to(_main.CIRCLE_CENTER) < float(_main.CIRCLE_RADIUS)
		var far_only  : bool    = (not is_center) and _is_edge_dark_middle_zone(disc_pos2)
		for pocket in pockets:
			if far_only and not _is_far_pocket_for_player(pocket):
				continue
			for wall in walls:
				var result := _evaluate_dark_cushion_shot(puck_pos, disc, pocket, all_live, wall)
				if not result.is_empty() and (result["score"] as float) > best_score:
					best_score = result["score"] as float
					best_shot  = result

	return best_shot


func _evaluate_dark_cushion_shot(puck_pos: Vector2, disc: Node, pocket: Vector2,
		all_live: Array, wall: Dictionary) -> Dictionary:
	var disc_pos    : Vector2 = (disc as Node2D).position
	var disc_to_pkt : Vector2 = pocket - disc_pos
	if disc_to_pkt.length() < 1.0:
		return {}
	var d2p_norm : Vector2 = disc_to_pkt.normalized()
	var ghost_ball : Vector2 = disc_pos - d2p_norm * DISC_DIAMETER
	if (ghost_ball.x < _main.TABLE_MIN.x or ghost_ball.x > _main.TABLE_MAX.x
			or ghost_ball.y < _main.TABLE_MIN.y or ghost_ball.y > _main.TABLE_MAX.y):
		return {}

	var is_vert : bool  = wall["vertical"] as bool
	var wall_c  : float = wall["coord"] as float
	var mirror  : Vector2
	if is_vert:
		mirror = Vector2(2.0 * wall_c - puck_pos.x, puck_pos.y)
	else:
		mirror = Vector2(puck_pos.x, 2.0 * wall_c - puck_pos.y)

	var m_to_ghost : Vector2 = ghost_ball - mirror
	if m_to_ghost.length() < 1.0:
		return {}

	var bounce : Vector2
	if is_vert:
		if abs(m_to_ghost.x) < 0.0001:
			return {}
		var ratio : float = (wall_c - mirror.x) / (ghost_ball.x - mirror.x)
		if ratio <= 0.0 or ratio >= 1.0:
			return {}
		bounce = mirror.lerp(ghost_ball, ratio)
		if bounce.y < _main.TABLE_MIN.y or bounce.y > _main.TABLE_MAX.y:
			return {}
	else:
		if abs(m_to_ghost.y) < 0.0001:
			return {}
		var ratio : float = (wall_c - mirror.y) / (ghost_ball.y - mirror.y)
		if ratio <= 0.0 or ratio >= 1.0:
			return {}
		bounce = mirror.lerp(ghost_ball, ratio)
		if bounce.x < _main.TABLE_MIN.x or bounce.x > _main.TABLE_MAX.x:
			return {}

	var puck_to_bounce : Vector2 = bounce - puck_pos
	if puck_to_bounce.length() < 1.0:
		return {}
	var initial_dir : Vector2 = puck_to_bounce.normalized()

	if not _is_shooting_into_board(initial_dir):
		return {}
	if not _aim_dir_is_valid(puck_pos, initial_dir):
		return {}

	var bounce_to_ghost : Vector2 = ghost_ball - bounce
	if bounce_to_ghost.length() < 1.0:
		return {}
	var post_dir : Vector2 = bounce_to_ghost.normalized()

	if _is_segment_blocked(puck_pos, bounce, null, all_live, DISC_RADIUS + PUCK_RADIUS):
		return {}
	if _is_segment_blocked(bounce, disc_pos, disc, all_live, DISC_RADIUS + PUCK_RADIUS):
		return {}
	if _is_segment_blocked(disc_pos, pocket, disc, all_live, DISC_RADIUS * 2):
		return {}

	var dk_pkt_r : float = float(_main.PUCK_POCKET_RADIUS) + 24.0
	for dk_pkt in _main.POCKET_CENTERS:
		if _segment_hits_circle(puck_pos, bounce, dk_pkt, dk_pkt_r):
			return {}
		if _segment_hits_circle(bounce, ghost_ball, dk_pkt, dk_pkt_r):
			return {}

	var dist_puck_bounce  : float = puck_pos.distance_to(bounce)
	var dist_bounce_ghost : float = bounce.distance_to(ghost_ball)
	var dist_disc_pkt     : float = disc_pos.distance_to(pocket)
	var angle_q           : float = post_dir.dot(d2p_norm)
	var puck_after_dark   : Vector2 = _puck_post_collision_dir(post_dir, d2p_norm)

	if _puck_path_risks_pocketing(ghost_ball, puck_after_dark, 6):
		return {}

	var score : float = 75.0
	score += angle_q * 20.0
	if dist_disc_pkt < 200.0:
		score += 22.0
	elif dist_disc_pkt < 400.0:
		score += 8.0
	score -= dist_disc_pkt * 0.012
	score -= (dist_puck_bounce + dist_bounce_ghost) * 0.06

	var safe_dist        : float = dist_disc_pkt + 70.0
	var v_disc_min       : float = SLOW_DAMP_BASELINE_V + maxf(0.0, safe_dist - SLOW_DAMP_DISTANCE) * GLOBAL_DAMP
	var transfer         : float = maxf(angle_q, 0.60) * DISC_TRANSFER
	var v_puck_at_ghost  : float = v_disc_min / transfer
	var v_puck_at_bounce : float = (v_puck_at_ghost + GLOBAL_DAMP * dist_bounce_ghost) / 0.80
	var v_puck_initial   : float = v_puck_at_bounce + GLOBAL_DAMP * dist_puck_bounce
	var power : float = clampf(v_puck_initial * PUCK_MASS / SHOT_SCALE, 2.0, float(_main.MAX_POWER) * 0.90)

	# Dark discs near the edge need a bit more force.
	var is_center_dark : bool = disc_pos.distance_to(_main.CIRCLE_CENTER) < float(_main.CIRCLE_RADIUS)
	if not is_center_dark:
		var edge_mult : float = 1.5 + clampf(dist_disc_pkt / 600.0, 0.0, 1.0)
		power = minf(power * edge_mult, float(_main.MAX_POWER) * 0.90)

	return {"score": score, "direction": initial_dir, "power": power}


func _find_best_bottom_bank_shot_from(puck_pos: Vector2, all_live: Array) -> Dictionary:
	var color    : int    = _main._player_color(_main.current_player)
	var disc_grp : String = "all_red_discs" if color == 1 else "all_black_discs"
	var pockets  : Array  = _main.POCKET_CENTERS
	var best_score := -INF
	var best_shot  := {}

	for disc in _main.get_tree().get_nodes_in_group(disc_grp):
		if not is_instance_valid(disc) or disc.is_queued_for_deletion():
			continue
		if disc.is_in_group("dark_discs"):
			continue
		if _is_in_close_half((disc as Node2D).position):
			continue
		for pocket in pockets:
			var result := _evaluate_bottom_bank_shot(puck_pos, disc, pocket, all_live)
			if not result.is_empty() and (result["score"] as float) > best_score:
				best_score = result["score"] as float
				best_shot  = result

	return best_shot


func _evaluate_bottom_bank_shot(puck_pos: Vector2, disc: Node, pocket: Vector2,
		all_live: Array) -> Dictionary:
	var disc_pos    : Vector2 = (disc as Node2D).position
	var disc_to_pkt : Vector2 = pocket - disc_pos
	if disc_to_pkt.length() < 1.0:
		return {}
	var d2p_norm   : Vector2 = disc_to_pkt.normalized()
	var ghost_ball : Vector2 = disc_pos - d2p_norm * DISC_DIAMETER
	if (ghost_ball.x < _main.TABLE_MIN.x or ghost_ball.x > _main.TABLE_MAX.x
			or ghost_ball.y < _main.TABLE_MIN.y or ghost_ball.y > _main.TABLE_MAX.y):
		return {}

	var wall_c : float   = _near_wall_y()
	var mirror : Vector2 = Vector2(puck_pos.x, 2.0 * wall_c - puck_pos.y)
	var m_to_ghost : Vector2 = ghost_ball - mirror
	if absf(m_to_ghost.y) < 0.0001:
		return {}
	var ratio : float = (wall_c - mirror.y) / (ghost_ball.y - mirror.y)
	if ratio <= 0.0 or ratio >= 1.0:
		return {}
	var bounce : Vector2 = mirror.lerp(ghost_ball, ratio)
	if bounce.x < _main.TABLE_MIN.x or bounce.x > _main.TABLE_MAX.x:
		return {}

	var puck_to_bounce : Vector2 = bounce - puck_pos
	if puck_to_bounce.length() < 1.0:
		return {}
	var initial_dir : Vector2 = puck_to_bounce.normalized()

	if not _is_shooting_into_board(initial_dir):
		return {}
	if not _aim_dir_is_valid(puck_pos, initial_dir):
		return {}

	var bounce_to_ghost : Vector2 = ghost_ball - bounce
	if bounce_to_ghost.length() < 1.0:
		return {}
	var post_dir : Vector2 = bounce_to_ghost.normalized()

	if _is_segment_blocked(puck_pos, bounce, null, all_live, DISC_RADIUS + PUCK_RADIUS):
		return {}
	if _is_dark_disc_in_path(puck_pos, bounce, null, all_live):
		return {}
	if _is_segment_blocked(bounce, disc_pos, disc, all_live, DISC_RADIUS + PUCK_RADIUS):
		return {}
	if _is_dark_disc_in_path(bounce, disc_pos, disc, all_live):
		return {}
	if _is_segment_blocked(disc_pos, pocket, disc, all_live, DISC_RADIUS * 2):
		return {}

	var pkt_r : float = float(_main.PUCK_POCKET_RADIUS) + 24.0
	for pkt in _main.POCKET_CENTERS:
		if _segment_hits_circle(puck_pos, bounce, pkt, pkt_r):
			return {}
		if _segment_hits_circle(bounce, ghost_ball, pkt, pkt_r):
			return {}

	var color2 : int = _main._player_color(_main.current_player)
	if _main._count_dark_discs_by_color(color2) == 0:
		var puck_after : Vector2 = _puck_post_collision_dir(post_dir, d2p_norm)
		if _puck_returns_to_zone(ghost_ball, puck_after):
			return {}

	var dist_puck_bounce  : float = puck_pos.distance_to(bounce)
	var dist_bounce_ghost : float = bounce.distance_to(ghost_ball)
	var dist_disc_pkt     : float = disc_pos.distance_to(pocket)
	var angle_q           : float = post_dir.dot(d2p_norm)
	var puck_after_bot    : Vector2 = _puck_post_collision_dir(post_dir, d2p_norm)

	if _puck_path_risks_pocketing(ghost_ball, puck_after_bot, 6):
		return {}

	var score : float = 50.0
	score += angle_q * 20.0
	if dist_disc_pkt < 200.0:
		score += 22.0
	elif dist_disc_pkt < 400.0:
		score += 8.0
	score -= dist_disc_pkt * 0.012
	score -= (dist_puck_bounce + dist_bounce_ghost) * 0.06

	var safe_dist        : float = dist_disc_pkt + 70.0
	var v_disc_min       : float = SLOW_DAMP_BASELINE_V + maxf(0.0, safe_dist - SLOW_DAMP_DISTANCE) * GLOBAL_DAMP
	var transfer         : float = maxf(angle_q, 0.60) * DISC_TRANSFER
	var v_puck_at_ghost  : float = v_disc_min / transfer
	var v_puck_at_bounce : float = (v_puck_at_ghost + GLOBAL_DAMP * dist_bounce_ghost) / 0.80
	var v_puck_initial   : float = v_puck_at_bounce + GLOBAL_DAMP * dist_puck_bounce
	var power : float = clampf(v_puck_initial * PUCK_MASS / SHOT_SCALE, 2.0, float(_main.MAX_POWER) * 0.90)

	return {"score": score, "direction": initial_dir, "power": power}


func _opening_fallback_shot(puck_pos: Vector2, all_live: Array) -> Dictionary:
	var color    : int    = _main._player_color(_main.current_player)
	var disc_grp : String = "all_red_discs" if color == 1 else "all_black_discs"
	var pockets  : Array  = _main.POCKET_CENTERS
	var use_thin : bool   = _discs_at_exact_start(disc_grp)

	var best_score : float   = -INF
	var best_pos   : Vector2 = Vector2.ZERO
	var best_dist  : float   = INF

	for disc in _main.get_tree().get_nodes_in_group(disc_grp):
		if not is_instance_valid(disc) or disc.is_queued_for_deletion():
			continue
		if disc.is_in_group("dark_discs"):
			continue
		var disc_pos   : Vector2 = (disc as Node2D).position
		if _path_has_illegal_first_contact(puck_pos, disc_pos, disc, all_live, color):
			continue
		var aim_target : Vector2 = _opening_thin_contact_point(puck_pos, disc_pos) if use_thin else disc_pos
		var d          : float   = puck_pos.distance_to(aim_target)
		var aim_dir    : Vector2 = (aim_target - puck_pos).normalized()
		if not _aim_dir_is_valid(puck_pos, aim_dir):
			continue
		var min_pkt_dist : float = INF
		for pkt in pockets:
			min_pkt_dist = minf(min_pkt_dist, disc_pos.distance_to(pkt as Vector2))
		var s : float = 1000.0 - min_pkt_dist - d * 0.3
		if s > best_score:
			best_score = s
			best_pos   = disc_pos
			best_dist  = d

	if best_pos == Vector2.ZERO:
		return {}
	var aim : Vector2
	if use_thin:
		aim = _opening_thin_contact_point(puck_pos, best_pos)
	else:
		var offset  : float   = randf_range(3.0, 10.0)
		var to_disc : Vector2 = best_pos - puck_pos
		if offset >= 0.5 and to_disc.length() > 0.001:
			var perp     : Vector2 = Vector2(-to_disc.y, to_disc.x).normalized()
			var tc       : Vector2 = (_main.TABLE_MIN + _main.TABLE_MAX) * 0.5
			var sign_dir : float   = 1.0 if (best_pos - tc).dot(perp) > 0.0 else -1.0
			aim = best_pos + perp * sign_dir * offset
		else:
			aim = best_pos
	var power : float = clampf(best_dist / 1700.0, 0.18, 0.55) * float(_main.MAX_POWER)
	return {"score": 40.0, "direction": (aim - puck_pos).normalized(), "power": power}


func _last_resort_hit(puck_pos: Vector2) -> Dictionary:
	var color    : int    = _main._player_color(_main.current_player)
	var disc_grp : String = "all_red_discs" if color == 1 else "all_black_discs"
	var all_live : Array  = _main._live_discs()

	var best_pos      : Vector2 = Vector2.ZERO
	var best_dist     : float   = INF
	var fallback_pos  : Vector2 = Vector2.ZERO
	var fallback_dist : float   = INF

	for disc in _main.get_tree().get_nodes_in_group(disc_grp):
		if not is_instance_valid(disc) or disc.is_queued_for_deletion():
			continue
		if disc.is_in_group("dark_discs"):
			continue
		var disc_pos : Vector2 = (disc as Node2D).position
		var d        : float   = puck_pos.distance_to(disc_pos)
		var dir      : Vector2 = (disc_pos - puck_pos).normalized()
		if not _aim_dir_is_valid(puck_pos, dir):
			continue
		if not _path_has_illegal_first_contact(puck_pos, disc_pos, disc, all_live, color):
			if d < best_dist:
				best_dist = d
				best_pos  = disc_pos
		else:
			if d < fallback_dist:
				fallback_dist = d
				fallback_pos  = disc_pos

	var chosen : Vector2
	var chosen_dist : float
	if best_pos != Vector2.ZERO:
		chosen = best_pos
		chosen_dist = best_dist
	elif fallback_pos != Vector2.ZERO:
		chosen = fallback_pos
		chosen_dist = fallback_dist
	else:
		var dir2 := Vector2(0.0, 1.0 if _is_top_player() else -1.0)
		return {"score": 0.0, "direction": dir2, "power": float(_main.MAX_POWER) * 0.25}

	var power : float = clampf(chosen_dist / 1700.0, 0.18, 0.55) * float(_main.MAX_POWER)
	return {"score": 0.0, "direction": (chosen - puck_pos).normalized(), "power": power}


func _path_has_illegal_first_contact(from: Vector2, to: Vector2,
		target: Node, all_discs: Array, shooter_color: int) -> bool:
	var opp_grp : String = "all_black_discs" if shooter_color == 1 else "all_red_discs"
	var seg     : Vector2 = to - from
	var seg_len : float   = seg.length()
	if seg_len < 0.001:
		return false
	var seg_dir : Vector2 = seg / seg_len

	for disc in all_discs:
		if not is_instance_valid(disc) or disc.is_queued_for_deletion():
			continue
		if disc == target:
			continue
		var is_opponent : bool = disc.is_in_group(opp_grp)
		var is_dark     : bool = disc.is_in_group("dark_discs")
		if not is_opponent and not is_dark:
			continue
		var to_disc : Vector2 = (disc as Node2D).position - from
		var along   : float   = to_disc.dot(seg_dir)
		if along < 0.0 or along > seg_len:
			continue
		var margin  : float = 8.0 if is_dark else 0.0
		var lateral : float = (to_disc - seg_dir * along).length()
		if lateral < (PUCK_RADIUS + DISC_RADIUS + margin):
			return true
	return false


func _is_dark_disc_in_path(from: Vector2, to: Vector2, exclude: Node, all_discs: Array) -> bool:
	const DARK_MARGIN := 8.0
	var seg     : Vector2 = to - from
	var seg_len : float   = seg.length()
	if seg_len < 0.001:
		return false
	var seg_dir : Vector2 = seg / seg_len

	for disc in all_discs:
		if not is_instance_valid(disc) or disc.is_queued_for_deletion():
			continue
		if disc == exclude:
			continue
		if not disc.is_in_group("dark_discs"):
			continue
		var to_disc : Vector2 = (disc as Node2D).position - from
		var along   : float   = to_disc.dot(seg_dir)
		if along < 0.0 or along > seg_len:
			continue
		var lateral : float = (to_disc - seg_dir * along).length()
		if lateral < (PUCK_RADIUS + DISC_RADIUS + DARK_MARGIN):
			return true
	return false


func _opponent_proximity_penalty(disc: Node, all_discs: Array, shooter_color: int) -> float:
	var opp_grp  : String  = "all_black_discs" if shooter_color == 1 else "all_red_discs"
	var disc_pos : Vector2 = (disc as Node2D).position
	var min_dist : float   = INF
	for other in all_discs:
		if not is_instance_valid(other) or other.is_queued_for_deletion():
			continue
		if not other.is_in_group(opp_grp):
			continue
		var d : float = disc_pos.distance_to((other as Node2D).position)
		if d < min_dist:
			min_dist = d
	if min_dist < DISC_DIAMETER * 1.15:
		return 80.0
	elif min_dist < DISC_DIAMETER * 2.0:
		return 38.0
	return 0.0


func _combo_nudge_bonus(from: Vector2, dir: Vector2, potted: Node,
		all_discs: Array, shooter_color: int) -> float:
	var disc_grp : String = "all_red_discs" if shooter_color == 1 else "all_black_discs"
	var opp_grp  : String = "all_black_discs" if shooter_color == 1 else "all_red_discs"
	var bonus    : float  = 0.0
	var seg_len  : float  = 500.0
	var seg_dir  : Vector2 = dir.normalized()

	var zone       : Rect2  = _main._current_bounds()
	var zone_mid_y : float  = zone.position.y + zone.size.y * 0.5
	var far_y_ref  : float  = (_main.TABLE_MAX.y + _main.TABLE_MIN.y) - zone_mid_y
	var far_thresh : float  = 220.0

	for own_disc in _main.get_tree().get_nodes_in_group(disc_grp):
		if not is_instance_valid(own_disc) or own_disc.is_queued_for_deletion():
			continue
		if own_disc == potted:
			continue
		var dpos : Vector2 = (own_disc as Node2D).position

		var is_blocked := false
		for opp in all_discs:
			if not is_instance_valid(opp) or opp.is_queued_for_deletion():
				continue
			if not opp.is_in_group(opp_grp):
				continue
			if dpos.distance_to((opp as Node2D).position) < DISC_DIAMETER * 1.5:
				is_blocked = true
				break
		var is_dark : bool = own_disc.is_in_group("dark_discs")
		var is_far  : bool = absf(dpos.y - far_y_ref) < far_thresh

		if not (is_blocked or is_dark or is_far):
			continue

		var to_disc : Vector2 = dpos - from
		var along   : float   = to_disc.dot(seg_dir)
		if along < 0.0 or along > seg_len:
			continue
		var lateral : float = (to_disc - seg_dir * along).length()
		if lateral < DISC_RADIUS + PUCK_RADIUS + 8.0:
			if is_blocked:
				bonus += 22.0
			elif is_dark:
				bonus += 30.0
			else:
				bonus += 12.0
	return bonus


func _animate_puck_to(target: Vector2) -> void:
	# Visually slide the striker to the planned start spot.
	var puck = _main.puck
	if not (puck and is_instance_valid(puck)):
		return
	if puck.position.distance_to(target) < 8.0:
		return

	_main.ai_moving_puck = true
	puck.set_deferred("collision_layer", 0)
	var start_pos : Vector2 = puck.position
	var pb  = _main.power_bar

	var tween := _main.create_tween()
	tween.tween_method(func(t: float) -> void:
		if not (puck and is_instance_valid(puck)):
			return
		puck.position = start_pos.lerp(target, t)
		_main._update_cue_geometry(false)
		_main._update_aim_line()
		pb.position.x = puck.position.x - pb.size.x * 0.5
		pb.position.y = puck.position.y + pb.size.y
	, 0.0, 1.0, 1.125).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	await tween.finished
	_main.ai_moving_puck = false
	await _main.get_tree().process_frame
	puck.set_deferred("collision_layer", 1)


func _animate_cue_aim(target_dir: Vector2) -> void:
	# Rotate the cue toward the chosen direction.
	var cue         = _main.cue
	var start_angle : float = cue.rotation
	var end_angle   : float = target_dir.angle()

	var tween := _main.create_tween()
	tween.tween_method(func(t: float) -> void:
		var angle : float = lerp_angle(start_angle, end_angle, t)
		cue.rotation = angle
		cue.aim_dir  = Vector2.from_angle(angle)
		_main._update_aim_line()
	, 0.0, 1.0, 0.40).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	await tween.finished
	cue.aim_dir  = target_dir
	cue.rotation = end_angle


func _animate_pullback(shot_power: float) -> void:
	# Pull the cue back before the strike.
	var cue  = _main.cue
	var puck = _main.puck
	if not (puck and is_instance_valid(puck)):
		return
	var anchor   : Vector2 = puck.position
	var aim      : Vector2 = cue.aim_dir
	var max_pull : float   = 150.0
	var pull     : float   = (shot_power / float(_main.MAX_POWER)) * max_pull

	var tween := _main.create_tween()
	tween.tween_property(cue, "position", anchor - aim * pull, 0.28)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await tween.finished
	await get_tree().create_timer(0.08).timeout


func _puck_post_collision_dir(aim_dir: Vector2, d2p_norm: Vector2) -> Vector2:
	const M1 : float = 4.5
	const M2 : float = 1.0
	var v1n    : float   = aim_dir.dot(d2p_norm)
	var result : Vector2 = aim_dir - d2p_norm * v1n * (2.0 * M2 / (M1 + M2))
	if result.length() < 0.001:
		return -d2p_norm
	return result.normalized()


func _puck_returns_to_zone(start: Vector2, direction: Vector2, max_dist: float = INF) -> bool:
	var min_b     : Vector2 = _main.TABLE_MIN
	var max_b     : Vector2 = _main.TABLE_MAX
	var pos       : Vector2 = start
	var d         : Vector2 = direction.normalized()
	var player    : int     = _main.current_player
	var num_p     : int     = _main.num_players
	var remaining : float   = max_dist

	for _bounce in range(8):
		var t_x := INF
		var t_y := INF
		if d.x > 0.0001:
			t_x = (max_b.x - pos.x) / d.x
		elif d.x < -0.0001:
			t_x = (min_b.x - pos.x) / d.x
		if d.y > 0.0001:
			t_y = (max_b.y - pos.y) / d.y
		elif d.y < -0.0001:
			t_y = (min_b.y - pos.y) / d.y

		var t : float = minf(t_x, t_y)
		if t < 0.5 or t >= 1e9:
			break
		t = minf(t, remaining)

		var hit : Vector2 = pos + d * t

		if _segment_crosses_zone_boundary(pos, hit, player, num_p):
			return true

		remaining -= t
		if remaining <= 0.5:
			break

		if t_x <= t_y:
			d.x = -d.x
		else:
			d.y = -d.y
		pos = hit

	return false


func _segment_crosses_zone_boundary(a: Vector2, b: Vector2, player: int, num_p: int) -> bool:
	match player:
		1: return a.y < 1431.0 and b.y >= 1431.0
		2:
			if num_p == 2:
				return a.y > 725.0 and b.y <= 725.0
			else:
				return a.x < 894.0 and b.x >= 894.0
		3: return a.y > 725.0 and b.y <= 725.0
		4: return a.x > 188.0 and b.x <= 188.0
	return false


func _segment_hits_circle(from: Vector2, to: Vector2, center: Vector2, radius: float) -> bool:
	var seg     : Vector2 = to - from
	var seg_len : float   = seg.length()
	if seg_len < 0.001:
		return false
	var d     : Vector2 = seg / seg_len
	var to_c  : Vector2 = center - from
	var along : float   = to_c.dot(d)
	if along < 0.0 or along > seg_len:
		return false
	return (to_c - d * along).length() < radius


func _puck_path_risks_pocketing(start: Vector2, dir: Vector2, max_bounces: int) -> bool:
	var pocket_r : float   = float(_main.PUCK_POCKET_RADIUS) + 24.0
	var pockets  : Array   = _main.POCKET_CENTERS
	var min_b    : Vector2 = _main.TABLE_MIN
	var max_b    : Vector2 = _main.TABLE_MAX
	var pos      : Vector2 = start
	var d        : Vector2 = dir.normalized()
	var dist_left : float  = 700.0

	for _i in range(max_bounces + 1):
		var t_x : float = INF
		var t_y : float = INF
		if d.x > 0.0001:    t_x = (max_b.x - pos.x) / d.x
		elif d.x < -0.0001: t_x = (min_b.x - pos.x) / d.x
		if d.y > 0.0001:    t_y = (max_b.y - pos.y) / d.y
		elif d.y < -0.0001: t_y = (min_b.y - pos.y) / d.y
		var t : float = minf(minf(t_x, t_y), dist_left)
		if t <= 0.001 or t >= 1e9:
			break
		var wall_hit : Vector2 = pos + d * t
		for pocket in pockets:
			if _segment_hits_circle(pos, wall_hit, pocket, pocket_r):
				return true
		dist_left -= t
		if dist_left <= 0.001:
			break
		if t_x <= t_y:
			d.x = -d.x
		else:
			d.y = -d.y
		pos = wall_hit
	return false


func _aim_dir_is_valid(puck_pos: Vector2, aim_dir: Vector2) -> bool:
	var cue             = _main.cue
	var corners : Array = _main._aim_corners()
	var prev_anchor : Vector2 = cue._anchor
	var prev_ca     : Vector2 = cue._corner_a
	var prev_cb     : Vector2 = cue._corner_b
	var prev_fwd    : Vector2 = cue._forward_dir

	cue._anchor      = puck_pos
	cue._corner_a    = corners[0]
	cue._corner_b    = corners[1]
	cue._forward_dir = cue._derive_forward_dir()

	var clamped : Vector2 = cue._clamp_aim_dir(aim_dir)

	cue._anchor      = prev_anchor
	cue._corner_a    = prev_ca
	cue._corner_b    = prev_cb
	cue._forward_dir = prev_fwd

	return aim_dir.dot(clamped) > cos(deg_to_rad(1.5))


func _runout_safety_bonus(ghost_ball: Vector2, puck_dir: Vector2,
		potted_disc: Node, all_live: Array, color: int) -> float:
	var disc_grp : String = "all_red_discs" if color == 1 else "all_black_discs"
	var bonus    : float  = 0.0
	var ray_end  : Vector2 = ghost_ball + puck_dir * 600.0
	for disc in _main.get_tree().get_nodes_in_group(disc_grp):
		if not is_instance_valid(disc) or disc.is_queued_for_deletion():
			continue
		if disc == potted_disc:
			continue
		var dp      : Vector2 = (disc as Node2D).position
		var to_disc : Vector2 = dp - ghost_ball
		var along   : float   = to_disc.dot(puck_dir)
		if along < 0.0 or along > 600.0:
			bonus += 3.0
			continue
		var lateral : float = (to_disc - puck_dir * along).length()
		if lateral > 60.0:
			bonus += 2.0
		else:
			bonus -= 8.0
	return bonus


func _is_in_close_half(disc_pos: Vector2) -> bool:
	var center_y : float = (_main.TABLE_MIN.y + _main.TABLE_MAX.y) * 0.5
	var zone     : Rect2 = _main._current_bounds()
	var is_top   : bool  = (zone.position.y + zone.size.y * 0.5) < center_y
	return disc_pos.y < center_y if is_top else disc_pos.y > center_y


func _close_half_shot_candidates() -> Array:
	var color    : int    = _main._player_color(_main.current_player)
	var disc_grp : String = "all_red_discs" if color == 1 else "all_black_discs"
	var center_y : float  = (_main.TABLE_MIN.y + _main.TABLE_MAX.y) * 0.5
	var zone     : Rect2  = _main._current_bounds()
	var is_top   : bool   = (zone.position.y + zone.size.y * 0.5) < center_y
	var pockets  : Array  = _main.POCKET_CENTERS

	var left  : float = zone.position.x + 8.0
	var right : float = zone.position.x + zone.size.x - 8.0
	var y_a   : float = zone.position.y + zone.size.y * (0.97 if is_top else 0.03)
	var y_b   : float = zone.position.y + zone.size.y * 0.5
	var y_c   : float = zone.position.y + zone.size.y * (0.08 if is_top else 0.92)

	var positions : Array = []

	for disc in _main.get_tree().get_nodes_in_group(disc_grp):
		if not is_instance_valid(disc) or disc.is_queued_for_deletion():
			continue
		if disc.is_in_group("dark_discs"):
			continue
		var disc_pos : Vector2 = (disc as Node2D).position
		if not _is_in_close_half(disc_pos):
			continue

		for pocket in pockets:
			if (pocket.y > center_y) != is_top:
				continue
			var d2p : Vector2 = pocket - disc_pos
			if d2p.length() < 1.0:
				continue
			var d2p_norm   : Vector2 = d2p.normalized()
			var ghost_ball : Vector2 = disc_pos - d2p_norm * DISC_DIAMETER

			var t : float = 5.0
			while t <= 700.0:
				var c : Vector2 = ghost_ball - d2p_norm * t
				if zone.has_point(c):
					positions.append(c)
				t += 6.0

			for sweep_y in [y_a, y_b, y_c]:
				var x : float = left
				while x <= right + 0.1:
					positions.append(Vector2(x, sweep_y))
					x += 8.0

	return positions


func _nearest_far_pocket(disc_pos: Vector2, is_top: bool) -> Vector2:
	var gz_center_y : float = (_main.TABLE_MIN.y + _main.TABLE_MAX.y) * 0.5
	var closest     : Vector2
	var min_d       : float = INF
	for pkt in _main.POCKET_CENTERS:
		var p      : Vector2 = pkt as Vector2
		var is_far : bool    = (p.y > gz_center_y) if is_top else (p.y < gz_center_y)
		if not is_far:
			continue
		var d : float = disc_pos.distance_to(p)
		if d < min_d:
			min_d   = d
			closest = p
	return closest


func _count_discs_near_segment(from: Vector2, to: Vector2, exclude: Node,
		all_discs: Array, radius: float) -> int:
	var seg     : Vector2 = to - from
	var seg_len : float   = seg.length()
	if seg_len < 0.001:
		return 0
	var seg_dir : Vector2 = seg / seg_len
	var count   : int     = 0
	for disc in all_discs:
		if not is_instance_valid(disc) or disc.is_queued_for_deletion():
			continue
		if disc == exclude:
			continue
		var to_disc : Vector2 = (disc as Node2D).position - from
		var along   : float   = to_disc.dot(seg_dir)
		if along < 0.0 or along > seg_len:
			continue
		var lateral : float = (to_disc - seg_dir * along).length()
		if lateral < radius:
			count += 1
	return count


func _is_segment_blocked(from: Vector2, to: Vector2, exclude: Node,
		all_discs: Array, clearance: float) -> bool:
	var seg     : Vector2 = to - from
	var seg_len : float   = seg.length()
	if seg_len < 0.001:
		return false
	var seg_dir : Vector2 = seg / seg_len

	for disc in all_discs:
		if not is_instance_valid(disc) or disc.is_queued_for_deletion():
			continue
		if disc == exclude:
			continue
		var to_disc : Vector2 = (disc as Node2D).position - from
		var along   : float   = to_disc.dot(seg_dir)
		if along < 0.0 or along > seg_len:
			continue
		var lateral : float = (to_disc - seg_dir * along).length()
		if lateral < clearance:
			return true
	return false
