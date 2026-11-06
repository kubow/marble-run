class_name TrackDecor
extends RefCounted
## Shared meshes/materials for obstacles, arches and pillars (built once).

static var _mats: Dictionary = {}
static var _meshes: Dictionary = {}

const OBSTACLE_COLORS := {
	"peg": Color("ff5a5f"),
	"bumper": Color("9b5de5"),
	"block": Color("ff9f1c"),
	"sweeper": Color("f15bb5"),
}


static func clear_cache() -> void:
	_mats.clear()
	_meshes.clear()
	_bouncy = null
	_solid = null


static func mat(c: Color, alpha := 1.0) -> StandardMaterial3D:
	var key := "%s/%.2f" % [c.to_html(), alpha]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.roughness = 0.3
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mats[key] = m
	return m


static func cylinder(r: float, h: float) -> CylinderMesh:
	var key := "cyl/%.3f/%.3f" % [r, h]
	if not _meshes.has(key):
		var m := CylinderMesh.new()
		m.top_radius = r
		m.bottom_radius = r
		m.height = h
		m.radial_segments = 14
		m.rings = 1
		_meshes[key] = m
	return _meshes[key]


static func box(size: Vector3) -> BoxMesh:
	var key := "box/%s" % str(size)
	if not _meshes.has(key):
		var m := BoxMesh.new()
		m.size = size
		_meshes[key] = m
	return _meshes[key]


static func mesh_instance(mesh: Mesh, material: Material, xf := Transform3D.IDENTITY) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.transform = xf
	return mi


static var _bouncy: PhysicsMaterial
static var _solid: PhysicsMaterial


static func bouncy() -> PhysicsMaterial:
	if _bouncy == null:
		_bouncy = PhysicsMaterial.new()
		_bouncy.bounce = 0.9
		_bouncy.friction = 0.2
	return _bouncy


static func solid() -> PhysicsMaterial:
	if _solid == null:
		_solid = PhysicsMaterial.new()
		_solid.bounce = 0.2
		_solid.friction = 0.4
	return _solid


## Builds an obstacle node in module-local space. Returns the node.
static func make_obstacle(def: TrackModuleDef, o: Dictionary, placement_xf: Transform3D, clock: Callable) -> Node3D:
	var kind := str(o.get("kind", "peg"))
	var t := float(o.get("t", 0.5))
	var u := float(o.get("u", 0.0))
	var local := def.floor_transform(t, u)
	var world := placement_xf * local
	var col: Color = OBSTACLE_COLORS.get(kind, Color.RED)
	var shape: Shape3D
	var mesh: Mesh
	var h := 0.0
	match kind:
		"peg", "bumper":
			var r := float(o.get("r", 0.2))
			h = float(o.get("h", 0.7))
			var cs := CylinderShape3D.new()
			cs.radius = r
			cs.height = h
			shape = cs
			mesh = cylinder(r, h)
		_:
			var sz: Array = o.get("size", [1.0, 0.5, 0.4])
			var size := Vector3(float(sz[0]), float(sz[1]), float(sz[2]))
			h = size.y
			var bs := BoxShape3D.new()
			bs.size = size
			shape = bs
			mesh = box(size)
	var body: PhysicsBody3D
	if kind == "sweeper":
		var mo := MovingObstacle.new()
		var w := def.profile_at(t * def.length).x
		mo.base = Transform3D(world.basis, world.origin + world.basis.y * (h * 0.5))
		mo.axis = world.basis.x.normalized()
		mo.amplitude = float(o.get("amp", 0.25)) * w
		mo.period = float(o.get("period", 2.0))
		mo.phase = float(o.get("phase", 0.0))
		mo.clock = clock
		body = mo
		body.transform = mo.base
	else:
		var sb := StaticBody3D.new()
		sb.physics_material_override = bouncy() if kind == "bumper" else solid()
		sb.transform = Transform3D(world.basis, world.origin + world.basis.y * (h * 0.5))
		body = sb
	var cs3 := CollisionShape3D.new()
	cs3.shape = shape
	body.add_child(cs3)
	body.add_child(mesh_instance(mesh, mat(col)))
	body.name = "Obstacle_%s" % kind
	return body


## Arch over the track at a connector (yaw-only frame).
static func make_arch(xf: Transform3D, half_w: float, c: Color, checkered := false) -> Node3D:
	var n := Node3D.new()
	n.transform = xf
	var post := cylinder(0.08, 2.4)
	for side in [-1.0, 1.0]:
		n.add_child(mesh_instance(post, mat(Color.WHITE), Transform3D(Basis(), Vector3(side * (half_w + 0.3), 1.0, 0))))
	if checkered:
		var count := 8
		var w := (half_w + 0.3) * 2.0 / count
		for i in count:
			var cc := Color.BLACK if i % 2 == 0 else Color.WHITE
			n.add_child(mesh_instance(box(Vector3(w, 0.35, 0.1)), mat(cc),
				Transform3D(Basis(), Vector3(-(half_w + 0.3) + w * (i + 0.5), 2.2, 0))))
	else:
		var bar := mesh_instance(box(Vector3((half_w + 0.3) * 2.0, 0.18, 0.12)), mat(c), Transform3D(Basis(), Vector3(0, 2.2, 0)))
		bar.name = "Bar"
		n.add_child(bar)
	return n
