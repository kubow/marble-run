extends TestCase
## Module geometry: connectors, profile continuity, seams, mesh budget.

var catalog := ModuleCatalog.get_default()


func test_module_ends_match_standard() -> void:
	var spec := catalog.spec
	var entry_t := Vector3(0, spec.grade, -1).normalized()
	for d in catalog.modules:
		var last := d.ring_count() - 1
		check(d.ring_pos[0].is_zero_approx(), "%s starts at origin" % d.id)
		check(d.ring_tangent[0].is_equal_approx(entry_t), "%s entry tangent" % d.id)
		check(absf(d.ring_up[0].x) < 1e-5, "%s no bank at entry" % d.id)
		var exit_t := d.exit_transform.basis * entry_t
		check(d.ring_tangent[last].angle_to(exit_t) < 1e-4, "%s exit tangent matches exit connector" % d.id)
		check(d.ring_pos[last].is_equal_approx(d.exit_transform.origin), "%s exit position" % d.id)
		for k in [0, last]:
			check(is_equal_approx(d.ring_half_w[k], spec.half_width), "%s width at end" % d.id)
			check(is_equal_approx(d.ring_wall_h[k], spec.wall_height), "%s wall at end" % d.id)
			check(absf(d.ring_dish[k]) < 1e-6, "%s dish at end" % d.id)
			check(absf(d.ring_kappa[k]) < 1e-6, "%s curvature at end" % d.id)
		check(d.length > 0.0 and d.length_3d >= d.length, "%s length" % d.id)


func test_catalogue_fields() -> void:
	var ids := {}
	var types := {}
	for d in catalog.modules:
		check(d.id != "" and not ids.has(d.id), "unique id %s" % d.id)
		ids[d.id] = true
		types[d.type] = true
		check(d.difficulty >= 0.0 and d.weight >= 0.0, "%s weights" % d.id)
	for t in ["straight", "gentle_curve", "sharp_curve", "downhill_ramp", "uphill_ramp", "wavy", "s_curve", "funnel", "narrow_bridge", "obstacle"]:
		check(types.has(t), "catalogue has a %s module" % t)
	check(ids.has("gentle_left") and ids.has("gentle_right") and ids.has("sharp_left") and ids.has("sharp_right"), "left/right curves")
	note("%d modules, %d types" % [catalog.modules.size(), types.size()])


func test_collision_winding_faces_up() -> void:
	# Godot's Plane(a, b, c) normal is (a - c) x (a - b); floor faces must point up.
	for d in catalog.modules:
		var rings: Array = []
		for k in d.ring_count():
			rings.append(TrackMeshBuilder.collision_ring(d, k))
		var faces := TrackMeshBuilder.faces_from_rings(rings)
		var mid := (TrackSpec.PROFILE_X.size() + 1) / 2  # floor quad near the centre
		var a := faces[mid * 6]
		var b := faces[mid * 6 + 1]
		var c := faces[mid * 6 + 2]
		var n := (a - c).cross(a - b)
		check(n.y > 0.0, "%s floor faces point up" % d.id)


func test_adjacent_strips_share_vertices() -> void:
	# Raw (unsnapped) strips of consecutive placements must coincide closely at
	# every connector, for every strip key (surface, wires); the view then
	# snaps them to bit-identical vertices (no seam to catch on).
	var gen := TrackGenerator.new()
	var worst := 0.0
	var joins := {}
	for i in 100:
		var level := gen.generate(GeneratorConfig.make(Hash64.splitmix64(i + 99), 1.0 + (i % 8), 24))
		var prev: Array = []
		for p in level.placements:
			var raw := TrackMeshBuilder.world_strips(p, [])
			var snapped := TrackMeshBuilder.world_strips(p, prev)
			for si in raw.size():
				var st: Dictionary = raw[si]
				if not st.entry or prev.is_empty():
					continue
				var match_found := false
				for ps in prev:
					if ps.exit and ps.key == st.key:
						match_found = true
						var a: PackedVector3Array = ps.rings[-1]
						var b: PackedVector3Array = st.rings[0]
						for j in a.size():
							worst = maxf(worst, a[j].distance_to(b[j]))
						check(snapped[si].rings[0] == a, "snapped ring identical")
						joins[st.key] = joins.get(st.key, 0) + 1
				check(match_found, "strip %s of %s/%s has a partner at the join" % [st.key, p.def.id, p.style])
			prev = snapped
	note("worst raw join mismatch %.6f m; joins checked per strip: %s" % [worst, str(joins)])
	check(worst < 1e-3, "joins coincide within 1 mm")
	check(joins.has("w0") and joins.has("surface"), "both surface and wire joins exercised")


func test_style_ends_are_standard() -> void:
	# A styled module that blends in/out starts/ends with the standard ring.
	for d in catalog.modules:
		for style in ["tube", "wires"]:
			var strips := TrackMeshBuilder.collision_strips(d, style, true, true)
			var last := d.ring_count() - 1
			for st in strips:
				if st.entry and st.key == "surface":
					check(st.rings[0] == TrackMeshBuilder.collision_ring(d, 0), "%s/%s entry ring standard" % [d.id, style])
				if st.exit and st.key == "surface":
					check(st.rings[-1] == TrackMeshBuilder.collision_ring(d, last), "%s/%s exit ring standard" % [d.id, style])


func test_tube_faces_inward_wires_outward() -> void:
	var d := catalog.get_def("straight")
	var tube: Array = TrackMeshBuilder.collision_strips(d, "tube", false, false)
	var faces := TrackMeshBuilder.faces_from_rings(tube[0].rings)
	var per_ring: int = ((tube[0].rings[0] as PackedVector3Array).size() - 1) * 6
	var bottom := per_ring / 2 - 3      # quad just left of the bottom centre
	var top := 0                         # quad next to the top-left gap
	var nb := (faces[bottom] - faces[bottom + 2]).cross(faces[bottom] - faces[bottom + 1])
	var nt := (faces[top] - faces[top + 2]).cross(faces[top] - faces[top + 1])
	check(nb.y > 0.0, "tube bottom faces up (inwards)")
	check(nt.y < 0.0, "tube ceiling faces down (inwards)")
	var wires: Array = TrackMeshBuilder.collision_strips(d, "wires", false, false)
	check_eq(wires.size(), 3, "three wire strips")
	for st in wires:
		var wf := TrackMeshBuilder.faces_from_rings(st.rings)
		# Wire loop starts at 120 deg, first edge goes over the top -> faces up.
		var n := (wf[0] - wf[2]).cross(wf[0] - wf[1])
		check(n.y > 0.0, "wire %s top facet faces up (outwards)" % st.key)


func test_jump_has_gap() -> void:
	for id in ["jump", "jump_big"]:
		var d := catalog.get_def(id)
		check(d.is_jump(), "%s is a jump" % id)
		var strips := TrackMeshBuilder.collision_strips(d, "trough")
		check_eq(strips.size(), 2, "%s collision split at the gap" % id)
		var gap := 0
		for k in d.ring_count() - 1:
			if d.gap_segment(k):
				gap += 1
		check(gap > 0, "%s has gap segments" % id)
		check(d.height_at(d.land_s()) < d.height_at(d.takeoff_s()), "%s lands lower than it takes off" % id)


func test_mesh_budget() -> void:
	var total := 0
	var count := 0
	for d in catalog.modules:
		for style in ["trough", "tube", "wires"]:
			var m := TrackMeshBuilder.build_mesh(d, style, true, true)
			var tris := 0
			for si in m.get_surface_count():
				var arr := m.surface_get_arrays(si)
				tris += arr[Mesh.ARRAY_INDEX].size() / 3
				for v in arr[Mesh.ARRAY_VERTEX]:
					if not v.is_finite():
						check(false, "%s/%s has non-finite vertex" % [d.id, style])
						break
			total += tris
			count += 1
			check(tris > 0 and tris < 4000, "%s/%s triangle count %d within budget" % [d.id, style, tris])
	note("avg %.0f render tris/module variant" % (float(total) / count))
