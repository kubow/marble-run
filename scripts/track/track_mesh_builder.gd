class_name TrackMeshBuilder
extends RefCounted
## Builds render meshes and collision triangles for modules by sweeping the
## standard cross-section along the module's sampled frames.
##
## Winding: Godot treats clockwise triangles as front faces. For a ring i and
## the next ring i+1 (further forward) with profile points j -> j+1 running
## left -> right, the triangles (A, C, D) and (A, D, B) face up/outwards, where
## A = (i, j), B = (i, j+1), C = (i+1, j), D = (i+1, j+1).

static var _mesh_cache: Dictionary = {}
static var _material: StandardMaterial3D


static func clear_cache() -> void:
	_mesh_cache.clear()
	_material = null


static func track_material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.roughness = 0.45
		_material.metallic_specular = 0.35
	return _material


## Closed cross-section loop for ring k (2D: lateral, height), with per-point
## colours keys. Inner surface first (left top -> right top), then the shell.
static func _loop(def: TrackModuleDef, k: int) -> PackedVector2Array:
	var w := def.ring_half_w[k]
	var hw := def.ring_wall_h[k]
	var lip := def.spec.lip
	var base := def.spec.base_depth
	var pts := TrackSpec.inner_profile(w, hw, def.ring_dish[k])
	pts.append(Vector2(w + lip, hw))
	pts.append(Vector2(w + lip, -base))
	pts.append(Vector2(-w - lip, -base))
	pts.append(Vector2(-w - lip, hw))
	return pts


static func get_mesh(def: TrackModuleDef) -> ArrayMesh:
	if _mesh_cache.has(def.id):
		return _mesh_cache[def.id]
	var m := build_mesh(def)
	_mesh_cache[def.id] = m
	return m


static func build_mesh(def: TrackModuleDef) -> ArrayMesh:
	var inner_n := TrackSpec.PROFILE_X.size()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var rings := def.ring_count()
	var floor_col := def.color
	var wall_col := def.color.lerp(Color.WHITE, 0.3)
	var lip_col := Color(1, 1, 1)
	var shell_col := def.color.darkened(0.35)
	var edges := 0
	for k in rings:
		var loop := _loop(def, k)
		var n := loop.size()
		edges = n
		# Smooth normals for the inner surface points.
		var inner_norm := PackedVector2Array()
		inner_norm.resize(inner_n)
		for j in inner_n:
			var acc := Vector2.ZERO
			if j > 0:
				var d0 := loop[j] - loop[j - 1]
				acc += Vector2(-d0.y, d0.x).normalized()
			if j < inner_n - 1:
				var d1 := loop[j + 1] - loop[j]
				acc += Vector2(-d1.y, d1.x).normalized()
			inner_norm[j] = acc.normalized()
		var c: Vector3 = def.ring_pos[k]
		var r: Vector3 = def.ring_right[k]
		var u: Vector3 = def.ring_up[k]
		var band := 1.0 if (k / 2) % 2 == 0 else 0.92
		for e in n:
			var a2 := loop[e]
			var b2 := loop[(e + 1) % n]
			var na: Vector2
			var nb: Vector2
			var col: Color
			if e < inner_n - 1:
				na = inner_norm[e]
				nb = inner_norm[e + 1]
				var ax := absf(a2.x) / def.ring_half_w[k]
				col = wall_col if ax > TrackSpec.WALL_START + 0.05 and absf(b2.x) / def.ring_half_w[k] > TrackSpec.WALL_START + 0.05 else floor_col
			else:
				var d := b2 - a2
				na = Vector2(-d.y, d.x).normalized()
				nb = na
				col = lip_col if absf(d.y) < 1e-4 and a2.y > 0.0 else shell_col
			col = Color(col.r * band, col.g * band, col.b * band)
			verts.append(c + r * a2.x + u * a2.y)
			verts.append(c + r * b2.x + u * b2.y)
			norms.append((r * na.x + u * na.y).normalized())
			norms.append((r * nb.x + u * nb.y).normalized())
			cols.append(col)
			cols.append(col)
	for k in rings - 1:
		for e in edges:
			var a := (k * edges + e) * 2
			var b := a + 1
			var cc := ((k + 1) * edges + e) * 2
			var dd := cc + 1
			idx.append_array([a, cc, dd, a, dd, b])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, track_material())
	return mesh


## Collision ring k in local space: inner surface plus the flat lip tops.
static func collision_ring(def: TrackModuleDef, k: int) -> PackedVector3Array:
	var w := def.ring_half_w[k]
	var hw := def.ring_wall_h[k]
	var lip := def.spec.lip
	var c: Vector3 = def.ring_pos[k]
	var r: Vector3 = def.ring_right[k]
	var u: Vector3 = def.ring_up[k]
	var out := PackedVector3Array()
	out.append(c + r * (-w - lip) + u * hw)
	for p in TrackSpec.inner_profile(w, hw, def.ring_dish[k]):
		out.append(c + r * p.x + u * p.y)
	out.append(c + r * (w + lip) + u * hw)
	return out


## World-space collision rings for a placement. If prev_last_ring is given it
## replaces ring 0 so that adjacent modules share bit-identical vertices.
static func world_rings(p: TrackPlacement, prev_last_ring: PackedVector3Array) -> Array:
	var out: Array = []
	for k in p.def.ring_count():
		out.append(p.transform * collision_ring(p.def, k))
	if prev_last_ring.size() == out[0].size():
		out[0] = prev_last_ring
	return out


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
