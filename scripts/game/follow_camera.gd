class_name FollowCamera
extends Camera3D
## Smooth third-person chase camera. Heading follows the track tangent (stable
## through curves) blended with the marble's velocity; all motion is
## exponentially smoothed to avoid shaking.

var target: Marble
var tracker: TrackTracker
var distance := 5.0
var height := 2.3
var look_ahead := 3.0
var heading_smooth := 3.0
var position_smooth := 6.0
var look_smooth := 10.0

var _fwd := Vector3.FORWARD
var _look := Vector3.ZERO


func _ready() -> void:
	fov = 70.0
	near = 0.05
	far = 400.0


func snap() -> void:
	if target == null:
		return
	var p := target.global_position
	_fwd = _desired_forward()
	global_position = p - _fwd * distance + Vector3.UP * height
	_look = p + _fwd * look_ahead
	look_at(_look, Vector3.UP)
	reset_physics_interpolation()


func _desired_forward() -> Vector3:
	var f := Vector3(tracker.tangent.x, 0.0, tracker.tangent.z) if tracker else Vector3.FORWARD
	if f.length_squared() < 1e-6:
		f = _fwd
	f = f.normalized()
	var v := target.linear_velocity
	var vh := Vector3(v.x, 0.0, v.z)
	if vh.length() > 1.0 and vh.normalized().dot(f) > 0.0:
		f = (f * 0.75 + vh.normalized() * 0.25).normalized()
	return f


func _process(delta: float) -> void:
	if target == null:
		return
	var p := target.get_global_transform_interpolated().origin
	var want := _desired_forward()
	_fwd = _fwd.slerp(want, 1.0 - exp(-heading_smooth * delta)).normalized()
	var desired := p - _fwd * distance + Vector3.UP * height
	global_position = global_position.lerp(desired, 1.0 - exp(-position_smooth * delta))
	_look = _look.lerp(p + _fwd * look_ahead, 1.0 - exp(-look_smooth * delta))
	if global_position.distance_squared_to(_look) > 1e-4:
		look_at(_look, Vector3.UP)
