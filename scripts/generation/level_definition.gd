class_name LevelDefinition
extends RefCounted
## Output of the generator: a reproducible, fully placed level.

var config: GeneratorConfig
var generator_version := 0
var fingerprint := ""
var placements: Array[TrackPlacement] = []
var checkpoints: PackedInt32Array = PackedInt32Array()
var finish_index := -1
var stats := {}


func total_length() -> float:
	if placements.is_empty():
		return 0.0
	return placements[-1].end_distance()


func module_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for p in placements:
		out.append(p.def.id)
	return out


## Text summary used for hashing and comparisons (positions rounded to mm).
func logical_text() -> String:
	var parts := PackedStringArray()
	parts.append("v%d|%s|%s" % [generator_version, fingerprint, config.to_code()])
	for p in placements:
		var o := p.transform.origin
		parts.append("%s:%d:%s:%.3f,%.3f,%.3f:%.4f:%s" % [p.def.id, p.variant, p.env, o.x, o.y, o.z, p.yaw_in, "C" if p.checkpoint else ""])
	return "\n".join(parts)


func logical_hash() -> String:
	return Hash64.to_hex(Hash64.fnv1a64(logical_text()))


func to_dict() -> Dictionary:
	var mods: Array = []
	for p in placements:
		mods.append(p.to_dict())
	return {
		"generator_version": generator_version,
		"fingerprint": fingerprint,
		"code": config.to_code(),
		"hash": logical_hash(),
		"modules": mods,
		"checkpoints": Array(checkpoints),
		"finish_index": finish_index,
	}
