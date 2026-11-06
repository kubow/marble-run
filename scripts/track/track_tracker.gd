class_name TrackTracker
extends RefCounted
## Locates the marble on the track: current module, distance along the track,
## nearest centreline point, tangent and lateral offset. Searches only modules
## around the current one, so cost is constant per tick.

var placements: Dictionary = {}   ## index -> TrackPlacement (active window)
var current := 0                  ## Current module index.
var distance := 0.0               ## Distance along the track at nearest point (m).
var max_distance := 0.0           ## Furthest distance reached.
var nearest := Vector3.ZERO
var tangent := Vector3.FORWARD
var half_width := 1.5
var offset := Vector3.ZERO        ## marble - nearest
var local_t := 0.0                ## Fraction along the current module.


func add(p: TrackPlacement) -> void:
	placements[p.index] = p


func remove(index: int) -> void:
	placements.erase(index)


func reset(index: int) -> void:
	current = index
	if placements.has(index):
		var p: TrackPlacement = placements[index]
		distance = p.start_distance
		nearest = p.centerline[0]


func update(pos: Vector3) -> void:
	var best_d2 := INF
	var best_idx := current
	for idx in range(current - 1, current + 3):
		if not placements.has(idx):
			continue
		var p: TrackPlacement = placements[idx]
		var cl := p.centerline
		for k in cl.size() - 1:
			var a := cl[k]
			var b := cl[k + 1]
			var ab := b - a
			var t := clampf((pos - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
			var q := a + ab * t
			var d2 := pos.distance_squared_to(q)
			if d2 < best_d2:
				best_d2 = d2
				best_idx = idx
				nearest = q
				tangent = ab.normalized()
				var d0 := p.def.ring_dist[k]
				var d1 := p.def.ring_dist[k + 1]
				distance = p.start_distance + lerpf(d0, d1, t)
				half_width = lerpf(p.def.ring_half_w[k], p.def.ring_half_w[k + 1], t)
				local_t = lerpf(p.def.ring_s[k], p.def.ring_s[k + 1], t) / p.def.length
	current = best_idx
	offset = pos - nearest
	max_distance = maxf(max_distance, distance)


func current_placement() -> TrackPlacement:
	return placements.get(current)


## True if the marble is clearly off the track (fallen).
func is_off_track(pos: Vector3) -> bool:
	if pos.y < nearest.y - 2.5:
		return true
	var lateral := Vector2(offset.x, offset.z).length()
	return lateral > half_width + 3.0
