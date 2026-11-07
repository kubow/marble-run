extends TestCase
## Physics smoke tests with the real engine (Jolt), headless.
## These complement the analytic validator: they show that typical tracks are
## traversable, but cannot prove every generated level is completable.

var gen := TrackGenerator.new()


func _sim(ids: Array, seconds: float, autopilot := false, envs: Array = []) -> Dictionary:
	var level := gen.assemble(PackedStringArray(ids), PackedInt32Array(), PackedStringArray(envs))
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
	var st := {"jump": 0.0, "lift": 0.0, "prev": 0.0, "inner": 0.0}
	var f := func(sim: SimHarness) -> float:
		var vy := sim.marble.linear_velocity.y
		if sim.ticks > 60:
			# Within 0.25 m of a connector counts as "at a join".
			var p := sim.tracker.current_placement()
			var s := sim.tracker.local_t * p.def.length
			var at_join := s < 0.25 or s > p.def.length - 0.25
			var dv := absf(vy - st.prev)
			if at_join:
				st.jump = maxf(st.jump, dv)
			else:
				st.inner = maxf(st.inner, dv)
			st.lift = maxf(st.lift, sim.tracker.offset.y - sim.marble.radius)
		st.prev = vy
		return 0.0
	var r: Dictionary = await h.run(60.0, f)
	await h.dispose()
	var max_jump: float = st.jump
	var max_lift: float = st.lift
	var inner: float = st.inner
	note("result %s, max dv_y/tick at joins %.4f m/s (inside modules %.4f), max lift above floor %.4f m" % [r.result, max_jump, inner, max_lift])
	check_eq(r.result, "finished", "finished")
	# Joins must behave like any internal edge of one mesh (no extra seam).
	check(max_jump <= inner * 1.1 + 0.01, "joins no worse than ordinary mesh edges")
	check(max_lift < 0.05, "marble stays on the floor across joins")


func test_autopilot_traverses_levels() -> void:
	var results := {}
	var failed: Array = []
	var configs: Array = []
	var hands_off := 0
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
		# Same level with no input at all: harder levels should not allow this.
		if cfg.difficulty >= 2.0:
			var h0 := SimHarness.new(tree, level)
			var r0: Dictionary = await h0.run(level.total_length() / 1.5 + 20.0)
			await h0.dispose()
			if r0.result == "finished":
				hands_off += 1
		if r.result != "finished":
			failed.append("%s %s at module %d (%s) speed max %.1f" % [cfg.to_code(), r.result, r.module, r.module_id, r.max_speed])
	note("autopilot (steer + throttle) results: %s; hands-off finishes at difficulty >= 2: %d" % [str(results), hands_off])
	check(hands_off <= configs.size() / 3, "most levels from difficulty 2 demand player input")
	for f in failed:
		note("  " + f)
	check(results.get("finished", 0) >= configs.size() - 1, "autopilot finishes generated levels")


func _env_track(env: String, ids: Array) -> Array:
	var envs: Array = ["classic"]
	for i in ids.size():
		envs.append(env)
	envs.append("classic")
	return [["start"] + ids + ["finish"], envs]


func test_environments_no_input() -> void:
	var cases := {
		"tube": ["straight", "gentle_left", "sharp_right", "wavy", "downhill", "s_curve_left", "straight"],
		"wires": ["straight", "gentle_left", "s_curve_right", "downhill", "gentle_right", "straight"],
		"ramps": ["downhill", "straight", "jump", "straight"],
	}
	for env in cases:
		var t := _env_track(env, cases[env])
		var r := await _sim(t[0], 90.0, false, t[1])
		note("%s: %s after %.1f s, max %.1f m/s" % [env, r.result, r.ticks / 60.0, r.max_speed])
		check_eq(r.result, "finished", "%s track finished without input" % env)


func test_jump_flies_and_lands() -> void:
	var t := _env_track("ramps", ["downhill_steep", "jump_big", "straight"])
	var level := gen.assemble(PackedStringArray(t[0]), PackedInt32Array(), PackedStringArray(t[1]))
	check(level.stats.invalid.is_empty(), "jump track validates: %s" % str(level.stats.invalid))
	var h := SimHarness.new(tree, level)
	var st := {"air": 0, "max_air": 0}
	var f := func(sim: SimHarness) -> float:
		var p := sim.tracker.current_placement()
		if p and p.def.is_jump() and p.def.in_gap(sim.tracker.local_t * p.def.length):
			st.air += 1
		return 0.0
	var r: Dictionary = await h.run(60.0, f)
	await h.dispose()
	note("jump: %s, %d ticks over the gap" % [r.result, st.air])
	check_eq(r.result, "finished", "landed and finished")
	check(st.air > 5, "marble actually flew over the gap")


func test_braking_short_of_jump_fails() -> void:
	# Full brake from the start: the marble must not clear the gap (the jump
	# needs speed), proving gaps are real hazards.
	var t := _env_track("ramps", ["straight", "jump", "straight"])
	var level := gen.assemble(PackedStringArray(t[0]), PackedInt32Array(), PackedStringArray(t[1]))
	var h := SimHarness.new(tree, level)
	var f := func(sim: SimHarness) -> float:
		sim.marble.forward_axis = sim.tracker.tangent
		sim.marble.throttle = -1.0 if sim.tracker.current >= 2 else 0.0
		return 0.0
	var r: Dictionary = await h.run(40.0, f)
	await h.dispose()
	note("braking into the jump: %s at module %s" % [r.result, r.module_id])
	check(r.result != "finished", "braking prevents clearing the gap")


func test_throttle_and_brake() -> void:
	var ids := ["start", "straight_long", "straight_long", "straight_long", "finish"]
	var speeds := {}
	for mode in [0.0, 1.0, -1.0]:
		var level := gen.assemble(PackedStringArray(ids))
		var h := SimHarness.new(tree, level)
		var f := func(sim: SimHarness) -> float:
			sim.marble.forward_axis = sim.tracker.tangent
			sim.marble.throttle = mode
			return 0.0
		var stv := {"v": 0.0}
		var g := func(sim: SimHarness) -> float:
			f.call(sim)
			if sim.ticks == 300:
				stv.v = sim.marble.speed()
			return 0.0
		await h.run(5.1, g)
		await h.dispose()
		speeds[mode] = stv.v
	note("speed after 5 s: coast %.2f, boost %.2f, brake %.2f m/s" % [speeds[0.0], speeds[1.0], speeds[-1.0]])
	check(speeds[1.0] > speeds[0.0] + 3.0, "boost accelerates")
	check(speeds[-1.0] < 1.0, "brake slows the marble almost to a stop")
	check(speeds[-1.0] >= 0.0, "brake never reverses")


func test_wire_calibration() -> void:
	# Terminal speed on wires vs the validator model (it must not be optimistic
	# about losses there: wires lose more energy than the plastic trough).
	var ids: Array = []
	for i in 5:
		ids.append("straight_long")
	var t := _env_track("wires", ids)
	var r := await _sim(t[0], 90.0, false, t[1])
	var sp: Array = r.speeds
	var tail := sp.slice(maxi(0, sp.size() - 8), sp.size() - 2)
	var v_term := 0.0
	for v in tail:
		v_term += v
	v_term /= maxf(tail.size(), 1)
	var g5 := 9.8 * 5.0 / 7.0 * 0.07 / sqrt(1.0 + 0.0049)
	note("wires: %s, late speed %.2f m/s -> effective damping %.3f (validator pessimistic %.3f)" % [
		r.result, v_term, g5 / maxf(v_term, 0.01), ReachabilityValidator.new().damp_eff * ReachabilityValidator.new().lo_damp_mul])
	check_eq(r.result, "finished", "wires straight finished")


func test_wire_entry_is_smooth() -> void:
	# Regression: the marble used to be kicked up where the wires begin (flush
	# leading edges / wire ends inside the funnel). Enter at 6-9 m/s, coasting
	# and boosting, straight and curved: it must stay low and finish.
	var worst := 0.0
	for v0 in [6.0, 8.0, 9.0]:
		for thr in [0.0, 1.0]:
			for mid in ["straight", "gentle_left"]:
				var level := gen.assemble(PackedStringArray(["start", mid, "straight", "finish"]), PackedInt32Array(), PackedStringArray(["classic", "wires", "wires", "classic"]))
				var h := SimHarness.new(tree, level)
				var p: TrackPlacement = level.placements[1]
				var fwd := -p.transform.basis.z
				h.marble.respawn(Transform3D(Basis(), p.transform.origin - fwd * 0.5 + Vector3.UP * 0.33), fwd * v0)
				h.tracker.reset(1)
				var st := {"maxy": 0.0}
				var f := func(sim: SimHarness) -> float:
					sim.marble.forward_axis = sim.tracker.tangent
					sim.marble.throttle = thr if sim.tracker.current == 1 else 0.0
					if sim.tracker.current == 1 and sim.ticks > 5:
						st.maxy = maxf(st.maxy, sim.tracker.offset.y)
					return 0.0
				var r: Dictionary = await h.run(20.0, f)
				await h.dispose()
				worst = maxf(worst, st.maxy)
				check_eq(r.result, "finished", "%s wires at %.0f m/s throttle %.0f" % [mid, v0, thr])
	note("max marble height entering wires: %.2f m (resting 0.27)" % worst)
	check(worst < 0.4, "no kick-up at the wire entry")
