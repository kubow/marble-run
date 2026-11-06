class_name SteerInput
extends Node
## Steering input: keyboard (arrows / A,D) or touch-and-drag anywhere not
## covered by a button. Drag distance from the touch start maps to -1..1.

var sensitivity := 1.0
var invert := false
var drag_fraction := 0.12   ## Fraction of screen width for full deflection.

var _touch := -1
var _start_x := 0.0
var _x := 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch == -1:
			_touch = event.index
			_start_x = event.position.x
			_x = _start_x
		elif not event.pressed and event.index == _touch:
			_touch = -1
	elif event is InputEventScreenDrag and event.index == _touch:
		_x = event.position.x
		# Re-anchor so reversing direction responds immediately.
		var full := _full_width()
		if absf(_x - _start_x) > full:
			_start_x = _x - signf(_x - _start_x) * full


func _full_width() -> float:
	var w := get_viewport().get_visible_rect().size.x
	return maxf(w * drag_fraction / maxf(sensitivity, 0.1), 8.0)


func release() -> void:
	_touch = -1


func value() -> float:
	var k := Input.get_axis("steer_left", "steer_right")
	var t := 0.0
	if _touch != -1:
		t = clampf((_x - _start_x) / _full_width(), -1.0, 1.0)
	var v := k if absf(k) > absf(t) else t
	return -v if invert else v
