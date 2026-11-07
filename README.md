# Marble Run (procedural)

An offline, procedural 3D marble run for Android and Linux, built with Godot 4.7
and GDScript only. A marble rolls down an elevated toy-like track assembled from
reusable modules by a deterministic, seeded generator. Steer left/right, avoid
falling off, reach the finish.

* 18 analytic track modules (straights, gentle/sharp curves, S-bends, ramps,
  waves, funnel/bowl, narrow bridge, static and moving obstacles) defined in
  `resources/modules/catalog.json` — no external models.
* Deterministic generation from 64-bit seeds, with overlap, slope, curvature,
  speed and obstacle-lane validation; ~12 ms per level on desktop.
* Numbered levels with rising difficulty, custom seeds / shareable track codes,
  endless mode with streaming generation.
* Jolt physics, merged seam-free collision, physics-tick steering forces.
* Local persistence (ConfigFile), no network permission, no telemetry.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how generation works,
[BUILD.md](BUILD.md) for Android builds and
[docs/LIMITATIONS.md](docs/LIMITATIONS.md) for known limitations.

## Controls

| Action | Touch | Keyboard |
|---|---|---|
| Steer | drag left/right anywhere | ← → or A / D |
| Pause | `II` button | Esc / P |
| Restart | pause menu | R |
| Next level | completion panel | N |
| Debug overlay | Settings | F3 |
| Autopilot (dev) | — | F4 |

With mouse touch emulation enabled, dragging with the mouse also steers on desktop.

Each level gives 3 lives; falling respawns you at the last checkpoint (blue
arches). Getting stuck for 2.5 s also returns you to the checkpoint (no life lost).

## Linux setup

Requirements: Godot **4.7.x** standard (non-.NET) build. On Arch/Manjaro:

```sh
sudo pacman -S godot        # 4.7.2 was used for development
```

Any official 4.7.x binary from godotengine.org works too (set `GODOT=/path/to/godot`
for the scripts).

```sh
git clone <this repo> && cd marble-run
godot --path . --import     # first run: import resources
godot --path .              # play (main menu)
godot --path . -e           # open in the editor
```

### Developer flags

Pass after `--`:

```sh
godot --path . -- --level=5                 # jump straight into level 5
godot --path . -- --seed=94DF7E97AD170C8E-3-14
godot --path . -- --endless --autopilot --debug
godot --path . --disable-vsync -- --level=10 --autopilot --bench   # timing report
godot --path . -- --level=3 --shot=/tmp/s.png --shot-frames=300    # screenshot
godot --path . --rendering-method gl_compatibility -- --level=2   # Compatibility renderer
```

## Tests

```sh
tools/run_tests.sh                 # all suites (~80 s), exit code 0 on success
tools/run_tests.sh --only=physics  # filter by suite or test name
```

The runner is a plain `SceneTree` script (`tests/run_tests.gd`, no plugins) run
headless with `--fixed-fps 60`, so physics runs ≈ 50× faster than real time.
Results are also written to `builds/test_results.txt`; the latest run is recorded
in [docs/TEST_RESULTS.md](docs/TEST_RESULTS.md).

| Suite | Covers |
|---|---|
| `test_hash` | SplitMix64 / FNV-1a against Python reference values, seed parsing, track codes |
| `test_geometry` | connector frames, end-profile continuity, collision winding, shared join vertices, mesh budget |
| `test_generation` | 1000 seeds: determinism, variety, connector alignment, no overlaps (independent brute-force check), start/finish/checkpoints, bounded attempts, validator re-check, obstacle lanes, version fingerprint, golden levels |
| `test_persistence` | save/restore, versioned best times, seed replay after a simulated restart |
| `test_endless` | stream determinism, 10 000 streamed modules without overlap, difficulty ramp, isolation from level generation, 90 s physics run with streaming collision |
| `test_physics` | no-input smoke run, damping calibration, seam test across 12 joins, autopilot traversal of 30 generated levels |

Passing these tests does **not** guarantee every generated track is completable
by a human; see the limitations document.

## Project layout

```
project.godot, export_presets.cfg, icon.svg
scenes/      main_menu/ game/ marble/ track/ ui/   (thin scenes, logic in scripts)
scripts/
  generation/   module defs, catalogue, generator, validator, overlap grid
  track/        mesh + collision builder, track view, obstacles, tracker
  physics/      marble body and mesh
  game/         app autoload, game loop, session, camera, input, progression, autopilot
  persistence/  SaveData (ConfigFile)
  ui/           theme, HUD, main menu
  debug/        debug overlay
  util/         Hash64
resources/modules/catalog.json   all module parameters
tests/       test runner and suites
tools/       run_tests.sh, build_android.sh, debug_level.gd
docs/        ARCHITECTURE.md, LIMITATIONS.md, TEST_RESULTS.md
builds/      build outputs (git-ignored)
```

`tools/debug_level.gd` prints a level's module list and traces an autopilot run:

```sh
godot --headless --fixed-fps 60 --path . -s res://tools/debug_level.gd -- 94DF7E97AD170C8E-3-14 0
```

## Changing generation

Edit `catalog.json` or generator/validator constants, then run the tests. The
fingerprint test will fail: bump `TrackGenerator.VERSION`, add the printed
fingerprint to `FINGERPRINTS`, and update `GOLDEN` in `tests/test_generation.gd`.
Saved best times are keyed per generator version.
