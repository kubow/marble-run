class_name MovingObstacle
extends AnimatableBody3D
## Sweeper moving side to side across the track. Its position is a pure
## function of the shared game clock, so motion is deterministic and does not
## drift with frame rate.

var base := Transform3D.IDENTITY
var axis := Vector3.RIGHT
var amplitude := 0.5
var period := 2.0
var phase := 0.0
var clock: Callable   ## Returns elapsed game time in seconds.


func _ready() -> void:
	sync_to_physics = false
	_apply(0.0)


func _physics_process(_delta: float) -> void:
	_apply(clock.call() if clock.is_valid() else 0.0)


func _apply(t: float) -> void:
	var off := axis * amplitude * sin(TAU * (t / period + phase))
	global_transform = Transform3D(base.basis, base.origin + off)
