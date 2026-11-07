extends Node3D
## Game scene controller: builds the world, runs the play loop (checkpoints,
## falls, finish, timer) and wires HUD/input. Generation lives in TrackSession,
## physics in Marble, rendering in TrackView.

enum State { PLAYING, PAUSED, FINISHED, GAME_OVER }

const MARBLE_SCENE := preload("res://scenes/marble/marble.tscn")
const TRACK_SCENE := preload("res://scenes/track/track_view.tscn")
const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const LIVES := 3
const STALL_SPEED := 0.25
const STALL_SECONDS := 2.5

var session: TrackSession
var view: TrackView
var marble: Marble
var cam: FollowCamera
var steer_input: SteerInput
var hud: Hud
var debug: DebugOverlay
var light: DirectionalLight3D
var autopilot: Autopilot = null

var state := State.PLAYING
var kind := "level"
var level_number := 0
var ticks := 0                  ## Physics ticks while playing (timer source).
var lives := LIVES
var checkpoint_index := 0
var _stall_ticks := 0
var _respawn_cooldown := 0


func _ready() -> void:
	_build_world()
	_start_from_request()


func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("6fb7ff")
	sm.sky_horizon_color = Color("ffe0f2")
	sm.ground_horizon_color = Color("ffe0f2")
	sm.ground_bottom_color = Color("c7b8ff")
	sm.sun_angle_max = 30.0
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.45
	e.ambient_light_sky_contribution = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = true
	e.fog_light_color = Color("f3dcf5")
	e.fog_density = 0.004
	e.fog_sky_affect = 0.0
	env.environment = e
	add_child(env)

	light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -30, 0)
	light.light_energy = 1.0
	light.shadow_enabled = bool(App.setting("shadows", true))
	light.directional_shadow_max_distance = 40.0
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(light)

	view = TRACK_SCENE.instantiate()
	view.clock = func() -> float: return ticks / float(Engine.physics_ticks_per_second)
	add_child(view)

	marble = MARBLE_SCENE.instantiate()
	add_child(marble)

	cam = FollowCamera.new()
	cam.distance = 5.0 * float(App.setting("camera_distance", 1.0))
	cam.height = 2.6 * float(App.setting("camera_distance", 1.0))
	add_child(cam)
	cam.make_current()

	steer_input = SteerInput.new()
	steer_input.sensitivity = float(App.setting("steer_sensitivity", 1.0))
	steer_input.invert = bool(App.setting("invert_steer", false))
	add_child(steer_input)

	hud = HUD_SCENE.instantiate()
	hud.show_fps = bool(App.setting("show_fps", false))
	add_child(hud)
	hud.pause_pressed.connect(_toggle_pause)
	hud.resume_pressed.connect(_toggle_pause)
	hud.restart_pressed.connect(_restart)
	hud.next_pressed.connect(_next_level)
	hud.menu_pressed.connect(func(): App.goto_menu())


func _start_from_request() -> void:
	var req := App.request
	if req.is_empty():
		req = {"kind": "level", "level": App.save.unlocked_level}
	kind = str(req.get("kind", "level"))
	session = TrackSession.new(view)
	match kind:
		"endless":
			var p := Hash64.parse_seed(str(req.get("code", "")))
			var s: int = p.value if p.ok else App.ENDLESS_SEED
			session.start_endless(s)
			hud.set_title("Endless", "seed %s" % session.code)
			App.save.set_last_endless(session.code)
		"custom":
			var cfg := GeneratorConfig.from_code(str(req.get("code", "")))
			if cfg == null:
				cfg = LevelProgression.config_for_level(1)
			session.start_level(cfg)
			hud.set_title("Custom track", session.code)
			App.save.set_last_custom(session.code)
		_:
			level_number = maxi(1, int(req.get("level", 1)))
			session.start_level(LevelProgression.config_for_level(level_number))
			hud.set_title("Level %d" % level_number, session.code)
			App.save.set_last_level(level_number, session.code)
	App.save.save_data()

	debug = DebugOverlay.new()
	debug.session = session
	debug.marble = marble
	add_child(debug)
	_set_debug(bool(App.setting("debug", false)) or App.dev_args.has("debug"))
	if App.dev_args.has("autopilot"):
		autopilot = Autopilot.new()

	cam.target = marble
	cam.tracker = session.tracker
	_spawn(0, true)
	lives = LIVES
	hud.set_lives(lives)
	var saved_v := int(req.get("saved_generator_version", TrackGenerator.VERSION))
	if saved_v != TrackGenerator.VERSION:
		hud.toast("Saved with generator v%d - layout may differ in v%d" % [saved_v, TrackGenerator.VERSION], 4.0)
	else:
		hud.toast("Drag ↔ to steer, ↕ to speed up / brake", 3.0)


func _spawn(index: int, snap_camera: bool) -> void:
	checkpoint_index = index
	var sp := session.spawn_state(index, marble.radius)
	marble.global_transform = sp[0]
	marble.linear_velocity = sp[1]
	marble.respawn(sp[0], sp[1])
	session.tracker.reset(index)
	_stall_ticks = 0
	_respawn_cooldown = 20
	steer_input.release()
	if snap_camera:
		cam.global_position = sp[0].origin
		cam.call_deferred("snap")


func _physics_process(_delta: float) -> void:
	if state != State.PLAYING:
		return
	ticks += 1
	var pos := marble.global_position
	var tr := session.tracker
	tr.update(pos)
	session.update_stream(checkpoint_index)
	marble.steer_axis = Autopilot.right_of(tr.tangent)
	marble.forward_axis = tr.tangent
	marble.steer = autopilot.steer(tr, marble.linear_velocity) if autopilot else steer_input.value()
	marble.throttle = 0.0 if autopilot else steer_input.throttle()

	# Checkpoints
	var cur := tr.current_placement()
	if cur and cur.checkpoint and cur.index > checkpoint_index:
		checkpoint_index = cur.index
		view.mark_checkpoint(cur.index)
		hud.toast("Checkpoint")

	if _respawn_cooldown > 0:
		_respawn_cooldown -= 1
	elif tr.is_off_track(pos):
		_on_fall()
		return

	_stall_ticks = _stall_ticks + 1 if marble.speed() < STALL_SPEED else 0
	if _stall_ticks > int(STALL_SECONDS * Engine.physics_ticks_per_second):
		hud.toast("Stuck - back to checkpoint")
		_spawn(checkpoint_index, false)

	if session.is_finished():
		_on_finish()


func _process(_delta: float) -> void:
	var t := ticks / float(Engine.physics_ticks_per_second)
	hud.set_time(t)
	if session == null:
		return
	if session.endless:
		hud.set_progress(-1.0, "%d m  ·  %.1f m/s" % [int(session.tracker.max_distance), marble.speed()])
	else:
		hud.set_progress(session.progress(), "%d%%  ·  %.1f m/s" % [int(session.progress() * 100.0), marble.speed()])
	if debug.visible:
		hud.set_debug(debug.text(Engine.get_frames_per_second()))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_pause()
	elif event.is_action_pressed("restart"):
		_restart()
	elif event.is_action_pressed("next_level") and state == State.FINISHED:
		_next_level()
	elif event.is_action_pressed("debug_toggle"):
		_set_debug(not debug.visible)
	elif event.is_action_pressed("autopilot_toggle"):
		autopilot = null if autopilot else Autopilot.new()
		hud.toast("Autopilot %s" % ("on" if autopilot else "off"))


func _set_debug(on: bool) -> void:
	debug.visible = on
	if not on:
		hud.set_debug("")


func _on_fall() -> void:
	lives -= 1
	hud.set_lives(lives)
	if lives <= 0:
		_game_over()
		return
	hud.toast("Oops!")
	_spawn(checkpoint_index, true)


func _on_finish() -> void:
	state = State.FINISHED
	var t := ticks / float(Engine.physics_ticks_per_second)
	var key := SaveData.level_key(level_number) if kind == "level" else SaveData.code_key(session.code)
	var new_best := App.save.record_time(key, t)
	var has_next := kind == "level" and level_number < LevelProgression.MAX_LEVEL
	if kind == "level":
		App.save.unlocked_level = maxi(App.save.unlocked_level, level_number + 1)
	App.save.save_data()
	hud.show_complete(t, App.save.best_time(key), new_best, has_next)


func _game_over() -> void:
	state = State.GAME_OVER
	marble.steer = 0.0
	var body := ""
	if session.endless:
		var d := session.tracker.max_distance
		var best := d > App.save.best_endless
		App.save.best_endless = maxf(App.save.best_endless, d)
		App.save.save_data()
		body = "Distance  %d m\nBest  %d m%s" % [int(d), int(App.save.best_endless), "  (new!)" if best else ""]
	else:
		body = "Reached %d%% of the track" % int(session.progress() * 100.0)
	hud.show_game_over(body)


func _toggle_pause() -> void:
	if state == State.PLAYING:
		state = State.PAUSED
		get_tree().paused = true
		hud.show_pause(true)
	elif state == State.PAUSED:
		state = State.PLAYING
		get_tree().paused = false
		hud.show_pause(false)


func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _next_level() -> void:
	if kind == "level":
		App.start_level(level_number + 1)
