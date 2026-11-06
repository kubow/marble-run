class_name TrackGenerator
extends RefCounted
## Deterministic, seeded track generator (see docs/ARCHITECTURE.md).
##
## Determinism rules:
##   * one RandomNumberGenerator per generation, seeded from the config seed;
##   * candidate lists are built in catalogue (file) order;
##   * no global random state, no dictionary-order dependent iteration.
##
## VERSIONING: any change to this file's rules, the validator constants or the
## catalogue changes generated levels. Bump VERSION and add the new value from
## config_fingerprint() to FINGERPRINTS (tests/test_generation.gd enforces it).

const VERSION := 1
const FINGERPRINTS := {
	1: "D6902695074F881F",
}

const FALLBACK_IDS := ["straight", "gentle_left", "gentle_right", "downhill"]
const ENDLESS_FORCED_ID := "downhill_steep"
const YAW_SOFT_LIMIT := 70.0 * PI / 180.0
const YAW_HARD_LIMIT := 150.0 * PI / 180.0
const ENDLESS_YAW_SOFT := 35.0 * PI / 180.0
const ENDLESS_YAW_HARD := 80.0 * PI / 180.0
const SPAWN_SPEED := 3.0
const RECOVERY_AFTER := 3.0     ## After a module this hard, the next must be easy.
const RECOVERY_MAX := 2.0

var catalog: ModuleCatalog
var validator: ReachabilityValidator


func _init(p_catalog: ModuleCatalog = null) -> void:
	catalog = p_catalog if p_catalog != null else ModuleCatalog.get_default()
	validator = ReachabilityValidator.new()


## Fingerprint of everything that influences generated levels.
func config_fingerprint() -> String:
	var text := "gen:%d|fallback:%s|forced:%s|yaw:%.4f,%.4f,%.4f,%.4f|spawn:%.2f|rec:%.2f,%.2f|val:%s|cat:%s" % [
		VERSION, ",".join(FALLBACK_IDS), ENDLESS_FORCED_ID, YAW_SOFT_LIMIT, YAW_HARD_LIMIT,
		ENDLESS_YAW_SOFT, ENDLESS_YAW_HARD, SPAWN_SPEED, RECOVERY_AFTER, RECOVERY_MAX,
		validator.describe(), catalog.canonical_text()]
	return Hash64.to_hex(Hash64.fnv1a64(text))


# ---------------------------------------------------------------------------
class State:
	var cfg: GeneratorConfig
	var rng := RandomNumberGenerator.new()
	var grid := OverlapGrid.new()
	var placements: Array[TrackPlacement] = []
	var next_index := 0
	var yaw := 0.0
	var xf := Transform3D.IDENTITY
	var v_lo := 0.0
	var v_hi := 0.0
	var distance := 0.0
	var attempts := 0
	var backtracks := 0
	var fallbacks := 0
	var forced := 0
	var since_checkpoint := 0
	var endless := false

	func last() -> TrackPlacement:
		return placements[-1] if not placements.is_empty() else null


func _make_state(cfg: GeneratorConfig) -> State:
	var st := State.new()
	st.cfg = cfg
	st.rng.seed = cfg.seed
	st.endless = cfg.mode == GeneratorConfig.Mode.ENDLESS
	st.v_lo = SPAWN_SPEED
	st.v_hi = SPAWN_SPEED
	return st


# --- Level generation --------------------------------------------------------

func generate(cfg: GeneratorConfig) -> LevelDefinition:
	var t0 := Time.get_ticks_usec()
	var st := _make_state(cfg)
	_commit(st, catalog.get_def("start"), -1, {"v_lo": SPAWN_SPEED, "v_hi": SPAWN_SPEED})
	var budget := cfg.attempt_budget_per_segment * cfg.segment_count
	while st.placements.size() - 1 < cfg.segment_count and st.attempts < budget:
		if not _extend(st, cfg.difficulty):
			_backtrack(st)
	# Finish: always possible eventually because start+finish alone is valid.
	var finish := catalog.get_def("finish")
	while true:
		if _try_place(st, finish, -1, cfg.difficulty, true):
			break
		if st.placements.size() <= 1:
			push_error("TrackGenerator: could not place finish")
			break
		_backtrack(st)
	var level := LevelDefinition.new()
	level.config = cfg
	level.generator_version = VERSION
	level.fingerprint = config_fingerprint()
	level.placements = st.placements
	level.finish_index = st.placements.size() - 1
	_assign_checkpoints(level.placements, cfg.checkpoint_interval)
	for p in level.placements:
		if p.checkpoint:
			level.checkpoints.append(p.index)
	level.stats = {
		"attempts": st.attempts, "backtracks": st.backtracks, "fallbacks": st.fallbacks,
		"segments": st.placements.size() - 2, "usec": Time.get_ticks_usec() - t0,
	}
	return level


static func _assign_checkpoints(list: Array[TrackPlacement], interval: int) -> void:
	var since := 0
	for i in list.size():
		var p := list[i]
		p.checkpoint = false
		if i == 0:
			p.checkpoint = true
			since = 0
		elif p.def.id != "finish" and (since >= interval or (p.def.difficulty >= RECOVERY_AFTER and since >= 2)):
			p.checkpoint = true
			since = 0
		since += 1


# --- Core step ---------------------------------------------------------------

func _eligible(st: State, difficulty: float, tried: Dictionary) -> Array:
	var tier := clampi(int(floor(difficulty)), 1, 5)
	var pref := clampf(0.5 + difficulty * 0.4, 0.5, 3.2)
	var soft := ENDLESS_YAW_SOFT if st.endless else YAW_SOFT_LIMIT
	var defs: Array = []
	var weights := PackedFloat32Array()
	for d in catalog.modules:
		if d.weight <= 0.0 or d.tier > tier or tried.has(d.id):
			continue
		var w := d.weight * exp(-0.5 * pow((d.difficulty - pref) / 1.2, 2.0))
		if d.exit_yaw != 0.0:
			var ny := st.yaw + d.exit_yaw
			if absf(ny) > soft and absf(ny) > absf(st.yaw):
				w *= 0.2
			elif absf(ny) < absf(st.yaw):
				w *= 1.5
		defs.append(d)
		weights.append(w)
	return [defs, weights]


func _extend(st: State, difficulty: float) -> bool:
	var tried := {}
	for i in st.cfg.max_tries_per_slot:
		var e := _eligible(st, difficulty, tried)
		var defs: Array = e[0]
		if defs.is_empty():
			break
		var pick := st.rng.rand_weighted(e[1])
		if pick < 0:
			break
		var d: TrackModuleDef = defs[pick]
		tried[d.id] = true
		var variant := -1
		if d.has_obstacles():
			variant = st.rng.randi_range(0, d.obstacle_layouts.size() - 1)
		if _try_place(st, d, variant, difficulty, false):
			return true
	# Deterministic fallbacks, easiest first, preferring turns back to centre.
	var order: Array = FALLBACK_IDS.duplicate()
	if st.yaw > 0.0:
		order = ["straight", "gentle_right", "downhill", "gentle_left"]
	elif st.yaw < 0.0:
		order = ["straight", "gentle_left", "downhill", "gentle_right"]
	for id in order:
		if tried.has(id):
			continue
		if _try_place(st, catalog.get_def(id), -1, difficulty, false):
			st.fallbacks += 1
			return true
	return false


func _try_place(st: State, d: TrackModuleDef, variant: int, difficulty: float, is_finish: bool) -> bool:
	st.attempts += 1
	var prev := st.last()
	if prev != null and not is_finish:
		if prev.def.difficulty >= RECOVERY_AFTER and d.difficulty > RECOVERY_MAX:
			return false
		var cap := 3.5 + difficulty * 0.6
		var recent := d.difficulty + prev.def.difficulty
		if st.placements.size() >= 2:
			recent += st.placements[-2].def.difficulty
		if recent > cap:
			return false
	var hard := ENDLESS_YAW_HARD if st.endless else YAW_HARD_LIMIT
	if absf(st.yaw + d.exit_yaw) > hard:
		return false
	var chk := validator.check_module(d, st.v_lo, st.v_hi, variant)
	if not chk.ok:
		return false
	var pts := st.xf * d.ring_pos
	var min_idx := 0
	if st.endless:
		min_idx = maxi(0, st.next_index - 60)
	if st.grid.overlaps(pts, OverlapGrid.sample_radii(d), st.next_index - 1, min_idx):
		return false
	_commit(st, d, variant, chk)
	return true


func _commit(st: State, d: TrackModuleDef, variant: int, chk: Dictionary) -> TrackPlacement:
	var p := TrackPlacement.new()
	p.setup(st.next_index, d, variant, st.xf)
	p.yaw_in = st.yaw
	p.v_lo_in = st.v_lo
	p.v_hi_in = st.v_hi
	p.v_lo_out = chk.v_lo
	p.v_hi_out = chk.v_hi
	p.start_distance = st.distance
	st.grid.insert(p.index, p.centerline, OverlapGrid.sample_radii(d))
	st.placements.append(p)
	st.next_index += 1
	st.yaw += d.exit_yaw
	st.xf = p.exit_transform
	st.v_lo = chk.v_lo
	st.v_hi = chk.v_hi
	st.distance += d.length_3d
	return p


func _backtrack(st: State) -> void:
	if st.placements.size() <= 1:
		return
	var p: TrackPlacement = st.placements.pop_back()
	st.grid.remove(p.index, p.centerline)
	st.next_index = p.index
	st.yaw = p.yaw_in
	st.xf = p.transform
	st.v_lo = p.v_lo_in
	st.v_hi = p.v_hi_in
	st.distance = p.start_distance
	st.backtracks += 1


# --- Endless streaming ----------------------------------------------------------

class EndlessStream:
	var gen: TrackGenerator
	var st: State
	var start_difficulty := 1.0
	var ramp_per_module := 0.04
	var max_difficulty := 7.0
	var checkpoint_interval := 4
	var _since_checkpoint := 0

	func difficulty_at(index: int) -> float:
		return minf(start_difficulty + index * ramp_per_module, max_difficulty)

	## Produces the next placement. Never backtracks (earlier modules may already
	## be visible); if nothing validates, a steep downhill is forced, which drops
	## below any earlier section.
	func next() -> TrackPlacement:
		if st.placements.is_empty():
			var s := gen._commit(st, gen.catalog.get_def("start"), -1, {"v_lo": SPAWN_SPEED, "v_hi": SPAWN_SPEED})
			s.checkpoint = true
			_since_checkpoint = 1
			return s
		var diff := difficulty_at(st.next_index)
		if not gen._extend(st, diff):
			var d := gen.catalog.get_def(ENDLESS_FORCED_ID)
			var chk := gen.validator.check_module(d, st.v_lo, st.v_hi, -1)
			if not chk.ok:
				chk = {"v_lo": maxf(st.v_lo, SPAWN_SPEED), "v_hi": maxf(st.v_hi, SPAWN_SPEED)}
			var fp := gen._commit(st, d, -1, chk)
			fp.forced = true
			st.forced += 1
		var p: TrackPlacement = st.placements[-1]
		if _since_checkpoint >= checkpoint_interval or (p.def.difficulty >= RECOVERY_AFTER and _since_checkpoint >= 2):
			p.checkpoint = true
			_since_checkpoint = 0
		_since_checkpoint += 1
		# Keep memory bounded: only recent placements are needed for constraints.
		if st.placements.size() > 8:
			st.placements = st.placements.slice(st.placements.size() - 8)
		return p

	## Forget overlap samples of a placement that left the active window.
	func forget(p: TrackPlacement) -> void:
		st.grid.remove(p.index, p.centerline)


func create_endless(p_seed: int, start_difficulty := 1.0) -> EndlessStream:
	var cfg := GeneratorConfig.make(p_seed, start_difficulty, 1, GeneratorConfig.Mode.ENDLESS)
	var es := EndlessStream.new()
	es.gen = self
	es.st = _make_state(cfg)
	es.start_difficulty = start_difficulty
	return es


# --- Fixed layouts (tests / tutorials) ----------------------------------------

## Assembles an explicit module sequence without random choices. Speeds are
## still estimated; validation failures are recorded in stats.invalid.
func assemble(ids: PackedStringArray, variants := PackedInt32Array()) -> LevelDefinition:
	var cfg := GeneratorConfig.make(0, 1.0, ids.size())
	var st := _make_state(cfg)
	var invalid := PackedStringArray()
	for i in ids.size():
		var d := catalog.get_def(ids[i])
		var variant := variants[i] if i < variants.size() else (0 if d.has_obstacles() else -1)
		var chk := validator.check_module(d, st.v_lo, st.v_hi, variant)
		if not chk.ok:
			invalid.append("%s: %s" % [d.id, chk.reason])
			chk = {"v_lo": maxf(st.v_lo, 1.0), "v_hi": st.v_hi}
		_commit(st, d, variant, chk)
	var level := LevelDefinition.new()
	level.config = cfg
	level.generator_version = VERSION
	level.placements = st.placements
	level.finish_index = st.placements.size() - 1
	_assign_checkpoints(level.placements, cfg.checkpoint_interval)
	for p in level.placements:
		if p.checkpoint:
			level.checkpoints.append(p.index)
	level.stats = {"invalid": invalid}
	return level
