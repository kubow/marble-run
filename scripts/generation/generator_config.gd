class_name GeneratorConfig
extends RefCounted
## Input of the track generator.

enum Mode { LEVEL, ENDLESS }

var seed := 0                  ## 64-bit seed.
var difficulty := 1.0          ## Target difficulty, 1 (easy) .. 8 (hard).
var segment_count := 12        ## Number of modules between start and finish.
var mode := Mode.LEVEL
var checkpoint_interval := 4   ## Max modules between checkpoints.
var max_tries_per_slot := 8    ## Weighted candidates tried before fallbacks.
var attempt_budget_per_segment := 60


static func make(p_seed: int, p_difficulty: float, p_segments: int, p_mode := Mode.LEVEL) -> GeneratorConfig:
	var c := GeneratorConfig.new()
	c.seed = p_seed
	# Quantised to 0.01 so the shareable code reproduces it exactly.
	c.difficulty = snappedf(clampf(p_difficulty, 1.0, 8.0), 0.01)
	c.segment_count = clampi(p_segments, 3, 200)
	c.mode = p_mode
	return c


## Highest module tier allowed for this difficulty.
func tier() -> int:
	return clampi(int(floor(difficulty)), 1, 5)


## Shareable track code: SEEDHEX-DIFFICULTY-SEGMENTS
func to_code() -> String:
	var d := str(int(difficulty)) if is_equal_approx(difficulty, roundf(difficulty)) else String.num(difficulty, 2)
	return "%s-%s-%d" % [Hash64.to_hex(seed), d, segment_count]


## Parses a track code or a bare seed (decimal or hex). Returns null if invalid.
static func from_code(code: String, default_difficulty := 3.0, default_segments := 20) -> GeneratorConfig:
	var parts := code.strip_edges().split("-", false)
	if parts.is_empty():
		return null
	# Allow a leading minus for negative decimal seeds.
	var seed_text := parts[0]
	var rest := parts.slice(1)
	if code.strip_edges().begins_with("-"):
		seed_text = "-" + seed_text
	var p := Hash64.parse_seed(seed_text)
	if not p.ok:
		return null
	var diff := default_difficulty
	var segs := default_segments
	if rest.size() >= 1:
		if not rest[0].is_valid_float():
			return null
		diff = rest[0].to_float()
	if rest.size() >= 2:
		if not rest[1].is_valid_int():
			return null
		segs = rest[1].to_int()
	return GeneratorConfig.make(p.value, diff, segs)
