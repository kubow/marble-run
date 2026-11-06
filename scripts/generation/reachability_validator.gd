class_name ReachabilityValidator
extends RefCounted
## Conservative, analytic traversability check for a single module given an
## entry speed interval [v_lo, v_hi].
##
## Speed model along the sampled centreline (rolling solid sphere):
##     v_next = sqrt(v^2 - 2 * g * 5/7 * dy) - c * ds
## where c is an effective linear damping per metre (calibrated against the
## real physics in tests/test_physics.gd). The pessimistic bound uses a larger
## c, the optimistic bound a smaller c. A module is rejected when:
##   * the pessimistic speed drops below MIN_SPEED (marble could stall),
##   * the optimistic speed exceeds what banking + walls can hold in a curve,
##   * the optimistic speed would launch the marble off a crest (no jumps),
##   * slopes exceed limits, or
##   * an obstacle row leaves no lane, or lanes need too sharp a lateral move.
## Passing this check does NOT prove a level is completable; it only rejects
## configurations that are clearly or plausibly impossible.

const G := 9.8
const ROLL := 5.0 / 7.0

var damp_eff := 0.10        ## Effective dv/ds loss (1/s), calibrated (tests/test_physics.gd).
var lo_damp_mul := 1.5      ## Pessimistic multiplier.
var hi_damp_mul := 0.5      ## Optimistic multiplier.
var min_speed := 1.0        ## Below this the marble is considered stalled (m/s).
var wall_grip := 0.5        ## Lateral g a standard wall can provide.
var crest_safety := 0.7     ## Fraction of g allowed as centripetal need on crests.
var max_down_slope := 0.75
var max_up_slope := 0.25
var max_speed := 14.0       ## Absolute optimistic speed cap (m/s).
var narrow_max_speed := 9.0 ## Speed cap on narrow sections (m/s).
var steer_accel := 4.0      ## Lateral acceleration the player can produce (m/s^2).
var min_slack := 0.25       ## Required free lateral room for the ball centre (m).
var obstacle_hit_keep := 0.5 ## Pessimistic speed fraction kept after an obstacle module.


func describe() -> String:
	return "damp=%s lo=%s hi=%s min=%s grip=%s crest=%s down=%s up=%s vmax=%s narrow=%s steer=%s slack=%s hit=%s" % [
		damp_eff, lo_damp_mul, hi_damp_mul, min_speed, wall_grip, crest_safety,
		max_down_slope, max_up_slope, max_speed, narrow_max_speed, steer_accel, min_slack, obstacle_hit_keep]


## Returns {ok, reason, v_lo, v_hi, v_min}.
func check_module(def: TrackModuleDef, v_lo: float, v_hi: float, variant: int = -1) -> Dictionary:
	var res := {"ok": true, "reason": "", "v_lo": v_lo, "v_hi": v_hi, "v_min": v_lo}
	if def.min_entry_speed > 0.0 and v_lo < def.min_entry_speed:
		return _fail(res, "entry speed %.2f < required %.2f" % [v_lo, def.min_entry_speed])
	var c_lo := damp_eff * lo_damp_mul
	var c_hi := damp_eff * hi_damp_mul
	var std_wall := def.spec.wall_height
	var lo := v_lo
	var hi := v_hi
	var vmin := v_lo
	var n := def.ring_count()
	for k in n:
		var slope := def.ring_slope[k]
		if slope < -max_down_slope:
			return _fail(res, "slope %.2f too steep" % slope)
		if slope > max_up_slope:
			return _fail(res, "uphill slope %.2f too steep" % slope)
		if k > 0:
			var ds := def.ring_dist[k] - def.ring_dist[k - 1]
			var dy := def.ring_pos[k].y - def.ring_pos[k - 1].y
			var e_lo := lo * lo - 2.0 * G * ROLL * dy
			if e_lo <= 0.0:
				return _fail(res, "stall (energy)")
			lo = sqrt(e_lo) - c_lo * ds
			var e_hi := hi * hi - 2.0 * G * ROLL * dy
			hi = sqrt(maxf(e_hi, 0.0)) - c_hi * ds
			vmin = minf(vmin, lo)
			if lo < min_speed:
				return _fail(res, "stall: speed %.2f" % lo)
		# Curves: lateral acceleration capacity from banking and walls.
		var kap := absf(def.ring_kappa[k])
		if kap > 1e-4:
			var bank := absf(def.bank_at(def.ring_s[k]))
			var wall_ratio := clampf(def.ring_wall_h[k] / std_wall, 0.0, 1.5) if std_wall > 0.0 else 0.0
			var cap := G * (sin(bank) + wall_grip * wall_ratio)
			if hi * hi * kap > cap:
				return _fail(res, "too fast for curve (%.2f m/s, r=%.1f m)" % [hi, 1.0 / kap])
		# Crests: do not leave the surface.
		var vc := def.ring_vcurv[k]
		if vc < 0.0:
			var cos_t := 1.0 / sqrt(1.0 + slope * slope)
			if hi * hi * -vc > crest_safety * G * cos_t:
				return _fail(res, "would jump on crest (%.2f m/s)" % hi)
		if hi > max_speed:
			return _fail(res, "too fast (%.2f m/s)" % hi)
		if def.ring_half_w[k] < 0.8 * def.spec.half_width and hi > narrow_max_speed:
			return _fail(res, "too fast for narrow section (%.2f m/s)" % hi)
	if variant >= 0 and variant < def.obstacle_layouts.size():
		var ob := validate_layout(def, def.obstacle_layouts[variant], hi)
		if not ob.ok:
			return _fail(res, ob.reason)
		# Assume the marble may clip an obstacle and lose speed (pessimistic).
		lo = maxf(lo * obstacle_hit_keep, min_speed)
	res.v_lo = lo
	res.v_hi = maxf(hi, lo)
	res.v_min = vmin
	return res


func _fail(res: Dictionary, reason: String) -> Dictionary:
	res.ok = false
	res.reason = reason
	return res


## Blocked lateral interval [a, b] (metres, ball-centre space) of one obstacle.
func _blocked(def: TrackModuleDef, o: Dictionary) -> Vector2:
	var s := float(o.get("t", 0.5)) * def.length
	var w := def.profile_at(s).x
	var x := float(o.get("u", 0.0)) * w
	var br := def.spec.ball_radius
	var half := 0.0
	match str(o.get("kind", "peg")):
		"peg", "bumper":
			half = float(o.get("r", 0.2))
		"block":
			half = float(o.get("size", [1, 1, 1])[0]) * 0.5
		"sweeper":
			half = float(o.get("size", [1, 1, 1])[0]) * 0.5 + float(o.get("amp", 0.0)) * w
	return Vector2(x - half - br, x + half + br)


## Free lateral intervals for the ball centre given blocked intervals.
func _free_intervals(limit: float, blocked: Array) -> Array:
	blocked.sort_custom(func(a, b): return a.x < b.x)
	var free: Array = []
	var cur := -limit
	for b in blocked:
		if b.x > cur:
			free.append(Vector2(cur, minf(b.x, limit)))
		cur = maxf(cur, b.y)
	if cur < limit:
		free.append(Vector2(cur, limit))
	var out: Array = []
	for f in free:
		if f.y - f.x >= min_slack:
			out.append(f)
	return out


static func _interval_gap(a: Vector2, b: Vector2) -> float:
	if a.y < b.x:
		return b.x - a.y
	if b.y < a.x:
		return a.x - b.y
	return 0.0


## Checks that every obstacle row leaves a lane and that consecutive lanes are
## reachable with the available steering at speed v.
func validate_layout(def: TrackModuleDef, layout: Array, v: float) -> Dictionary:
	var br := def.spec.ball_radius
	var items: Array = []
	for o in layout:
		items.append({"s": float(o.get("t", 0.5)) * def.length, "o": o})
	items.sort_custom(func(a, b): return a.s < b.s)
	# Group into rows.
	var rows: Array = []
	for it in items:
		if rows.is_empty() or it.s - rows[-1].s > 2.0 * br + 0.5:
			rows.append({"s": it.s, "blocked": []})
		rows[-1].blocked.append(_blocked(def, it.o))
	var prev_free: Array = [Vector2(-0.05, 0.05)]  # marble assumed near centre at entry
	var prev_s := 0.0
	for row in rows:
		var limit := def.profile_at(row.s).x * TrackSpec.WALL_START
		var free := _free_intervals(limit, row.blocked)
		if free.is_empty():
			return {"ok": false, "reason": "obstacle row at s=%.1f leaves no lane" % row.s}
		var shift := INF
		for a in prev_free:
			for b in free:
				shift = minf(shift, _interval_gap(a, b))
		var dt: float = (row.s - prev_s) / maxf(v, 1.0)
		if shift > 0.0:
			var need := 2.0 * shift / (dt * dt)
			if need > steer_accel * 0.5:
				return {"ok": false, "reason": "lane change too abrupt at s=%.1f" % row.s}
		prev_free = free
		prev_s = row.s
	return {"ok": true, "reason": ""}
