class_name VesselSegment
extends Node3D
## One stretch of blood vessel: a curved centreline with a varying radius,
## rendered as a tube we fly inside. A segment either continues into one
## child segment or ends in a fork with two children.

const STEP := 1.5        # metres between centreline samples / mesh rings
const SIDES := 28        # vertices around each ring
const FORK_FLARE := 1.12 # how much the vessel widens just before a fork
const FORK_CHILD_R := 0.66
const FORK_SPREAD := 0.38

var pts := PackedVector3Array()    # centreline, local to this node
var tans := PackedVector3Array()   # forward direction
var ups := PackedVector3Array()    # parallel-transported "up"
var rights := PackedVector3Array()
var radii := PackedFloat32Array()
var length := 0.0
var start_dist := 0.0              # distance along the route at s = 0
var depth := 0
var children_segs: Array = []
var is_fork := false
var fork_axis := Vector2.RIGHT     # split direction in the end frame (right, up)
var fork_angle := 0.45             # divergence of each branch, radians


func build(rng: RandomNumberGenerator, origin: Vector3, dir: Vector3, up: Vector3,
		start_r: float, seg_len: float, diff: Dictionary, make_fork: bool) -> void:
	position = origin
	is_fork = make_fork
	var d := dir.normalized()
	var u := (up - d * up.dot(d)).normalized()
	var n := int(ceil(seg_len / STEP)) + 1
	length = (n - 1) * STEP

	var base_r: float = rng.randf_range(float(diff.r_min), float(diff.r_max))
	var narrow_chance: float = diff.narrow
	var narrow_depth: float = diff.narrow_depth
	var cons: Array[Vector3] = []   # (centre s, half width, radius factor)
	if length > 70.0 and rng.randf() < narrow_chance:
		cons.append(Vector3(rng.randf_range(35.0, length - 35.0), rng.randf_range(10.0, 22.0),
				rng.randf_range(narrow_depth, narrow_depth + 0.15)))
	if length > 160.0 and rng.randf() < narrow_chance * 0.5:
		cons.append(Vector3(rng.randf_range(35.0, length - 35.0), rng.randf_range(8.0, 16.0),
				rng.randf_range(narrow_depth, narrow_depth + 0.2)))

	var wobble_phase := rng.randf() * TAU
	var wobble_freq := rng.randf_range(0.03, 0.07)
	var max_turn: float = diff.get("turn", 0.016)
	var yaw_rate := 0.0
	var pitch_rate := 0.0
	var p := Vector3.ZERO

	for i in n:
		var s := i * STEP
		var r := base_r * (1.0 + 0.07 * sin(s * wobble_freq + wobble_phase))
		for c in cons:
			var x := absf(s - c.x) / c.y
			if x < 1.0:
				r *= lerpf(1.0, c.z, (cos(x * PI) + 1.0) * 0.5)
		r = lerpf(start_r, r, smoothstep(0.0, 20.0, s))
		r = maxf(r, 2.3)
		if is_fork:
			r *= lerpf(1.0, FORK_FLARE, smoothstep(length - 16.0, length, s))
		var right := d.cross(u).normalized()
		pts.append(p)
		tans.append(d)
		ups.append(u)
		rights.append(right)
		radii.append(r)

		# Random-walk the curvature so the vessel snakes around.
		yaw_rate = clampf(yaw_rate * 0.985 + rng.randf_range(-1.0, 1.0) * max_turn * 0.12, -max_turn, max_turn)
		pitch_rate = clampf(pitch_rate * 0.985 + rng.randf_range(-1.0, 1.0) * max_turn * 0.12, -max_turn, max_turn)
		var calm := 1.0 - smoothstep(length - 30.0, length - 10.0, s) if is_fork else 1.0
		calm *= smoothstep(0.0, 12.0, s)
		var nd := d.rotated(u, yaw_rate * STEP * calm)
		nd = nd.rotated(right, pitch_rate * STEP * calm).normalized()
		var axis := d.cross(nd)
		if axis.length() > 1e-6:
			u = u.rotated(axis.normalized(), d.angle_to(nd))
		u = (u - nd * u.dot(nd)).normalized()
		d = nd
		p += d * STEP

	if is_fork:
		var a := rng.randf_range(-0.6, 0.6)
		if rng.randf() < 0.3:
			a += PI * 0.5
		fork_axis = Vector2.from_angle(a)
		fork_angle = rng.randf_range(0.38, 0.55)


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
		var v := (start_dist + i * STEP) / 6.0
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


## Where each branch starts, as an offset in this segment's end frame.
func fork_offsets() -> Array[Vector2]:
	var re := radii[radii.size() - 1] / FORK_FLARE
	var out: Array[Vector2] = []
	out.append(fork_axis * re * FORK_SPREAD)
	out.append(-fork_axis * re * FORK_SPREAD)
	return out


func end_radius() -> float:
	return radii[radii.size() - 1]
