extends Sprite2D

signal shoot

# This file handles cue aiming and pullback before a shot.
const MAX_PULL_PIXELS := 150.0
const SHOT_SCALE := 1500.0
const CUE_WIDTH_PROFILE := [
	Vector2(22.0, 1.3),
	Vector2(50.0, 3.3),
	Vector2(100.0, 3.6),
	Vector2(150.0, 4.0),
	Vector2(250.0, 4.3),
	Vector2(400.0, 5.3),
	Vector2(700.0, 6.9),
	Vector2(1000.0, 10.9),
	Vector2(1300.0, 11.6),
]
const CORNER_VISIBILITY_MARGIN := 2.0

var power: float = 0.0
var aim_dir: Vector2 = Vector2.ZERO

var _anchor: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _click_pos: Vector2 = Vector2.ZERO
var _corner_a: Vector2 = Vector2.ZERO
var _corner_b: Vector2 = Vector2.ZERO
var _forward_dir: Vector2 = Vector2.ZERO

func set_aim_geometry(pos: Vector2, corner_a: Vector2, corner_b: Vector2, reset_dir: bool = false) -> void:
	_anchor = pos
	position = pos
	_dragging = false
	power = 0.0
	_corner_a = corner_a
	_corner_b = corner_b
	_forward_dir = _derive_forward_dir()
	if reset_dir or aim_dir == Vector2.ZERO:
		aim_dir = _forward_dir
	else:
		aim_dir = _clamp_aim_dir(aim_dir)
	if aim_dir != Vector2.ZERO:
		rotation = aim_dir.angle()

func set_anchor(pos: Vector2) -> void:
	_anchor = pos
	position = pos
	_dragging = false
	power = 0.0
	_forward_dir = _derive_forward_dir()
	if aim_dir != Vector2.ZERO:
		aim_dir = _clamp_aim_dir(aim_dir)
		rotation = aim_dir.angle()

func set_aim_constraint(corner_a: Vector2, corner_b: Vector2) -> void:
	_corner_a = corner_a
	_corner_b = corner_b
	_forward_dir = _derive_forward_dir()
	aim_dir = _forward_dir if aim_dir == Vector2.ZERO else _clamp_aim_dir(aim_dir)
	if aim_dir != Vector2.ZERO:
		rotation = aim_dir.angle()

func _derive_forward_dir() -> Vector2:
	if _corner_a == Vector2.ZERO or _corner_b == Vector2.ZERO:
		return Vector2.ZERO
	var edge := _corner_b - _corner_a
	var mid := (_corner_a + _corner_b) * 0.5
	if absf(edge.x) >= absf(edge.y):
		return Vector2(0.0, -signf(mid.y - _anchor.y))
	return Vector2(-signf(mid.x - _anchor.x), 0.0)

func _signed_angle(from_dir: Vector2, to_dir: Vector2) -> float:
	return wrapf(to_dir.angle() - from_dir.angle(), -PI, PI)

func _cue_half_width_at(along: float) -> float:
	if along < CUE_WIDTH_PROFILE[0].x:
		return 0.0
	for i in range(CUE_WIDTH_PROFILE.size() - 1):
		var a: Vector2 = CUE_WIDTH_PROFILE[i]
		var b: Vector2 = CUE_WIDTH_PROFILE[i + 1]
		if along <= b.x:
			var t := inverse_lerp(a.x, b.x, along)
			return lerpf(a.y, b.y, t)
	return CUE_WIDTH_PROFILE[CUE_WIDTH_PROFILE.size() - 1].y

func _corner_visible_at_angle(corner: Vector2, angle: float) -> bool:
	var shot_dir := _forward_dir.rotated(angle)
	var tail_dir := -shot_dir
	var to_corner := corner - _anchor
	var along := to_corner.dot(tail_dir)
	if along <= 0.0:
		return true
	var lateral := absf(to_corner.cross(tail_dir))
	return lateral >= _cue_half_width_at(along) + CORNER_VISIBILITY_MARGIN

func _limit_angle_for_visible_corner(corner: Vector2) -> float:
	var to_corner := _anchor - corner
	if to_corner == Vector2.ZERO:
		return 0.0
	var centerline_angle := _signed_angle(_forward_dir, to_corner.normalized())
	if is_zero_approx(centerline_angle):
		return 0.0

	var low := 0.0
	var high := absf(centerline_angle)
	var side := signf(centerline_angle)
	if _corner_visible_at_angle(corner, side * high):
		return centerline_angle
	for _i in range(18):
		var mid := (low + high) * 0.5
		if _corner_visible_at_angle(corner, side * mid):
			low = mid
		else:
			high = mid
	return side * low

# Keep the cue inside the allowed aim range and away from the inside corners.
func _clamp_aim_dir(d: Vector2) -> Vector2:
	if _corner_a == Vector2.ZERO or d == Vector2.ZERO or _forward_dir == Vector2.ZERO:
		return d
	var angle_a := _limit_angle_for_visible_corner(_corner_a)
	var angle_b := _limit_angle_for_visible_corner(_corner_b)
	var min_angle := minf(angle_a, angle_b)
	var max_angle := maxf(angle_a, angle_b)
	var requested := _signed_angle(_forward_dir, d.normalized())
	var clamped := clampf(requested, min_angle, max_angle)
	return _forward_dir.rotated(clamped)

func _process(_delta):
	var mouse_pos := get_global_mouse_position()
	var to_mouse := mouse_pos - _anchor

	if not _dragging:
		# Normal aiming.
		if to_mouse.length() > 1.0:
			aim_dir = _clamp_aim_dir(to_mouse.normalized())
			rotation = aim_dir.angle()
		position = _anchor
		power = 0.0

		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and to_mouse.length() > 1.0:
			_dragging = true
			_click_pos = mouse_pos
	else:
		# Pulling back increases shot power.
		var drag := mouse_pos - _click_pos
		var pull: float = clamp(-drag.dot(aim_dir), 0.0, MAX_PULL_PIXELS)
		power = (pull / MAX_PULL_PIXELS) * get_parent().MAX_POWER
		position = _anchor - aim_dir * pull
		rotation = aim_dir.angle()

		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_dragging = false
			if pull > 2.0:
				shoot.emit(power * SHOT_SCALE * aim_dir)
			power = 0.0
