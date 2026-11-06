class_name SaveData
extends RefCounted
## Local persistence in a ConfigFile (user://save.cfg). No network, no telemetry.
## Best times are keyed by generator version so a future generator change
## never mixes times from different layouts of the "same" level.

const DEFAULT_PATH := "user://save.cfg"
const FORMAT := 1

var path := DEFAULT_PATH
var unlocked_level := 1
var best_times: Dictionary = {}     ## "v<gen>:L<n>" or "v<gen>:<code>" -> seconds
var best_endless := 0.0             ## metres
var last: Dictionary = {}           ## {kind, level, code, generator_version}
var settings: Dictionary = {
	"steer_sensitivity": 1.0,
	"invert_steer": false,
	"shadows": true,
	"show_fps": false,
	"debug": false,
	"camera_distance": 1.0,
}


func _init(p_path := DEFAULT_PATH) -> void:
	path = p_path


func load_data() -> bool:
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return false
	unlocked_level = maxi(1, int(cf.get_value("progress", "unlocked_level", 1)))
	best_endless = float(cf.get_value("progress", "best_endless", 0.0))
	last = cf.get_value("progress", "last", {})
	if cf.has_section("best"):
		for k in cf.get_section_keys("best"):
			best_times[k.replace("_", ":")] = float(cf.get_value("best", k))
	if cf.has_section("settings"):
		for k in cf.get_section_keys("settings"):
			settings[k] = cf.get_value("settings", k)
	return true


func save_data() -> bool:
	var cf := ConfigFile.new()
	cf.set_value("meta", "format", FORMAT)
	cf.set_value("meta", "generator_version", TrackGenerator.VERSION)
	cf.set_value("progress", "unlocked_level", unlocked_level)
	cf.set_value("progress", "best_endless", best_endless)
	cf.set_value("progress", "last", last)
	for k in best_times:
		# ConfigFile keys may not contain ':'.
		cf.set_value("best", str(k).replace(":", "_"), best_times[k])
	for k in settings:
		cf.set_value("settings", k, settings[k])
	return cf.save(path) == OK


static func level_key(level: int, version := TrackGenerator.VERSION) -> String:
	return "v%d:L%d" % [version, level]


static func code_key(code: String, version := TrackGenerator.VERSION) -> String:
	return "v%d:%s" % [version, code]


func best_time(key: String) -> float:
	return float(best_times.get(key, -1.0))


## Records a time; returns true if it is a new best.
func record_time(key: String, seconds: float) -> bool:
	var old := best_time(key)
	if old < 0.0 or seconds < old:
		best_times[key] = seconds
		return true
	return false


func set_last_level(level: int, code: String) -> void:
	last = {"kind": "level", "level": level, "code": code, "generator_version": TrackGenerator.VERSION}


func set_last_custom(code: String) -> void:
	last = {"kind": "custom", "code": code, "generator_version": TrackGenerator.VERSION}


func set_last_endless(code: String) -> void:
	last = {"kind": "endless", "code": code, "generator_version": TrackGenerator.VERSION}
