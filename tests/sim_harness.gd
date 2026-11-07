class_name SimHarness
extends RefCounted
## Runs a marble over a level with real physics in the scene tree.

var tree: SceneTree
var root: Node3D
var view: TrackView
var marble: Marble
var tracker := TrackTracker.new()
var level: LevelDefinition
var ticks := 0
var autopilot: Autopilot = null
var log_speed: Array = []


func _init(p_tree: SceneTree, p_level: LevelDefinition) -> void:
	tree = p_tree
	level = p_level
	root = Node3D.new()
	tree.root.add_child(root)
	view = TrackView.new()
	view.show_pillars = false
	view.clock = func() -> float: return ticks / 60.0
	root.add_child(view)
	for p in level.placements:
		view.add_placement(p)
		tracker.add(p)
	view.rebuild_collision()
	marble = Marble.new()
	root.add_child(marble)
	spawn_at(0)


func spawn_at(index: int) -> void:
	var p: TrackPlacement = level.placements[index]
	var fwd := -p.transform.basis.z
	var pos := p.transform.origin + fwd * 1.0 + Vector3.UP * (marble.radius + 0.05)
	var v := maxf(p.v_lo_in * 0.9, 1.5) if index > 0 else TrackGenerator.SPAWN_SPEED
	marble.global_transform = Transform3D(Basis(), pos)
	marble.respawn(Transform3D(Basis(), pos), fwd * v)
	tracker.reset(index)


## Runs until finish, fall or timeout. Returns {result, ticks, distance, max_speed}.
func run(max_seconds: float, steer_fn := Callable()) -> Dictionary:
	var max_speed := 0.0
	var stall := 0
	var max_ticks := int(max_seconds * 60.0)
	while ticks < max_ticks:
		await tree.physics_frame
		ticks += 1
		var pos := marble.global_position
		tracker.update(pos)
		marble.steer_axis = Autopilot.right_of(tracker.tangent)
		marble.forward_axis = tracker.tangent
		if autopilot:
			marble.steer = autopilot.steer(tracker, marble.linear_velocity)
			marble.throttle = autopilot.throttle(tracker, marble.speed())
		elif steer_fn.is_valid():
			marble.steer = steer_fn.call(self)
		var sp := marble.speed()
		max_speed = maxf(max_speed, sp)
		if ticks % 30 == 0:
			log_speed.append(sp)
		if ticks > 10 and tracker.is_off_track(pos):
			return _res("fell", max_speed)
		stall = stall + 1 if sp < 0.3 else 0
		if stall > 180:
			return _res("stalled", max_speed)
		if tracker.current == level.finish_index and tracker.local_t > 0.5:
			return _res("finished", max_speed)
	return _res("timeout", max_speed)


func _res(r: String, max_speed: float) -> Dictionary:
	return {"result": r, "ticks": ticks, "distance": tracker.distance, "module": tracker.current,
		"module_id": level.placements[tracker.current].def.id, "max_speed": max_speed}


func dispose() -> void:
	root.queue_free()
	await tree.process_frame
