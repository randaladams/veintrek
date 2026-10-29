class_name VesselWorld
extends Node3D
## Grows the vessel ahead of the ship, one segment after another, and frees
## segments left behind.

const LOOKAHEAD := 300.0

var rng := RandomNumberGenerator.new()
var material: ShaderMaterial
var game: Node   # Game; untyped to avoid a circular class dependency
var _pending_free: Array = []   # [segment, free once route distance passes this]


func _init() -> void:
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/vessel.gdshader")


func clear() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_pending_free.clear()


func reset(seed_val: int) -> VesselSegment:
	clear()
	rng.seed = seed_val
	var diff: Dictionary = game.get_difficulty(0.0)
	var first := VesselSegment.new()
	first.start_dist = 0.0
	first.build(rng, Vector3.ZERO, Vector3.FORWARD, Vector3.UP, float(diff.r_max), 200.0, diff, false)
	_finish(first, diff)
	return first


func update(cur: VesselSegment, s: float, route_dist: float) -> void:
	var seg := cur
	var ahead := cur.length - s
	while ahead < LOOKAHEAD:
		ensure_next(seg)
		seg = seg.next_seg
		ahead += seg.length
	for i in range(_pending_free.size() - 1, -1, -1):
		var entry: Array = _pending_free[i]
		if route_dist >= float(entry[1]):
			_pending_free.remove_at(i)
			if is_instance_valid(entry[0]):
				entry[0].queue_free()


func ensure_next(seg: VesselSegment) -> void:
	if seg.next_seg != null:
		return
	var last := seg.pts.size() - 1
	var start := seg.start_dist + seg.length
	var diff: Dictionary = game.get_difficulty(start)
	var c := VesselSegment.new()
	c.start_dist = start
	var seg_len := rng.randf_range(float(diff.seg_min), float(diff.seg_max))
	c.build(rng, seg.position + seg.pts[last], seg.tans[last], seg.ups[last], seg.end_radius(),
			seg_len, diff, game.allow_turns_at(start, seg_len))
	seg.next_seg = c
	_finish(c, diff)


func _finish(seg: VesselSegment, diff: Dictionary) -> void:
	seg.build_mesh(material)
	add_child(seg)
	game.populate(seg, diff)


## Called when the ship moves from `old` into the next segment.
func on_leave(old: VesselSegment, route_dist: float) -> void:
	_pending_free.append([old, route_dist + 50.0])


## Keep coordinates near the origin on long runs to avoid float jitter.
func shift(v: Vector3) -> void:
	for c in get_children():
		if c is Node3D:
			c.position -= v
