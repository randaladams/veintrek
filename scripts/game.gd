class_name Game
extends Node3D
## Runs a flight: the ship, tilt steering, weapons, enemies and the vessel.

signal ended(result: Dictionary)
signal pause_requested

enum State { IDLE, DEMO, COUNTDOWN, PLAYING, DYING, COMPLETE }

const SHIP_RADIUS := 0.9
const MAX_LATERAL := 13.0
const LASER_SPEED := 150.0
const BOLT_SPEED := 34.0
const ORIGIN_SHIFT_DIST := 2500.0
const MAX_INTEGRITY := 100.0
const BLOB_DRAIN := 2.0           # integrity per second per white cell on the glass
const LASER_COLORS := [Color(0.3, 0.95, 1.0), Color(0.3, 0.95, 1.0), Color(0.4, 0.8, 1.0),
		Color(0.6, 0.7, 1.0), Color(0.9, 0.6, 1.0)]

var state := State.IDLE
var mode := "demo"
var level_index := 0

var world: VesselWorld
var fx_root: Node3D
var camera: Camera3D
var hud: Cockpit
var _env: WorldEnvironment
var _plasma: CPUParticles3D

# Ship state
var seg: VesselSegment
var s := 0.0
var offset := Vector2.ZERO
var lat_vel := Vector2.ZERO
var speed := 0.0
var integrity := MAX_INTEGRITY
var laser_level := 1
var kill_points := 0
var kills := 0
var route_dist := 0.0
var player_pos := Vector3.ZERO
var forward := Vector3.FORWARD

var _cam_basis := Basis()
var _fire_cd := 0.0
var _cannon_side := 1.0
var _wall_cd := 0.0
var _countdown := 0.0
var _end_timer := 0.0
var _shake := 0.0
var _neutral := Vector2.ZERO
var _has_tilt := false
var _fire_touches: Dictionary = {}
var _drain_accum := 0.0
var _alarm_cd := 0.0
var _jolt_cd := 0.0
var _prev_accel := Vector3.ZERO
var _level_len := 0.0
var _finish_announced := false
var _fork_announced: VesselSegment = null
var _seed := 0
var bot := false   # debug autopilot, enabled with the --bot user argument
var god := false   # debug invulnerability, --god


func _ready() -> void:
	world = VesselWorld.new()
	world.game = self
	add_child(world)
	fx_root = Node3D.new()
	add_child(fx_root)

	camera = Camera3D.new()
	camera.fov = 78.0
	camera.near = 0.1
	camera.far = 240.0
	add_child(camera)
	var spot := SpotLight3D.new()
	spot.spot_range = 70.0
	spot.spot_angle = 38.0
	spot.light_energy = 6.0
	spot.light_color = Color(1.0, 0.88, 0.8)
	spot.spot_attenuation = 0.5
	camera.add_child(spot)
	var omni := OmniLight3D.new()
	omni.omni_range = 22.0
	omni.light_energy = 2.2
	omni.light_color = Color(1.0, 0.55, 0.45)
	omni.position = Vector3(0, 1.0, 0)
	camera.add_child(omni)
	_plasma = _make_plasma()
	camera.add_child(_plasma)

	_env = WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.1, 0.0, 0.015)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.1, 0.1)
	e.ambient_light_energy = 0.6
	e.fog_enabled = true
	e.fog_light_color = Color(0.17, 0.008, 0.02)
	e.fog_density = 0.024
	e.glow_enabled = true
	e.glow_intensity = 0.9
	e.glow_bloom = 0.12
	e.glow_hdr_threshold = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.environment = e
	add_child(_env)

	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	hud = Cockpit.new()
	hud.game = self
	layer.add_child(hud)


func _make_plasma() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 140
	p.lifetime = 4.0
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(7, 7, 35)
	p.position = Vector3(0, 0, -45)
	p.direction = Vector3(0, 0, 1)
	p.spread = 180.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 1.2
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.6
	p.mesh = Meshes.sphere(0.06, 4, 2)
	p.material_override = Meshes.glow_mat(Color(1.0, 0.75, 0.55), 1.2)
	return p


# --- Run control ------------------------------------------------------------

func start_demo() -> void:
	_begin("demo", 0)
	state = State.DEMO
	speed = float(get_difficulty(0.0).speed)
	hud.visible = false


func start(run_mode: String, level: int = 0) -> void:
	_begin(run_mode, level)
	hud.visible = true
	hud.reset()
	_countdown = 3.2
	state = State.COUNTDOWN
	if mode == "campaign":
		var lv: Dictionary = G.LEVELS[level_index]
		hud.set_banner(("LEVEL %d · %s" % [level_index + 1, String(lv.name).to_upper()]), String(lv.place), String(lv.brief))
	else:
		hud.set_banner("ENDLESS", "How deep can you go?", "Hold the phone comfortably. That angle is your centre.")


func _begin(run_mode: String, level: int) -> void:
	mode = run_mode
	level_index = level
	_clear_fx()
	_seed = randi()
	s = 0.0
	offset = Vector2.ZERO
	lat_vel = Vector2.ZERO
	integrity = MAX_INTEGRITY
	laser_level = 1
	kill_points = 0
	kills = 0
	route_dist = 0.0
	_fire_touches.clear()
	_drain_accum = 0.0
	_finish_announced = false
	_fork_announced = null
	_level_len = float(G.LEVELS[level].length) if mode == "campaign" else 0.0
	speed = 0.0
	seg = world.reset(_seed)
	_update_camera(1.0, true)
	Sfx.start_ambience()


func resume(recalibrate: bool) -> void:
	_fire_touches.clear()
	if recalibrate and state == State.PLAYING:
		_countdown = 2.2
		state = State.COUNTDOWN
		hud.set_banner("RECALIBRATING", "Hold the phone where you want centre", "")


func is_playing() -> bool:
	return state == State.PLAYING


func get_difficulty(dist: float) -> Dictionary:
	match mode:
		"campaign":
			return G.level_diff(level_index)
		"endless":
			return G.endless_diff(dist)
	return G.demo_diff()


func allow_fork_at(dist: float) -> bool:
	# No branching right at the start, or just before a campaign finish line.
	if dist < 150.0:
		return false
	if mode == "campaign" and dist > _level_len - 120.0:
		return false
	return true


func score() -> int:
	return int(route_dist) + kill_points


func _clear_fx() -> void:
	for c in fx_root.get_children():
		c.queue_free()


# --- Main loop -------------------------------------------------------------

func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	_update_beat()
	match state:
		State.IDLE:
			return
		State.DEMO:
			_fly(delta, true)
		State.COUNTDOWN:
			_countdown -= delta
			hud.countdown = _countdown
			if _countdown <= 0.0:
				_calibrate()
				state = State.PLAYING
				hud.countdown = -1.0
				hud.clear_banner()
				Sfx.play("go")
			_update_camera(delta)
		State.PLAYING:
			var target_speed: float = get_difficulty(route_dist).speed
			speed = move_toward(speed, target_speed, delta * 12.0)
			_fly(delta, false)
			_combat(delta)
			_check_progress()
		State.DYING:
			speed = move_toward(speed, 0.0, delta * 18.0)
			_fly(delta, true)
			_move_projectiles(delta, false)
			_end_timer -= delta
			if _end_timer <= 0.0:
				_finish(false)
		State.COMPLETE:
			_fly(delta, true)
			_move_projectiles(delta, false)
			_end_timer -= delta
			if _end_timer <= 0.0:
				_finish(true)
	_push_hud()


func _update_beat() -> void:
	var b := Sfx.beat_value()
	world.material.set_shader_parameter("beat", b)
	hud.beat = b


func _fly(delta: float, autopilot: bool) -> void:
	var steer := _autopilot() if (autopilot or bot) else _read_steer()
	lat_vel = lat_vel.lerp(steer * MAX_LATERAL, clampf(delta * 6.0, 0.0, 1.0))
	offset += lat_vel * delta
	_fork_assist(delta, autopilot)
	s += speed * delta
	route_dist = seg.start_dist + s
	while s > seg.length:
		_enter_next_segment()
	_wall_check(autopilot)
	world.update(seg, s, route_dist)
	_update_camera(delta)
	if player_pos.length() > ORIGIN_SHIFT_DIST:
		_shift_origin()


func _enter_next_segment() -> void:
	if seg.children_segs.is_empty():
		world.make_children(seg)
	var fr_old := seg.frame_at(seg.length)
	var pos := seg.world_point_at(seg.length) + fr_old.x * offset.x + fr_old.y * offset.y
	var vel3 := fr_old.x * lat_vel.x + fr_old.y * lat_vel.y
	var best: VesselSegment = seg.children_segs[0]
	if seg.children_segs.size() > 1:
		var best_d := INF
		for c in seg.children_segs:
			var d: float = pos.distance_to(c.world_point_at(0.0))
			if d < best_d:
				best_d = d
				best = c
	s -= seg.length
	var old := seg
	seg = best
	route_dist = seg.start_dist + s
	world.on_enter(seg, old, route_dist)
	var fr := seg.frame_at(0.0)
	var rel := pos - seg.world_point_at(0.0)
	offset = Vector2(rel.dot(fr.x), rel.dot(fr.y))
	lat_vel = Vector2(vel3.dot(fr.x), vel3.dot(fr.y))


func _fork_assist(delta: float, autopilot: bool) -> void:
	# Near a branch, gently funnel the ship into whichever branch it leans toward.
	if not seg.is_fork:
		return
	var to_end := seg.length - s
	if to_end > 40.0:
		return
	var offs := seg.fork_offsets()
	var target := offs[0]
	if offset.distance_to(offs[1]) < offset.distance_to(offs[0]):
		target = offs[1]
	var strength := (1.0 - to_end / 40.0) * (2.6 if autopilot else 1.8)
	offset = offset.lerp(target, clampf(delta * strength, 0.0, 1.0))


func _wall_check(autopilot: bool) -> void:
	_wall_cd -= get_process_delta_time()
	var free_r := seg.radius_at(s) - SHIP_RADIUS
	var d := offset.length()
	if d <= free_r or d < 0.001:
		return
	var n := offset / d
	var push := d - free_r
	offset = n * free_r
	var vn := lat_vel.dot(n)
	if vn > 0.0:
		lat_vel -= n * vn * 1.7
	if autopilot or state != State.PLAYING:
		return
	if _wall_cd <= 0.0:
		_wall_cd = 0.45
		var dmg := 4.0 + clampf(vn, 0.0, 12.0) * 0.6 + push * 2.0
		var c := hud.size * 0.5
		var sp := c + Vector2(n.x, -n.y) * Vector2(hud.size.x * 0.42, hud.size.y * 0.36)
		damage(dmg, sp, "wall")


func _update_camera(delta: float, snap: bool = false) -> void:
	var fr := seg.frame_at(s)
	player_pos = seg.world_point_at(s) + fr.x * offset.x + fr.y * offset.y
	var look := seg.frame_at(s + 7.0)
	if s + 7.0 > seg.length and not seg.children_segs.is_empty():
		var nxt: VesselSegment = seg.children_segs[0]
		if seg.children_segs.size() > 1:
			var offs := seg.fork_offsets()
			if offset.distance_to(offs[1]) < offset.distance_to(offs[0]):
				nxt = seg.children_segs[1]
		look = nxt.frame_at(s + 7.0 - seg.length)
	# Bank and nudge the view toward the direction of travel.
	var b := look
	b = b.rotated(b.y, -lat_vel.x * 0.012)
	b = b.rotated(b.x, lat_vel.y * 0.012)
	b = b.rotated(b.z, -lat_vel.x * 0.022)
	b = b.orthonormalized()
	if snap:
		_cam_basis = b
	else:
		_cam_basis = _cam_basis.slerp(b, clampf(delta * 6.0, 0.0, 1.0)).orthonormalized()
	forward = -_cam_basis.z
	var shake_off := Vector3.ZERO
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 1.8)
		shake_off = Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * 0.35
		shake_off = _cam_basis * shake_off
	camera.global_transform = Transform3D(_cam_basis, player_pos + shake_off)


func _shift_origin() -> void:
	var v := player_pos
	world.shift(v)
	for c in fx_root.get_children():
		if c is Node3D:
			c.position -= v
	player_pos -= v
	camera.global_position -= v


# --- Input -------------------------------------------------------------------

func _tilt_angles() -> Vector2:
	var g := Input.get_gravity()
	if g.length_squared() < 0.01:
		g = Input.get_accelerometer()
	if g.length_squared() < 0.01:
		_has_tilt = false
		return Vector2.ZERO
	_has_tilt = true
	g = g.normalized()
	return Vector2(asin(clampf(g.x, -1.0, 1.0)), atan2(-g.z, -g.y))


func _calibrate() -> void:
	_neutral = _tilt_angles()


func _read_steer() -> Vector2:
	var v := Vector2(Input.get_axis("steer_left", "steer_right"), Input.get_axis("steer_down", "steer_up"))
	var a := _tilt_angles()
	if _has_tilt:
		var dv := a - _neutral
		dv.y = wrapf(dv.y, -PI, PI)
		var max_ang := deg_to_rad(22.0) / maxf(G.tilt_sensitivity, 0.2)
		var t := Vector2(dv.x / max_ang, -dv.y / max_ang)
		t.x = _curve(t.x)
		t.y = _curve(t.y)
		if G.invert_x:
			t.x = -t.x
		if G.invert_y:
			t.y = -t.y
		v += t
	return Vector2(clampf(v.x, -1.0, 1.0), clampf(v.y, -1.0, 1.0))


func _curve(x: float) -> float:
	var ax := absf(x)
	if ax < 0.06:
		return 0.0
	ax = (ax - 0.06) / 0.94
	return signf(x) * minf(pow(ax, 1.25), 1.0)


func _autopilot() -> Vector2:
	var r := maxf(seg.radius_at(s), 1.0)
	return (-offset / r * 1.6).limit_length(1.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if (state == State.PLAYING or state == State.COUNTDOWN) and hud.pause_rect().has_point(t.position):
				pause_requested.emit()
				get_viewport().set_input_as_handled()
				return
			if state == State.PLAYING and hud.try_scrape(t.position):
				Sfx.play("squish", -6.0, randf_range(1.2, 1.5))
				get_viewport().set_input_as_handled()
				return
			_fire_touches[t.index] = true
		else:
			_fire_touches.erase(t.index)
	elif event.is_action_pressed("pause"):
		if state == State.PLAYING or state == State.COUNTDOWN:
			pause_requested.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if state == State.PLAYING or state == State.COUNTDOWN:
			pause_requested.emit()


# --- Combat ------------------------------------------------------------------

func _combat(delta: float) -> void:
	_fire_cd -= delta
	var firing := G.auto_fire or bot or not _fire_touches.is_empty() or Input.is_action_pressed("fire")
	if firing and _fire_cd <= 0.0:
		_fire()
	_move_projectiles(delta, true)
	_check_contacts()

	var blobs := hud.active_blobs()
	if blobs > 0:
		var drain := BLOB_DRAIN * blobs * delta
		integrity -= drain
		if god:
			integrity = maxf(integrity, 1.0)
		if bot and randf() < delta * 1.5:
			hud.dislodge_one()
		_drain_accum += drain
		if _drain_accum > 12.0:
			_drain_accum = 0.0
			hud.add_crack(hud.random_blob_point(), 4.0)
			Sfx.play("crack", -8.0)
		if integrity <= 0.0:
			_die()

	# A sharp jolt of the phone shakes a white cell loose.
	_jolt_cd -= delta
	var acc := Input.get_accelerometer()
	if acc.length_squared() > 0.01:
		if _jolt_cd <= 0.0 and blobs > 0 and (acc - _prev_accel).length() > 13.0:
			if hud.dislodge_one():
				Sfx.play("squish", -4.0, 0.8)
				_jolt_cd = 0.45
		_prev_accel = acc

	_alarm_cd -= delta
	if integrity < 30.0 and _alarm_cd <= 0.0:
		_alarm_cd = 1.4
		Sfx.play("alarm", -8.0)


func _fire() -> void:
	var lvl := laser_level
	var interval: float = [0.22, 0.22, 0.14, 0.14, 0.11][lvl - 1]
	_fire_cd = interval
	var aim := _aim_direction()
	var shots: Array = []   # [local cannon offset, angular spread]
	match lvl:
		1:
			_cannon_side = -_cannon_side
			shots.append([Vector3(0.95 * _cannon_side, -0.6, -0.6), 0.0])
		2, 3:
			shots.append([Vector3(0.95, -0.6, -0.6), 0.0])
			shots.append([Vector3(-0.95, -0.6, -0.6), 0.0])
		4:
			shots.append([Vector3(0.95, -0.6, -0.6), 0.0])
			shots.append([Vector3(-0.95, -0.6, -0.6), 0.0])
			shots.append([Vector3(0.0, -0.85, -0.6), 0.0])
		_:
			shots.append([Vector3(0.95, -0.6, -0.6), 0.0])
			shots.append([Vector3(-0.95, -0.6, -0.6), 0.0])
			shots.append([Vector3(0.0, -0.85, -0.6), 0.0])
			shots.append([Vector3(1.2, -0.4, -0.6), 0.06])
			shots.append([Vector3(-1.2, -0.4, -0.6), -0.06])
	var target_pt := player_pos + aim * 70.0
	var mat := Meshes.glow_mat(LASER_COLORS[lvl - 1], 3.2)
	for sh in shots:
		var origin: Vector3 = camera.global_transform * (sh[0] as Vector3)
		var dir := (target_pt - origin).normalized()
		if absf(float(sh[1])) > 0.0:
			dir = dir.rotated(_cam_basis.y, float(sh[1]))
		var p := Projectile.new()
		fx_root.add_child(p)
		p.launch(origin, dir * LASER_SPEED + forward * speed, false)
		p.material_override = mat
		p.pierce = lvl >= 5
		p.damage = 1
	Sfx.play("laser", -9.0 if lvl > 1 else -7.0, randf_range(0.95, 1.08))


func _aim_direction() -> Vector3:
	# Light aim assist: snap to an enemy close to the crosshair.
	var best_dir := forward
	var best_cos := cos(deg_to_rad(7.0))
	for e in get_tree().get_nodes_in_group("enemy"):
		if e.dead:
			continue
		var to: Vector3 = e.global_position - player_pos
		var dist := to.length()
		if dist < 6.0 or dist > 85.0:
			continue
		var c := to.dot(forward) / dist
		if c > best_cos:
			best_cos = c
			best_dir = to / dist
	return best_dir


func enemy_fire(from: Vector3) -> void:
	var dist := from.distance_to(player_pos)
	var t := dist / (BOLT_SPEED + speed)
	var predicted := player_pos + forward * speed * t * 0.85
	var dir := (predicted - from).normalized()
	var b := Projectile.new()
	fx_root.add_child(b)
	b.launch(from, dir * BOLT_SPEED, true)
	Sfx.play("enemy_shot", -10.0, randf_range(0.9, 1.1))


func _move_projectiles(delta: float, collide: bool) -> void:
	var enemies := get_tree().get_nodes_in_group("enemy")
	for l in get_tree().get_nodes_in_group("laser"):
		var p := l as Projectile
		var p0 := p.position
		p.position += p.vel * delta
		p.life -= delta
		if collide:
			for e in enemies:
				if e.dead or p.hit_list.has(e):
					continue
				if _seg_hits_sphere(p0, p.position, e.global_position, e.radius):
					p.hit_list.append(e)
					if e.hit(p.damage):
						_on_kill(e)
					else:
						Sfx.play("thud", -10.0)
					if not p.pierce:
						p.life = 0.0
						break
		if p.life <= 0.0:
			p.queue_free()
	for b in get_tree().get_nodes_in_group("bolt"):
		var bp := b as Projectile
		var b0 := bp.position
		bp.position += bp.vel * delta
		bp.life -= delta
		if collide and _seg_hits_sphere(b0, bp.position, player_pos, SHIP_RADIUS + 0.45):
			bp.life = 0.0
			damage(8.0, camera.unproject_position(b0), "bolt")
		if bp.life <= 0.0:
			bp.queue_free()


func _seg_hits_sphere(a: Vector3, b: Vector3, c: Vector3, r: float) -> bool:
	var ab := b - a
	var l2 := ab.length_squared()
	var t := 0.0
	if l2 > 1e-6:
		t = clampf((c - a).dot(ab) / l2, 0.0, 1.0)
	return (a + ab * t).distance_squared_to(c) <= r * r


func _check_contacts() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if e.dead:
			continue
		var d: float = e.global_position.distance_to(player_pos)
		if d > e.radius + SHIP_RADIUS + 0.3:
			continue
		var sp := camera.unproject_position(e.global_position) if not camera.is_position_behind(e.global_position) else hud.size * 0.5
		if e is WhiteCell:
			e.dead = true
			e.queue_free()
			hud.add_blob(sp)
			Sfx.play("squish", -2.0)
			_vibrate(60)
			hud.show_message("WHITE CELL ON THE GLASS · TAP IT OR SHAKE!", Color(1.0, 0.95, 0.85), 2.0)
		else:
			e.dead = true
			burst(e.global_position, Color(0.9, 0.08, 0.06), 30)
			e.queue_free()
			damage(12.0, sp, "cell")
	for pu in get_tree().get_nodes_in_group("powerup"):
		if pu.global_position.distance_to(player_pos) < pu.radius:
			_collect(pu)


func _collect(pu: PowerUp) -> void:
	if pu.kind == "repair":
		var before := integrity
		integrity = minf(MAX_INTEGRITY, integrity + 30.0)
		hud.heal(integrity - before)
		hud.dislodge_one()
		hud.show_message("WINDOW REPAIRED +%d" % int(integrity - before), Color(0.4, 1.0, 0.9))
		Sfx.play("repair")
	else:
		if laser_level < 5:
			laser_level += 1
			hud.show_message("LASER MK-%d" % laser_level, Color(1.0, 0.82, 0.3))
		else:
			kill_points += 500
			hud.show_message("LASERS MAXED · +500", Color(1.0, 0.82, 0.3))
		Sfx.play("upgrade")
	burst(pu.global_position, Color(0.4, 1.0, 0.9) if pu.kind == "repair" else Color(1.0, 0.8, 0.2), 24)
	pu.queue_free()


func _on_kill(e: Node) -> void:
	kills += 1
	kill_points += int(e.points)
	Sfx.play("splat", -4.0, randf_range(0.85, 1.15))


func damage(amount: float, screen_pos: Vector2, kind: String) -> void:
	if state != State.PLAYING:
		return
	integrity -= amount
	if god:
		integrity = maxf(integrity, 1.0)
	hud.add_crack(screen_pos, amount)
	hud.flash(0.35 + amount * 0.02)
	_shake = maxf(_shake, 0.35 + amount * 0.03)
	Sfx.play("crack" if kind != "wall" else "scrape", -2.0, randf_range(0.9, 1.1))
	Sfx.play("thud", -4.0)
	_vibrate(int(30 + amount * 5))
	if integrity <= 0.0:
		_die()


func _vibrate(ms: int) -> void:
	if G.vibration and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)


func burst(pos: Vector3, color: Color, amount: int) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.8
	p.explosiveness = 0.95
	p.direction = Vector3(0, 0, 1)
	p.spread = 180.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 11.0
	p.gravity = Vector3.ZERO
	p.damping_min = 3.0
	p.damping_max = 7.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.4
	p.mesh = Meshes.droplet_mesh()
	p.material_override = Meshes.particle_mat()
	p.color = color
	fx_root.add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.3, false).timeout.connect(p.queue_free)


# --- Progress & ending -------------------------------------------------------

func _check_progress() -> void:
	if seg.is_fork and seg.length - s < 110.0 and _fork_announced != seg:
		_fork_announced = seg
		hud.show_message("BRANCH AHEAD · LEAN TO CHOOSE", Color(0.6, 0.95, 1.0), 1.8)
		Sfx.play("blip", -6.0)
	if mode == "campaign":
		var remaining := _level_len - route_dist
		if remaining < 200.0 and not _finish_announced:
			_finish_announced = true
			hud.show_message("TARGET 200 M AHEAD", Color(1.0, 0.85, 0.5), 2.0)
		if remaining <= 0.0:
			state = State.COMPLETE
			_end_timer = 2.4
			kill_points += int(integrity) * 10
			hud.set_banner("TARGET REACHED", String(G.LEVELS[level_index].place), "Glass bonus +%d" % (int(integrity) * 10))
			Sfx.play("victory")


func _die() -> void:
	if state != State.PLAYING:
		return
	integrity = 0.0
	state = State.DYING
	_end_timer = 2.4
	hud.shatter()
	_shake = 1.2
	Sfx.play("shatter")
	_vibrate(500)


func _finish(victory: bool) -> void:
	state = State.IDLE
	var res := {
		"mode": mode, "level": level_index, "victory": victory,
		"score": score(), "distance": int(route_dist), "kills": kills, "new_high": false,
	}
	if mode == "endless" and score() > G.high_score:
		G.high_score = score()
		res.new_high = true
	if mode == "campaign" and victory:
		G.complete_level(level_index, score())
	G.save_data()
	ended.emit(res)


func _push_hud() -> void:
	if not hud.visible:
		return
	hud.integrity = integrity
	hud.laser_level = laser_level
	hud.score = score()
	hud.distance = route_dist
	hud.speed = speed
	hud.remaining = _level_len - route_dist if mode == "campaign" else -1.0
	hud.fork_points.clear()
	if state == State.PLAYING and seg.is_fork and seg.length - s < 90.0:
		for c in seg.children_segs:
			var wp: Vector3 = c.world_point_at(minf(45.0, c.length))
			if not camera.is_position_behind(wp):
				hud.fork_points.append(camera.unproject_position(wp))


# --- Spawning ------------------------------------------------------------------

func populate(sg: VesselSegment, diff: Dictionary) -> void:
	var rng := world.rng
	var s0 := 70.0 if sg.start_dist < 1.0 else 6.0
	var s1 := sg.length - 8.0
	if mode == "campaign" and sg.start_dist + s0 > _level_len + 60.0:
		return
	if s1 <= s0:
		return
	var span := s1 - s0
	var red_n := int(round(span / 100.0 * float(diff.red) * rng.randf_range(0.75, 1.25)))
	var i := 0
	while i < red_n:
		var at := rng.randf_range(s0, s1)
		if rng.randf() < 0.12 and i + 3 < red_n:
			# A rouleau: a short stack of cells like coins.
			var o := _rand_disk(rng, sg.radius_at(at) * 0.5)
			for k in 4:
				_spawn_red(sg, minf(at + k * 1.1, s1), o, false, diff, rng)
			i += 4
			continue
		var shooter := mode != "demo" and rng.randf() < float(diff.shooter)
		_spawn_red(sg, at, _rand_disk(rng, sg.radius_at(at) * 0.7), shooter, diff, rng)
		i += 1
	if mode != "demo":
		var white_n := int(round(span / 100.0 * float(diff.white) * rng.randf_range(0.6, 1.3)))
		for k in white_n:
			var at := rng.randf_range(s0 + 10.0, s1)
			var w := WhiteCell.new()
			w.setup(self, sg, at, _rand_disk(rng, sg.radius_at(at) * 0.6), rng)
			sg.add_child(w)
		# Power-ups on a fixed spacing along the route; every branch gets them.
		var spacing: float = diff.powerup
		var k := int(ceil((sg.start_dist + s0) / spacing))
		while k * spacing < sg.start_dist + s1:
			var at := k * spacing - sg.start_dist
			_spawn_powerup(sg, at, rng)
			k += 1
		# Reward for picking a branch: sometimes a bonus pickup just inside it.
		if sg.depth > 0 and rng.randf() < 0.35 and sg.length > 60.0:
			_spawn_powerup(sg, 35.0, rng)


func _spawn_red(sg: VesselSegment, at: float, off: Vector2, shooter: bool, diff: Dictionary, rng: RandomNumberGenerator) -> void:
	var c := RedCell.new()
	c.setup(self, sg, at, off, shooter, float(diff.fire_interval), rng)
	sg.add_child(c)


func _spawn_powerup(sg: VesselSegment, at: float, rng: RandomNumberGenerator) -> void:
	var kind := "repair" if rng.randf() < 0.55 else "laser"
	var p := PowerUp.new()
	p.setup(kind, sg.local_offset_point(at, _rand_disk(rng, sg.radius_at(at) * 0.45)))
	sg.add_child(p)


func _rand_disk(rng: RandomNumberGenerator, r: float) -> Vector2:
	return Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * r
