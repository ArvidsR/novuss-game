extends Node2D

# This file plays a small effect when a piece falls into a pocket.
const PARTICLE_COUNT := 28
const LIFETIME := 0.65

func burst_at(pos: Vector2, base_color: Color) -> void:
	# Create quick particles at the pocket point.
	var p := CPUParticles2D.new()
	add_child(p)
	p.position = pos
	p.one_shot = true
	p.amount = PARTICLE_COUNT
	p.lifetime = LIFETIME
	p.explosiveness = 1.0
	p.spread = 180.0
	p.initial_velocity_min = 90.0
	p.initial_velocity_max = 260.0
	p.scale_amount_min = 1.5
	p.scale_amount_max = 4.0
	p.color = base_color
	p.gravity = Vector2.ZERO
	p.damping_min = 4.0
	p.damping_max = 9.0
	p.emitting = true

	# Add a ring so the pocket feels stronger.
	var ring := _make_ring(pos, base_color)
	add_child(ring)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector2(2.4, 2.4), 0.45)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "modulate:a", 0.0, 0.45)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	await get_tree().create_timer(LIFETIME + 0.15).timeout
	if is_instance_valid(p):
		p.queue_free()
	if is_instance_valid(ring):
		ring.queue_free()

func _make_ring(pos: Vector2, c: Color) -> Node2D:
	# Build a simple circle from many points.
	var node := Node2D.new()
	node.position = pos
	node.scale = Vector2.ONE
	node.modulate = Color(c.r, c.g, c.b, 0.85)
	var line := Line2D.new()
	line.width = 4.0
	line.default_color = Color(1, 1, 1, 1)
	line.closed = true
	var pts := PackedVector2Array()
	var segments := 32
	for i in segments:
		var a := TAU * float(i) / float(segments)
		pts.append(Vector2(cos(a), sin(a)) * 22.0)
	line.points = pts
	node.add_child(line)
	return node
