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
var tube_grip := 2.0        ## Lateral g a closed tube can provide.
var wire_safety := 0.5      ## Fraction of the geometric wire-cradle grip trusted.
var jump_margin := 0.4      ## Marble must land this far past the start of the landing (m).
var jump_keep := 0.85       ## Pessimistic extra speed fraction kept after a landing.
# Player skill: at difficulty > 1 sections may require braking or boosting.
# skill (0..1) scales the deceleration/acceleration the player is assumed to
# apply over the run-up; only CONTROL_SHARE of the physically possible change is
# counted, so demanded inputs are always comfortably achievable.
var brake_accel := 4.0      ## Full-brake deceleration of the rolling marble (m/s^2).
var boost_accel := 2.3      ## Full-boost acceleration of the rolling marble (m/s^2).
const CONTROL_SHARE := 0.6
const LIMIT_MERGE := 4.0    ## Speed limits closer than this (m) are merged.


func describe() -> String:
	return "damp=%s lo=%s hi=%s min=%s grip=%s crest=%s down=%s up=%s vmax=%s narrow=%s steer=%s slack=%s hit=%s tube=%s wire=%s jmargin=%s jkeep=%s brake=%s boost=%s share=%s" % [
		damp_eff, lo_damp_mul, hi_damp_mul, min_speed, wall_grip, crest_safety,
		max_down_slope, max_up_slope, max_speed, narrow_max_speed, steer_accel, min_slack, obstacle_hit_keep,
		tube_grip, wire_safety, jump_margin, jump_keep, brake_accel, boost_accel, CONTROL_SHARE]


## Returns {ok, reason, v_lo, v_hi, v_min, limits}. `style` is the environment
## geometry ("trough", "tube", "wires") the module is built with. `skill` (0..1)
## allows sections that need braking/boosting, given `runup` metres of track
## before the module. `limits` lists the speed requirements found:
## Vector3(s, v_min, v_max) with v_min = 0 / v_max = INF when unused.
func check_module(def: TrackModuleDef, v_lo: float, v_hi: float, variant: int = -1, style := "trough", skill := 0.0, runup := 0.0) -> Dictionary:
	var res := {"ok": true, "reason": "", "v_lo": v_lo, "v_hi": v_hi, "v_min": v_lo, "limits": []}
	var limits: Array = res.limits
	if def.min_entry_speed > 0.0 and v_lo < def.min_entry_speed:
		return _fail(res, "entry speed %.2f < required %.2f" % [v_lo, def.min_entry_speed])
	var c_lo := damp_eff * lo_damp_mul
	var c_hi := damp_eff * hi_damp_mul
	var std_wall := def.spec.wall_height
	var lo := v_lo
	var hi := v_hi
	var vmin := v_lo
	var n := def.ring_count()
	var k := 0
	while k < n:
		var sk := def.ring_s[k]
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
		var styled := style != "trough" and def.style_blend(sk, TrackSpec.blend_fraction(style)) > 0.5
		# Curves: lateral acceleration capacity from banking and walls/wires/tube.
		var kap := absf(def.ring_kappa[k])
		if kap > 1e-4:
			var bank := absf(def.bank_at(sk))
			var grip := 0.0
			if styled and style == "tube":
				grip = tube_grip
			elif styled and style == "wires":
				grip = wire_grip(def.spec)
			else:
				var wall_ratio := clampf(def.ring_wall_h[k] / std_wall, 0.0, 1.5) if std_wall > 0.0 else 0.0
				grip = wall_grip * wall_ratio
			var cap := G * (sin(bank) + grip)
			if hi * hi * kap > cap:
				var nh := _brake_to(hi, sqrt(cap / kap), runup + def.ring_dist[k], skill)
				if nh < 0.0:
					return _fail(res, "too fast for curve (%.2f m/s, r=%.1f m)" % [hi, 1.0 / kap])
				_add_limit(limits, sk, 0.0, nh)
				hi = nh
				lo = minf(lo, nh * 0.8)
		# Crests: do not leave the surface (a closed tube holds the marble).
		var vc := def.ring_vcurv[k]
		if vc < 0.0 and not (styled and style == "tube"):
			var cos_t := 1.0 / sqrt(1.0 + slope * slope)
			if hi * hi * -vc > crest_safety * G * cos_t:
				var nh := _brake_to(hi, sqrt(crest_safety * G * cos_t / -vc), runup + def.ring_dist[k], skill)
				if nh < 0.0:
					return _fail(res, "would jump on crest (%.2f m/s)" % hi)
				_add_limit(limits, sk, 0.0, nh)
				hi = nh
				lo = minf(lo, nh * 0.8)
		var cap_v := max_speed
		if def.ring_half_w[k] < 0.8 * def.spec.half_width:
			cap_v = minf(cap_v, narrow_max_speed)
		if hi > cap_v:
			var nh := _brake_to(hi, cap_v, runup + def.ring_dist[k], skill)
			if nh < 0.0:
				return _fail(res, "too fast (%.2f m/s, limit %.1f)" % [hi, cap_v])
			_add_limit(limits, sk, 0.0, nh)
			hi = nh
			lo = minf(lo, nh * 0.8)
		# Jumps: fly both speed bounds over the gap and continue after landing.
		if def.is_jump() and is_equal_approx(sk, def.takeoff_s()):
			var win := jump_window(def)
			if win.y - win.x < 1.0:
				return _fail(res, "jump speed window too narrow")
			var run := runup + def.ring_dist[k]
			if hi > win.y:
				var nh := _brake_to(hi, win.y, run, skill)
				if nh < 0.0:
					return _fail(res, "too fast for jump (%.1f > %.1f m/s)" % [hi, win.y])
				_add_limit(limits, sk, 0.0, nh)
				hi = nh
				lo = minf(lo, hi)
			if lo < win.x:
				if skill <= 0.0 or win.x * win.x - lo * lo > 2.0 * boost_accel * skill * run * CONTROL_SHARE:
					return _fail(res, "too slow for jump (%.1f < %.1f m/s)" % [lo, win.x])
				_add_limit(limits, sk, win.x, INF)
				lo = win.x
				hi = maxf(hi, lo)
			var jl := jump_flight(def, lo)
			var jh := jump_flight(def, hi)
			if not jl.ok:
				return _fail(res, "jump at %.1f m/s: %s" % [lo, jl.reason])
			if not jh.ok:
				return _fail(res, "jump at %.1f m/s: %s" % [hi, jh.reason])
			# Restart integration at the first ring after both landings; add the
			# height gained between each landing point and that ring.
			var s_after := maxf(jl.s_hit, jh.s_hit)
			var r := k + 1
			while r < n and def.ring_s[r] < s_after:
				r += 1
			if r >= n:
				return _fail(res, "lands at the module end")
			var y_r := def.ring_pos[r].y
			lo = sqrt(maxf(jl.v * jl.v + 2.0 * G * ROLL * (jl.y_hit - y_r), 0.0)) * jump_keep
			hi = sqrt(maxf(jh.v * jh.v + 2.0 * G * ROLL * (jh.y_hit - y_r), 0.0))
			if lo < min_speed:
				return _fail(res, "stall after landing")
			k = r + 1
			continue
		k += 1
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


## Lateral grip (in g) of the 3-wire cradle: the side wire supports the marble
## along the line from the wire centre to the marble centre.
func wire_grip(spec: TrackSpec) -> float:
	var dx := spec.wire_side_dx
	var dy := spec.ball_radius - spec.wire_side_y
	return wire_safety * dx / maxf(dy, 0.01)


## Ballistic flight of the marble centre from the kicker lip at speed v.
## Returns {ok, reason, s_hit, y_hit, v} where v is the speed kept along the
## landing surface (the normal component is lost on impact).
func jump_flight(def: TrackModuleDef, v: float) -> Dictionary:
	var st := def.takeoff_s()
	var sl := def.land_s()
	var th := atan(def.slope_at(st))
	var vx := v * cos(th)
	var vy := v * sin(th)
	if vx < 0.1:
		return {"ok": false, "reason": "no forward speed"}
	var y0 := def.height_at(st)
	var s := sl
	var steps := 0
	while s <= def.length:
		var t := (s - st) / vx
		var y := y0 + vy * t - 0.5 * G * t * t
		var surf := def.height_at(s)
		if y <= surf:
			if s < sl + jump_margin:
				return {"ok": false, "reason": "falls short of the landing"}
			if s > def.length - 2.0:
				return {"ok": false, "reason": "overshoots the landing"}
			var vyh := vy - G * t
			var phi := atan(def.slope_at(s))
			var along := vx * cos(phi) + vyh * sin(phi)
			return {"ok": true, "reason": "", "s_hit": s, "y_hit": surf, "v": maxf(along, 0.0)}
		s += 0.05
		steps += 1
	return {"ok": false, "reason": "overshoots the module"}


## Speed after braking from `hi` to `v_safe` within `run` metres, or -1 if the
## player (at this skill) cannot. Hands-off safe speeds pass unchanged.
func _brake_to(hi: float, v_safe: float, run: float, skill: float) -> float:
	var target := v_safe * 0.95
	if hi <= v_safe:
		return hi
	if skill <= 0.0:
		return -1.0
	if hi * hi - target * target <= 2.0 * brake_accel * skill * run * CONTROL_SHARE:
		return target
	return -1.0


static func _add_limit(limits: Array, s: float, vmin: float, vmax: float) -> void:
	if not limits.is_empty():
		var last: Vector3 = limits[-1]
		if s - last.x < LIMIT_MERGE:
			limits[-1] = Vector3(last.x, maxf(last.y, vmin), minf(last.z, vmax))
			return
	limits.append(Vector3(s, vmin, vmax))


static var _window_cache: Dictionary = {}


## Take-off speeds for which the jump clears the gap and lands before the end:
## Vector2(min, max) with 0.3 m/s safety margins (empty if min >= max).
func jump_window(def: TrackModuleDef) -> Vector2:
	var key := "%s/%s/%s" % [def.id, jump_margin, def.length]
	if _window_cache.has(key):
		return _window_cache[key]
	var vmin := INF
	var vmax := -INF
	var v := 0.5
	while v <= 25.0:
		if jump_flight(def, v).ok:
			vmin = minf(vmin, v)
			vmax = maxf(vmax, v)
		v += 0.1
	var w := Vector2(vmin + 0.3, vmax - 0.3) if vmin < INF else Vector2(INF, -INF)
	_window_cache[key] = w
	return w


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
