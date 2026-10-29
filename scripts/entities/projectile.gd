class_name Projectile
extends MeshInstance3D
## Player laser or enemy plasma bolt. Moved and collided by Game.

var vel := Vector3.ZERO
var life := 1.2
var damage := 1
var pierce := false
var hostile := false
var hit_list: Array = []


func launch(pos: Vector3, velocity: Vector3, is_hostile: bool) -> void:
	vel = velocity
	hostile = is_hostile
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if hostile:
		mesh = Meshes.sphere(0.38, 8, 4)
		material_override = Meshes.glow_mat(Color(0.7, 1.0, 0.15), 3.0)
		life = 4.0
		add_to_group("bolt")
	else:
		mesh = Meshes.laser_mesh()
		add_to_group("laser")
		var dir := velocity.normalized()
		if absf(dir.dot(Vector3.UP)) < 0.999:
			transform.basis = Basis(Quaternion(Vector3.UP, dir))
	position = pos
