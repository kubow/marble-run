# Test results

Latest full run of `tools/run_tests.sh` (generator v3, Godot 4.7.2, Jolt, headless, `--fixed-fps 60`, 2026-11-07).

```
== test_hash.gd
  [PASS] test_splitmix_reference_values (0 ms)
  [PASS] test_level_seeds_stable (0 ms)
  [PASS] test_fnv (0 ms)
  [PASS] test_parse_roundtrip (0 ms)
== test_geometry.gd
  [PASS] test_module_ends_match_standard (0 ms)
    note: 21 modules, 13 types
  [PASS] test_catalogue_fields (0 ms)
  [PASS] test_collision_winding_faces_up (15 ms)
    note: worst raw join mismatch 0.000035 m; joins checked per strip: { "surface": 2139, "w0": 361, "w1": 361, "w2": 361 }
  [PASS] test_adjacent_strips_share_vertices (2603 ms)
  [PASS] test_style_ends_are_standard (31 ms)
  [PASS] test_tube_faces_inward_wires_outward (0 ms)
  [PASS] test_jump_has_gap (2 ms)
    note: avg 1152 render tris/module variant
  [PASS] test_mesh_budget (234 ms)
== test_generation.gd
  [PASS] test_same_seed_identical (2305 ms)
    note: modules per environment: { "classic": 9941, "tube": 2137, "wires": 4569, "ramps": 7353 }
    note: 1000 unique sequences out of 1000; 21 module types used
  [PASS] test_different_seeds_vary (20630 ms)
  [PASS] test_connectors_align (243 ms)
  [PASS] test_no_invalid_overlap (209 ms)
  [PASS] test_start_finish_checkpoints (28 ms)
    note: max attempts 68, max gen time 35.3 ms, mean 20.41 ms, total backtracks 1, short levels 0
  [PASS] test_bounded_attempts (4 ms)
  [PASS] test_validator_accepts_every_module (703 ms)
    note: speed demands per module: { "easy": 0.16, "mid": 0.44, "hard": 0.51 }
  [PASS] test_speed_demands_follow_difficulty (22 ms)
    note: jump_small take-off window 3.2..8.3 m/s
    note: jump take-off window 3.8..9.2 m/s
    note: jump_big take-off window 5.6..9.9 m/s
  [PASS] test_jump_windows (0 ms)
  [PASS] test_obstacle_layouts_valid (0 ms)
    note: fingerprint v3 = BBE1C1E2620D3A3A
  [PASS] test_generator_version_fingerprint (10 ms)
    note: level 1: 3537EE502DD20CA2-1-10 58EAE167C4A0A242
    note: level 2: 479389DD8BE4977F-2.2-12 FCB93F3142FED78A
    note: level 3: 94DF7E97AD170C8E-3.4-14 D87F5DD34017FA12
    note: level 4: 959211D402682BD8-4.6-16 655699C72816A152
    note: level 5: F82670827605D845-5-18 2006D14692099DF2
    note: level 10: 0FDC38D05DDE0357-7-28 4CAA08D8A2E680FD
  [PASS] test_golden_levels (130 ms)
== test_persistence.gd
  [PASS] test_save_and_restore_progress (1 ms)
  [PASS] test_best_times_are_versioned (0 ms)
  [PASS] test_seed_replay_after_restart (59 ms)
  [PASS] test_missing_save_is_fresh (0 ms)
== test_endless.gd
  [PASS] test_stream_deterministic (168 ms)
    note: 10000 endless modules, 0 forced fallbacks, 0 overlaps
  [PASS] test_stream_window_no_overlap_and_bounded (28698 ms)
    note: mean module difficulty first 40: 1.19, last 40: 2.04
  [PASS] test_difficulty_ramps_up (101 ms)
  [PASS] test_endless_does_not_affect_levels (70 ms)
    note: 90 s endless: 549 m, 39 collision rebuilds, max 14 active modules, fell=false
  [PASS] test_endless_session_physics (2682 ms)
== test_physics.gd
    note: result finished after 18.3 s, max speed 7.30
  [PASS] test_smoke_basic_track_no_input (412 ms)
    note: terminal-ish speed 5.53 m/s -> effective damping 0.088 (validator uses 0.100)
  [PASS] test_calibrate_terminal_speed (511 ms)
    note: result finished, max dv_y/tick at joins 0.0334 m/s (inside modules 0.1626), max lift above floor 0.0006 m
  [PASS] test_joins_have_no_seams (603 ms)
    note: autopilot (steer + throttle) results: { "finished": 30 }; hands-off finishes at difficulty >= 2: 5
  [PASS] test_autopilot_traverses_levels (73712 ms)
    note: tube: finished after 21.6 s, max 7.3 m/s
    note: wires: finished after 19.9 s, max 7.0 m/s
    note: ramps: finished after 11.5 s, max 8.5 m/s
  [PASS] test_environments_no_input (1259 ms)
    note: jump: finished, 29 ticks over the gap
  [PASS] test_jump_flies_and_lands (224 ms)
    note: braking into the jump: stalled at module jump
  [PASS] test_braking_short_of_jump_fails (203 ms)
    note: speed after 5 s: coast 4.14, boost 13.30, brake 0.00 m/s
  [PASS] test_throttle_and_brake (374 ms)
    note: wires: finished, late speed 5.41 m/s -> effective damping 0.090 (validator pessimistic 0.150)
  [PASS] test_wire_calibration (466 ms)
    note: max marble height entering wires: 0.35 m (resting 0.27)
  [PASS] test_wire_entry_is_smooth (1142 ms)
43 tests, 0 failed, 138.1 s
```

Build verification (same date):

- `builds/marble-run-debug.apk`: 28522963 bytes, signed with the Android debug key, `apksigner verify` OK, arm64-v8a, no permissions.
- Not installed on a device (none connected).
