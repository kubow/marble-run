extends TestCase
## Deterministic generation tests over many seeds.

const SEED_COUNT := 1000

var gen := TrackGenerator.new()
var _levels: Array = []   # cached generated levels for SEED_COUNT seeds


func _config_for(i: int) -> GeneratorConfig:
	# Spread seeds over all difficulties and lengths used by the game.
	var s := Hash64.splitmix64(0x5EED + i)
	var diff := 1.0 + float(i % 8)
	var segs := 10 + (i % 4) * 8
	return GeneratorConfig.make(s, diff, segs)


func _all_levels() -> Array:
	if _levels.is_empty():
		for i in SEED_COUNT:
			_levels.append(gen.generate(_config_for(i)))
	return _levels


func test_same_seed_identical() -> void:
	for i in 50:
		var cfg := _config_for(i)
		var a := gen.generate(cfg)
		var b := TrackGenerator.new().generate(GeneratorConfig.from_code(cfg.to_code()))
		if not check_eq(a.module_ids(), b.module_ids(), "sequence seed %d" % i):
			return
		for k in a.placements.size():
			if not check(a.placements[k].transform == b.placements[k].transform, "transform %d of seed %d" % [k, i]):
				return
			check_eq(a.placements[k].variant, b.placements[k].variant, "variant")
		check_eq(a.logical_hash(), b.logical_hash(), "hash")


func test_different_seeds_vary() -> void:
	var levels := _all_levels()
	var seqs := {}
	var used := {}
	var envs := {}
	for l in levels:
		seqs[",".join(l.module_ids())] = true
		for id in l.module_ids():
			used[id] = true
		for p in l.placements:
			envs[p.env] = envs.get(p.env, 0) + 1
	note("modules per environment: %s" % str(envs))
	for e in gen.catalog.environments:
		check(envs.has(e.id), "environment %s used somewhere" % e.id)
	var unique := seqs.size()
	note("%d unique sequences out of %d; %d module types used" % [unique, levels.size(), used.size()])
	check(unique >= int(levels.size() * 0.95), "at least 95% unique sequences")
	for d in gen.catalog.modules:
		check(used.has(d.id), "module %s used somewhere" % d.id)


func test_connectors_align() -> void:
	for l in _all_levels():
		var ps: Array = l.placements
		for k in range(1, ps.size()):
			var a: TrackPlacement = ps[k - 1]
			var b: TrackPlacement = ps[k]
			var exit_pt := a.centerline[a.centerline.size() - 1]
			var entry_pt := b.centerline[0]
			if not check(exit_pt.distance_to(entry_pt) < 1e-3, "centreline gap %f at %s->%s" % [exit_pt.distance_to(entry_pt), a.def.id, b.def.id]):
				return
			var ta := a.transform.basis * a.def.ring_tangent[a.def.ring_count() - 1]
			var tb := b.transform.basis * b.def.ring_tangent[0]
			if not check(ta.angle_to(tb) < deg_to_rad(0.1), "tangent kink %s->%s" % [a.def.id, b.def.id]):
				return
			var ua := a.transform.basis * a.def.ring_up[a.def.ring_count() - 1]
			var ub := b.transform.basis * b.def.ring_up[0]
			if not check(ua.angle_to(ub) < deg_to_rad(0.1), "bank mismatch %s->%s" % [a.def.id, b.def.id]):
				return
			check(is_equal_approx(a.def.ring_half_w[a.def.ring_count() - 1], b.def.ring_half_w[0]), "width mismatch")


## Independent brute-force overlap check (not the generator's own grid).
func test_no_invalid_overlap() -> void:
	var bad := 0
	for l in _all_levels():
		var ps: Array = l.placements
		var boxes: Array = []
		for p in ps:
			var bb := AABB(p.centerline[0], Vector3.ZERO)
			for q in p.centerline:
				bb = bb.expand(q)
			boxes.append(bb.grow(p.def.max_half_width + 1.0))
		for i in ps.size():
			for j in range(i + 2, ps.size()):
				var bi: AABB = boxes[i]
				var bj: AABB = boxes[j]
				var bi2 := AABB(Vector3(bi.position.x, bi.position.y - 4.0, bi.position.z), bi.size + Vector3(0, 8.0, 0))
				if not bi2.intersects(bj):
					continue
				if _sections_overlap(ps[i], ps[j]):
					bad += 1
					if bad < 5:
						check(false, "overlap seed %s modules %d/%d" % [l.config.to_code(), i, j])
	check_eq(bad, 0, "overlapping section pairs")


func _sections_overlap(a: TrackPlacement, b: TrackPlacement) -> bool:
	for ka in a.centerline.size():
		var p := a.centerline[ka]
		for kb in b.centerline.size():
			var q := b.centerline[kb]
			if absf(p.y - q.y) >= 3.5:
				continue
			var lim := a.def.ring_half_w[ka] + b.def.ring_half_w[kb] + 0.3
			if Vector2(p.x - q.x, p.z - q.z).length() < lim:
				return true
	return false


func test_start_finish_checkpoints() -> void:
	for l in _all_levels():
		var ps: Array = l.placements
		if not check(ps.size() >= 3, "too short"):
			return
		check_eq(ps[0].def.id, "start", "first module")
		check_eq(ps[-1].def.id, "finish", "last module")
		check_eq(l.finish_index, ps.size() - 1, "finish index")
		check(l.checkpoints.size() >= 1 and l.checkpoints[0] == 0, "checkpoint at start")
		var last_cp := 0
		for p in ps:
			if p.checkpoint:
				check(p.index - last_cp <= l.config.checkpoint_interval + 1 or p.index == 0, "checkpoint spacing")
				last_cp = p.index
		var reached: int = ps.size() - 2
		check(reached >= mini(l.config.segment_count, 3), "segment count %d for %s" % [reached, l.config.to_code()])


func test_bounded_attempts() -> void:
	var max_attempts := 0
	var max_usec := 0
	var total_usec := 0
	var short := 0
	var backtracks := 0
	for l in _all_levels():
		var budget: int = l.config.attempt_budget_per_segment * l.config.segment_count
		# + finish placement attempts, bounded by number of placements.
		check(l.stats.attempts <= budget + l.placements.size() + 1, "attempts within budget")
		max_attempts = maxi(max_attempts, l.stats.attempts)
		max_usec = maxi(max_usec, l.stats.usec)
		total_usec += l.stats.usec
		backtracks += l.stats.backtracks
		if l.stats.segments < l.config.segment_count:
			short += 1
	note("max attempts %d, max gen time %.1f ms, mean %.2f ms, total backtracks %d, short levels %d" % [
		max_attempts, max_usec / 1000.0, total_usec / 1000.0 / SEED_COUNT, backtracks, short])
	check(short <= SEED_COUNT / 100, "at most 1% of levels shorter than requested")


func test_validator_accepts_every_module() -> void:
	# Every placed module re-validates with its recorded entry speeds, the
	# level's skill and the same run-up, and reproduces its speed limits.
	var v := ReachabilityValidator.new()
	for l in _all_levels().slice(0, 200):
		var skill := TrackGenerator.skill_for(l.config.difficulty)
		for i in l.placements.size():
			var p: TrackPlacement = l.placements[i]
			var runup: float = l.placements[i - 1].def.length_3d if i > 0 else 0.0
			var style := "trough" if p.def.id == "finish" else p.style
			var r := v.check_module(p.def, p.v_lo_in, p.v_hi_in, p.variant, style, skill if p.def.id != "start" else 0.0, runup)
			if not check(r.ok, "%s in %s: %s" % [p.def.id, l.config.to_code(), r.reason]):
				return
			check_eq(r.limits.size(), p.limits.size(), "speed limits reproduced")


func test_speed_demands_follow_difficulty() -> void:
	# Level 1 is hands-off safe (no speed limits); harder levels demand braking
	# and boosting, more as difficulty rises.
	var by_band := {"easy": 0, "mid": 0, "hard": 0}
	var counts := {"easy": 0, "mid": 0, "hard": 0}
	for l in _all_levels():
		var n := 0
		for p in l.placements:
			n += p.limits.size()
		if l.config.difficulty < 1.5:
			check_eq(n, 0, "difficulty 1 has no speed demands")
		var band := "easy" if l.config.difficulty < 3.0 else ("mid" if l.config.difficulty < 6.0 else "hard")
		by_band[band] += n / maxf(l.placements.size(), 1)
		counts[band] += 1
	for b in by_band:
		by_band[b] = snappedf(by_band[b] / maxf(counts[b], 1), 0.01)
	note("speed demands per module: %s" % str(by_band))
	check(by_band.hard > by_band.mid and by_band.mid > by_band.easy, "demands grow with difficulty")


func test_jump_windows() -> void:
	var v := ReachabilityValidator.new()
	for d in gen.catalog.modules:
		if d.is_jump():
			var w := v.jump_window(d)
			note("%s take-off window %.1f..%.1f m/s" % [d.id, w.x, w.y])
			check(w.y - w.x >= 1.0, "%s has a usable take-off speed window" % d.id)


func test_obstacle_layouts_valid() -> void:
	var v := ReachabilityValidator.new()
	for d in gen.catalog.modules:
		for i in d.obstacle_layouts.size():
			var r := v.validate_layout(d, d.obstacle_layouts[i], 6.0)
			check(r.ok, "%s layout %d: %s" % [d.id, i, r.reason])


func test_generator_version_fingerprint() -> void:
	var fp := gen.config_fingerprint()
	note("fingerprint v%d = %s" % [TrackGenerator.VERSION, fp])
	check(TrackGenerator.FINGERPRINTS.has(TrackGenerator.VERSION), "fingerprint recorded for current version")
	check_eq(fp, TrackGenerator.FINGERPRINTS.get(TrackGenerator.VERSION, ""),
		"generator config changed without bumping TrackGenerator.VERSION")


func test_golden_levels() -> void:
	# Logical hashes of the first levels for this generator version. If these
	# change, the generator output changed: bump VERSION.
	var expected: Dictionary = GOLDEN.get(TrackGenerator.VERSION, {})
	for n in [1, 2, 3, 4, 5, 10]:
		var l := gen.generate(LevelProgression.config_for_level(n))
		note("level %d: %s %s" % [n, l.config.to_code(), l.logical_hash()])
		check_eq(l.logical_hash(), expected.get(n, ""), "golden hash level %d" % n)


const GOLDEN := {
	1: {1: "1DEE5B156B1FD4BF", 2: "4703201E86C2DC5E", 3: "971C00233C29D2D5",
		4: "BCBF1D54A74ED1E1", 5: "6B504C161EBD7EC6", 10: "6389BCB380BC8603"},
	2: {1: "916CAFE2A31FBEFD", 2: "21F6E2967D15A979", 3: "7CEDC5F2D7CD441A",
		4: "08C7167BE04E41A8", 5: "5B61FBB0CBCACAA1", 10: "3F173835E9A487D6"},
	3: {1: "58EAE167C4A0A242", 2: "FCB93F3142FED78A", 3: "D87F5DD34017FA12",
		4: "655699C72816A152", 5: "2006D14692099DF2", 10: "4CAA08D8A2E680FD"},
}
