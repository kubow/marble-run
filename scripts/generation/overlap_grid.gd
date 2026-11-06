class_name OverlapGrid
extends RefCounted
## Spatial hash of centreline samples used to keep track sections apart.
## Only lookups by key are performed, never iteration, so results do not depend
## on dictionary ordering.

const CELL := 8.0

var vertical_clearance := 4.0   ## Sections closer than this vertically must not overlap.
var margin := 0.6               ## Extra horizontal clearance (m).
var _cells: Dictionary = {}     ## Vector2i -> Array of [index, Vector3, radius]


static func _key(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL)), int(floor(p.z / CELL)))


static func sample_radii(def: TrackModuleDef) -> PackedFloat32Array:
	var r := PackedFloat32Array()
	for k in def.ring_count():
		r.append(def.ring_half_w[k] + def.spec.lip + 0.2)
	return r


func insert(index: int, points: PackedVector3Array, radii: PackedFloat32Array) -> void:
	for k in points.size():
		var key := _key(points[k])
		if not _cells.has(key):
			_cells[key] = []
		_cells[key].append([index, points[k], radii[k]])


func remove(index: int, points: PackedVector3Array) -> void:
	var seen := {}
	for p in points:
		var key := _key(p)
		if seen.has(key) or not _cells.has(key):
			continue
		seen[key] = true
		var arr: Array = _cells[key]
		var kept: Array = []
		for e in arr:
			if e[0] != index:
				kept.append(e)
		if kept.is_empty():
			_cells.erase(key)
		else:
			_cells[key] = kept


## True if any point collides with an entry whose index is < max_index.
func overlaps(points: PackedVector3Array, radii: PackedFloat32Array, max_index: int, min_index := 0) -> bool:
	for k in points.size():
		var p := points[k]
		var base := _key(p)
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var key := base + Vector2i(dx, dz)
				if not _cells.has(key):
					continue
				for e in _cells[key]:
					var idx: int = e[0]
					if idx >= max_index or idx < min_index:
						continue
					var q: Vector3 = e[1]
					if absf(q.y - p.y) >= vertical_clearance:
						continue
					var lim: float = radii[k] + e[2] + margin
					var dxz := Vector2(q.x - p.x, q.z - p.z)
					if dxz.length_squared() < lim * lim:
						return true
	return false


func clear() -> void:
	_cells.clear()
