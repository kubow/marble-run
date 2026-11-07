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
var tube_radius := 1.1       ## Tube environment: inner radius (m), bottom at floor level.
var wire_radius := 0.035     ## Wire environment: wire thickness radius (m).
var wire_side_dx := 0.245    ## Wire environment: lateral offset of the side wires (m).
var wire_side_y := 0.06      ## Wire environment: height of side wire centres (m).
var narrow_half_width := 0.32 ## Wire environment: lead-in channel half width (m).

## Normalised lateral positions of the inner profile (-1 = left wall top).
const PROFILE_X := [-1.0, -0.96, -0.9, -0.8, -0.6, -0.3, 0.0, 0.3, 0.6, 0.8, 0.9, 0.96, 1.0]
## Where the curved wall starts (normalised).
const WALL_START := 0.8
## Styled modules (tube / wires) blend from the standard profile within this
## fraction of the module length at each end, so connectors stay standard.
const STYLE_BLEND := 0.12
## Wires need a long, gentle funnel into the narrow wire cradle (~18 degrees).
const WIRE_BLEND := 0.3


static func blend_fraction(style: String) -> float:
	return WIRE_BLEND if style == "wires" else STYLE_BLEND


static func from_dict(d: Dictionary) -> TrackSpec:
	var s := TrackSpec.new()
	s.half_width = float(d.get("half_width", s.half_width))
	s.wall_height = float(d.get("wall_height", s.wall_height))
	s.grade = float(d.get("grade", s.grade))
	s.lip = float(d.get("lip", s.lip))
	s.base_depth = float(d.get("base_depth", s.base_depth))
	s.ring_spacing = float(d.get("ring_spacing", s.ring_spacing))
	s.ball_radius = float(d.get("ball_radius", s.ball_radius))
	s.tube_radius = float(d.get("tube_radius", s.tube_radius))
	s.wire_radius = float(d.get("wire_radius", s.wire_radius))
	s.wire_side_dx = float(d.get("wire_side_dx", s.wire_side_dx))
	s.wire_side_y = float(d.get("wire_side_y", s.wire_side_y))
	s.narrow_half_width = float(d.get("narrow_half_width", s.narrow_half_width))
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
