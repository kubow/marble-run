class_name TrackModuleDef
extends RefCounted
## One reusable track module, defined analytically in its own local space.
##
## Local space convention: the ENTRY connector is the origin, forward is -Z,
## up is +Y, right is +X. The centreline is parameterised by horizontal arc
## length s in [0, length]. Heading (yaw), height and cross-section parameters
## are smooth functions of s chosen so that at both ends:
##   * slope == spec.grade, bank == 0, curvature == 0,
##   * width/wall/dish == standard values.
## Hence the exit ring of any module equals the entry ring of any other module
## once the next module is placed at this module's exit connector transform.
## Connector transforms are yaw-only frames (the shared grade is implied).

var id := ""
var type := ""
var length := 10.0           ## Horizontal arc length (m).
var curve := "none"          ## "none" | "arc" | "s"
var turn_deg := 0.0          ## arc: total heading change; s: peak heading offset.
var elevation := 0.0         ## Extra height change on top of base grade (m).
var wave_amp := 0.0          ## Depth of vertical waves (m).
var wave_count := 0
var width_scale := 1.0       ## Mid-module width multiplier.
var wall_scale := 1.0        ## Mid-module wall height multiplier.
var dish := 0.0              ## Mid-module floor curvature depth (m at the wall).
var bank_deg := 0.0          ## Peak banking angle at peak curvature.
var window := "plateau"      ## Shape of width/wall/dish blend: "plateau" | "bell".
var difficulty := 1.0        ## Difficulty weight used by the generator.
var tier := 1                ## Minimum level tier at which the module appears.
var weight := 1.0            ## Base selection weight.
var min_entry_speed := 0.0   ## Required entry speed (m/s), 0 = none.
var color := Color.WHITE
var obstacle_layouts: Array = []   ## Array of Array[Dictionary]
# Jump modules: kicker ramp, air gap (no geometry), sloped landing.
var kick_start_t := 0.0      ## Kicker starts rising here (fraction of length).
var takeoff_t := -1.0        ## Lip of the kicker; < 0 means "not a jump".
var land_t := -1.0           ## Start of the landing surface.
var kick_height := 0.0       ## Kicker rise above the base grade at the lip (m).
var land_drop := 0.0         ## Extra drop of the landing section (m, negative).

var spec: TrackSpec

# --- Sampled data (local space), built once by build_samples() -------------
var ring_s := PackedFloat32Array()
var ring_pos := PackedVector3Array()
var ring_right := PackedVector3Array()
var ring_up := PackedVector3Array()
var ring_tangent := PackedVector3Array()
var ring_half_w := PackedFloat32Array()
var ring_wall_h := PackedFloat32Array()
var ring_dish := PackedFloat32Array()
var ring_dist := PackedFloat32Array()      ## Cumulative 3D length.
var ring_kappa := PackedFloat32Array()     ## Horizontal curvature (1/m, signed, + = left).
var ring_slope := PackedFloat32Array()     ## dy/ds
var ring_vcurv := PackedFloat32Array()     ## Vertical curvature (1/m, - = crest).
var exit_transform := Transform3D.IDENTITY
var exit_yaw := 0.0
var length_3d := 0.0
var elevation_change := 0.0
var max_half_width := 0.0
var kappa_peak := 0.0


static func from_dict(d: Dictionary, p_spec: TrackSpec) -> TrackModuleDef:
	var m := TrackModuleDef.new()
	m.spec = p_spec
	m.id = str(d.get("id", ""))
	m.type = str(d.get("type", "straight"))
	m.length = float(d.get("length", 10.0))
	m.curve = str(d.get("curve", "none"))
	m.turn_deg = float(d.get("turn_deg", 0.0))
	m.elevation = float(d.get("elevation", 0.0))
	m.wave_amp = float(d.get("wave_amp", 0.0))
	m.wave_count = int(d.get("wave_count", 0))
	m.width_scale = float(d.get("width_scale", 1.0))
	m.wall_scale = float(d.get("wall_scale", 1.0))
	m.dish = float(d.get("dish", 0.0))
	m.bank_deg = float(d.get("bank_deg", 0.0))
	m.window = str(d.get("window", "plateau"))
	m.difficulty = float(d.get("difficulty", 1.0))
	m.tier = int(d.get("tier", 1))
	m.weight = float(d.get("weight", 1.0))
	m.min_entry_speed = float(d.get("min_entry_speed", 0.0))
	m.color = Color.html(str(d.get("color", "#ffffff")))
	m.obstacle_layouts = d.get("obstacle_layouts", [])
	m.kick_start_t = float(d.get("kick_start_t", 0.0))
	m.takeoff_t = float(d.get("takeoff_t", -1.0))
	m.land_t = float(d.get("land_t", -1.0))
	m.kick_height = float(d.get("kick_height", 0.0))
	m.land_drop = float(d.get("land_drop", 0.0))
	m.build_samples()
	return m


# --- Analytic shape functions ----------------------------------------------

func _turn_rad() -> float:
	return deg_to_rad(turn_deg)


func yaw_at(s: float) -> float:
	var t := s / length
	match curve:
		"arc":
			return _turn_rad() * (t - sin(TAU * t) / TAU)
		"s":
			return _turn_rad() * 0.5 * (1.0 - cos(TAU * t))
	return 0.0


func kappa_at(s: float) -> float:
	var t := s / length
	match curve:
		"arc":
			return _turn_rad() / length * (1.0 - cos(TAU * t))
		"s":
			return _turn_rad() * PI / length * sin(TAU * t)
	return 0.0


func _peak_kappa() -> float:
	match curve:
		"arc":
			return absf(2.0 * _turn_rad() / length)
		"s":
			return absf(_turn_rad() * PI / length)
	return 0.0


func is_jump() -> bool:
	return takeoff_t > 0.0 and land_t > takeoff_t


func takeoff_s() -> float:
	return takeoff_t * length


func land_s() -> float:
	return land_t * length


## True if s lies strictly inside the air gap of a jump.
func in_gap(s: float) -> bool:
	return is_jump() and s > takeoff_s() + 1e-4 and s < land_s() - 1e-4


## True if the ring segment k -> k+1 is inside the air gap (no geometry).
func gap_segment(k: int) -> bool:
	if not is_jump():
		return false
	return ring_s[k] >= takeoff_s() - 1e-4 and ring_s[k + 1] <= land_s() + 1e-4


func _jump_height(s: float) -> float:
	var s0 := kick_start_t * length
	var st := takeoff_s()
	var sl := land_s()
	if s <= st:
		var k := 0.0
		if s > s0:
			var u := (s - s0) / (st - s0)
			k = kick_height * u * u
		return spec.grade * s + k
	if s >= sl:
		var u := (s - sl) / (length - sl)
		return spec.grade * s + land_drop * (1.0 - (1.0 - u) * (1.0 - u))
	# Inside the gap: straight line between lip and landing (tracking only).
	var a := _jump_height(st)
	var b := _jump_height(sl)
	return lerpf(a, b, (s - st) / (sl - st))


func _jump_slope(s: float) -> float:
	var s0 := kick_start_t * length
	var st := takeoff_s()
	var sl := land_s()
	if s <= st:
		if s > s0:
			return spec.grade + 2.0 * kick_height * (s - s0) / ((st - s0) * (st - s0))
		return spec.grade
	if s >= sl:
		var ll := length - sl
		var u := (s - sl) / ll
		return spec.grade + land_drop * 2.0 * (1.0 - u) / ll
	return (_jump_height(sl) - _jump_height(st)) / (sl - st)


func _jump_dd(s: float) -> float:
	var s0 := kick_start_t * length
	var st := takeoff_s()
	var sl := land_s()
	if s <= st:
		return 2.0 * kick_height / ((st - s0) * (st - s0)) if s > s0 else 0.0
	if s >= sl:
		var ll := length - sl
		return -2.0 * land_drop / (ll * ll)
	return 0.0


func height_at(s: float) -> float:
	if is_jump():
		return _jump_height(s)
	var t := s / length
	var s5 := t * t * t * (t * (6.0 * t - 15.0) + 10.0)
	var w := sin(PI * wave_count * t)
	return spec.grade * s + elevation * s5 - wave_amp * w * w


func slope_at(s: float) -> float:
	if is_jump():
		return _jump_slope(s)
	var t := s / length
	var ds5 := 30.0 * t * t * (t - 1.0) * (t - 1.0)
	var k := PI * wave_count / length
	return spec.grade + elevation * ds5 / length - wave_amp * k * sin(2.0 * PI * wave_count * t)


func height_dd_at(s: float) -> float:
	if is_jump():
		return _jump_dd(s)
	var t := s / length
	var dds5 := 120.0 * t * t * t - 180.0 * t * t + 60.0 * t
	var k := PI * wave_count / length
	return elevation * dds5 / (length * length) - wave_amp * 2.0 * k * k * cos(2.0 * PI * wave_count * t)


func window_at(s: float) -> float:
	var t := clampf(s / length, 0.0, 1.0)
	if window == "bell":
		var w := sin(PI * t)
		return w * w
	if window == "landing":
		# Wider, taller walls on the landing to catch the marble.
		return _smooth(land_t, land_t + 0.08, t) * (1.0 - _smooth(0.85, 1.0, t))
	return _smooth(0.0, 0.2, t) * (1.0 - _smooth(0.8, 1.0, t))


static func _smooth(e0: float, e1: float, x: float) -> float:
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## (half_width, wall_height, dish) at s.
func profile_at(s: float) -> Vector3:
	var f := window_at(s)
	return Vector3(
		spec.half_width * lerpf(1.0, width_scale, f),
		spec.wall_height * lerpf(1.0, wall_scale, f),
		dish * f)


## Style blend factor: 0 at both ends, 1 in the styled middle of the module.
func style_blend(s: float, b := TrackSpec.STYLE_BLEND) -> float:
	var t := clampf(s / length, 0.0, 1.0)
	return _smooth(0.0, b, t) * (1.0 - _smooth(1.0 - b, 1.0, t))


func bank_at(s: float) -> float:
	if kappa_peak <= 0.0:
		return 0.0
	return deg_to_rad(bank_deg) * kappa_at(s) / kappa_peak


## Orthonormal frame (right, up, tangent) at s with banking applied.
func frame_vectors_at(s: float) -> Array:
	var yaw := yaw_at(s)
	var dir := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var tangent := Vector3(dir.x, slope_at(s), dir.z).normalized()
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var up := right.cross(tangent).normalized()
	var phi := bank_at(s)
	if phi != 0.0:
		var r2 := right * cos(phi) + up * sin(phi)
		var u2 := up * cos(phi) - right * sin(phi)
		right = r2
		up = u2
	return [right, up, tangent]


## Horizontal position by numeric integration of the heading (midpoint rule).
func _integrate_xz(s0: float, xz0: Vector2, s1: float, steps: int) -> Vector2:
	var p := xz0
	var h := (s1 - s0) / steps
	for i in steps:
		var yaw := yaw_at(s0 + (i + 0.5) * h)
		p += Vector2(-sin(yaw), -cos(yaw)) * h
	return p


func build_samples() -> void:
	kappa_peak = _peak_kappa()
	var segs := int(ceil(length / spec.ring_spacing))
	segs = maxi(segs, int(ceil(absf(_turn_rad()) / 0.08)))
	if wave_count > 0:
		segs = maxi(segs, wave_count * 12)
	if width_scale != 1.0 or wall_scale != 1.0 or dish != 0.0:
		segs = maxi(segs, 16)
	segs = maxi(segs, 6)
	# Sample positions: uniform plus exact style-blend and jump boundaries.
	var s_list: Array = []
	for i in segs + 1:
		s_list.append(length * float(i) / segs)
	for b in [TrackSpec.STYLE_BLEND, TrackSpec.WIRE_BLEND]:
		for f in [b / 3.0, b * 2.0 / 3.0, b, b * 4.0 / 3.0, 1.0 - b * 4.0 / 3.0, 1.0 - b, 1.0 - b * 2.0 / 3.0, 1.0 - b / 3.0]:
			s_list.append(length * f)
	if is_jump():
		s_list.append(takeoff_s())
		s_list.append(land_s())
	s_list.sort()
	var uniq: Array = []
	for v in s_list:
		if uniq.is_empty() or v - uniq[-1] > 0.05:
			uniq.append(v)
		elif v == length or (is_jump() and (is_equal_approx(v, takeoff_s()) or is_equal_approx(v, land_s()))):
			uniq[-1] = v
	ring_s.clear(); ring_pos.clear(); ring_right.clear(); ring_up.clear(); ring_tangent.clear()
	ring_half_w.clear(); ring_wall_h.clear(); ring_dish.clear(); ring_dist.clear()
	ring_kappa.clear(); ring_slope.clear(); ring_vcurv.clear()
	var xz := Vector2.ZERO
	var prev := Vector3.ZERO
	var dist := 0.0
	max_half_width = 0.0
	for i in uniq.size():
		var s: float = uniq[i]
		if i > 0:
			xz = _integrate_xz(ring_s[i - 1], xz, s, 8)
		var p := Vector3(xz.x, height_at(s), xz.y)
		if i > 0:
			dist += p.distance_to(prev)
		prev = p
		var fv := frame_vectors_at(s)
		var prof := profile_at(s)
		var sl := slope_at(s)
		ring_s.append(s)
		ring_pos.append(p)
		ring_right.append(fv[0])
		ring_up.append(fv[1])
		ring_tangent.append(fv[2])
		ring_half_w.append(prof.x)
		ring_wall_h.append(prof.y)
		ring_dish.append(prof.z)
		ring_dist.append(dist)
		ring_kappa.append(kappa_at(s))
		ring_slope.append(sl)
		ring_vcurv.append(height_dd_at(s) / pow(1.0 + sl * sl, 1.5))
		max_half_width = maxf(max_half_width, prof.x)
	length_3d = dist
	var end := ring_pos[ring_pos.size() - 1]
	exit_yaw = yaw_at(length)
	exit_transform = Transform3D(Basis(Vector3.UP, exit_yaw), end)
	elevation_change = end.y


func ring_count() -> int:
	return ring_pos.size()


## Local transform of a point on the floor at fraction t along the module and
## normalised lateral offset u (-1..1). Basis: x = right, y = up, z = back.
func floor_transform(t: float, u: float) -> Transform3D:
	var s := clampf(t, 0.0, 1.0) * length
	var xz := _integrate_xz(0.0, Vector2.ZERO, s, maxi(8, int(s * 4.0)))
	var center := Vector3(xz.x, height_at(s), xz.y)
	var fv := frame_vectors_at(s)
	var prof := profile_at(s)
	var right: Vector3 = fv[0]
	var up: Vector3 = fv[1]
	var tangent: Vector3 = fv[2]
	var origin := center + right * (u * prof.x) + up * TrackSpec.surface_height(u, prof.y, prof.z)
	return Transform3D(Basis(right, up, -tangent), origin)


## 3D track distance from the entry to horizontal arc position s.
func dist_at_s(s: float) -> float:
	for k in range(1, ring_s.size()):
		if ring_s[k] >= s:
			var f := (s - ring_s[k - 1]) / maxf(ring_s[k] - ring_s[k - 1], 1e-6)
			return lerpf(ring_dist[k - 1], ring_dist[k], f)
	return length_3d


func has_obstacles() -> bool:
	return not obstacle_layouts.is_empty()
