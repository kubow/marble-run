class_name TrackSession
extends RefCounted
## Owns the generated track for one play session and keeps the TrackView and
## TrackTracker in sync with it. LEVEL mode builds everything up front;
## ENDLESS mode streams modules ahead of the marble and recycles old ones.

var view: TrackView
var tracker := TrackTracker.new()
var generator := TrackGenerator.new()
var endless := false
var level: LevelDefinition                 ## LEVEL mode
var stream: TrackGenerator.EndlessStream   ## ENDLESS mode
var placements: Dictionary = {}            ## index -> TrackPlacement (active)
var first_index := 0
var last_index := -1
var finish_index := -1
var ahead := 10                            ## ENDLESS: modules kept ahead of the marble.
var behind := 3                            ## ENDLESS: modules kept behind.
var code := ""
var gen_usec := 0


func _init(p_view: TrackView) -> void:
	view = p_view


func start_level(cfg: GeneratorConfig) -> void:
	endless = false
	level = generator.generate(cfg)
	gen_usec = level.stats.usec
	code = cfg.to_code()
	for p in level.placements:
		_add(p)
	finish_index = level.finish_index
	view.rebuild_collision()
	tracker.reset(0)


func start_endless(p_seed: int) -> void:
	endless = true
	stream = generator.create_endless(p_seed, 1.0)
	code = Hash64.to_hex(p_seed)
	var t0 := Time.get_ticks_usec()
	for i in ahead + 1:
		_add(stream.next())
	gen_usec = Time.get_ticks_usec() - t0
	view.rebuild_collision()
	tracker.reset(0)


func _add(p: TrackPlacement) -> void:
	placements[p.index] = p
	view.add_placement(p)
	tracker.add(p)
	last_index = maxi(last_index, p.index)


func placement(index: int) -> TrackPlacement:
	return placements.get(index)


## ENDLESS: generate ahead / drop behind. keep_from protects the checkpoint.
## Returns true if the collision was rebuilt.
func update_stream(keep_from: int) -> bool:
	if not endless:
		return false
	var changed := false
	while last_index - tracker.current < ahead:
		var t0 := Time.get_ticks_usec()
		_add(stream.next())
		gen_usec = Time.get_ticks_usec() - t0
		changed = true
	while first_index < mini(tracker.current - behind, keep_from):
		var p: TrackPlacement = placements.get(first_index)
		if p:
			view.remove_placement(p.index)
			tracker.remove(p.index)
			stream.forget(p)
			placements.erase(p.index)
		first_index += 1
		changed = true
	if changed:
		view.rebuild_collision()
	return changed


func is_finished() -> bool:
	return not endless and tracker.current == finish_index and tracker.local_t > 0.5


func total_length() -> float:
	return level.total_length() if level else 0.0


func progress() -> float:
	if endless:
		return 0.0
	return clampf(tracker.distance / maxf(total_length(), 1.0), 0.0, 1.0)


## Spawn transform and velocity at the entry of placement `index`.
func spawn_state(index: int, radius: float) -> Array:
	var p := placement(index)
	var fwd := -p.transform.basis.z
	var pos := p.transform.origin + fwd * 1.0 + Vector3.UP * (radius + 0.05)
	var v := TrackGenerator.SPAWN_SPEED if index == 0 else maxf(p.v_lo_in * 0.9, 2.0)
	return [Transform3D(Basis(), pos), fwd * v]
