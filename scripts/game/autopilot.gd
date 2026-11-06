class_name Autopilot
extends RefCounted
## Simple lane-following controller used by automated traversal tests and the
## debug demo mode. It steers towards the centre of the nearest free lane of
## the next obstacle row (or the track centre), with PD damping.

var kp := 2.2
var kd := 0.9
var validator := ReachabilityValidator.new()


static func right_of(tangent: Vector3) -> Vector3:
	return Vector3(-tangent.z, 0.0, tangent.x).normalized()


func steer(tracker: TrackTracker, velocity: Vector3) -> float:
	var right := right_of(tracker.tangent)
	var lateral := tracker.offset.dot(right)
	var lat_vel := velocity.dot(right)
	var target := _target_lateral(tracker, lateral)
	return clampf(-(kp * (lateral - target) + kd * lat_vel), -1.0, 1.0)


func _target_lateral(tracker: TrackTracker, lateral: float) -> float:
	for idx in [tracker.current, tracker.current + 1]:
		var p: TrackPlacement = tracker.placements.get(idx)
		if p == null:
			continue
		var layout := p.obstacle_layout()
		if layout.is_empty():
			continue
		var s_now := tracker.local_t * p.def.length if idx == tracker.current else -1.0
		var rows := {}
		var keys: Array = []
		for o in layout:
			var s := float(o.get("t", 0.5)) * p.def.length
			if s < s_now - 0.3:
				continue
			var key := snappedf(s, 0.5)
			if not rows.has(key):
				rows[key] = []
				keys.append(key)
			rows[key].append(validator._blocked(p.def, o))
		if keys.is_empty():
			continue
		keys.sort()
		var row_s: float = keys[0]
		var limit := p.def.profile_at(row_s).x * TrackSpec.WALL_START
		var free := validator._free_intervals(limit, rows[row_s])
		var best := 0.0
		var best_d := INF
		# Nearest point inside a free lane (with a small margin): minimal moves.
		for f in free:
			var m := minf(0.15, (f.y - f.x) * 0.5)
			var c := clampf(lateral, f.x + m, f.y - m)
			if absf(c - lateral) < best_d:
				best_d = absf(c - lateral)
				best = c
		return best
	return 0.0
