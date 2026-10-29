class_name RedCell
extends Node3D
## Red blood cell drifting with the flow. Infected ones are darker and shoot.

var game: Node
var seg: VesselSegment
var s := 0.0
var off := Vector2.ZERO
var flow := 0.0
var radius := 1.4
var hp := 1
var shooter := false
var dead := false
var points := 50
var _fire_interval := 2.5
var _fire_timer := 1.0
var _spin_axis := Vector3.UP
var _spin_speed := 1.0
var _core: MeshInstance3D
var _t := 0.0


func setup(g: Node, sg: VesselSegment, at_s: float, offset: Vector2, is_shooter: bool,
		fire_interval: float, rng: RandomNumberGenerator) -> void:
	game = g
	seg = sg
	s = at_s
	off = offset
	shooter = is_shooter
	_fire_interval = fire_interval
	_fire_timer = rng.randf_range(0.6, fire_interval + 0.6)
	flow = rng.randf_range(-1.5, 3.5)
	_spin_axis = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
	_spin_speed = rng.randf_range(0.3, 1.4)
	hp = 2 if shooter else 1
	points = 120 if shooter else 50
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.red_cell()
	mi.material_override = Meshes.red_cell_mat(shooter)
	add_child(mi)
	if shooter:
		_core = MeshInstance3D.new()
		_core.mesh = Meshes.sphere(0.42, 8, 4)
		_core.material_override = Meshes.glow_mat(Color(0.75, 1.0, 0.2), 3.0)
		add_child(_core)
	rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
	add_to_group("enemy")
	_place()


func _place() -> void:
	position = seg.local_offset_point(s, off)


func _process(delta: float) -> void:
	_t += delta
	rotate(_spin_axis, _spin_speed * delta)
	s = clampf(s + flow * delta, 0.0, seg.length)
	_place()
	if _core:
		_core.scale = Vector3.ONE * (1.0 + 0.25 * sin(_t * 9.0))
	if shooter and game.is_playing():
		var to_cell: Vector3 = global_position - game.player_pos
		var dist := to_cell.length()
		if dist < 95.0 and dist > 10.0 and to_cell.dot(game.forward) > dist * 0.5:
			_fire_timer -= delta
			if _fire_timer <= 0.0:
				_fire_timer = _fire_interval * randf_range(0.75, 1.3)
				game.enemy_fire(global_position)


## Returns true when the hit destroys the cell.
func hit(dmg: int) -> bool:
	if dead:
		return false
	hp -= dmg
	if hp <= 0:
		dead = true
		game.burst(global_position, Color(0.9, 0.08, 0.06) if not shooter else Color(0.6, 0.9, 0.2), 28)
		queue_free()
		return true
	game.burst(global_position, Color(1.0, 0.4, 0.3), 8)
	return false
