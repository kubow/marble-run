class_name TrackSpec
extends RefCounted
## Shared track standard: every connector uses this width, wall height and
## base grade, which is what makes any module attachable to any other.

var half_width := 1.5        ## Half of the usable floor width at connectors (m).
var wall_height := 0.45      ## Side wall height at connectors (m).
var grade := -0.07           ## Base slope (dy per horizontal metre) at every connector.
var lip := 0.1               ## Visual wall thickness (m).
var base_depth := 0.3        ## Visual depth of the track body below the floor (m).
var ring_spacing := 0.8      ## Target distance between generated cross-section rings (m).
var ball_radius := 0.28      ## Marble radius the track is designed for (m).

## Normalised lateral positions of the inner profile (-1 = left wall top).
const PROFILE_X := [-1.0, -0.96, -0.9, -0.8, -0.6, -0.3, 0.0, 0.3, 0.6, 0.8, 0.9, 0.96, 1.0]
## Where the curved wall starts (normalised).
const WALL_START := 0.8


static func from_dict(d: Dictionary) -> TrackSpec:
	var s := TrackSpec.new()
	s.half_width = float(d.get("half_width", s.half_width))
	s.wall_height = float(d.get("wall_height", s.wall_height))
	s.grade = float(d.get("grade", s.grade))
	s.lip = float(d.get("lip", s.lip))
	s.base_depth = float(d.get("base_depth", s.base_depth))
	s.ring_spacing = float(d.get("ring_spacing", s.ring_spacing))
	s.ball_radius = float(d.get("ball_radius", s.ball_radius))
	return s


## Height of the inner surface at normalised lateral x for the given profile.
static func surface_height(x: float, wall_h: float, dish: float) -> float:
	var ax := absf(x)
	var h := dish * x * x
	if ax > WALL_START:
		var k := (ax - WALL_START) / (1.0 - WALL_START)
		h += wall_h * k * k
	return h


## Inner profile points (lateral metres, height) left -> right.
static func inner_profile(half_w: float, wall_h: float, dish: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for x in PROFILE_X:
		pts.append(Vector2(x * half_w, surface_height(x, wall_h, dish)))
	return pts
