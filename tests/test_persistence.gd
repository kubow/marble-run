extends TestCase
## Save/restore and seed replay across a simulated restart.

const PATH := "user://test_save.cfg"


func _cleanup() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func test_save_and_restore_progress() -> void:
	_cleanup()
	var s := SaveData.new(PATH)
	s.unlocked_level = 7
	s.best_endless = 432.5
	check(s.record_time(SaveData.level_key(3), 61.25), "first time is best")
	check(not s.record_time(SaveData.level_key(3), 70.0), "slower is not best")
	check(s.record_time(SaveData.level_key(3), 59.5), "faster is best")
	s.record_time(SaveData.code_key("94DF7E97AD170C8E-3-14"), 33.0)
	s.settings.steer_sensitivity = 1.4
	s.settings.invert_steer = true
	s.set_last_level(6, "ABC-6-20")
	check(s.save_data(), "saved")
	var r := SaveData.new(PATH)
	check(r.load_data(), "loaded")
	check_eq(r.unlocked_level, 7, "unlocked level")
	check_eq(r.best_endless, 432.5, "best endless")
	check_eq(r.best_time(SaveData.level_key(3)), 59.5, "best time")
	check_eq(r.best_time(SaveData.code_key("94DF7E97AD170C8E-3-14")), 33.0, "custom best time")
	check_eq(r.settings.steer_sensitivity, 1.4, "setting float")
	check_eq(r.settings.invert_steer, true, "setting bool")
	check_eq(r.last.get("level"), 6, "last level")
	check_eq(r.last.get("generator_version"), TrackGenerator.VERSION, "generator version stored with last level")
	_cleanup()


func test_best_times_are_versioned() -> void:
	check(SaveData.level_key(5, 1) != SaveData.level_key(5, 2), "keys differ per generator version")
	check(SaveData.level_key(5).begins_with("v%d:" % TrackGenerator.VERSION), "current version in key")


func test_seed_replay_after_restart() -> void:
	_cleanup()
	var gen := TrackGenerator.new()
	var cfg := GeneratorConfig.make(Hash64.splitmix64(4242), 5.5, 26)
	var original := gen.generate(cfg)
	var s := SaveData.new(PATH)
	s.set_last_custom(cfg.to_code())
	s.save_data()
	# "Restart": fresh objects, fresh catalogue instance, reload from disk.
	var s2 := SaveData.new(PATH)
	s2.load_data()
	var cat := ModuleCatalog.load_from_file(ModuleCatalog.DEFAULT_PATH)
	var cfg2 := GeneratorConfig.from_code(str(s2.last.code))
	check(cfg2 != null, "stored code parses")
	var replay := TrackGenerator.new(cat).generate(cfg2)
	check_eq(replay.logical_hash(), original.logical_hash(), "replayed level identical")
	check_eq(replay.module_ids(), original.module_ids(), "same modules")
	_cleanup()


func test_missing_save_is_fresh() -> void:
	_cleanup()
	var s := SaveData.new(PATH)
	check(not s.load_data(), "no file -> load returns false")
	check_eq(s.unlocked_level, 1, "defaults")
