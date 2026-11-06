class_name DebugOverlay
extends Node3D
## Debug visualisation (F3): connectors, collision wireframe, marble velocity.
## Text (module, seed, generation stats) is shown by the HUD.

var session: TrackSession
var marble: Marble

var _static_mi: MeshInstance3D
var _vel_mi: MeshInstance3D
var _vel_mesh := ImmediateMesh.new()
var _mat: StandardMaterial3D
var _dirty := true


func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.no_depth_test = true
	_static_mi = MeshInstance3D.new()
	_static_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_static_mi)
	_vel_mi = MeshInstance3D.new()
	_vel_mi.mesh = _vel_mesh
	_vel_mi.material_override = _mat
	_vel_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_vel_mi)
	if session:
		session.view.collision_rebuilt.connect(func(): _dirty = true)


func _process(_delta: float) -> void:
	if not visible or session == null:
		return
	if _dirty:
		_dirty = false
		_rebuild_static()
	_vel_mesh.clear_surfaces()
	if marble:
		var p := marble.get_global_transform_interpolated().origin
		_vel_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		_vel_mesh.surface_set_color(Color.YELLOW)
		_vel_mesh.surface_add_vertex(p)
		_vel_mesh.surface_add_vertex(p + marble.linear_velocity * 0.4)
		_vel_mesh.surface_set_color(Color.MAGENTA)
		_vel_mesh.surface_add_vertex(p)
		_vel_mesh.surface_add_vertex(p + marble.steer_axis * marble.steer * 1.5)
		_vel_mesh.surface_end()


func _rebuild_static() -> void:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	# Collision wireframe (each triangle's two "ring" edges is enough to read it).
	var faces := session.view.all_faces()
	var wire := Color(0.1, 1.0, 0.4, 0.55)
	for i in range(0, faces.size(), 3):
		verts.append_array([faces[i], faces[i + 1], faces[i], faces[i + 2]])
		cols.append_array([wire, wire, wire, wire])
	# Connectors: right (red), up (green), forward (blue).
	for idx in session.view.active_indices():
		var p: TrackPlacement = session.placement(idx)
		if p == null:
			continue
		var o := p.transform.origin + Vector3.UP * 0.05
		var b := p.transform.basis
		for pair in [[b.x, Color.RED], [b.y, Color.GREEN], [-b.z, Color.BLUE]]:
			verts.append_array([o, o + pair[0] * 1.2])
			cols.append_array([pair[1], pair[1]])
		if p.checkpoint:
			verts.append_array([o, o + Vector3.UP * 3.0])
			cols.append_array([Color.CYAN, Color.CYAN])
	if verts.is_empty():
		_static_mi.mesh = null
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	m.surface_set_material(0, _mat)
	_static_mi.mesh = m


func text(fps: int) -> String:
	if session == null:
		return ""
	var t := session.tracker
	var p := t.current_placement()
	var lines := PackedStringArray()
	lines.append("track %s  gen v%d" % [session.code, TrackGenerator.VERSION])
	if session.level:
		var st: Dictionary = session.level.stats
		lines.append("gen %.1f ms, %d attempts, %d backtracks, %d fallbacks" % [st.usec / 1000.0, st.attempts, st.backtracks, st.fallbacks])
	else:
		lines.append("endless: last chunk %.2f ms, active %d..%d, forced %d" % [session.gen_usec / 1000.0, session.first_index, session.last_index, session.stream.st.forced])
	if p:
		lines.append("module #%d %s (%s) t=%.2f var=%d diff=%.1f" % [p.index, p.def.id, p.def.type, t.local_t, p.variant, p.def.difficulty])
		lines.append("est. entry speed %.1f..%.1f m/s" % [p.v_lo_in, p.v_hi_in])
	if marble:
		lines.append("speed %.2f m/s  steer %.2f  offset %.2f" % [marble.speed(), marble.steer, Vector2(t.offset.x, t.offset.z).length()])
	lines.append("collision tris %d  fps %d" % [session.view.face_count, fps])
	return "\n".join(lines)
