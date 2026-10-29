extends Node
## Wires the game world and the menus together.

var game: Game
var ui: UI
var _in_run := false


func _ready() -> void:
	game = Game.new()
	add_child(game)
	ui = UI.new()
	ui.main = self
	add_child(ui)
	game.ended.connect(_on_ended)
	game.pause_requested.connect(request_pause)
	to_menu()
	_debug_args()


func to_menu() -> void:
	get_tree().paused = false
	_in_run = false
	game.start_demo()
	ui.show_screen("main")


func start_campaign(level: int) -> void:
	get_tree().paused = false
	_in_run = true
	ui.hide_screens()
	game.start("campaign", level)


func start_endless() -> void:
	get_tree().paused = false
	_in_run = true
	ui.hide_screens()
	game.start("endless")


func request_pause() -> void:
	if not _in_run or get_tree().paused:
		return
	get_tree().paused = true
	ui.show_screen("pause")


func resume(recalibrate: bool) -> void:
	ui.hide_screens()
	get_tree().paused = false
	game.resume(recalibrate)


func _on_ended(result: Dictionary) -> void:
	_in_run = false
	ui.show_result(result)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		ui.on_back()


## Developer options, passed after "--" on the command line:
##   --start=endless | --start=campaign:N   jump straight into a run
##   --bot                                  autopilot + auto-fire
##   --god                                  window never breaks
##   --timescale=N                          speed up time
##   --shots=DIR --shot-every=SEC --shot-count=N   save screenshots, then quit
func _debug_args() -> void:
	var shots_dir := ""
	var every := 2.0
	var count := 5
	for a in OS.get_cmdline_user_args():
		if a == "--bot":
			game.bot = true
		elif a.begins_with("--menu="):
			ui.show_screen(a.get_slice("=", 1))
		elif a == "--fake-result":
			ui.show_result({"mode": "campaign", "level": 1, "victory": true, "score": 4210, "distance": 1600, "kills": 37, "new_high": false})
		elif a == "--selftest":
			_selftest()
		elif a == "--god":
			game.god = true
		elif a.begins_with("--timescale="):
			Engine.time_scale = float(a.get_slice("=", 1))
		elif a == "--start=endless":
			start_endless()
		elif a.begins_with("--start=campaign:"):
			start_campaign(int(a.get_slice(":", 1)))
		elif a.begins_with("--shots="):
			shots_dir = a.get_slice("=", 1)
		elif a.begins_with("--shot-every="):
			every = float(a.get_slice("=", 1))
		elif a.begins_with("--shot-count="):
			count = int(a.get_slice("=", 1))
	if shots_dir != "":
		_take_shots(shots_dir, every, count)


func _take_shots(dir: String, every: float, count: int) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	for i in count:
		await get_tree().create_timer(every, true).timeout
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			img.save_png("%s/shot_%02d.png" % [dir, i])
		print("[shot] %d integrity=%.0f dist=%.0f score=%d state=%d nodes=%d segs=%d fps=%d turn=%s@%.0f off=%s" % [i, game.integrity, game.route_dist, game.score(), game.state, Performance.get_monitor(Performance.OBJECT_NODE_COUNT), game.world.get_child_count(), Engine.get_frames_per_second(), game.hud.turn_dir, game.hud.turn_dist, game.offset.round()])
		if i == count - 1:
			print("[dmg] ", game.dmg_log, " shocks_left=", game.shock_charges, " laser=", game.laser_level, " kills=", game.kills)
	get_tree().quit()


## Injects real input events (no bot, no auto-fire) and checks the game responds.
func _selftest() -> void:
	var ok := true
	for key in ["input_devices/sensors/enable_accelerometer", "input_devices/sensors/enable_gravity"]:
		var on := bool(ProjectSettings.get_setting(key, false))
		print("[selftest] %s = %s" % [key, on])
		ok = ok and on
	start_endless()
	while not game.is_playing():   # wait out the countdown
		await get_tree().process_frame
	print("[selftest] run started, state=%d" % game.state)
	var W := get_viewport().get_visible_rect().size.x
	var H := get_viewport().get_visible_rect().size.y

	# Right side: hold to fire.
	_touch(0, Vector2(W * 0.8, H * 0.5), true)
	await get_tree().create_timer(0.6).timeout
	var lasers := get_tree().get_nodes_in_group("laser").size()
	print("[selftest] lasers while holding right side: %d" % lasers)
	ok = ok and lasers > 0
	_touch(0, Vector2(W * 0.8, H * 0.5), false)
	await get_tree().create_timer(1.6).timeout   # let the lasers expire

	# Left side: shock, with a white cell stuck to the glass. Must not fire.
	game.hud.add_blob(Vector2(W * 0.5, H * 0.4))
	var before := game.shock_charges
	var shots_before := game.shots_fired
	_touch(1, Vector2(W * 0.2, H * 0.5), true)
	await get_tree().create_timer(0.3).timeout
	_touch(1, Vector2(W * 0.2, H * 0.5), false)
	var left_lasers := game.shots_fired - shots_before
	print("[selftest] shock charges %d -> %d, cells on glass now %d, shots fired from left side %d" % [
			before, game.shock_charges, game.hud.active_blobs(), left_lasers])
	ok = ok and before == 3 and game.shock_charges == 2 and game.hud.active_blobs() == 0 and left_lasers == 0

	# Pause button (top right) still wins over the fire zone.
	_touch(2, game.hud.pause_rect().get_center(), true)
	await get_tree().process_frame
	await get_tree().process_frame
	print("[selftest] paused after tapping pause button: %s" % get_tree().paused)
	ok = ok and get_tree().paused
	print("[selftest] RESULT: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var t := InputEventScreenTouch.new()
	t.index = index
	t.position = pos
	t.pressed = pressed
	Input.parse_input_event(t)
