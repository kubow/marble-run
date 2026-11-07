# Test results

Latest full run of `tools/run_tests.sh` (Godot 4.7.2, Jolt, headless, `--fixed-fps 60`, 2026-11-07).

```
== test_hash.gd
  [PASS] test_splitmix_reference_values (0 ms)
  [PASS] test_level_seeds_stable (0 ms)
  [PASS] test_fnv (0 ms)
  [PASS] test_parse_roundtrip (0 ms)
== test_geometry.gd
  [PASS] test_module_ends_match_standard (0 ms)
    note: 18 modules, 12 types
  [PASS] test_catalogue_fields (0 ms)
  [PASS] test_collision_winding_faces_up (5 ms)
       [0] test_adjacent_rings_share_vertices (res://tests/test_geometry.gd:73)
       [1] _run (res://tests/run_tests.gd:44)
    note: worst raw join mismatch %.2e m
  [PASS] test_adjacent_rings_share_vertices (2097 ms)
    note: avg 608 render tris/module
  [PASS] test_mesh_budget (13 ms)
== test_generation.gd
  [PASS] test_same_seed_identical (1507 ms)
    note: 998 unique sequences out of 1000; 18 module types used
  [PASS] test_different_seeds_vary (12571 ms)
  [PASS] test_connectors_align (262 ms)
  [PASS] test_no_invalid_overlap (180 ms)
  [PASS] test_start_finish_checkpoints (36 ms)
    note: max attempts 150, max gen time 19.9 ms, mean 12.40 ms, total backtracks 6, short levels 0
  [PASS] test_bounded_attempts (7 ms)
  [PASS] test_validator_accepts_every_module (201 ms)
  [PASS] test_obstacle_layouts_valid (0 ms)
    note: fingerprint v1 = D6902695074F881F
  [PASS] test_generator_version_fingerprint (7 ms)
    note: level 1: 3537EE502DD20CA2-1-10 1DEE5B156B1FD4BF
    note: level 2: 479389DD8BE4977F-2-12 4703201E86C2DC5E
    note: level 3: 94DF7E97AD170C8E-3-14 971C00233C29D2D5
    note: level 4: 959211D402682BD8-4-16 BCBF1D54A74ED1E1
    note: level 5: F82670827605D845-4.35-18 6B504C161EBD7EC6
    note: level 10: 0FDC38D05DDE0357-6.1-28 6389BCB380BC8603
  [PASS] test_golden_levels (83 ms)
== test_persistence.gd
  [PASS] test_save_and_restore_progress (1 ms)
  [PASS] test_best_times_are_versioned (0 ms)
  [PASS] test_seed_replay_after_restart (37 ms)
  [PASS] test_missing_save_is_fresh (0 ms)
== test_endless.gd
  [PASS] test_stream_deterministic (82 ms)
    note: 10000 endless modules, 0 forced fallbacks, 0 overlaps
  [PASS] test_stream_window_no_overlap_and_bounded (12331 ms)
    note: mean module difficulty first 40: 0.54, last 40: 1.98
  [PASS] test_difficulty_ramps_up (56 ms)
  [PASS] test_endless_does_not_affect_levels (39 ms)
    note: 90 s endless: 472 m, 38 collision rebuilds, max 14 active modules, fell=false
  [PASS] test_endless_session_physics (2053 ms)
== test_physics.gd
    note: result finished after 19.8 s, max speed 6.88
  [PASS] test_smoke_basic_track_no_input (360 ms)
    note: terminal-ish speed 4.70 m/s -> effective damping 0.104 (validator uses 0.100)
  [PASS] test_calibrate_terminal_speed (477 ms)
    note: result finished, max dv_y/tick 0.1361 m/s, max lift above floor 0.0004 m
  [PASS] test_joins_have_no_seams (540 ms)
    note: autopilot results: { "finished": 30 }
  [PASS] test_autopilot_traverses_levels (44944 ms)
32 tests, 0 failed, 78.1 s
```

Build verification (same date):

- `builds/marble-run-debug.apk`: 28498387 bytes, signed with the Android debug key, `apksigner verify` OK, arm64-v8a, no permissions.
- Not installed on a device (none connected).
