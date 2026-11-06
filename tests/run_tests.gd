extends SceneTree
## Headless test runner.
##   godot --headless --path . -s res://tests/run_tests.gd [-- --only=name] [--quick]
## Exit code 0 when all tests pass. Writes builds/test_results.txt.

const SUITES := [
	"res://tests/test_hash.gd",
	"res://tests/test_geometry.gd",
	"res://tests/test_generation.gd",
	"res://tests/test_persistence.gd",
	"res://tests/test_endless.gd",
	"res://tests/test_physics.gd",
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	var total := 0
	var failed := 0
	var lines := PackedStringArray()
	var t_all := Time.get_ticks_msec()
	for path in SUITES:
		var script: GDScript = load(path)
		var suite: TestCase = script.new()
		suite.tree = self
		print("== ", path.get_file())
		for m in script.get_script_method_list():
			var name: String = m.name
			if not name.begins_with("test_"):
				continue
			if only != "" and not (name.contains(only) or path.contains(only)):
				continue
			total += 1
			suite.current = name
			var before := suite.failures.size()
			var t0 := Time.get_ticks_msec()
			await suite.call(name)
			var ms := Time.get_ticks_msec() - t0
			var ok := suite.failures.size() == before
			if not ok:
				failed += 1
			var line := "  [%s] %s (%d ms)" % ["PASS" if ok else "FAIL", name, ms]
			print(line)
			lines.append(line)
			for i in range(before, suite.failures.size()):
				print("      ", suite.failures[i])
				lines.append("      " + suite.failures[i])
		for n in suite.notes:
			lines.append("      note " + n)
	var summary := "%d tests, %d failed, %.1f s" % [total, failed, (Time.get_ticks_msec() - t_all) / 1000.0]
	print(summary)
	lines.append(summary)
	var dir := ProjectSettings.globalize_path("res://builds")
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("test_results.txt"), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines) + "\n")
	TrackMeshBuilder.clear_cache()
	TrackDecor.clear_cache()
	await process_frame
	quit(0 if failed == 0 else 1)
