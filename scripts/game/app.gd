extends Node
## Autoload "App": persistence, settings, input map and scene flow.

const MENU_SCENE := "res://scenes/main_menu/main_menu.tscn"
const GAME_SCENE := "res://scenes/game/game.tscn"
const ENDLESS_SEED := 0x454E444C455353   ## "ENDLESS"

var save := SaveData.new()
## What the game scene should play: {kind: "level"|"custom"|"endless", level, code}
var request: Dictionary = {}


## Developer flags (after "--"): --level=N --seed=CODE --endless --autopilot
## --debug --shot=PATH --shot-frames=N  (screenshot then quit)
var dev_args: Dictionary = {}


func _ready() -> void:
	_register_inputs()
	save.load_data()
	# Warm the catalogue (samples) once.
	ModuleCatalog.get_default()
	_parse_dev_args()


func _parse_dev_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			dev_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if dev_args.has("level"):
		request = {"kind": "level", "level": int(dev_args.level)}
	elif dev_args.has("seed"):
		request = {"kind": "custom", "code": str(dev_args.seed)}
	elif dev_args.has("endless"):
		request = {"kind": "endless", "code": Hash64.to_hex(ENDLESS_SEED)}
	if not request.is_empty():
		_go(GAME_SCENE)
	if dev_args.has("shot"):
		_screenshot_later(str(dev_args.shot), int(dev_args.get("shot-frames", "180")))


func _screenshot_later(path: String, frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("screenshot saved: ", path)
	get_tree().quit()


func _exit_tree() -> void:
	# Release static render caches before the servers shut down.
	TrackMeshBuilder.clear_cache()
	TrackDecor.clear_cache()


func _register_inputs() -> void:
	_add_keys("steer_left", [KEY_LEFT, KEY_A])
	_add_keys("steer_right", [KEY_RIGHT, KEY_D])
	_add_keys("pause", [KEY_ESCAPE, KEY_P])
	_add_keys("restart", [KEY_R])
	_add_keys("next_level", [KEY_N])
	_add_keys("debug_toggle", [KEY_F3])
	_add_keys("autopilot_toggle", [KEY_F4])


func _add_keys(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func setting(key: String, default = null):
	return save.settings.get(key, default)


func set_setting(key: String, value) -> void:
	save.settings[key] = value
	save.save_data()


func start_level(n: int) -> void:
	request = {"kind": "level", "level": n}
	_go(GAME_SCENE)


func start_custom(code: String) -> void:
	request = {"kind": "custom", "code": code}
	_go(GAME_SCENE)


func start_endless(seed_value := ENDLESS_SEED) -> void:
	request = {"kind": "endless", "code": Hash64.to_hex(seed_value)}
	_go(GAME_SCENE)


func can_continue() -> bool:
	return not save.last.is_empty()


func continue_last() -> void:
	var l := save.last
	match str(l.get("kind", "")):
		"level":
			start_level(int(l.get("level", save.unlocked_level)))
		"custom":
			start_custom(str(l.get("code", "")))
		"endless":
			var p := Hash64.parse_seed(str(l.get("code", "")))
			start_endless(p.value if p.ok else ENDLESS_SEED)
		_:
			start_level(save.unlocked_level)


func goto_menu() -> void:
	_go(MENU_SCENE)


func _go(path: String) -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file.call_deferred(path)
