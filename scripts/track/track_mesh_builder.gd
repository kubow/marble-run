class_name TrackMeshBuilder
extends RefCounted
## Builds render meshes and collision strips for a module in one of three
## geometry styles by sweeping cross-sections along the module's sampled frames:
##   trough - open plastic channel (classic / ramps environments; jump gaps),
##   tube   - closed see-through pipe,
##   wires  - three metal wires (one under the marble, one on each side).
## Styled geometry blends from the standard trough profile at a module end only
## when the neighbouring module has another style (blend_in / blend_out), so
## every connector between different styles is the standard ring.
##
## Winding: Godot treats clockwise triangles as front faces. For a ring i and
## the next ring i+1 (further forward) with profile points j -> j+1 running
## left -> right, the triangles (A, C, D) and (A, D, B) face up/inwards, where
## A = (i, j), B = (i, j+1), C = (i+1, j), D = (i+1, j+1). Tube points run
## left -> bottom -> right around the circle, so tube faces point inwards; wire
## loops run clockwise (seen from behind) so wire faces point outwards.
##
## Collision is a list of strips {key, rings, entry, exit}. At a connector, a
## strip that starts at the entry reuses the previous module's last ring of the
## strip with the same key, so joins share bit-identical vertices.

static var _mesh_cache: Dictionary = {}
static var _strip_cache: Dictionary = {}
static var _material: StandardMaterial3D
static var _glass: StandardMaterial3D
static var _metal: StandardMaterial3D

const TUBE_GAP_DEG := 4.0
const WIRE_SIDES := 6
const BRACKET_SPACING := 1.6


static func clear_cache() -> void:
	_mesh_cache.clear()
	_strip_cache.clear()
	_material = null
	_glass = null
	_metal = null


static func track_material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.vertex_color_is_srgb = true
		_material.roughness = 0.45
		_material.metallic_specular = 0.35
	return _material


static func glass_material() -> StandardMaterial3D:
	if _glass == null:
		_glass = StandardMaterial3D.new()
		_glass.vertex_color_use_as_albedo = true
		_glass.vertex_color_is_srgb = true
		_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glass.cull_mode = BaseMaterial3D.CULL_DISABLED
		_glass.roughness = 0.1
		_glass.metallic_specular = 0.8
	return _glass


static func metal_material() -> StandardMaterial3D:
	if _metal == null:
		_metal = StandardMaterial3D.new()
		_metal.vertex_color_use_as_albedo = true
		_metal.vertex_color_is_srgb = true
		_metal.metallic = 0.85
		_metal.roughness = 0.25
		_metal.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _metal


# --- Cross-sections ------------------------------------------------------------

## Style blend at ring k: 0 = standard trough profile, 1 = full style.
static func blend(def: TrackModuleDef, k: int, style: String, bin: bool, bout: bool) -> float:
	if style == "trough":
		return 0.0
	var t := def.ring_s[k] / def.length
	var b := TrackSpec.blend_fraction(style)
	var f := 1.0
	if bin:
		f *= TrackModuleDef._smooth(0.0, b, t)
	if bout:
		f *= 1.0 - TrackModuleDef._smooth(1.0 - b, 1.0, t)
	return f


## (half width, wall height, dish) of the channel surface at ring k.
static func surface_params(def: TrackModuleDef, k: int, style: String, f: float) -> Vector3:
	var w := def.ring_half_w[k]
	var hw := def.ring_wall_h[k]
	var dish := def.ring_dish[k]
	if style == "wires":
		w = lerpf(w, def.spec.narrow_half_width, f)
		# Taller walls part-way through the funnel keep a deflected marble in.
		hw = lerpf(hw, 0.3, f) + 0.35 * sin(PI * f)
		dish = lerpf(dish, 0.0, f)
	return Vector3(w, hw, dish)


## Collision cross-section (15 points, left -> right): lip, inner profile, lip.
## For tubes the points are blended towards a nearly closed circle.
static func surface_ring_2d(def: TrackModuleDef, k: int, style: String, f: float) -> PackedVector2Array:
	var pr := surface_params(def, k, style, f)
	var lip := def.spec.lip
	var pts := PackedVector2Array([Vector2(-pr.x - lip, pr.y)])
	pts.append_array(TrackSpec.inner_profile(pr.x, pr.y, pr.z))
	pts.append(Vector2(pr.x + lip, pr.y))
	if style == "tube" and f > 0.0:
		var r := def.spec.tube_radius
		var n := pts.size()
		var g := deg_to_rad(TUBE_GAP_DEG)
		for i in n:
			var phi := lerpf(-(PI - g), PI - g, float(i) / (n - 1))
			pts[i] = pts[i].lerp(Vector2(r * sin(phi), r - r * cos(phi)), f)
	return pts


## Closed visual loop of an open channel: inner surface then the body shell.
static func _channel_loop(def: TrackModuleDef, k: int, style: String, f: float) -> PackedVector2Array:
	var pr := surface_params(def, k, style, f)
	var lip := def.spec.lip
	var base := def.spec.base_depth
	var pts := TrackSpec.inner_profile(pr.x, pr.y, pr.z)
	pts.append(Vector2(pr.x + lip, pr.y))
	pts.append(Vector2(pr.x + lip, -base))
	pts.append(Vector2(-pr.x - lip, -base))
	pts.append(Vector2(-pr.x - lip, pr.y))
	return pts


## Wire centres (bottom, left, right) in the ring plane.
static func wire_centres(spec: TrackSpec) -> Array:
	return [Vector2(0.0, -spec.wire_radius), Vector2(-spec.wire_side_dx, spec.wire_side_y), Vector2(spec.wire_side_dx, spec.wire_side_y)]


## Collision for each wire: a narrow flat strip on the wire surface facing the
## resting marble (2 points, left -> right, front side towards the marble).
## Round wire meshes made the marble chatter between three convex prisms and
## bleed speed; flat contact strips roll as smoothly as the trough while the
## visual wires stay round.
const WIRE_STRIP_HALF := 0.045


static func wire_contact_strips(spec: TrackSpec) -> Array:
	var ball := Vector2(0.0, spec.ball_radius)
	var out: Array = []
	for c in wire_centres(spec):
		var n: Vector2 = (ball - c).normalized()
		var cp: Vector2 = c + n * spec.wire_radius
		var d := Vector2(n.y, -n.x)
		out.append(PackedVector2Array([cp - d * WIRE_STRIP_HALF, cp + d * WIRE_STRIP_HALF]))
	return out


## Hexagonal wire loop (clockwise seen from behind -> outward faces), flat top.
static func _wire_loop(spec: TrackSpec, centre: Vector2, closed_repeat: bool) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for j in WIRE_SIDES:
		var a := deg_to_rad(120.0 - j * 360.0 / WIRE_SIDES)
		pts.append(centre + Vector2(cos(a), sin(a)) * spec.wire_radius)
	if closed_repeat:
		pts.append(pts[0])
	return pts


static func _to3d(def: TrackModuleDef, k: int, p: Vector2) -> Vector3:
	return def.ring_pos[k] + def.ring_right[k] * p.x + def.ring_up[k] * p.y


## Ring indices with t in [t0, t1] (inclusive, small tolerance).
static func _ring_range(def: TrackModuleDef, t0: float, t1: float) -> Array:
	var out: Array = []
	for k in def.ring_count():
		var t := def.ring_s[k] / def.length
		if t >= t0 - 1e-4 and t <= t1 + 1e-4:
			out.append(k)
	return out


## Consecutive ring index runs of the walkable trough, split at a jump gap.
static func _trough_runs(def: TrackModuleDef) -> Array:
	var runs: Array = []
	var cur: Array = [0]
	for k in range(1, def.ring_count()):
		if def.gap_segment(k - 1):
			runs.append(cur)
			cur = [k]
		else:
			cur.append(k)
	runs.append(cur)
	var out: Array = []
	for r in runs:
		if r.size() >= 2:
			out.append(r)
	return out


# --- Collision -------------------------------------------------------------------

## Local collision strips for a module/style (cached).
static func collision_strips(def: TrackModuleDef, style := "trough", bin := true, bout := true) -> Array:
	var key := "%s/%s/%d%d" % [def.id, style, int(bin), int(bout)]
	if _strip_cache.has(key):
		return _strip_cache[key]
	var strips: Array = []
	var last := def.ring_count() - 1
	match style:
		"wires":
			var b := TrackSpec.WIRE_BLEND
			if bin:
				strips.append(_surface_strip(def, _ring_range(def, 0.0, b * 4.0 / 3.0), style, bin, bout))
			if bout:
				strips.append(_surface_strip(def, _ring_range(def, 1.0 - b * 4.0 / 3.0, 1.0), style, bin, bout))
			var ks := _ring_range(def, b * 2.0 / 3.0 if bin else 0.0, 1.0 - b * 2.0 / 3.0 if bout else 1.0)
			var contacts := wire_contact_strips(def.spec)
			for w in contacts.size():
				var rings: Array = []
				for k in ks:
					var ring := PackedVector3Array()
					for p in contacts[w]:
						ring.append(_to3d(def, k, p))
					rings.append(ring)
				strips.append({"key": "w%d" % w, "rings": rings, "entry": ks[0] == 0, "exit": ks[-1] == last})
		"tube":
			var all: Array = []
			for k in def.ring_count():
				all.append(k)
			strips.append(_surface_strip(def, all, style, bin, bout))
		_:
			for run in _trough_runs(def):
				strips.append(_surface_strip(def, run, style, bin, bout))
	_strip_cache[key] = strips
	return strips


static func _surface_strip(def: TrackModuleDef, ks: Array, style: String, bin: bool, bout: bool) -> Dictionary:
	var rings: Array = []
	for k in ks:
		var f := blend(def, k, style, bin, bout)
		var ring := PackedVector3Array()
		for p in surface_ring_2d(def, k, style, f):
			ring.append(_to3d(def, k, p))
		rings.append(ring)
	return {"key": "surface", "rings": rings, "entry": ks[0] == 0, "exit": ks[-1] == def.ring_count() - 1}


## Standard (trough) collision ring k in local space. Kept for tests/tools.
static func collision_ring(def: TrackModuleDef, k: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in surface_ring_2d(def, k, "trough", 0.0):
		out.append(_to3d(def, k, p))
	return out


## World-space collision strips for a placement. Strips starting at the entry
## reuse the matching last ring of the previous placement (shared vertices).
static func world_strips(p: TrackPlacement, prev_strips: Array) -> Array:
	var out: Array = []
	for st in collision_strips(p.def, p.style, p.blend_in, p.blend_out):
		var rings: Array = []
		for r in st.rings:
			rings.append(p.transform * (r as PackedVector3Array))
		if st.entry:
			for ps in prev_strips:
				if ps.exit and ps.key == st.key and (ps.rings[-1] as PackedVector3Array).size() == (rings[0] as PackedVector3Array).size():
					rings[0] = ps.rings[-1]
					break
		out.append({"key": st.key, "rings": rings, "entry": st.entry, "exit": st.exit})
	return out


static func faces_from_strips(strips: Array) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for st in strips:
		faces.append_array(faces_from_rings(st.rings))
	return faces


static func faces_from_rings(rings: Array) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for k in rings.size() - 1:
		var r0: PackedVector3Array = rings[k]
		var r1: PackedVector3Array = rings[k + 1]
		for j in r0.size() - 1:
			var a := r0[j]
			var b := r0[j + 1]
			var c := r1[j]
			var d := r1[j + 1]
			faces.append_array([a, c, d, a, d, b])
	return faces


# --- Render meshes ---------------------------------------------------------------

static func get_mesh(def: TrackModuleDef, style := "trough", bin := true, bout := true) -> ArrayMesh:
	var key := "%s/%s/%d%d" % [def.id, style, int(bin), int(bout)]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var m := build_mesh(def, style, bin, bout)
	_mesh_cache[key] = m
	return m


class Arrays:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()

	func commit(mesh: ArrayMesh, mat: Material) -> void:
		if idx.is_empty():
			return
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_COLOR] = cols
		arrays[Mesh.ARRAY_INDEX] = idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)


## Sweeps 2D loops along rings `ks`. Points [0, smooth_n) get smooth normals;
## other edges are flat. If `radial` is finite, normals point away from it.
## col_fn(k, e, a2, b2, point_index) -> Color
static func _sweep(a: Arrays, def: TrackModuleDef, ks: Array, loops: Array, closed: bool, smooth_n: int, col_fn: Callable, radial := Vector2(INF, INF)) -> void:
	var n: int = (loops[0] as PackedVector2Array).size()
	var edges := n if closed else n - 1
	var base := a.verts.size()
	for i in ks.size():
		var k: int = ks[i]
		var loop: PackedVector2Array = loops[i]
		var sm := PackedVector2Array()
		sm.resize(n)
		for j in mini(smooth_n, n):
			var acc := Vector2.ZERO
			if j > 0:
				var d0 := loop[j] - loop[j - 1]
				acc += Vector2(-d0.y, d0.x).normalized()
			if j < mini(smooth_n, n) - 1:
				var d1 := loop[j + 1] - loop[j]
				acc += Vector2(-d1.y, d1.x).normalized()
			sm[j] = acc.normalized()
		var r := def.ring_right[k]
		var u := def.ring_up[k]
		var band := 1.0 if (k / 2) % 2 == 0 else 0.92
		for e in edges:
			var a2 := loop[e]
			var b2 := loop[(e + 1) % n]
			var na: Vector2
			var nb: Vector2
			if radial.is_finite():
				na = (a2 - radial).normalized()
				nb = (b2 - radial).normalized()
			elif e < smooth_n - 1:
				na = sm[e]
				nb = sm[e + 1]
			else:
				var d := b2 - a2
				na = Vector2(-d.y, d.x).normalized()
				nb = na
			var ca: Color = col_fn.call(k, e, a2, b2, e)
			var cb: Color = col_fn.call(k, e, a2, b2, (e + 1) % n)
			a.verts.append(_to3d(def, k, a2))
			a.verts.append(_to3d(def, k, b2))
			a.norms.append((r * na.x + u * na.y).normalized())
			a.norms.append((r * nb.x + u * nb.y).normalized())
			a.cols.append(Color(ca.r * band, ca.g * band, ca.b * band, ca.a))
			a.cols.append(Color(cb.r * band, cb.g * band, cb.b * band, cb.a))
	for i in ks.size() - 1:
		for e in edges:
			var p0 := base + (i * edges + e) * 2
			var p1 := p0 + 1
			var q0 := base + ((i + 1) * edges + e) * 2
			var q1 := q0 + 1
			a.idx.append_array([p0, q0, q1, p0, q1, p1])


## Flat polygon cap (e.g. the open ends at a jump gap), facing `facing`.
static func _cap(a: Arrays, def: TrackModuleDef, k: int, loop: PackedVector2Array, color: Color, facing: Vector3) -> void:
	var tri := Geometry2D.triangulate_polygon(loop)
	if tri.is_empty():
		return
	var base := a.verts.size()
	for p in loop:
		a.verts.append(_to3d(def, k, p))
		a.norms.append(facing)
		a.cols.append(color)
	for i in range(0, tri.size(), 3):
		var i0 := base + tri[i]
		var i1 := base + tri[i + 1]
		var i2 := base + tri[i + 2]
		var n := (a.verts[i0] - a.verts[i2]).cross(a.verts[i0] - a.verts[i1])
		if n.dot(facing) < 0.0:
			a.idx.append_array([i0, i2, i1])
		else:
			a.idx.append_array([i0, i1, i2])


static func _channel_colors(def: TrackModuleDef) -> Callable:
	var floor_col := def.color
	var wall_col := def.color.lerp(Color.WHITE, 0.3)
	var shell_col := def.color.darkened(0.35)
	var inner_n := TrackSpec.PROFILE_X.size()
	return func(_k: int, e: int, a2: Vector2, b2: Vector2, _pi: int) -> Color:
		if e < inner_n - 1:
			var xa := absf(float(TrackSpec.PROFILE_X[e]))
			var xb := absf(float(TrackSpec.PROFILE_X[e + 1]))
			return wall_col if xa > TrackSpec.WALL_START + 0.05 and xb > TrackSpec.WALL_START + 0.05 else floor_col
		var d := b2 - a2
		return Color.WHITE if absf(d.y) < 1e-4 and a2.y > 0.0 else shell_col


static func build_mesh(def: TrackModuleDef, style := "trough", bin := true, bout := true) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var solid := Arrays.new()
	var inner_n := TrackSpec.PROFILE_X.size()
	var chan_col := _channel_colors(def)
	match style:
		"tube":
			var glass := Arrays.new()
			var ks: Array = []
			var loops: Array = []
			for k in def.ring_count():
				ks.append(k)
				loops.append(surface_ring_2d(def, k, style, blend(def, k, style, bin, bout)))
			var bottom := def.color
			var top := Color("cfe8ff")
			var n := (loops[0] as PackedVector2Array).size()
			var tube_col := func(k: int, _e: int, _a: Vector2, _b: Vector2, pi: int) -> Color:
				var f := blend(def, k, style, bin, bout)
				var side := absf(float(pi) / (n - 1) * 2.0 - 1.0)
				var upper := TrackModuleDef._smooth(0.3, 0.6, side) * f
				var c := bottom.lerp(top, upper)
				c.a = lerpf(1.0, 0.25, upper)
				return c
			_sweep(glass, def, ks, loops, false, n, tube_col)
			glass.commit(mesh, glass_material())
		"wires":
			var b := TrackSpec.WIRE_BLEND
			for rng in [[bin, 0.0, b * 4.0 / 3.0], [bout, 1.0 - b * 4.0 / 3.0, 1.0]]:
				if not rng[0]:
					continue
				var rks := _ring_range(def, rng[1], rng[2])
				var rloops: Array = []
				for k in rks:
					rloops.append(_channel_loop(def, k, style, blend(def, k, style, bin, bout)))
				_sweep(solid, def, rks, rloops, true, inner_n, chan_col)
			var metal := Arrays.new()
			var ks := _ring_range(def, b * 2.0 / 3.0 if bin else 0.0, 1.0 - b * 2.0 / 3.0 if bout else 1.0)
			var wire_col := def.color.lerp(Color("d9dee8"), 0.6)
			var flat := func(_k: int, _e: int, _a: Vector2, _b: Vector2, _pi: int) -> Color: return wire_col
			for c in wire_centres(def.spec):
				var loops: Array = []
				for k in ks:
					loops.append(_wire_loop(def.spec, c, false))
				_sweep(metal, def, ks, loops, true, 0, flat, c)
			_brackets(metal, def, ks, wire_col.darkened(0.25))
			metal.commit(mesh, metal_material())
		_:
			var runs := _trough_runs(def)
			for run in runs:
				var loops: Array = []
				for k in run:
					loops.append(_channel_loop(def, k, style, 0.0))
				_sweep(solid, def, run, loops, true, inner_n, chan_col)
			if def.is_jump() and runs.size() == 2:
				var k0: int = runs[0][-1]
				var k1: int = runs[1][0]
				var cap_col := def.color.darkened(0.2)
				_cap(solid, def, k0, _channel_loop(def, k0, style, 0.0), cap_col, def.ring_tangent[k0])
				_cap(solid, def, k1, _channel_loop(def, k1, style, 0.0), cap_col, -def.ring_tangent[k1])
	solid.commit(mesh, track_material())
	return mesh


## U-shaped brackets holding the three wires, every BRACKET_SPACING metres.
static func _brackets(a: Arrays, def: TrackModuleDef, ks: Array, col: Color) -> void:
	var c := wire_centres(def.spec)
	var path := [c[1] + Vector2(0, -0.03), c[0] + Vector2(0, -0.03), c[2] + Vector2(0, -0.03)]
	var next_d := -1.0
	for k in ks:
		var d := def.ring_dist[k]
		if d < next_d:
			continue
		next_d = d + BRACKET_SPACING
		var t: Vector3 = def.ring_tangent[k] * 0.025
		for i in 2:
			var p0 := _to3d(def, k, path[i])
			var p1 := _to3d(def, k, path[i + 1])
			var side := (p1 - p0).cross(t).normalized() * 0.012
			_quad(a, p0 - t + side, p1 - t + side, p1 + t + side, p0 + t + side, col)
			_quad(a, p0 - t - side, p1 - t - side, p1 + t - side, p0 + t - side, col)
			_quad(a, p0 - t + side, p1 - t + side, p1 - t - side, p0 - t - side, col)
			_quad(a, p0 + t + side, p1 + t + side, p1 + t - side, p0 + t - side, col)


static func _quad(a: Arrays, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, col: Color) -> void:
	var base := a.verts.size()
	var n := (p1 - p0).cross(p3 - p0).normalized()
	for p in [p0, p1, p2, p3]:
		a.verts.append(p)
		a.norms.append(n)
		a.cols.append(col)
	a.idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
