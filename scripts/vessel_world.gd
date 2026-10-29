class_name VesselWorld
extends Node3D
## Grows the vessel network ahead of the ship and frees what is left behind.

const LOOKAHEAD := 280.0

var rng := RandomNumberGenerator.new()
var material: ShaderMaterial
var game: Node   # Game; untyped to avoid a circular class dependency
var _pending_free: Array = []   # [segment, free once route distance passes this, free_subtree]


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
	_expand(cur, cur.length - s)
	for i in range(_pending_free.size() - 1, -1, -1):
		var entry: Array = _pending_free[i]
		if route_dist >= float(entry[1]):
			_pending_free.remove_at(i)
			if is_instance_valid(entry[0]):
				if entry[2]:
					_free_tree(entry[0])
				else:
					entry[0].queue_free()


func _expand(seg: VesselSegment, dist_to_end: float) -> void:
	if dist_to_end > LOOKAHEAD:
		return
	if seg.children_segs.is_empty():
		make_children(seg)
	for c in seg.children_segs:
		_expand(c, dist_to_end + c.length)


func make_children(seg: VesselSegment) -> void:
	var last := seg.pts.size() - 1
	var end_p := seg.position + seg.pts[last]
	var d := seg.tans[last]
	var u := seg.ups[last]
	var r := seg.rights[last]
	var child_start := seg.start_dist + seg.length
	var diff: Dictionary = game.get_difficulty(child_start)
	if seg.is_fork:
		var re := seg.end_radius() / VesselSegment.FORK_FLARE
		var ax3 := (r * seg.fork_axis.x + u * seg.fork_axis.y).normalized()
		for sgn in [1.0, -1.0]:
			var side: Vector3 = ax3 * sgn
			var q := Quaternion(d.cross(side).normalized(), seg.fork_angle)
			_spawn_child(seg, end_p + side * re * VesselSegment.FORK_SPREAD, q * d, q * u,
					re * VesselSegment.FORK_CHILD_R, child_start, diff)
	else:
		_spawn_child(seg, end_p, d, u, seg.end_radius(), child_start, diff)


func _spawn_child(parent: VesselSegment, origin: Vector3, d: Vector3, u: Vector3,
		start_r: float, start_dist: float, diff: Dictionary) -> void:
	var c := VesselSegment.new()
	c.start_dist = start_dist
	c.depth = parent.depth + 1
	var make_fork: bool = rng.randf() < float(diff.fork) and game.allow_fork_at(start_dist)
	var seg_len := rng.randf_range(float(diff.seg_min), float(diff.seg_max))
	c.build(rng, origin, d, u, start_r, seg_len, diff, make_fork)
	parent.children_segs.append(c)
	_finish(c, diff)


func _finish(seg: VesselSegment, diff: Dictionary) -> void:
	seg.build_mesh(material)
	add_child(seg)
	game.populate(seg, diff)


## Called when the ship moves from `old` into `entered`.
func on_enter(entered: VesselSegment, old: VesselSegment, route_dist: float) -> void:
	for sib in old.children_segs:
		if sib != entered:
			_pending_free.append([sib, route_dist + 70.0, true])
	old.children_segs = [entered]
	_pending_free.append([old, route_dist + 45.0, false])


func _free_tree(seg: VesselSegment) -> void:
	for c in seg.children_segs:
		if is_instance_valid(c):
			_free_tree(c)
	seg.queue_free()


## Keep coordinates near the origin on long runs to avoid float jitter.
func shift(v: Vector3) -> void:
	for c in get_children():
		if c is Node3D:
			c.position -= v
