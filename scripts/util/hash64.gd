class_name Hash64
extends RefCounted
## Portable 64-bit integer hashing used for seeds and fingerprints.
##
## GDScript integers are signed 64-bit. Multiplication/addition overflow is not
## something we want to rely on, so 64-bit wrap-around arithmetic is done with
## 16-bit limbs where every intermediate product fits comfortably in 63 bits.
## Values are stored as the signed int64 with the same bit pattern as the
## unsigned value (two's complement).
##
## Algorithms (documented, stable):
##   splitmix64(x): z = x + 0x9E3779B97F4A7C15
##                  z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9
##                  z = (z ^ (z >> 27)) * 0x94D049BB133111EB
##                  return z ^ (z >> 31)          (all ops mod 2^64, >> logical)
##   level_seed(master, n) = splitmix64(master ^ splitmix64(n))
##   fnv1a64(bytes): h = 0xCBF29CE484222325; for b: h = (h ^ b) * 0x100000001B3

const M16 := 0xFFFF
# Unsigned constants written as their signed two's complement equivalents.
const SM_GAMMA := -7046029254386353131   # 0x9E3779B97F4A7C15
const SM_MUL1 := -4658895280553007687    # 0xBF58476D1CE4E5B9
const SM_MUL2 := -7723592293110705685    # 0x94D049BB133111EB
const FNV_OFFSET := -3750763034362895579 # 0xCBF29CE484222325
const FNV_PRIME := 1099511628211         # 0x00000100000001B3

## Master seed for the numbered level progression ("MARBLE" + 0001).
const MASTER_SEED := 5566821059107553281 # 0x4D4152424C450001


static func _limbs(a: int) -> PackedInt64Array:
	return PackedInt64Array([a & M16, (a >> 16) & M16, (a >> 32) & M16, (a >> 48) & M16])


static func _join(l0: int, l1: int, l2: int, l3: int) -> int:
	return ((l3 & M16) << 48) | ((l2 & M16) << 32) | ((l1 & M16) << 16) | (l0 & M16)


## (a * b) mod 2^64
static func mul(a: int, b: int) -> int:
	var x := _limbs(a)
	var y := _limbs(b)
	var r0 := x[0] * y[0]
	var r1 := x[1] * y[0] + x[0] * y[1]
	var r2 := x[2] * y[0] + x[1] * y[1] + x[0] * y[2]
	var r3 := x[3] * y[0] + x[2] * y[1] + x[1] * y[2] + x[0] * y[3]
	var l0 := r0 & M16
	r1 += r0 >> 16
	var l1 := r1 & M16
	r2 += r1 >> 16
	var l2 := r2 & M16
	r3 += r2 >> 16
	return _join(l0, l1, l2, r3)


## (a + b) mod 2^64
static func add(a: int, b: int) -> int:
	var x := _limbs(a)
	var y := _limbs(b)
	var c := x[0] + y[0]
	var l0 := c & M16
	c = x[1] + y[1] + (c >> 16)
	var l1 := c & M16
	c = x[2] + y[2] + (c >> 16)
	var l2 := c & M16
	c = x[3] + y[3] + (c >> 16)
	return _join(l0, l1, l2, c)


## Logical (unsigned) right shift, 0 < n < 64.
static func shr(a: int, n: int) -> int:
	return (a >> n) & ~(-1 << (64 - n))


static func splitmix64(x: int) -> int:
	var z := add(x, SM_GAMMA)
	z = mul(z ^ shr(z, 30), SM_MUL1)
	z = mul(z ^ shr(z, 27), SM_MUL2)
	return z ^ shr(z, 31)


static func level_seed(master: int, level: int) -> int:
	return splitmix64(master ^ splitmix64(level))


static func fnv1a64_bytes(data: PackedByteArray) -> int:
	var h := FNV_OFFSET
	for b in data:
		h = mul(h ^ b, FNV_PRIME)
	return h


static func fnv1a64(text: String) -> int:
	return fnv1a64_bytes(text.to_utf8_buffer())


## 16 upper-case hex digits of the unsigned bit pattern.
static func to_hex(a: int) -> String:
	var l := _limbs(a)
	return "%04X%04X%04X%04X" % [l[3], l[2], l[1], l[0]]


## Parses "0x..." / 1-16 hex digits (with letters or 16 digits) or a decimal int.
## Returns {"ok": bool, "value": int}.
static func parse_seed(text: String) -> Dictionary:
	var t := text.strip_edges().to_upper()
	if t.is_empty():
		return {"ok": false, "value": 0}
	var is_hex := false
	if t.begins_with("0X"):
		t = t.substr(2)
		is_hex = true
	elif t.length() == 16 or not t.lstrip("-").is_valid_int():
		is_hex = true
	if is_hex:
		if t.is_empty() or t.length() > 16 or not t.is_valid_hex_number(false):
			return {"ok": false, "value": 0}
		var padded := t.lpad(16, "0")
		var v := 0
		for i in 4:
			var part := padded.substr(i * 4, 4).hex_to_int()
			v = v | ((part & M16) << (48 - 16 * i))
		return {"ok": true, "value": v}
	return {"ok": true, "value": t.to_int()}
