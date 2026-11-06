extends TestCase
## Physics smoke tests with the real engine (Jolt), headless.
## These complement the analytic validator: they show that typical tracks are
## traversable, but cannot prove every generated level is completable.

var gen := TrackGenerator.new()


func _sim(ids: Array, seconds: float, autopilot := false) -> Dictionary:
	var level := gen.assemble(PackedStringArray(ids))
	var h := SimHarness.new(tree, level)
	if autopilot:
		h.autopilot = Autopilot.new()
	var r: Dictionary = await h.run(seconds)
	r["speeds"] = h.log_speed
	await h.dispose()
	return r


func test_smoke_basic_track_no_input() -> void:
	var r := await _sim(["start", "straight", "gentle_left", "straight", "gentle_right", "downhill", "straight", "finish"], 60.0)
	note("result %s after %.1f s, max speed %.2f" % [r.result, r.ticks / 60.0, r.max_speed])
	check_eq(r.result, "finished", "marble rolls to the finish without input")


func test_calibrate_terminal_speed() -> void:
	var r := await _sim(["start", "straight_long", "straight_long", "straight_long", "straight_long", "straight_long", "straight_long", "finish"], 90.0)
	var sp: Array = r.speeds
	var tail := sp.slice(maxi(0, sp.size() - 8), sp.size() - 2)
	var v_term := 0.0
	for v in tail:
		v_term += v
	v_term /= maxf(tail.size(), 1)
	var g5 := 9.8 * 5.0 / 7.0 * 0.07 / sqrt(1.0 + 0.0049)
	var c := g5 / maxf(v_term, 0.01)
	note("speed samples (0.5 s): %s" % str(sp.map(func(x): return snappedf(x, 0.01))))
	note("terminal-ish speed %.2f m/s -> effective damping %.3f (validator uses %.3f)" % [v_term, c, ReachabilityValidator.new().damp_eff])
	check_eq(r.result, "finished", "long straight finished")


func test_joins_have_no_seams() -> void:
	# Many short modules = many joins. Track height above the floor and vertical
	# velocity jumps between ticks; a catching seam produces spikes.
	var ids := ["start"]
	for i in 12:
		ids.append("straight")
	ids.append("finish")
	var level := gen.assemble(PackedStringArray(ids))
	var h := SimHarness.new(tree, level)
	var st := {"jump": 0.0, "lift": 0.0, "prev": 0.0}
	var f := func(sim: SimHarness) -> float:
		var vy := sim.marble.linear_velocity.y
		if sim.ticks > 60:
			st.jump = maxf(st.jump, absf(vy - st.prev))
			st.lift = maxf(st.lift, sim.tracker.offset.y - sim.marble.radius)
		st.prev = vy
		return 0.0
	var r: Dictionary = await h.run(60.0, f)
	await h.dispose()
	var max_jump: float = st.jump
	var max_lift: float = st.lift
	note("result %s, max dv_y/tick %.4f m/s, max lift above floor %.4f m" % [r.result, max_jump, max_lift])
	check_eq(r.result, "finished", "finished")
	check(max_jump < 0.15, "no vertical velocity spikes at joins")
	check(max_lift < 0.05, "marble stays on the floor across joins")


func test_autopilot_traverses_levels() -> void:
	var results := {}
	var failed: Array = []
	var configs: Array = []
	for n in range(1, 13):
		configs.append(LevelProgression.config_for_level(n))
	for i in 18:
		configs.append(GeneratorConfig.make(Hash64.splitmix64(777 + i), 3.0 + (i % 6), 24))
	for cfg in configs:
		var level := gen.generate(cfg)
		var h := SimHarness.new(tree, level)
		h.autopilot = Autopilot.new()
		var r: Dictionary = await h.run(level.total_length() / 1.5 + 20.0)
		await h.dispose()
		results[r.result] = results.get(r.result, 0) + 1
		if r.result != "finished":
			failed.append("%s %s at module %d (%s) speed max %.1f" % [cfg.to_code(), r.result, r.module, r.module_id, r.max_speed])
	note("autopilot results: %s" % str(results))
	for f in failed:
		note("  " + f)
	check(results.get("finished", 0) >= configs.size() - 1, "autopilot finishes generated levels")
