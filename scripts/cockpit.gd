class_name Cockpit
extends Control
## The view out of the cockpit: window struts, dashboard gauges, cracks in the
## glass and white cells stuck to it. Everything is drawn procedurally.

const FRAME := Color(0.13, 0.12, 0.135)
const FRAME_HI := Color(0.33, 0.31, 0.34)
const FRAME_LO := Color(0.045, 0.04, 0.05)
const DASH := Color(0.085, 0.075, 0.085)
const SCREEN_BG := Color(0.12, 0.0, 0.015, 0.92)
const AMBER := Color(1.0, 0.72, 0.3)
const CYAN := Color(0.45, 0.95, 1.0)

var game: Node

# Values pushed by Game every frame.
var integrity := 100.0
var laser_level := 1
var score := 0
var distance := 0.0
var speed := 0.0
var remaining := -1.0
var beat := 0.0
var countdown := -1.0
var fork_points: Array[Vector2] = []
var steer := Vector2.ZERO
var tilt_ok := true

var _cracks: Array = []   # {lines: Array[PackedVector2Array] (normalised), o: Vector2, r: float}
var _blobs: Array = []    # {p, r, taps, ph, jig, fall, vy, a}
var _flash := 0.0
var _white := 0.0
var _msg := ""
var _msg_t := 0.0
var _msg_col := Color.WHITE
var _banner := ["", "", ""]
var _t := 0.0
var _ecg: PackedFloat32Array = PackedFloat32Array()
var _font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	_ecg.resize(90)


func reset() -> void:
	_cracks.clear()
	_blobs.clear()
	_flash = 0.0
	_white = 0.0
	_msg = ""
	_msg_t = 0.0
	countdown = -1.0
	fork_points.clear()


func _process(delta: float) -> void:
	_t += delta
	_flash = maxf(0.0, _flash - delta * 2.2)
	_white = maxf(0.0, _white - delta * 0.9)
	_msg_t -= delta
	for b in _blobs:
		b.jig = maxf(0.0, b.jig - delta * 3.0)
		if b.fall:
			b.vy += delta * 2.2
			var p: Vector2 = b.p
			p.y += b.vy * delta
			b.p = p
			b.a -= delta * 1.4
	_blobs = _blobs.filter(func(b): return b.a > 0.0)
	# Scrolling heartbeat trace for the dashboard.
	for i in _ecg.size() - 1:
		_ecg[i] = _ecg[i + 1]
	_ecg[_ecg.size() - 1] = beat
	queue_redraw()


# --- Events from Game -----------------------------------------------------------

func flash(amount: float) -> void:
	_flash = clampf(maxf(_flash, amount), 0.0, 0.8)


func show_message(text: String, col: Color = Color.WHITE, dur: float = 1.6) -> void:
	_msg = text
	_msg_col = col
	_msg_t = dur


func set_banner(title: String, sub: String, body: String) -> void:
	_banner = [title, sub, body]


func clear_banner() -> void:
	_banner = ["", "", ""]


func add_crack(screen_pos: Vector2, severity: float) -> void:
	var W := size.x
	var H := size.y
	if W < 1.0:
		return
	var o := Vector2(clampf(screen_pos.x, W * 0.06, W * 0.94), clampf(screen_pos.y, H * 0.07, H * 0.74))
	o += Vector2(randf_range(-1, 1), randf_range(-1, 1)) * H * 0.03
	var lines: Array[PackedVector2Array] = []
	var count := clampi(3 + int(severity / 3.0), 3, 9)
	for i in count:
		var ang := TAU * float(i) / count + randf_range(-0.4, 0.4)
		var len := H * (0.05 + severity * 0.007) * randf_range(0.6, 1.5)
		lines.append(_crack_line(o, ang, len, 5))
		if randf() < 0.45:
			var mid: Vector2 = lines[lines.size() - 1][2]
			lines.append(_crack_line(mid, ang + randf_range(-1.0, 1.0), len * 0.45, 3))
	var norm: Array[PackedVector2Array] = []
	for l in lines:
		var nl := PackedVector2Array()
		for p in l:
			nl.append(Vector2(p.x / W, p.y / H))
		norm.append(nl)
	_cracks.append({"lines": norm, "o": Vector2(o.x / W, o.y / H), "r": randf_range(0.008, 0.016)})
	while _cracks.size() > 34:
		_cracks.pop_front()


func _crack_line(from: Vector2, ang: float, len: float, steps: int) -> PackedVector2Array:
	var pl := PackedVector2Array([from])
	var p := from
	var a := ang
	for k in steps:
		a += randf_range(-0.55, 0.55)
		p += Vector2.from_angle(a) * len / steps
		pl.append(p)
	return pl


func heal(amount: float) -> void:
	var n := int(ceil(amount / 6.0))
	for i in n:
		if _cracks.is_empty():
			break
		_cracks.pop_front()


func shatter() -> void:
	_white = 1.0
	for i in 14:
		add_crack(Vector2(randf() * size.x, randf() * size.y * 0.75), 12.0)


func add_blob(screen_pos: Vector2) -> void:
	var p := Vector2(clampf(screen_pos.x / maxf(size.x, 1.0), 0.12, 0.88), clampf(screen_pos.y / maxf(size.y, 1.0), 0.14, 0.66))
	_blobs.append({"p": p, "r": randf_range(0.085, 0.12), "taps": 3, "ph": randf() * TAU,
			"jig": 1.0, "fall": false, "vy": 0.0, "a": 1.0})


func active_blobs() -> int:
	var n := 0
	for b in _blobs:
		if not b.fall:
			n += 1
	return n


func random_blob_point() -> Vector2:
	for b in _blobs:
		if not b.fall:
			return Vector2(b.p.x * size.x, b.p.y * size.y)
	return size * 0.5


func try_scrape(pos: Vector2) -> bool:
	for i in range(_blobs.size() - 1, -1, -1):
		var b: Dictionary = _blobs[i]
		if b.fall:
			continue
		var c := Vector2(b.p.x * size.x, b.p.y * size.y)
		if c.distance_to(pos) < b.r * size.y * 1.25:
			b.taps -= 1
			b.jig = 1.0
			if b.taps <= 0:
				b.fall = true
			return true
	return false


func dislodge_one() -> bool:
	for b in _blobs:
		if not b.fall:
			b.fall = true
			b.vy = 0.3
			return true
	return false


func pause_rect() -> Rect2:
	var h := size.y
	return Rect2(size.x - h * 0.14, h * 0.0, h * 0.14, h * 0.13)


# --- Drawing -----------------------------------------------------------------

func _draw() -> void:
	var W := size.x
	var H := size.y
	if W < 1.0:
		return
	_draw_fork_markers()
	_draw_blobs(W, H)
	_draw_cracks(W, H)
	_draw_frame(W, H)
	_draw_dashboard(W, H)
	_draw_crosshair(W, H)
	_draw_overlays(W, H)
	_draw_texts(W, H)
	_draw_pause(W, H)


func _draw_fork_markers() -> void:
	var a := 0.55 + 0.45 * sin(_t * 8.0)
	var sz := size.y * 0.05
	for p in fork_points:
		var col := Color(CYAN, a)
		for k in 4:
			var ang := PI * 0.25 + k * PI * 0.5
			var d := Vector2.from_angle(ang)
			var corner := p + d * sz
			draw_line(corner, corner - Vector2(d.x, 0) * sz * 0.6, col, 3.0, true)
			draw_line(corner, corner - Vector2(0, d.y) * sz * 0.6, col, 3.0, true)


func _draw_blobs(W: float, H: float) -> void:
	for b in _blobs:
		var c := Vector2(b.p.x * W, b.p.y * H)
		var r: float = b.r * H
		var alpha: float = b.a
		var jig: float = b.jig
		var pts := PackedVector2Array()
		for k in 30:
			var th := TAU * k / 30.0
			var rr := r * (1.0 + 0.08 * sin(5.0 * th + _t * 2.6 + b.ph) + 0.05 * sin(3.0 * th - _t * 1.7)
					+ jig * 0.12 * sin(th * 7.0 + _t * 40.0))
			pts.append(c + Vector2.from_angle(th) * rr)
		draw_colored_polygon(pts, Color(0.93, 0.87, 0.82, 0.78 * alpha))
		pts.append(pts[0])
		draw_polyline(pts, Color(0.7, 0.6, 0.62, 0.9 * alpha), 3.0, true)
		# Lobed nucleus
		for k in 3:
			var nc := c + Vector2.from_angle(b.ph + k * 2.1 + sin(_t + k) * 0.2) * r * 0.28
			draw_circle(nc, r * 0.24, Color(0.48, 0.3, 0.58, 0.8 * alpha))
		for k in 7:
			var g := c + Vector2.from_angle(b.ph * 3.0 + k * 0.9) * r * (0.45 + 0.08 * (k % 3))
			draw_circle(g, r * 0.035, Color(0.75, 0.62, 0.7, 0.8 * alpha))
		if not b.fall:
			var tap_txt := "TAP ×%d" % int(b.taps)
			draw_string(_font, c + Vector2(-r, r * 1.25), tap_txt, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0,
					int(H * 0.028), Color(1, 0.95, 0.9, 0.85 * alpha))


func _draw_cracks(W: float, H: float) -> void:
	for cr in _cracks:
		var o := Vector2(cr.o.x * W, cr.o.y * H)
		draw_circle(o, cr.r * H, Color(1, 1, 1, 0.22))
		for l in cr.lines:
			var pl := PackedVector2Array()
			for p in l:
				pl.append(Vector2(p.x * W, p.y * H))
			draw_polyline(pl, Color(0, 0, 0, 0.35), 3.0, true)
			draw_polyline(pl, Color(0.95, 0.97, 1.0, 0.75), 1.4, true)


func _strut(a: Vector2, b: Vector2, w: float) -> void:
	draw_line(a, b, FRAME_LO, w + 4.0, true)
	draw_line(a, b, FRAME, w, true)
	var n := (b - a).orthogonal().normalized()
	draw_line(a + n * w * 0.3, b + n * w * 0.3, FRAME_HI, maxf(1.5, w * 0.12), true)
	var len := a.distance_to(b)
	var count := int(len / (w * 4.0))
	for k in range(1, count):
		var p := a.lerp(b, float(k) / count) - n * w * 0.15
		draw_circle(p, w * 0.08, FRAME_HI)


func _draw_frame(W: float, H: float) -> void:
	var dash_y := H * 0.8
	var pw := W * 0.045
	var top := H * 0.05
	var inner := Rect2(W * 0.27, H * 0.115, W * 0.46, H * 0.5)
	var sw := H * 0.028
	# Outer pillars and roof
	draw_rect(Rect2(0, 0, W, top), FRAME)
	draw_line(Vector2(0, top), Vector2(W, top), FRAME_HI, 2.0)
	draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(pw, top), Vector2(pw * 1.4, dash_y), Vector2(0, dash_y)]), FRAME)
	draw_colored_polygon(PackedVector2Array([Vector2(W, 0), Vector2(W - pw, top), Vector2(W - pw * 1.4, dash_y), Vector2(W, dash_y)]), FRAME)
	draw_line(Vector2(pw, top), Vector2(pw * 1.4, dash_y), FRAME_HI, 2.0, true)
	draw_line(Vector2(W - pw, top), Vector2(W - pw * 1.4, dash_y), FRAME_HI, 2.0, true)
	# Struts from the front pane out to the frame, like a freighter canopy.
	var tl := inner.position
	var tr := Vector2(inner.end.x, inner.position.y)
	var bl := Vector2(inner.position.x, inner.end.y)
	var br := inner.end
	_strut(tl, Vector2(pw * 0.9, top * 0.9), sw)
	_strut(tr, Vector2(W - pw * 0.9, top * 0.9), sw)
	_strut(bl, Vector2(W * 0.16, dash_y - H * 0.04), sw * 1.1)
	_strut(br, Vector2(W * 0.84, dash_y - H * 0.04), sw * 1.1)
	_strut(Vector2(inner.position.x, inner.position.y + inner.size.y * 0.55), Vector2(pw * 1.2, H * 0.5), sw * 0.8)
	_strut(Vector2(inner.end.x, inner.position.y + inner.size.y * 0.55), Vector2(W - pw * 1.2, H * 0.5), sw * 0.8)
	_strut(Vector2(W * 0.5, top), Vector2(W * 0.5, inner.position.y), sw * 0.7)
	# Front pane border
	_strut(tl, tr, sw * 0.6)
	_strut(bl, br, sw * 0.7)
	_strut(tl, bl, sw * 0.6)
	_strut(tr, br, sw * 0.6)


func _draw_dashboard(W: float, H: float) -> void:
	var dash_y := H * 0.8
	var top_edge := PackedVector2Array()
	var n := 28
	for i in n + 1:
		var x := W * float(i) / n
		var k := absf(x - W * 0.5) / (W * 0.5)
		top_edge.append(Vector2(x, dash_y - k * k * H * 0.08))
	var poly := top_edge.duplicate()
	poly.append(Vector2(W, H))
	poly.append(Vector2(0, H))
	draw_colored_polygon(poly, DASH)
	draw_polyline(top_edge, FRAME_HI, 3.0, true)

	var fs := int(H * 0.03)
	# Left: glass integrity gauge
	var gc := Vector2(W * 0.16, H * 0.895)
	var gr := H * 0.062
	draw_circle(gc, gr * 1.25, FRAME_LO)
	draw_arc(gc, gr, PI * 0.8, PI * 2.2, 40, Color(0.25, 0.05, 0.06), gr * 0.28, true)
	var frac := clampf(integrity / 100.0, 0.0, 1.0)
	var gcol := Color(0.3, 1.0, 0.6).lerp(Color(1.0, 0.85, 0.2), clampf((0.7 - frac) * 2.5, 0, 1))
	if frac < 0.3:
		gcol = Color(1.0, 0.2, 0.15) if fmod(_t, 0.5) < 0.3 else Color(0.6, 0.05, 0.05)
	if frac > 0.0:
		draw_arc(gc, gr, PI * 0.8, PI * 0.8 + PI * 1.4 * frac, 40, gcol, gr * 0.28, true)
	draw_string(_font, gc + Vector2(-gr, fs * 0.35), "%d" % int(ceil(integrity)), HORIZONTAL_ALIGNMENT_CENTER, gr * 2.0, int(fs * 1.35), gcol)
	draw_string(_font, gc + Vector2(-gr * 1.6, gr * 1.15), "GLASS", HORIZONTAL_ALIGNMENT_CENTER, gr * 3.2, int(fs * 0.75), Color(0.75, 0.7, 0.72))

	# Centre: score screen with heartbeat trace
	var sr := Rect2(W * 0.36, H * 0.835, W * 0.28, H * 0.145)
	draw_rect(sr, SCREEN_BG)
	draw_rect(sr, Color(0.5, 0.1, 0.1), false, 2.0)
	draw_string(_font, Vector2(sr.position.x, sr.position.y + fs * 1.45), "%d" % score, HORIZONTAL_ALIGNMENT_CENTER, sr.size.x, int(fs * 1.5), AMBER)
	var line2 := "%d m" % int(distance)
	if remaining >= 0.0:
		line2 = "TARGET %d m" % int(maxf(remaining, 0.0))
	draw_string(_font, Vector2(sr.position.x, sr.position.y + fs * 2.55), line2, HORIZONTAL_ALIGNMENT_CENTER, sr.size.x, int(fs * 0.85), Color(1.0, 0.6, 0.5))
	var ecg := PackedVector2Array()
	var base_y := sr.end.y - sr.size.y * 0.16
	for i in _ecg.size():
		var x := sr.position.x + 6.0 + (sr.size.x - 12.0) * float(i) / (_ecg.size() - 1)
		var v := _ecg[i]
		ecg.append(Vector2(x, base_y - v * sr.size.y * 0.22 + sin(i * 2.7) * v * 3.0))
	draw_polyline(ecg, Color(0.4, 1.0, 0.55, 0.85), 2.0, true)

	# Right: laser level pips and speed
	var lx := W * 0.76
	var ly := H * 0.88
	draw_string(_font, Vector2(lx, ly - fs * 0.6), "LASER MK-%d" % laser_level, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs * 0.8), CYAN)
	for i in 5:
		var on := i < laser_level
		var pr := Rect2(lx + i * H * 0.042, ly, H * 0.032, H * 0.032)
		draw_rect(pr, CYAN if on else Color(0.12, 0.2, 0.22))
		draw_rect(pr, Color(0, 0, 0, 0.5), false, 1.5)
	draw_string(_font, Vector2(lx, ly + H * 0.075), "%d KM/H" % int(speed * 3.6), HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs * 0.75), Color(0.75, 0.7, 0.72))

	# Blinking indicator lights
	for i in 6:
		var on := fmod(_t * (0.7 + i * 0.37) + i, 1.0) < 0.5
		var cols := [Color(1, 0.2, 0.15), AMBER, Color(0.3, 1, 0.5)]
		var col: Color = cols[i % 3]
		draw_circle(Vector2(W * 0.27 + i * H * 0.026, H * 0.955), H * 0.007, col if on else col.darkened(0.8))
		draw_circle(Vector2(W * 0.68 + i * H * 0.026, H * 0.955), H * 0.007, col if not on else col.darkened(0.8))


func _draw_crosshair(W: float, H: float) -> void:
	var c := Vector2(W * 0.5, H * 0.5)
	var r := H * 0.03
	var col := Color(0.55, 1.0, 1.0, 0.6)
	draw_arc(c, r, 0, TAU, 24, col, 1.5, true)
	for k in 4:
		var d := Vector2.from_angle(k * PI * 0.5)
		draw_line(c + d * r * 1.3, c + d * r * 2.0, col, 2.0, true)
	# Steering indicator: where the tilt is pushing the ship.
	var sp := c + Vector2(steer.x, -steer.y) * r * 2.4
	draw_line(c, sp, Color(1.0, 0.8, 0.3, 0.5), 2.0, true)
	draw_circle(sp, r * 0.22, Color(1.0, 0.8, 0.3, 0.9))


func _draw_overlays(W: float, H: float) -> void:
	if _flash > 0.0:
		draw_rect(Rect2(0, 0, W, H), Color(1.0, 0.1, 0.05, _flash * 0.45))
	if integrity < 30.0 and integrity > 0.0:
		var a := (0.5 + 0.5 * sin(_t * 7.0)) * 0.35
		var e := H * 0.1
		draw_rect(Rect2(0, 0, W, e), Color(1, 0, 0, a))
		draw_rect(Rect2(0, H - e, W, e), Color(1, 0, 0, a * 0.6))
		draw_rect(Rect2(0, 0, e, H), Color(1, 0, 0, a))
		draw_rect(Rect2(W - e, 0, e, H), Color(1, 0, 0, a))
	if _white > 0.0:
		draw_rect(Rect2(0, 0, W, H), Color(1, 0.95, 0.95, _white * 0.7))


func _shadow_text(pos: Vector2, text: String, width: float, fsize: int, col: Color) -> void:
	draw_string(_font, pos + Vector2(2, 2), text, HORIZONTAL_ALIGNMENT_CENTER, width, fsize, Color(0, 0, 0, col.a * 0.8))
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, fsize, col)


func _draw_texts(W: float, H: float) -> void:
	if _banner[0] != "":
		_shadow_text(Vector2(0, H * 0.24), _banner[0], W, int(H * 0.07), Color(1.0, 0.85, 0.8))
		_shadow_text(Vector2(0, H * 0.3), _banner[1], W, int(H * 0.04), AMBER)
		_shadow_text(Vector2(0, H * 0.67), _banner[2], W, int(H * 0.032), Color(1, 0.9, 0.88, 0.9))
	if countdown > 0.0:
		var n := int(ceil(countdown))
		var f := countdown - floorf(countdown)
		_shadow_text(Vector2(0, H * 0.5 + H * 0.05), str(n), W, int(H * (0.12 + f * 0.05)), Color(1, 1, 1, 0.5 + f * 0.5))
	if _msg_t > 0.0:
		var a := clampf(_msg_t * 2.0, 0.0, 1.0)
		_shadow_text(Vector2(0, H * 0.4), _msg, W, int(H * 0.04), Color(_msg_col, a))
	if not tilt_ok:
		_shadow_text(Vector2(0, H * 0.14), "NO TILT SENSOR DATA", W, int(H * 0.035), Color(1, 0.8, 0.3))
	if integrity < 30.0 and integrity > 0.0 and fmod(_t, 0.8) < 0.5:
		_shadow_text(Vector2(0, H * 0.71), "GLASS CRITICAL", W, int(H * 0.035), Color(1, 0.25, 0.2))


func _draw_pause(W: float, H: float) -> void:
	var r := pause_rect()
	var c := r.get_center() + Vector2(-H * 0.01, H * 0.005)
	var rad := H * 0.04
	draw_circle(c, rad, Color(0.05, 0.02, 0.03, 0.85))
	draw_arc(c, rad, 0, TAU, 24, Color(0.85, 0.3, 0.25), 2.0, true)
	var bw := rad * 0.22
	var bh := rad * 0.9
	draw_rect(Rect2(c.x - bw * 1.6, c.y - bh * 0.5, bw, bh), Color(1, 0.85, 0.8))
	draw_rect(Rect2(c.x + bw * 0.6, c.y - bh * 0.5, bw, bh), Color(1, 0.85, 0.8))
