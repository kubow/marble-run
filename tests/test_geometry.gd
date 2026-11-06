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


func test_adjacent_rings_share_vertices() -> void:
	# Raw (unsnapped) rings of consecutive placements must coincide closely; the
	# view then snaps them to bit-identical vertices (no seam to catch on).
	var gen := TrackGenerator.new()
	var worst := 0.0
	for i in 100:
		var level := gen.generate(GeneratorConfig.make(Hash64.splitmix64(i + 99), 1.0 + (i % 8), 24))
		var prev_rings: Array = []
		for p in level.placements:
			var raw := TrackMeshBuilder.world_rings(p, PackedVector3Array())
			if not prev_rings.is_empty():
				var a: PackedVector3Array = prev_rings[-1]
				var b: PackedVector3Array = raw[0]
				for j in a.size():
					worst = maxf(worst, a[j].distance_to(b[j]))
				var snapped := TrackMeshBuilder.world_rings(p, a)
				check(snapped[0] == a, "snapped ring identical")
			prev_rings = raw
	note("worst raw join mismatch %.2e m" % worst)
	check(worst < 1e-3, "joins coincide within 1 mm")


func test_mesh_budget() -> void:
	var total := 0
	for d in catalog.modules:
		var m := TrackMeshBuilder.build_mesh(d)
		var arr := m.surface_get_arrays(0)
		var tris: int = arr[Mesh.ARRAY_INDEX].size() / 3
		total += tris
		check(tris > 0 and tris < 2500, "%s triangle count %d within budget" % [d.id, tris])
		for v in arr[Mesh.ARRAY_VERTEX]:
			if not v.is_finite():
				check(false, "%s has non-finite vertex" % d.id)
				break
	note("avg %.0f render tris/module" % (float(total) / catalog.modules.size()))
