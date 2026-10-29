class_name PowerUp
extends Node3D
## Floating pickup: "repair" restores window strength, "laser" upgrades the guns.

var kind := "repair"
var radius := 2.6
var _spin: Node3D
var _t := 0.0


func setup(k: String, local_pos: Vector3) -> void:
	kind = k
	position = local_pos
	_spin = Node3D.new()
	add_child(_spin)
	if kind == "repair":
		var col := Color(0.25, 1.0, 0.85)
		var ring := MeshInstance3D.new()
		ring.mesh = Meshes.torus(0.85, 1.1)
		ring.material_override = Meshes.glow_mat(col, 2.2)
		ring.rotation.x = PI * 0.5
		_spin.add_child(ring)
		for r in [0.0, PI * 0.5]:
			var bar := MeshInstance3D.new()
			bar.mesh = Meshes.box(Vector3(0.28, 1.1, 0.28))
			bar.material_override = Meshes.glow_mat(Color(0.9, 1.0, 1.0), 2.5)
			bar.rotation.z = r
			_spin.add_child(bar)
	else:
		var col := Color(1.0, 0.78, 0.15)
		var gem := MeshInstance3D.new()
		gem.mesh = Meshes.crystal()
		gem.material_override = Meshes.glow_mat(col, 2.6)
		_spin.add_child(gem)
		var ring := MeshInstance3D.new()
		ring.mesh = Meshes.torus(1.15, 1.3)
		ring.material_override = Meshes.glow_mat(Color(1.0, 0.55, 0.1), 2.0)
		_spin.add_child(ring)
	add_to_group("powerup")


func _process(delta: float) -> void:
	_t += delta
	_spin.rotation.y += delta * 2.2
	_spin.rotation.z = sin(_t * 1.7) * 0.3
	_spin.position.y = sin(_t * 2.5) * 0.25
