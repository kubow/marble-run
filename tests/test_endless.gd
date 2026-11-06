extends TestCase
## Endless streaming: determinism, bounded memory, no overlap, difficulty ramp.

var gen := TrackGenerator.new()


func _stream_ids(s: int, count: int) -> Array:
	var es := gen.create_endless(s)
	var out: Array = []
	for i in count:
		var p := es.next()
		out.append("%s:%d:%s" % [p.def.id, p.variant, str(p.transform.origin)])
		if i >= 20:
			es.forget(p)  # mimic the game recycling old modules (order-independent)
	return out


func test_stream_deterministic() -> void:
	check_eq(_stream_ids(99, 150), _stream_ids(99, 150), "same seed, same stream")
	check(_stream_ids(99, 60) != _stream_ids(100, 60), "different seed differs")


func test_stream_window_no_overlap_and_bounded() -> void:
	var forced := 0
	var total := 0
	var bad := 0
	for sidx in 40:
		var es := gen.create_endless(Hash64.splitmix64(sidx))
		var window: Array = []
		for i in 250:
			var p := es.next()
			total += 1
			if p.forced:
				forced += 1
			# Independent overlap check against the visible window (last 14).
			for q in window.slice(0, maxi(0, window.size() - 1)):
				if _overlap(p, q):
					bad += 1
			window.append(p)
			if window.size() > 14:
				es.forget(window.pop_front())
		check(es.st.placements.size() <= 8, "generator keeps only recent placements")
	note("%d endless modules, %d forced fallbacks, %d overlaps" % [total, forced, bad])
	check_eq(bad, 0, "no overlaps in active window")
	check(forced <= total / 200, "forced fallbacks are rare")


func _overlap(a: TrackPlacement, b: TrackPlacement) -> bool:
	for ka in a.centerline.size():
		var p := a.centerline[ka]
		for kb in b.centerline.size():
			var q := b.centerline[kb]
			if absf(p.y - q.y) >= 3.5:
				continue
			if Vector2(p.x - q.x, p.z - q.z).length() < a.def.ring_half_w[ka] + b.def.ring_half_w[kb] + 0.3:
				return true
	return false


func test_difficulty_ramps_up() -> void:
	var es := gen.create_endless(7)
	var early := 0.0
	var late := 0.0
	for i in 240:
		var p := es.next()
		if i >= 1 and i < 41:
			early += p.def.difficulty
		elif i >= 200:
			late += p.def.difficulty
		es.forget(p)
	note("mean module difficulty first 40: %.2f, last 40: %.2f" % [early / 40.0, late / 40.0])
	check(late > early, "later modules are harder on average")


func test_endless_does_not_affect_levels() -> void:
	var cfg := LevelProgression.config_for_level(6)
	var before := gen.generate(cfg).logical_hash()
	var es := gen.create_endless(123)
	for i in 50:
		es.next()
	var after := gen.generate(cfg).logical_hash()
	check_eq(after, before, "level hash unchanged by endless generation")


func test_endless_session_physics() -> void:
	# Real streaming session with the autopilot: modules are added/removed and
	# the merged collision is rebuilt while the marble rolls.
	var root := Node3D.new()
	tree.root.add_child(root)
	var view := TrackView.new()
	view.show_pillars = false
	var t := {"ticks": 0}
	view.clock = func() -> float: return t.ticks / 60.0
	root.add_child(view)
	var session := TrackSession.new(view)
	session.start_endless(31337)
	var marble := Marble.new()
	root.add_child(marble)
	var sp := session.spawn_state(0, marble.radius)
	marble.global_transform = sp[0]
	marble.respawn(sp[0], sp[1])
	var ap := Autopilot.new()
	var rebuilds := 0
	var fell := false
	var max_active := 0
	var checkpoint := 0
	for i in 60 * 90:
		await tree.physics_frame
		t.ticks += 1
		session.tracker.update(marble.global_position)
		var cur := session.tracker.current_placement()
		if cur and cur.checkpoint:
			checkpoint = maxi(checkpoint, cur.index)
		if session.update_stream(checkpoint):
			rebuilds += 1
		max_active = maxi(max_active, view.active_indices().size())
		marble.steer_axis = Autopilot.right_of(session.tracker.tangent)
		marble.steer = ap.steer(session.tracker, marble.linear_velocity)
		if i > 10 and session.tracker.is_off_track(marble.global_position):
			fell = true
			break
	note("90 s endless: %.0f m, %d collision rebuilds, max %d active modules, fell=%s" % [
		session.tracker.max_distance, rebuilds, max_active, str(fell)])
	check(not fell, "autopilot survives 90 s of endless streaming")
	check(session.tracker.max_distance > 300.0, "travelled a meaningful distance")
	check(max_active <= session.ahead + session.behind + 6, "active window bounded")
	root.queue_free()
	await tree.process_frame
