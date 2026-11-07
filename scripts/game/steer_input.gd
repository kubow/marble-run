class_name SteerInput
extends Node
## Steering and throttle input: keyboard (arrows / WASD) or touch-and-drag
## anywhere not covered by a button. Horizontal drag distance from the touch
## start steers; vertical drag accelerates (up) or brakes (down).

var sensitivity := 1.0
var invert := false
var drag_fraction := 0.12   ## Fraction of screen width for full deflection.

var _touch := -1
var _start_x := 0.0
var _x := 0.0
var _start_y := 0.0
var _y := 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch == -1:
			_touch = event.index
			_start_x = event.position.x
			_x = _start_x
			_start_y = event.position.y
			_y = _start_y
		elif not event.pressed and event.index == _touch:
			_touch = -1
	elif event is InputEventScreenDrag and event.index == _touch:
		_x = event.position.x
		_y = event.position.y
		# Re-anchor so reversing direction responds immediately.
		var full := _full_width()
		if absf(_x - _start_x) > full:
			_start_x = _x - signf(_x - _start_x) * full
		if absf(_y - _start_y) > full:
			_start_y = _y - signf(_y - _start_y) * full


func _full_width() -> float:
	var w := get_viewport().get_visible_rect().size.x
	return maxf(w * drag_fraction / maxf(sensitivity, 0.1), 8.0)


func release() -> void:
	_touch = -1


## -1 (brake) .. 1 (accelerate). Small vertical drags are ignored so steering
## does not accidentally change speed.
func throttle() -> float:
	var k := Input.get_axis("brake", "accelerate")
	var t := 0.0
	if _touch != -1:
		var raw := clampf((_start_y - _y) / _full_width(), -1.0, 1.0)
		t = signf(raw) * clampf((absf(raw) - 0.25) / 0.75, 0.0, 1.0)
	return k if absf(k) > absf(t) else t


func value() -> float:
	var k := Input.get_axis("steer_left", "steer_right")
	var t := 0.0
	if _touch != -1:
		t = clampf((_x - _start_x) / _full_width(), -1.0, 1.0)
	var v := k if absf(k) > absf(t) else t
	return -v if invert else v
