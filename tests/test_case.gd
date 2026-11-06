class_name TestCase
extends RefCounted
## Minimal test base class (no plugins). Methods named test_* are run in
## declaration order by tests/run_tests.gd. Methods may be coroutines.

var tree: SceneTree
var failures: PackedStringArray = PackedStringArray()
var notes: PackedStringArray = PackedStringArray()
var current := ""


func check(cond: bool, msg: String) -> bool:
	if not cond:
		failures.append("%s: %s" % [current, msg])
	return cond


func check_eq(a, b, msg: String) -> bool:
	return check(a == b, "%s (got %s, expected %s)" % [msg, str(a), str(b)])


func note(msg: String) -> void:
	notes.append("%s: %s" % [current, msg])
	print("    note: ", msg)
