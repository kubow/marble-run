class_name MarbleMesh
extends RefCounted
## Beach-ball style sphere with coloured segments so rolling is visible.

const COLORS := [Color("ff4d6d"), Color("ffffff"), Color("3a86ff"), Color("ffffff"), Color("ffbe0b"), Color("ffffff")]


static func build(radius: float, rings := 12, segments := 24) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for i in rings + 1:
		var v := float(i) / rings
		var phi := v * PI
		for j in segments + 1:
			var u := float(j) / segments
			var th := u * TAU
			var n := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			verts.append(n * radius)
			norms.append(n)
			var seg := int(floor(u * COLORS.size())) % COLORS.size()
			var c: Color = COLORS[seg]
			if absf(n.y) > 0.92:
				c = Color.WHITE
			cols.append(c)
	for i in rings:
		for j in segments:
			var a := i * (segments + 1) + j
			var b := a + 1
			var c := a + segments + 1
			var d := c + 1
			idx.append_array([a, d, b, a, c, d])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.15
	m.metallic_specular = 0.8
	mesh.surface_set_material(0, m)
	return mesh
