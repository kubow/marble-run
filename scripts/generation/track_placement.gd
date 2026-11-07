class_name TrackPlacement
extends RefCounted
## A module instance placed in the world by the generator.

var index := 0
var def: TrackModuleDef
var variant := -1                       ## Obstacle layout index or -1.
var env := "classic"                    ## Environment id (see catalog "environments").
var style := "trough"                   ## Geometry style: trough | tube | wires.
var env_left_in := 0                    ## Generator state before this module (for backtracking).
var blend_in := true                    ## Styled geometry blends from the standard profile at entry.
var blend_out := true                   ## ... and back to it at the exit.
var transform := Transform3D.IDENTITY   ## World transform of the entry connector.
var exit_transform := Transform3D.IDENTITY
var yaw_in := 0.0                       ## Net heading at entry (radians).
var v_lo_in := 0.0                      ## Pessimistic entry speed estimate.
var v_hi_in := 0.0                      ## Optimistic entry speed estimate.
var v_lo_out := 0.0
var v_hi_out := 0.0
var checkpoint := false                 ## Checkpoint at this module's entry.
var start_distance := 0.0               ## Track distance at entry (m).
var centerline := PackedVector3Array()  ## World-space centreline ring points.
var forced := false                     ## Endless only: placed without full validation.


func setup(p_index: int, p_def: TrackModuleDef, p_variant: int, p_xf: Transform3D) -> void:
	index = p_index
	def = p_def
	variant = p_variant
	transform = p_xf
	exit_transform = p_xf * p_def.exit_transform
	centerline = p_xf * p_def.ring_pos


func end_distance() -> float:
	return start_distance + def.length_3d


func obstacle_layout() -> Array:
	if variant >= 0 and variant < def.obstacle_layouts.size():
		return def.obstacle_layouts[variant]
	return []


func to_dict() -> Dictionary:
	var o := transform.origin
	return {
		"id": def.id,
		"variant": variant,
		"env": env,
		"origin": [o.x, o.y, o.z],
		"yaw": yaw_in,
		"checkpoint": checkpoint,
	}
