# Test results

Latest full run of `tools/run_tests.sh` (generator v2, Godot 4.7.2, Jolt, headless, `--fixed-fps 60`, 2026-11-07).

```
== test_hash.gd
  [PASS] test_splitmix_reference_values (0 ms)
  [PASS] test_level_seeds_stable (0 ms)
  [PASS] test_fnv (0 ms)
  [PASS] test_parse_roundtrip (0 ms)
== test_geometry.gd
  [PASS] test_module_ends_match_standard (0 ms)
    note: 20 modules, 13 types
  [PASS] test_catalogue_fields (1 ms)
  [PASS] test_collision_winding_faces_up (13 ms)
    note: worst raw join mismatch 0.000034 m; joins checked per strip: { "surface": 2133, "w0": 367, "w1": 367, "w2": 367 }
  [PASS] test_adjacent_strips_share_vertices (2436 ms)
  [PASS] test_style_ends_are_standard (25 ms)
  [PASS] test_tube_faces_inward_wires_outward (0 ms)
  [PASS] test_jump_has_gap (2 ms)
    note: avg 1134 render tris/module variant
  [PASS] test_mesh_budget (189 ms)
== test_generation.gd
  [PASS] test_same_seed_identical (2364 ms)
    note: modules per environment: { "classic": 10491, "tube": 4979, "wires": 4382, "ramps": 4148 }
    note: 1000 unique sequences out of 1000; 20 module types used
  [PASS] test_different_seeds_vary (20672 ms)
  [PASS] test_connectors_align (260 ms)
  [PASS] test_no_invalid_overlap (218 ms)
  [PASS] test_start_finish_checkpoints (35 ms)
    note: max attempts 167, max gen time 41.8 ms, mean 20.43 ms, total backtracks 0, short levels 0
  [PASS] test_bounded_attempts (6 ms)
  [PASS] test_validator_accepts_every_module (423 ms)
  [PASS] test_obstacle_layouts_valid (0 ms)
    note: fingerprint v2 = 2BA1F9EF76FEB4C0
  [PASS] test_generator_version_fingerprint (9 ms)
    note: level 1: 3537EE502DD20CA2-1-10 916CAFE2A31FBEFD
    note: level 2: 479389DD8BE4977F-2-12 21F6E2967D15A979
    note: level 3: 94DF7E97AD170C8E-3-14 7CEDC5F2D7CD441A
    note: level 4: 959211D402682BD8-4-16 08C7167BE04E41A8
    note: level 5: F82670827605D845-4.35-18 5B61FBB0CBCACAA1
    note: level 10: 0FDC38D05DDE0357-6.1-28 3F173835E9A487D6
  [PASS] test_golden_levels (131 ms)
== test_persistence.gd
  [PASS] test_save_and_restore_progress (0 ms)
  [PASS] test_best_times_are_versioned (0 ms)
  [PASS] test_seed_replay_after_restart (64 ms)
  [PASS] test_missing_save_is_fresh (0 ms)
== test_endless.gd
  [PASS] test_stream_deterministic (158 ms)
    note: 10000 endless modules, 0 forced fallbacks, 0 overlaps
  [PASS] test_stream_window_no_overlap_and_bounded (29475 ms)
    note: mean module difficulty first 40: 0.64, last 40: 1.34
  [PASS] test_difficulty_ramps_up (100 ms)
  [PASS] test_endless_does_not_affect_levels (63 ms)
    note: 90 s endless: 488 m, 41 collision rebuilds, max 14 active modules, fell=false
  [PASS] test_endless_session_physics (2563 ms)
== test_physics.gd
    note: result finished after 19.8 s, max speed 6.89
  [PASS] test_smoke_basic_track_no_input (422 ms)
    note: terminal-ish speed 4.70 m/s -> effective damping 0.104 (validator uses 0.100)
  [PASS] test_calibrate_terminal_speed (513 ms)
    note: result finished, max dv_y/tick at joins 0.0979 m/s (inside modules 0.1489), max lift above floor 0.0005 m
  [PASS] test_joins_have_no_seams (641 ms)
    note: autopilot results: { "finished": 30 }
  [PASS] test_autopilot_traverses_levels (44401 ms)
    note: tube: finished after 23.5 s, max 6.9 m/s
    note: wires: finished after 21.9 s, max 6.7 m/s
    note: ramps: finished after 12.0 s, max 8.0 m/s
  [PASS] test_environments_no_input (1198 ms)
    note: jump: finished, 31 ticks over the gap
  [PASS] test_jump_flies_and_lands (222 ms)
    note: braking into the jump: stalled at module jump
  [PASS] test_braking_short_of_jump_fails (176 ms)
    note: speed after 5 s: coast 3.73, boost 13.29, brake 0.00 m/s
  [PASS] test_throttle_and_brake (270 ms)
    note: wires: finished, late speed 4.50 m/s -> effective damping 0.109 (validator pessimistic 0.150)
  [PASS] test_wire_calibration (496 ms)
40 tests, 0 failed, 107.8 s
```

Build verification (same date):

- `builds/marble-run-debug.apk`: 28518867 bytes, signed with the Android debug key, `apksigner verify` OK, arm64-v8a, no permissions.
- Not installed on a device (none connected).
