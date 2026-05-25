extends Node2D

# This file draws the dashed aiming guide.
@export var dash_length: float = 14.0
@export var gap_length: float = 10.0
@export var max_length: float = 1500.0
@export var line_width: float = 4.0
@export var color: Color = Color(1.0, 1.0, 1.0, 0.7)
@export var bounce_color: Color = Color(1.0, 1.0, 1.0, 0.35)

var _origin: Vector2 = Vector2.ZERO
var _direction: Vector2 = Vector2.ZERO
var _exclude: Array = []
var _enabled: bool = false

func aim_from(from: Vector2, to: Vector2, exclude_rids: Array = []) -> void:
	# Save the current aim data and redraw the line.
	_origin = from
	var d := to - from
	_direction = d.normalized() if d.length() > 1.0 else Vector2.ZERO
	_exclude = exclude_rids
	queue_redraw()

func set_enabled(e: bool) -> void:
	if _enabled == e:
		return
	_enabled = e
	queue_redraw()

func _draw() -> void:
	# Stop here if aiming is hidden or there is no direction.
	if not _enabled or _direction == Vector2.ZERO:
		return

	# First ray shows the main path.
	var space := get_world_2d().direct_space_state
	var end := _origin + _direction * max_length
	var query := PhysicsRayQueryParameters2D.create(_origin, end, 1)
	query.exclude = _exclude
	var hit := space.intersect_ray(query)
	var stop: Vector2 = hit.position if hit else end
	_draw_dashed(_origin, stop, color)

	# If we hit a wall, draw one bounce preview too.
	if hit and hit.collider is StaticBody2D:
		var refl_dir: Vector2 = _direction.bounce(hit.normal)
		var bounce_start: Vector2 = stop + refl_dir * 2.0
		var bounce_end: Vector2 = bounce_start + refl_dir * 320.0
		var q2 := PhysicsRayQueryParameters2D.create(bounce_start, bounce_end, 1)
		q2.exclude = _exclude
		var hit2 := space.intersect_ray(q2)
		var b_stop: Vector2 = hit2.position if hit2 else bounce_end
		_draw_dashed(bounce_start, b_stop, bounce_color)

func _draw_dashed(a: Vector2, b: Vector2, base_color: Color) -> void:
	# Draw the line as many short pieces with gaps.
	var total := a.distance_to(b)
	if total < 1.0:
		return
	var unit := (b - a) / total
	var dist := 0.0
	var step := dash_length + gap_length
	while dist < total:
		var seg_start: Vector2 = a + unit * dist
		var seg_end: Vector2 = a + unit * minf(dist + dash_length, total)
		var fade: float = 1.0 - clampf(dist / max_length, 0.0, 1.0)
		var c: Color = base_color
		c.a *= clampf(fade, 0.18, 1.0)
		draw_line(seg_start, seg_end, c, line_width, true)
		dist += step
