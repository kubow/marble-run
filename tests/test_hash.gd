extends TestCase
## Seed hashing must be bit-exact and platform independent.


func test_splitmix_reference_values() -> void:
	# Reference values computed with Python's arbitrary-precision integers.
	check_eq(Hash64.splitmix64(0), -2152535657050944081, "splitmix64(0)")
	check_eq(Hash64.splitmix64(1), -7995527694508729151, "splitmix64(1)")
	check_eq(Hash64.splitmix64(-5), 1635312068028924514, "splitmix64(-5)")


func test_level_seeds_stable() -> void:
	check_eq(Hash64.level_seed(Hash64.MASTER_SEED, 1), 3834795635862801570, "level 1")
	check_eq(Hash64.level_seed(Hash64.MASTER_SEED, 2), 5157617582897141631, "level 2")
	check_eq(Hash64.level_seed(Hash64.MASTER_SEED, 3), -7719312046380610418, "level 3")
	check_eq(Hash64.to_hex(Hash64.level_seed(Hash64.MASTER_SEED, 3)), "94DF7E97AD170C8E", "hex")


func test_fnv() -> void:
	check_eq(Hash64.fnv1a64("marble"), 4424506444230486560, "fnv marble")
	check_eq(Hash64.fnv1a64(""), Hash64.FNV_OFFSET, "fnv empty")


func test_parse_roundtrip() -> void:
	for v in [0, 1, -1, 123456789, Hash64.MASTER_SEED, -7719312046380610418]:
		var p := Hash64.parse_seed(Hash64.to_hex(v))
		check(p.ok and p.value == v, "hex roundtrip %d" % v)
	var d := Hash64.parse_seed("42")
	check(d.ok and d.value == 42, "decimal parse")
	check(not Hash64.parse_seed("xyz!").ok, "invalid rejected")
	var c := GeneratorConfig.from_code("94DF7E97AD170C8E-4-22")
	check(c != null and c.seed == -7719312046380610418 and c.segment_count == 22 and int(c.difficulty) == 4, "track code parse")
	check_eq(c.to_code(), "94DF7E97AD170C8E-4-22", "track code roundtrip")
