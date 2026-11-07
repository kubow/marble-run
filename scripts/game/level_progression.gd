class_name LevelProgression
extends RefCounted
## Maps level numbers to generator configurations.
##   seed(n)        = Hash64.level_seed(MASTER_SEED, n)   (SplitMix64, see hash64.gd)
##   difficulty(n)  = 1 + 1.2 * (n - 1) for n <= 4, then 4.6 + 0.4 * (n - 4), capped at 8
##   segments(n)    = 10 + 2 * (n - 1), capped at 40
## Level 1: hands-off safe intro (classic + tube).  Level 2: + wires, small
## jumps, sharp and S curves, first brake/boost demands.  Level 3: + bigger
## jumps, uphills, waves, funnels, bridges, static obstacles.  Level 4: + moving
## obstacles, big jumps.  Level 5+: everything, steadily harder.

const MAX_LEVEL := 999


static func difficulty_for(n: int) -> float:
	if n <= 4:
		return 1.0 + 1.2 * (maxi(n, 1) - 1)
	return minf(4.6 + 0.4 * (n - 4), 8.0)


static func segments_for(n: int) -> int:
	return mini(10 + 2 * (maxi(n, 1) - 1), 40)


static func seed_for(n: int) -> int:
	return Hash64.level_seed(Hash64.MASTER_SEED, n)


static func config_for_level(n: int) -> GeneratorConfig:
	return GeneratorConfig.make(seed_for(n), difficulty_for(n), segments_for(n))
