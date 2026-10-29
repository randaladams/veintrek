class_name VesselSegment
extends Node3D
## One stretch of blood vessel: a curved centreline with a varying radius,
## rendered as a tube we fly inside. Segments chain end to end into a single
## path. Some segments contain sharp, announced turns.

const STEP := 1.5   # metres between centreline samples / mesh rings
const SIDES := 32   # vertices around each ring

var pts := PackedVector3Array()    # centreline, local to this node
var tans := PackedVector3Array()   # forward direction
var ups := PackedVector3Array()    # parallel-transported "up"
var rights := PackedVector3Array()
var radii := PackedFloat32Array()
var curv := PackedVector2Array()   # curvature in the local (right, up) frame, rad/m
var length := 0.0
var start_dist := 0.0              # distance along the route at s = 0
var next_seg: VesselSegment = null
## Sharp turns: each {s: start, len: length, dir: Vector2 (right, up), deg: total angle}
var turns: Array[Dictionary] = []


func build(rng: RandomNumberGenerator, origin: Vector3, dir: Vector3, up: Vector3,
		start_r: float, seg_len: float, diff: Dictionary, allow_turns: bool) -> void:
	position = origin
	var d := dir.normalized()
	var u := (up - d * up.dot(d)).normalized()
	var n := int(ceil(seg_len / STEP)) + 1
	length = (n - 1) * STEP

	var base_r: float = rng.randf_range(float(diff.r_min), float(diff.r_max))
	var narrow_chance: float = diff.narrow
	var narrow_depth: float = diff.narrow_depth
	var cons: Array[Vector3] = []   # (centre s, half width, radius factor)
	if length > 70.0 and rng.randf() < narrow_chance:
		cons.append(Vector3(rng.randf_range(35.0, length - 35.0), rng.randf_range(12.0, 24.0),
				rng.randf_range(narrow_depth, narrow_depth + 0.15)))

	# Plan sharp turns. Each is a smooth bend of 50-95 degrees over 25-45 m.
	if allow_turns:
		var want: float = length / 100.0 * float(diff.turns)
		var count := int(want) + (1 if rng.randf() < want - int(want) else 0)
		var cursor := 30.0
		for k in count:
			var deg := rng.randf_range(float(diff.turn_deg_min), float(diff.turn_deg_max))
			var peak: float = diff.sharp   # peak curvature, rad/m
			# With a sine-shaped curvature profile the total angle is peak * len * 2/pi.
			var tlen := deg_to_rad(deg) * PI / (2.0 * peak)
			var room := length - 15.0 - cursor - tlen
			if room < 0.0:
				break
			var ts := cursor + rng.randf_range(0.0, room / float(count - k))
			# Mostly left/right, sometimes up/down or diagonal, so the arrow reads clearly.
			var dirs := [Vector2.LEFT, Vector2.RIGHT, Vector2.LEFT, Vector2.RIGHT,
					Vector2.UP, Vector2.DOWN, Vector2(1, 1).normalized(), Vector2(-1, 1).normalized(),
					Vector2(1, -1).normalized(), Vector2(-1, -1).normalized()]
			var td: Vector2 = dirs[rng.randi() % dirs.size()]
			turns.append({"s": ts, "len": tlen, "dir": td, "deg": deg, "peak": peak})
			cursor = ts + tlen + 45.0

	var wobble_phase := rng.randf() * TAU
	var wobble_freq := rng.randf_range(0.03, 0.07)
	var max_turn: float = diff.get("turn", 0.01)
	var yaw_rate := 0.0
	var pitch_rate := 0.0
	var p := Vector3.ZERO

	for i in n:
		var s := i * STEP
		var r := base_r * (1.0 + 0.06 * sin(s * wobble_freq + wobble_phase))
		for c in cons:
			var x := absf(s - c.x) / c.y
			if x < 1.0:
				r *= lerpf(1.0, c.z, (cos(x * PI) + 1.0) * 0.5)
		r = lerpf(start_r, r, smoothstep(0.0, 25.0, s))
		r = maxf(r, 3.5)
		var right := d.cross(u).normalized()
		pts.append(p)
		tans.append(d)
		ups.append(u)
		rights.append(right)
		radii.append(r)

		# Gentle random wander, calmed down around sharp turns.
		var calm := smoothstep(0.0, 12.0, s)
		var k2 := Vector2.ZERO   # curvature this step, in (right, up)
		for t in turns:
			var a: float = (s - float(t.s)) / float(t.len)
			if a > -0.3 and a < 1.3:
				calm = 0.0
			if a >= 0.0 and a <= 1.0:
				k2 += (t.dir as Vector2) * float(t.peak) * sin(PI * a)
		yaw_rate = clampf(yaw_rate * 0.985 + rng.randf_range(-1.0, 1.0) * max_turn * 0.12, -max_turn, max_turn)
		pitch_rate = clampf(pitch_rate * 0.985 + rng.randf_range(-1.0, 1.0) * max_turn * 0.12, -max_turn, max_turn)
		k2 += Vector2(yaw_rate, pitch_rate) * calm
		curv.append(k2)

		# Bend the direction toward (right * k.x + up * k.y).
		var bend := right * k2.x + u * k2.y
		var nd := d
		if bend.length() > 1e-6:
			nd = d.rotated(d.cross(bend).normalized(), bend.length() * STEP).normalized()
		var axis := d.cross(nd)
		if axis.length() > 1e-6:
			u = u.rotated(axis.normalized(), d.angle_to(nd))
		u = (u - nd * u.dot(nd)).normalized()
		d = nd
		p += d * STEP


func build_mesh(mat: Material) -> void:
	var n := pts.size()
	var ring := SIDES + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	verts.resize(n * ring)
	norms.resize(n * ring)
	uvs.resize(n * ring)
	idx.resize((n - 1) * SIDES * 6)
	var cosv := PackedFloat32Array()
	var sinv := PackedFloat32Array()
	for j in ring:
		var a := TAU * float(j) / SIDES
		cosv.append(cos(a))
		sinv.append(sin(a))
	for i in n:
		var c := pts[i]
		var rt := rights[i]
		var up := ups[i]
		var r := radii[i]
		var v := (start_dist + i * STEP) / 8.0
		var base := i * ring
		for j in ring:
			var radial := rt * cosv[j] + up * sinv[j]
			verts[base + j] = c + radial * r
			norms[base + j] = -radial
			uvs[base + j] = Vector2(float(j) / SIDES, v)
	var k := 0
	for i in n - 1:
		for j in SIDES:
			var a := i * ring + j
			var b := a + 1
			var c := a + ring
			var e := c + 1
			idx[k] = a
			idx[k + 1] = c
			idx[k + 2] = b
			idx[k + 3] = b
			idx[k + 4] = c
			idx[k + 5] = e
			k += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# --- Sampling -------------------------------------------------------------

func _locate(s: float) -> Vector2:
	var f := clampf(s / STEP, 0.0, float(pts.size() - 1) - 0.0001)
	var i := int(f)
	return Vector2(i, f - i)


func point_at(s: float) -> Vector3:
	var l := _locate(s)
	var i := int(l.x)
	return pts[i].lerp(pts[i + 1], l.y)


func world_point_at(s: float) -> Vector3:
	return position + point_at(s)


func radius_at(s: float) -> float:
	var l := _locate(s)
	var i := int(l.x)
	return lerpf(radii[i], radii[i + 1], l.y)


func curvature_at(s: float) -> Vector2:
	var l := _locate(s)
	var i := int(l.x)
	return curv[i].lerp(curv[i + 1], l.y)


## Basis with x = right, y = up, z = backwards (so -z looks down the vessel).
func frame_at(s: float) -> Basis:
	var l := _locate(s)
	var i := int(l.x)
	var t := tans[i].lerp(tans[i + 1], l.y).normalized()
	var u := ups[i].lerp(ups[i + 1], l.y)
	u = (u - t * u.dot(t)).normalized()
	return Basis(t.cross(u), u, -t)


func local_offset_point(s: float, off: Vector2) -> Vector3:
	var b := frame_at(s)
	return point_at(s) + b.x * off.x + b.y * off.y


func end_radius() -> float:
	return radii[radii.size() - 1]


## True if s falls inside (or within `margin` metres of) a sharp turn.
func in_turn(s: float, margin: float = 0.0) -> bool:
	for t in turns:
		if s > float(t.s) - margin and s < float(t.s) + float(t.len) + margin:
			return true
	return false
