extends SceneTree
## Difficulty/fun metrics for the level progression.
##   godot --headless --fixed-fps 60 --path . -s res://tools/level_stats.gd -- [last_level] [--no-sim]
## Per level: environment mix, jumps, hard modules, mean module difficulty and
## how far the marble gets with NO input (a level finished hands-off is too easy)
## and with the autopilot (should finish).

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var last := int(args[0]) if args.size() > 0 and args[0].is_valid_int() else 12
	var sim := not args.has("--no-sim")
	var gen := TrackGenerator.new()
	var totals := {}
	var no_input_finished := 0
	var auto_finished := 0
	print("lvl diff segs  len   classic tube wires ramps | jumps hard  meanD brk bst | no-input        | autopilot")
	for n in range(1, last + 1):
		var cfg := LevelProgression.config_for_level(n)
		var l := gen.generate(cfg)
		var env := {"classic": 0, "tube": 0, "wires": 0, "ramps": 0}
		var jumps := 0
		var hard := 0
		var dsum := 0.0
		var mods := 0
		var brakes := 0
		var boosts := 0
		for p in l.placements:
			if p.def.id == "start" or p.def.id == "finish":
				continue
			mods += 1
			env[p.env] = env.get(p.env, 0) + 1
			totals[p.env] = totals.get(p.env, 0) + 1
			dsum += p.def.difficulty
			if p.def.is_jump():
				jumps += 1
			if p.def.difficulty >= 2.5:
				hard += 1
			for lim in p.limits:
				if lim.z < INF:
					brakes += 1
				if lim.y > 0.0:
					boosts += 1
		totals["jumps"] = totals.get("jumps", 0) + jumps
		var line := "%3d %4.1f %4d %5.0f   %5d %4d %5d %5d | %5d %4d  %5.2f %3d %3d" % [n, cfg.difficulty, cfg.segment_count, l.total_length(),
			env.classic, env.tube, env.wires, env.ramps, jumps, hard, dsum / maxf(mods, 1), brakes, boosts]
		totals["brake"] = totals.get("brake", 0) + brakes
		totals["boost"] = totals.get("boost", 0) + boosts
		if sim:
			var h := SimHarness.new(self, l)
			var r: Dictionary = await h.run(l.total_length() / 1.5 + 20.0)
			await h.dispose()
			var h2 := SimHarness.new(self, l)
			h2.autopilot = Autopilot.new()
			var r2: Dictionary = await h2.run(l.total_length() / 1.5 + 20.0)
			await h2.dispose()
			if r.result == "finished":
				no_input_finished += 1
			if r2.result == "finished":
				auto_finished += 1
			line += " | %-8s %4.0f%% | %s %.0fs" % [r.result, 100.0 * r.distance / l.total_length(), r2.result, r2.ticks / 60.0]
		print(line)
	print("totals: ", totals)
	if sim:
		print("no-input finished %d/%d (lower = more demanding), autopilot finished %d/%d" % [no_input_finished, last, auto_finished, last])
	quit()
