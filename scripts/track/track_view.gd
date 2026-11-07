class_name TrackView
extends Node3D
## Renders placed modules and owns the track collision.
##
## Collision: all active modules are merged into ONE ConcavePolygonShape3D.
## Adjacent modules share bit-identical vertices at joins (see
## TrackMeshBuilder.world_rings) so the marble crosses joins as if the track
## were a single mesh; Jolt's active-edge detection then suppresses internal
## edge "ghost" contacts. Obstacles are separate simple convex bodies.

signal collision_rebuilt

var clock: Callable                  ## Game time provider for moving obstacles.
var show_pillars := true

var _entries: Dictionary = {}        ## index -> {node, rings, faces, placement, arch}
var _order: Array[int] = []          ## Active indices in track order.
var _body: StaticBody3D
var _shape_node: CollisionShape3D
var _pool: Array[MeshInstance3D] = []
var _track_material: PhysicsMaterial
var face_count := 0


func _ready() -> void:
	_body = StaticBody3D.new()
	_body.name = "TrackBody"
	_track_material = PhysicsMaterial.new()
	_track_material.friction = 0.7
	_track_material.bounce = 0.05
	_body.physics_material_override = _track_material
	_shape_node = CollisionShape3D.new()
	_body.add_child(_shape_node)
	add_child(_body)


func clear() -> void:
	for idx in _order.duplicate():
		remove_placement(idx)
	_order.clear()
	_entries.clear()
	rebuild_collision()


func has_placement(index: int) -> bool:
	return _entries.has(index)


func active_indices() -> Array[int]:
	return _order


func _take_mesh_instance() -> MeshInstance3D:
	if not _pool.is_empty():
		return _pool.pop_back()
	var mi := MeshInstance3D.new()
	return mi


func add_placement(p: TrackPlacement) -> void:
	var prev_strips: Array = []
	if _entries.has(p.index - 1):
		prev_strips = _entries[p.index - 1].strips
	var strips := TrackMeshBuilder.world_strips(p, prev_strips)
	var root := Node3D.new()
	root.name = "Module_%d_%s" % [p.index, p.def.id]
	var mi := _take_mesh_instance()
	mi.mesh = TrackMeshBuilder.get_mesh(p.def, p.style, p.blend_in, p.blend_out)
	mi.transform = p.transform
	root.add_child(mi)
	for o in p.obstacle_layout():
		root.add_child(TrackDecor.make_obstacle(p.def, o, p.transform, clock))
	var arch: Node3D = null
	if p.checkpoint and p.index > 0:
		arch = TrackDecor.make_arch(p.transform, p.def.spec.half_width, Color("4cc9f0"))
		root.add_child(arch)
	if p.def.id == "finish":
		var fxf := p.transform * p.def.floor_transform(0.5, 0.0)
		var flat := Transform3D(p.transform.basis, fxf.origin)
		root.add_child(TrackDecor.make_arch(flat, p.def.spec.half_width, Color.WHITE, true))
		root.add_child(_end_wall(p.exit_transform, p.def.spec, false))
	if p.def.id == "start":
		root.add_child(_end_wall(p.transform, p.def.spec, true))
	for lim in p.limits:
		root.add_child(_speed_sign(p, lim))
	if show_pillars and p.index % 2 == 0:
		var top := p.transform.origin + Vector3(0, -p.def.spec.base_depth, 0)
		root.add_child(TrackDecor.mesh_instance(TrackDecor.cylinder(0.12, 40.0), TrackDecor.mat(Color("e8e8ff")),
			Transform3D(Basis(), top + Vector3(0, -20.0, 0))))
	add_child(root)
	_entries[p.index] = {
		"node": root, "mesh": mi, "strips": strips,
		"faces": TrackMeshBuilder.faces_from_strips(strips), "placement": p, "arch": arch,
	}
	_order.append(p.index)


## Trackside sign ~8 m before a speed requirement: red = brake, green = boost.
func _speed_sign(p: TrackPlacement, lim: Vector3) -> Node3D:
	var s := maxf(lim.x - 8.0, 0.5)
	var xf := p.def.floor_transform(s / p.def.length, 0.0)
	var w := p.def.profile_at(s).x
	var right := xf.basis.x.normalized()
	var pos := p.transform * (xf.origin + right * (maxf(w, p.def.spec.tube_radius) + 0.7))
	var n := Node3D.new()
	var face := p.transform.basis * Vector3(-xf.basis.z.x, 0.0, -xf.basis.z.z)
	n.transform = Transform3D(Basis.looking_at(-face.normalized(), Vector3.UP), pos)
	var col := Color("ff4d6d") if lim.z < INF else Color("2ec27e")
	n.add_child(TrackDecor.mesh_instance(TrackDecor.cylinder(0.05, 1.6), TrackDecor.mat(Color.WHITE), Transform3D(Basis(), Vector3(0, 0.4, 0))))
	n.add_child(TrackDecor.mesh_instance(TrackDecor.box(Vector3(0.7, 0.7, 0.06)), TrackDecor.mat(Color.WHITE), Transform3D(Basis(), Vector3(0, 1.4, 0))))
	n.add_child(TrackDecor.mesh_instance(TrackDecor.box(Vector3(0.56, 0.56, 0.08)), TrackDecor.mat(col), Transform3D(Basis(), Vector3(0, 1.4, 0))))
	n.name = "SpeedSign"
	return n


## Wall across the track at a connector. back=true places it behind (start).
func _end_wall(xf: Transform3D, spec: TrackSpec, back: bool) -> Node3D:
	var sb := StaticBody3D.new()
	var size := Vector3(spec.half_width * 2.0 + spec.lip * 2.0 + 0.4, 1.4, 0.3)
	var off := Vector3(0, size.y * 0.5 - 0.2, 0.15 if back else -0.15)
	sb.transform = xf * Transform3D(Basis(), off)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	sb.add_child(TrackDecor.mesh_instance(TrackDecor.box(size), TrackDecor.mat(Color("ffd166") if not back else Color("c9d6ff"))))
	return sb


func remove_placement(index: int) -> void:
	if not _entries.has(index):
		return
	var e: Dictionary = _entries[index]
	var mi: MeshInstance3D = e.mesh
	var root: Node3D = e.node
	root.remove_child(mi)
	_pool.append(mi)
	root.queue_free()
	_entries.erase(index)
	_order.erase(index)


func rebuild_collision() -> void:
	var faces := PackedVector3Array()
	for idx in _order:
		faces.append_array(_entries[idx].faces)
	face_count = faces.size() / 3
	if faces.is_empty():
		_shape_node.shape = null
	else:
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		shape.backface_collision = false
		_shape_node.shape = shape
	collision_rebuilt.emit()


func mark_checkpoint(index: int) -> void:
	if not _entries.has(index):
		return
	var arch: Node3D = _entries[index].arch
	if arch and arch.has_node("Bar"):
		(arch.get_node("Bar") as MeshInstance3D).material_override = TrackDecor.mat(Color("80ed99"))


func faces_of(index: int) -> PackedVector3Array:
	return _entries[index].faces if _entries.has(index) else PackedVector3Array()


func strips_of(index: int) -> Array:
	return _entries[index].strips if _entries.has(index) else []


func all_faces() -> PackedVector3Array:
	var faces := PackedVector3Array()
	for idx in _order:
		faces.append_array(_entries[idx].faces)
	return faces
