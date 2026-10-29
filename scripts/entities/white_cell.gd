class_name WhiteCell
extends Node3D
## Leukocyte. Drifts until the ship gets close, then hunts it down and
## latches onto the cockpit glass.

var game: Node
var seg: VesselSegment
var s := 0.0
var off := Vector2.ZERO
var radius := 1.7
var hp := 2
var dead := false
var chasing := false
var points := 150
var vel := Vector3.ZERO
var speed := 11.0
var _mat: ShaderMaterial
var _t := 0.0
var _hurt := 0.0


func setup(g: Node, sg: VesselSegment, at_s: float, offset: Vector2, rng: RandomNumberGenerator) -> void:
	game = g
	seg = sg
	s = at_s
	off = offset
	_t = rng.randf() * 10.0
	speed = rng.randf_range(9.0, 13.0)
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.white_cell_mesh()
	_mat = Meshes.white_cell_mat(rng.randf() * 100.0)
	mi.material_override = _mat
	add_child(mi)
	add_to_group("enemy")
	position = seg.local_offset_point(s, off)


func _process(delta: float) -> void:
	_t += delta
	if _hurt > 0.0:
		_hurt = maxf(0.0, _hurt - delta * 4.0)
		_mat.set_shader_parameter("hurt", _hurt)
	scale = Vector3.ONE * (1.0 + 0.06 * sin(_t * 3.1))
	if not chasing:
		var wob := Vector2(sin(_t * 0.8), cos(_t * 0.6)) * 0.6
		position = seg.local_offset_point(s, off + wob)
		if game.is_playing():
			var to_cell: Vector3 = global_position - game.player_pos
			if to_cell.length() < 60.0 and to_cell.dot(game.forward) > 0.0:
				chasing = true
	else:
		var to_ship: Vector3 = game.player_pos - global_position
		if to_ship.dot(game.forward) > 12.0:
			chasing = false   # left behind
			return
		vel = vel.lerp(to_ship.normalized() * speed, clampf(delta * 2.0, 0.0, 1.0))
		global_position += vel * delta


func hit(dmg: int) -> bool:
	if dead:
		return false
	hp -= dmg
	_hurt = 1.0
	if hp <= 0:
		dead = true
		game.burst(global_position, Color(0.95, 0.9, 0.85), 30)
		queue_free()
		return true
	game.burst(global_position, Color(0.95, 0.9, 0.85), 6)
	return false
