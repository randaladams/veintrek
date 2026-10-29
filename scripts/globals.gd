extends Node
## Global settings, save data and level definitions (autoload "G").

const SAVE_PATH := "user://veintrek.cfg"

var tilt_sensitivity := 1.0
var invert_x := false
var invert_y := false
var auto_fire := false
var vibration := true
var volume := 0.8

var high_score := 0
var unlocked_level := 0
var level_best: Dictionary = {}

## Baseline tuning values. Levels and endless mode override some of them.
const DEFAULT_DIFF := {
	"speed": 20.0,          # forward speed, m/s
	"r_min": 10.0,          # vessel radius range, m
	"r_max": 12.5,
	"narrow": 0.25,         # chance per segment of a constriction
	"narrow_depth": 0.6,    # radius multiplier at the tightest point
	"turns": 0.3,           # sharp turns per 100 m
	"turn_deg_min": 50.0,   # how far each sharp turn bends
	"turn_deg_max": 80.0,
	"sharp": 0.04,          # peak curvature in a sharp turn, rad per metre
	"red": 5.0,             # red cells per 100 m
	"shooter": 0.15,        # fraction of red cells that shoot
	"fire_interval": 2.6,   # seconds between shots from a shooter
	"white": 0.5,           # white cells per 100 m
	"powerup": 250.0,       # metres between power-ups
	"seg_min": 150.0,
	"seg_max": 240.0,
	"turn": 0.008,          # max curvature of the gentle wander, rad per metre
}

const LEVELS: Array = [
	{
		"name": "Insertion", "place": "Femoral Artery",
		"brief": "Learn to steer. Lean into the turns when the arrows flash.",
		"length": 1200.0, "speed": 18.0, "r_min": 12.0, "r_max": 14.0,
		"narrow": 0.15, "narrow_depth": 0.7, "turns": 0.22, "turn_deg_max": 65.0, "sharp": 0.032,
		"red": 5.0, "shooter": 0.0, "white": 0.0, "powerup": 220.0,
	},
	{
		"name": "Upstream", "place": "Iliac Artery",
		"brief": "Infected red cells are firing back. Shoot the dark ones first.",
		"length": 1600.0, "speed": 20.0, "r_min": 11.0, "r_max": 13.0,
		"narrow": 0.25, "narrow_depth": 0.65, "turns": 0.28,
		"red": 6.0, "shooter": 0.22, "white": 0.3, "powerup": 240.0,
	},
	{
		"name": "Hairpins", "place": "Abdominal Aorta",
		"brief": "The aorta twists hard. Watch for turn warnings and lean early.",
		"length": 2000.0, "speed": 21.0, "r_min": 10.5, "r_max": 12.5,
		"narrow": 0.25, "narrow_depth": 0.6, "turns": 0.5, "turn_deg_min": 60.0, "turn_deg_max": 95.0, "sharp": 0.045,
		"red": 6.0, "shooter": 0.22, "white": 0.6, "powerup": 250.0,
	},
	{
		"name": "Capillary Run", "place": "Renal Capillaries",
		"brief": "Tight squeezes ahead. Stay centred or scrape the walls.",
		"length": 2000.0, "speed": 19.0, "r_min": 7.5, "r_max": 9.0,
		"narrow": 0.55, "narrow_depth": 0.6, "turns": 0.3, "sharp": 0.04,
		"red": 6.0, "shooter": 0.22, "white": 0.6, "powerup": 230.0,
	},
	{
		"name": "Immune Response", "place": "Splenic Vessels",
		"brief": "White cells swarm here. Touch the left side to shock them off the glass.",
		"length": 2200.0, "speed": 22.0, "r_min": 10.0, "r_max": 12.0,
		"narrow": 0.35, "narrow_depth": 0.6, "turns": 0.3,
		"red": 6.0, "shooter": 0.3, "white": 1.5, "powerup": 230.0,
	},
	{
		"name": "The Heart", "place": "Coronary Artery",
		"brief": "Everything the body has left. Reach the heart.",
		"length": 2600.0, "speed": 24.0, "r_min": 8.5, "r_max": 11.5,
		"narrow": 0.45, "narrow_depth": 0.55, "turns": 0.45, "turn_deg_max": 95.0, "sharp": 0.048,
		"red": 8.0, "shooter": 0.3, "fire_interval": 2.4, "white": 1.1, "powerup": 250.0,
	},
]


func _ready() -> void:
	_setup_input()
	load_data()
	apply_audio()


func level_diff(index: int) -> Dictionary:
	var d := DEFAULT_DIFF.duplicate()
	d.merge(LEVELS[index], true)
	return d


func endless_diff(dist: float) -> Dictionary:
	var t := clampf(dist / 9000.0, 0.0, 1.0)
	var d := DEFAULT_DIFF.duplicate()
	d.merge({
		"speed": lerpf(19.0, 30.0, t),
		"r_min": lerpf(11.0, 7.5, t),
		"r_max": lerpf(13.0, 10.0, t),
		"narrow": lerpf(0.2, 0.6, t),
		"narrow_depth": lerpf(0.68, 0.55, t),
		"turns": lerpf(0.22, 0.55, t),
		"turn_deg_max": lerpf(70.0, 100.0, t),
		"sharp": lerpf(0.032, 0.05, t),
		"red": lerpf(4.5, 10.0, t),
		"shooter": lerpf(0.08, 0.35, t),
		"fire_interval": lerpf(3.0, 2.0, t),
		"white": lerpf(0.3, 1.5, t),
		"powerup": lerpf(240.0, 300.0, t),
	}, true)
	return d


func demo_diff() -> Dictionary:
	var d := DEFAULT_DIFF.duplicate()
	d.merge({"speed": 13.0, "red": 5.0, "shooter": 0.0, "white": 0.0, "turns": 0.3}, true)
	return d


func complete_level(index: int, score: int) -> void:
	unlocked_level = maxi(unlocked_level, mini(index + 1, LEVELS.size() - 1))
	level_best[index] = maxi(int(level_best.get(index, 0)), score)
	save_data()


func apply_audio() -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(bus, volume <= 0.01)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volume, 0.01)))


func save_data() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("settings", "tilt_sensitivity", tilt_sensitivity)
	cfg.set_value("settings", "invert_x", invert_x)
	cfg.set_value("settings", "invert_y", invert_y)
	cfg.set_value("settings", "auto_fire", auto_fire)
	cfg.set_value("settings", "vibration", vibration)
	cfg.set_value("settings", "volume", volume)
	cfg.set_value("progress", "high_score", high_score)
	cfg.set_value("progress", "unlocked_level", unlocked_level)
	for k in level_best.keys():
		cfg.set_value("progress", "best_%d" % int(k), int(level_best[k]))
	cfg.save(SAVE_PATH)


func load_data() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	tilt_sensitivity = float(cfg.get_value("settings", "tilt_sensitivity", 1.0))
	invert_x = bool(cfg.get_value("settings", "invert_x", false))
	invert_y = bool(cfg.get_value("settings", "invert_y", false))
	auto_fire = bool(cfg.get_value("settings", "auto_fire", false))
	vibration = bool(cfg.get_value("settings", "vibration", true))
	volume = float(cfg.get_value("settings", "volume", 0.8))
	high_score = int(cfg.get_value("progress", "high_score", 0))
	unlocked_level = clampi(int(cfg.get_value("progress", "unlocked_level", 0)), 0, LEVELS.size() - 1)
	for i in LEVELS.size():
		var b := int(cfg.get_value("progress", "best_%d" % i, 0))
		if b > 0:
			level_best[i] = b


func _setup_input() -> void:
	var map := {
		"steer_left": [KEY_LEFT, KEY_A],
		"steer_right": [KEY_RIGHT, KEY_D],
		"steer_up": [KEY_UP, KEY_W],
		"steer_down": [KEY_DOWN, KEY_S],
		"fire": [KEY_SPACE, KEY_J],
		"shock": [KEY_E, KEY_K],
		"pause": [KEY_ESCAPE, KEY_P],
	}
	for action in map.keys():
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in map[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
