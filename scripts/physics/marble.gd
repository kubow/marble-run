class_name Marble
extends RigidBody3D
## Player marble. Gravity, friction and momentum come from the physics engine;
## the player only adds a bounded lateral steering force each physics tick.
## Position is only written on (re)spawn, inside _integrate_forces.

@export var radius := 0.28
@export var marble_mass := 1.0
@export var max_steer_force := 6.0     ## N at full steering input.
@export var friction := 0.8
@export var bounce := 0.15
@export var damping := 0.12            ## Linear damping (1/s).
@export var spin_damping := 0.05       ## Angular damping (1/s).
@export var max_speed := 22.0          ## Hard safety cap (m/s).
@export var boost_force := 3.5         ## N at full throttle along the track.
@export var brake_force := 6.0         ## N at full brake, against the motion.
@export var boost_max_speed := 15.0    ## Boosting stops adding force above this (m/s).

var steer := 0.0                       ## -1 (left) .. 1 (right), set by the game.
var steer_axis := Vector3.RIGHT        ## World direction of "right".
var steer_enabled := true
var throttle := 0.0                    ## -1 (brake) .. 1 (accelerate), set by the game.
var forward_axis := Vector3.FORWARD    ## World direction of the track ahead.

var _reset_pending := false
var _reset_xf := Transform3D.IDENTITY
var _reset_vel := Vector3.ZERO
var _reset_interp := false


func _init() -> void:
	mass = marble_mass
	continuous_cd = true
	can_sleep = false
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	custom_integrator = false


func _ready() -> void:
	mass = marble_mass
	linear_damp = damping
	angular_damp = spin_damping
	var pm := PhysicsMaterial.new()
	pm.friction = friction
	pm.bounce = bounce
	physics_material_override = pm
	if get_node_or_null("Shape") == null:
		var cs := CollisionShape3D.new()
		cs.name = "Shape"
		var sph := SphereShape3D.new()
		sph.radius = radius
		cs.shape = sph
		add_child(cs)
	if get_node_or_null("Mesh") == null:
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = MarbleMesh.build(radius)
		add_child(mi)


## Teleports the marble safely on the next physics step.
func respawn(xf: Transform3D, velocity: Vector3) -> void:
	_reset_xf = xf
	_reset_vel = velocity
	_reset_pending = true
	sleeping = false


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _reset_pending:
		_reset_pending = false
		state.transform = _reset_xf
		state.linear_velocity = _reset_vel
		# Spin consistent with rolling: w = (up x v) / r
		state.angular_velocity = Vector3.UP.cross(_reset_vel) / radius
		_reset_interp = true
		return
	if steer_enabled and steer != 0.0:
		var axis := Vector3(steer_axis.x, 0.0, steer_axis.z).normalized()
		state.apply_central_force(axis * clampf(steer, -1.0, 1.0) * max_steer_force * mass)
	var v := state.linear_velocity
	var sp := v.length()
	if steer_enabled and throttle > 0.0 and sp < boost_max_speed:
		state.apply_central_force(forward_axis.normalized() * minf(throttle, 1.0) * boost_force * mass)
	elif steer_enabled and throttle < 0.0 and sp > 0.05:
		# Brake against the motion; fades out near standstill so it never reverses.
		state.apply_central_force(-v / sp * minf(-throttle, 1.0) * brake_force * mass * minf(sp, 1.0))
	if sp > max_speed:
		state.linear_velocity = v.normalized() * max_speed


func _physics_process(_delta: float) -> void:
	if _reset_interp:
		_reset_interp = false
		reset_physics_interpolation()


func speed() -> float:
	return linear_velocity.length()
