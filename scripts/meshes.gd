class_name Meshes
extends RefCounted
## Procedural meshes and shared materials, built once and cached.

static var _cache: Dictionary = {}


static func red_cell() -> ArrayMesh:
	if _cache.has("rbc"):
		return _cache["rbc"]
	# Biconcave disc from the Evans-Fung red blood cell profile, revolved around Y.
	var radius := 1.35
	var half := 16
	var segs := 24
	var prof_r: Array[float] = []
	var prof_z: Array[float] = []
	for k in half + 1:   # top surface, centre -> rim
		var a := PI * 0.5 * float(k) / half
		var r := sin(a)
		prof_r.append(r)
		prof_z.append(_rbc_h(r, cos(a)))
	for k in range(half - 1, -1, -1):   # bottom surface, rim -> centre
		var a := PI * 0.5 * float(k) / half
		var r := sin(a)
		prof_r.append(r)
		prof_z.append(-_rbc_h(r, cos(a)))
	var rows := prof_r.size()
	var ring := segs + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for i in rows:
		var i0 := maxi(i - 1, 0)
		var i1 := mini(i + 1, rows - 1)
		var dr := prof_r[i1] - prof_r[i0]
		var dz := prof_z[i1] - prof_z[i0]
		var n2 := Vector2(-dz, dr).normalized()
		if i == 0:
			n2 = Vector2(0, 1)
		elif i == rows - 1:
			n2 = Vector2(0, -1)
		for j in ring:
			var phi := TAU * float(j) / segs
			var cp := cos(phi)
			var sp := sin(phi)
			verts.append(Vector3(prof_r[i] * cp, prof_z[i], prof_r[i] * sp) * radius)
			norms.append(Vector3(n2.x * cp, n2.y, n2.x * sp).normalized())
	for i in rows - 1:
		for j in segs:
			var a := i * ring + j
			var b := a + 1
			var c := a + ring
			var d := c + 1
			idx.append_array([a, c, b, b, c, d])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_cache["rbc"] = m
	return m


static func _rbc_h(r: float, root: float) -> float:
	var r2 := r * r
	return 0.5 * root * (0.207 + 2.003 * r2 - 1.123 * r2 * r2)


static func red_cell_mat(infected: bool) -> StandardMaterial3D:
	var key := "rbc_mat_inf" if infected else "rbc_mat"
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	if infected:
		m.albedo_color = Color(0.35, 0.04, 0.16)
		m.emission_enabled = true
		m.emission = Color(0.45, 0.08, 0.3)
		m.emission_energy_multiplier = 0.8
	else:
		m.albedo_color = Color(0.95, 0.16, 0.12)
		m.emission_enabled = true
		m.emission = Color(0.55, 0.05, 0.04)
		m.emission_energy_multiplier = 0.7
	m.roughness = 0.3
	m.metallic_specular = 0.7
	m.rim_enabled = true
	m.rim = 0.5
	m.rim_tint = 0.4
	_cache[key] = m
	return m


static func glow_mat(color: Color, energy: float = 2.5) -> StandardMaterial3D:
	var key := "glow_%s_%.2f" % [color.to_html(), energy]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	_cache[key] = m
	return m


static func sphere(radius: float, segs: int = 12, rings_n: int = 6) -> SphereMesh:
	var key := "sphere_%.3f_%d_%d" % [radius, segs, rings_n]
	if _cache.has(key):
		return _cache[key]
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = segs
	s.rings = rings_n
	_cache[key] = s
	return s


static func white_cell_mesh() -> SphereMesh:
	return sphere(1.5, 32, 16)


static func white_cell_mat(seed_val: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("res://shaders/white_cell.gdshader")
	m.set_shader_parameter("seed", seed_val)
	return m


static func _shader(path: String) -> Shader:
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]


static func laser_mesh() -> CapsuleMesh:
	if _cache.has("laser"):
		return _cache["laser"]
	var c := CapsuleMesh.new()
	c.radius = 0.09
	c.height = 2.6
	c.radial_segments = 6
	c.rings = 1
	_cache["laser"] = c
	return c


static func droplet_mesh() -> SphereMesh:
	return sphere(0.16, 6, 3)


static func particle_mat() -> StandardMaterial3D:
	if _cache.has("particle_mat"):
		return _cache["particle_mat"]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	_cache["particle_mat"] = m
	return m


static func torus(inner: float, outer: float) -> TorusMesh:
	var key := "torus_%.2f_%.2f" % [inner, outer]
	if _cache.has(key):
		return _cache[key]
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 24
	t.ring_segments = 8
	_cache[key] = t
	return t


static func box(size: Vector3) -> BoxMesh:
	var key := "box_%s" % str(size)
	if _cache.has(key):
		return _cache[key]
	var b := BoxMesh.new()
	b.size = size
	_cache[key] = b
	return b


static func crystal() -> SphereMesh:
	# A 4-sided, 2-ring sphere is a diamond / octahedron.
	if _cache.has("crystal"):
		return _cache["crystal"]
	var s := SphereMesh.new()
	s.radius = 0.75
	s.height = 1.9
	s.radial_segments = 4
	s.rings = 1
	_cache["crystal"] = s
	return s
