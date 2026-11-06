class_name ModuleCatalog
extends RefCounted
## Loads module definitions from JSON. Order of modules is the order in the
## file (arrays only), so iteration is deterministic.

const DEFAULT_PATH := "res://resources/modules/catalog.json"

var spec: TrackSpec
var modules: Array[TrackModuleDef] = []
var by_id: Dictionary = {}
var source_text := ""
var raw: Dictionary = {}

static var _default: ModuleCatalog


## Shared catalogue instance (module samples/meshes are cached on it).
static func get_default() -> ModuleCatalog:
	if _default == null:
		_default = ModuleCatalog.load_from_file(DEFAULT_PATH)
	return _default


static func load_from_file(path: String) -> ModuleCatalog:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("ModuleCatalog: cannot open %s" % path)
		return ModuleCatalog.new()
	return load_from_text(f.get_as_text())


static func load_from_text(text: String) -> ModuleCatalog:
	var c := ModuleCatalog.new()
	c.source_text = text
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("ModuleCatalog: invalid JSON")
		return c
	c.raw = data
	c.spec = TrackSpec.from_dict(data.get("track", {}))
	for md in data.get("modules", []):
		var m := TrackModuleDef.from_dict(md, c.spec)
		if c.by_id.has(m.id):
			push_error("ModuleCatalog: duplicate id %s" % m.id)
			continue
		c.modules.append(m)
		c.by_id[m.id] = m
	return c


func get_def(id: String) -> TrackModuleDef:
	return by_id.get(id)


## Canonical text of the configuration (sorted keys) for fingerprinting.
func canonical_text() -> String:
	var copy := raw.duplicate(true)
	copy.erase("_comment")
	return JSON.stringify(copy, "", true)
