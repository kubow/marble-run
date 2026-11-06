class_name LevelProgression
extends RefCounted
## Maps level numbers to generator configurations.
##   seed(n)        = Hash64.level_seed(MASTER_SEED, n)   (SplitMix64, see hash64.gd)
##   difficulty(n)  = n for n <= 4, then 4 + 0.35 * (n - 4), capped at 8
##   segments(n)    = 10 + 2 * (n - 1), capped at 40
## Level 1: straights, gentle curves, downhills.  Level 2: + sharp and S curves.
## Level 3: + uphill, waves, funnels, narrow bridges, static obstacles.
## Level 4: + moving obstacles.  Level 5+: everything, gradually harder.

const MAX_LEVEL := 999


static func difficulty_for(n: int) -> float:
	if n <= 4:
		return float(maxi(n, 1))
	return minf(4.0 + 0.35 * (n - 4), 8.0)


static func segments_for(n: int) -> int:
	return mini(10 + 2 * (maxi(n, 1) - 1), 40)


static func seed_for(n: int) -> int:
	return Hash64.level_seed(Hash64.MASTER_SEED, n)


static func config_for_level(n: int) -> GeneratorConfig:
	return GeneratorConfig.make(seed_for(n), difficulty_for(n), segments_for(n))
